// Run from the repo root: node --test supabase/functions/delete-account/logic.test.ts
// Fictional data only. The network is faked; nothing calls Supabase.
import { test } from "node:test";
import assert from "node:assert/strict";
import { bearer, handle } from "./logic.ts";

const KEY = "sb_publishable_test_key";
const SECRET = "sb_secret_test_key";
const URL_BASE = "https://example-project.supabase.co";
const env = { supabaseUrl: URL_BASE, publishableKeys: JSON.stringify({ default: KEY }), secretKeys: JSON.stringify({ default: SECRET }) };
const ME = "11111111-1111-4111-8111-111111111111";
const SOMEONE_ELSE = "22222222-2222-4222-8222-222222222222";
const TOKEN = "eyJfakeheader.eyJfakepayload.fakesignature";

function request(body: unknown = {}, headers: Record<string, string> = { apikey: KEY, Authorization: `Bearer ${TOKEN}` }, method = "POST") {
  return new Request("http://localhost/delete-account", {
    method,
    headers: { "Content-Type": "application/json", ...headers },
    body: method === "POST" ? JSON.stringify(body) : undefined,
  });
}

type Call = { url: string; init: RequestInit };
/** Fakes Supabase Auth: the user lookup answers [who], the admin delete answers [deleted]. */
function fakeAuth(who: Response | Error, deleted: Response | Error = new Response("{}", { status: 200 })) {
  const calls: Call[] = [];
  const fn = async (url: string, init: RequestInit) => {
    calls.push({ url, init });
    const next = url.endsWith("/auth/v1/user") ? who : url.includes("/auth/v1/admin/users/") ? deleted : undefined;
    if (next === undefined) throw new Error(`unexpected call to ${url}`);
    if (next instanceof Error) throw next;
    return next;
  };
  return { fn, calls };
}
const user = (id: unknown) => new Response(JSON.stringify({ id, email: "tester@example.test" }), { status: 200 });
const header = (init: RequestInit, name: string) => new Headers(init.headers).get(name);
const neverCalled = async () => {
  throw new Error("Supabase must not be called");
};

// --- denial paths ---

test("rejects GET, a missing or wrong apikey, and a missing token, without calling Supabase", async () => {
  assert.equal((await handle(request({}, {}, "GET"), env, neverCalled)).status, 405);
  assert.equal((await handle(request({}, { Authorization: `Bearer ${TOKEN}` }), env, neverCalled)).status, 401);
  assert.equal((await handle(request({}, { apikey: "sb_publishable_other", Authorization: `Bearer ${TOKEN}` }), env, neverCalled)).status, 401);
  assert.equal((await handle(request({}, { apikey: KEY }), env, neverCalled)).status, 401);
  assert.equal((await handle(request({}, { apikey: KEY, Authorization: "Basic abc" }), env, neverCalled)).status, 401);
});

test("an invalid or expired token deletes nothing", async () => {
  for (const status of [401, 403]) {
    const auth = fakeAuth(new Response("{}", { status }));
    assert.equal((await handle(request(), env, auth.fn)).status, 401);
    assert.equal(auth.calls.length, 1, "no delete call");
  }
  for (const id of [undefined, 42, "not-a-uuid", `${ME}/../${SOMEONE_ELSE}`]) {
    const auth = fakeAuth(user(id));
    assert.equal((await handle(request(), env, auth.fn)).status, 401);
    assert.equal(auth.calls.length, 1, "no delete call");
  }
});

test("a user ID in the request is ignored: only the token's own user is deleted", async () => {
  const auth = fakeAuth(user(ME));
  const res = await handle(request({ userId: SOMEONE_ELSE, id: SOMEONE_ELSE }), env, auth.fn);
  assert.equal(res.status, 200);
  assert.deepEqual(auth.calls.map((c) => c.url), [`${URL_BASE}/auth/v1/user`, `${URL_BASE}/auth/v1/admin/users/${ME}`]);
  assert.equal(auth.calls[1].init.method, "DELETE");
});

test("the lookup uses the caller's token; only the delete uses the secret key", async () => {
  const auth = fakeAuth(user(ME));
  await handle(request(), env, auth.fn);
  const [lookup, del] = auth.calls;
  assert.equal(header(lookup.init, "authorization"), `Bearer ${TOKEN}`);
  assert.equal(header(lookup.init, "apikey"), KEY);
  assert.ok(!JSON.stringify(lookup.init.headers).includes(SECRET), "secret not sent with the user's request");
  assert.equal(header(del.init, "authorization"), `Bearer ${SECRET}`);
  assert.equal(header(del.init, "apikey"), SECRET);
});

test("missing server config fails closed without calling Supabase", async () => {
  for (const broken of [{ ...env, supabaseUrl: undefined }, { ...env, secretKeys: undefined }, { ...env, secretKeys: "" }]) {
    assert.equal((await handle(request(), broken, neverCalled)).status, 500);
  }
});

test("upstream failures are 502 and never report success", async () => {
  assert.equal((await handle(request(), env, fakeAuth(new Response("{}", { status: 500 })).fn)).status, 502);
  assert.equal((await handle(request(), env, fakeAuth(new Error("offline")).fn)).status, 502);
  assert.equal((await handle(request(), env, fakeAuth(user(ME), new Response("{}", { status: 500 })).fn)).status, 502);
  assert.equal((await handle(request(), env, fakeAuth(user(ME), new Error("offline")).fn)).status, 502);
  // Already gone counts as deleted (a retry after a lost answer).
  assert.equal((await handle(request(), env, fakeAuth(user(ME), new Response("{}", { status: 404 })).fn)).status, 200);
});

test("bearer: only a well-formed Bearer token", () => {
  const r = (h?: string) => new Request("http://localhost", h ? { headers: { Authorization: h } } : {});
  assert.equal(bearer(r(`Bearer ${TOKEN}`)), TOKEN);
  assert.equal(bearer(r("Bearer short")), null);
  assert.equal(bearer(r("Bearer a b c d e f g h i j k l m n o p")), null);
  assert.equal(bearer(r()), null);
});
