// Run from the repo root: node --test supabase/functions/saved-places/logic.test.ts
// Fictional data only. The network is faked; nothing calls Google or Supabase.
import { test } from "node:test";
import assert from "node:assert/strict";
import { cityOf, FIELD_MASK, handle, mapBasics } from "./logic.ts";

const KEY = "sb_publishable_test_key";
const TOKEN = "fake.user.token-0123456789abcdef";
const env = { supabaseUrl: "https://fake.supabase.test", placesKey: "fake-places-key", publishableKeys: JSON.stringify({ default: KEY }) };

function request(headers: Record<string, string> = { apikey: KEY, authorization: `Bearer ${TOKEN}` }, method = "POST", body: unknown = {}) {
  return new Request("http://localhost/saved-places", {
    method,
    headers: { "Content-Type": "application/json", ...headers },
    body: method === "POST" ? JSON.stringify(body) : undefined,
  });
}
const neverCalled = async () => {
  throw new Error("must not be called");
};
const place = (id: string) => ({
  id,
  displayName: { text: `Test Place ${id}` },
  formattedAddress: "1 Fictional St, Testville",
  location: { latitude: 10, longitude: 20 },
  addressComponents: [{ longText: "Testville", types: ["locality", "political"] }],
});

/** Supabase answers the caller's rows; Google answers per place. */
function backend(rows: unknown, opts: { rowsStatus?: number; slow?: string[] } = {}) {
  const calls: { url: string; init: RequestInit }[] = [];
  const fn = async (url: string, init: RequestInit) => {
    calls.push({ url, init });
    if (url.includes("/rest/v1/saved_places")) return new Response(JSON.stringify(rows), { status: opts.rowsStatus ?? 200 });
    const id = url.split("/").pop()!;
    if (id === "gone") return new Response("", { status: 404 });
    if (id === "down") return new Response("", { status: 500 });
    if (opts.slow?.includes(id)) {
      await new Promise((_, reject) => init.signal?.addEventListener("abort", () => reject(new DOMException("aborted", "AbortError"))));
    }
    return new Response(JSON.stringify(place(id)));
  };
  return { fn, calls };
}

test("needs POST, the publishable key and a signed-in caller, before any call", async () => {
  assert.equal((await handle(request(undefined, "GET"), env, neverCalled)).status, 405);
  assert.equal((await handle(request({ authorization: `Bearer ${TOKEN}` }), env, neverCalled)).status, 401);
  assert.equal((await handle(request({ apikey: KEY }), env, neverCalled)).status, 401, "no access token");
  assert.equal((await handle(request(), { ...env, placesKey: undefined }, neverCalled)).status, 500);
});

test("reads only the caller's own rows with their token; IDs in the body are ignored", async () => {
  const b = backend([{ place_id: "a" }, { place_id: "gone" }, { place_id: "down" }, { place_id: "a" }, { place_id: "x/../y" }]);
  const res = await handle(request(undefined, "POST", { placeIds: ["someone-elses"] }), env, b.fn);
  assert.equal(res.status, 200);
  const rowsCall = b.calls[0];
  assert.ok(rowsCall.url.startsWith("https://fake.supabase.test/rest/v1/saved_places?"));
  assert.equal((rowsCall.init.headers as Record<string, string>).Authorization, `Bearer ${TOKEN}`);
  const google = b.calls.slice(1);
  assert.deepEqual(google.map((c) => c.url.split("/").pop()), ["a", "gone", "down"], "own, unique, well-formed IDs only");
  assert.ok(!google.some((c) => c.url.includes("someone-elses")));
  for (const c of google) {
    const h = c.init.headers as Record<string, string>;
    assert.equal(h["X-Goog-FieldMask"], FIELD_MASK);
    assert.ok(!c.url.includes("fake-places-key"));
  }
  const { places } = await res.json();
  assert.deepEqual(places[0], { placeId: "a", name: "Test Place a", address: "1 Fictional St, Testville", city: "Testville", latitude: 10, longitude: 20 });
  assert.deepEqual(places[1], { placeId: "gone", error: "not_found" });
  assert.deepEqual(places[2], { placeId: "down", error: "unavailable" });
});

test("an expired token is refused without any Google call", async () => {
  const b = backend({}, { rowsStatus: 401 });
  assert.equal((await handle(request(), env, b.fn)).status, 401);
  assert.equal(b.calls.length, 1);
});

test("no saved places: no Google calls", async () => {
  const b = backend([]);
  const { places } = await (await handle(request(), env, b.fn)).json();
  assert.deepEqual(places, []);
  assert.equal(b.calls.length, 1);
});

test("a deadline returns the finished places; stalled ones come back unavailable", async () => {
  const b = backend([{ place_id: "fast" }, { place_id: "stuck" }], { slow: ["stuck"] });
  const started = Date.now();
  const { places } = await (await handle(request(), env, b.fn, 200)).json();
  assert.ok(Date.now() - started < 2000);
  assert.equal(places[0].name, "Test Place fast");
  assert.deepEqual(places[1], { placeId: "stuck", error: "unavailable" });
});

test("the field mask stays basic: no ratings, photos, reviews or hours", () => {
  for (const f of ["rating", "photos", "reviews", "regularOpeningHours", "priceLevel"]) assert.ok(!FIELD_MASK.includes(f), f);
});

test("mapping: no name is unavailable; bad coordinates are dropped together", () => {
  assert.deepEqual(mapBasics({}, "x"), { placeId: "x", error: "unavailable" });
  const m = mapBasics({ displayName: { text: "N" }, location: { latitude: 200, longitude: 1 } }, "x") as { latitude: unknown; longitude: unknown };
  assert.equal(m.latitude, null);
  assert.equal(m.longitude, null);
});

test("city: locality, else postal town, else county", () => {
  assert.equal(cityOf([{ longText: "Testshire", types: ["administrative_area_level_2"] }, { longText: "Testford", types: ["postal_town"] }]), "Testford");
  assert.equal(cityOf([{ longText: "Testshire", types: ["administrative_area_level_2"] }]), "Testshire");
  assert.equal(cityOf(null), null);
});
