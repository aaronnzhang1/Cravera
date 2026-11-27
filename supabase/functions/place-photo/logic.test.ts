// Run from the repo root: node --test supabase/functions/place-photo/logic.test.ts
// Fictional data only. The network is faked; nothing calls Google.
import { test } from "node:test";
import assert from "node:assert/strict";
import { handle, isSafePhotoUri, PHOTO_NAME } from "./logic.ts";

const KEY = "sb_publishable_test_key";
const env = { placesKey: "fake-places-key", publishableKeys: JSON.stringify({ default: KEY }) };
const NAME = "places/fake-place-1/photos/AbC_123-xyz";
const GOOD_URI = "https://lh3.googleusercontent.com/places/fake-photo=s800";

function request(body: unknown, headers: Record<string, string> = { apikey: KEY }, method = "POST") {
  return new Request("http://localhost/place-photo", {
    method,
    headers: { "Content-Type": "application/json", ...headers },
    body: method === "POST" ? JSON.stringify(body) : undefined,
  });
}

function fakeFetch(response: Response | Error) {
  const calls: { url: string; init: RequestInit }[] = [];
  const fn = async (url: string, init: RequestInit) => {
    calls.push({ url, init });
    if (response instanceof Error) throw response;
    return response;
  };
  return { fn, calls };
}

const neverCalled = async () => {
  throw new Error("Google must not be called");
};

// --- access ---

test("rejects a missing or wrong apikey without calling Google", async () => {
  assert.equal((await handle(request({ photoName: NAME }, {}), env, neverCalled)).status, 401);
  assert.equal((await handle(request({ photoName: NAME }, { apikey: "sb_publishable_other" }), env, neverCalled)).status, 401);
  assert.equal(
    (await handle(request({ photoName: NAME }), { ...env, publishableKeys: undefined }, neverCalled)).status,
    401,
  );
});

test("rejects non-POST and a missing Places key", async () => {
  assert.equal((await handle(request(null, { apikey: KEY }, "GET"), env, neverCalled)).status, 405);
  assert.equal((await handle(request({ photoName: NAME }), { ...env, placesKey: undefined }, neverCalled)).status, 500);
});

// --- input: only Places photo names reach Google ---

test("only accepts Places photo names", () => {
  assert.ok(PHOTO_NAME.test(NAME));
  for (const bad of [
    "",
    "places/x",
    "places/x/photos/",
    "places/x/photos/y/media",
    "places/../photos/y",
    "places/x/photos/y?key=1",
    "places/x/photos/y#z",
    "https://evil.example/places/x/photos/y",
    "places/x/reviews/y",
    "places/x/photos/y\n",
  ]) {
    assert.ok(!PHOTO_NAME.test(bad), JSON.stringify(bad));
  }
});

test("a bad photo name is a 400 and never calls Google", async () => {
  assert.equal((await handle(request({ photoName: "places/x/photos/y/../../z" }), env, neverCalled)).status, 400);
  assert.equal((await handle(request({}), env, neverCalled)).status, 400);
});

// --- the call to Google ---

test("asks Google for a link, not the image, with the key only in a header", async () => {
  const { fn, calls } = fakeFetch(new Response(JSON.stringify({ photoUri: GOOD_URI })));
  const res = await handle(request({ photoName: NAME }), env, fn);
  assert.equal(res.status, 200);
  assert.deepEqual(await res.json(), { photoUri: GOOD_URI });
  assert.equal(
    calls[0].url,
    `https://places.googleapis.com/v1/${NAME}/media?maxWidthPx=800&skipHttpRedirect=true`,
  );
  assert.ok(!calls[0].url.includes("fake-places-key"));
  assert.equal((calls[0].init.headers as Record<string, string>)["X-Goog-Api-Key"], "fake-places-key");
  assert.equal(calls[0].init.redirect, "error");
});

// --- what comes back ---

test("only passes on https googleusercontent.com links", () => {
  assert.ok(isSafePhotoUri(GOOD_URI));
  assert.ok(!isSafePhotoUri("http://lh3.googleusercontent.com/x"));
  assert.ok(!isSafePhotoUri("https://evil.example/x"));
  assert.ok(!isSafePhotoUri("https://googleusercontent.com.evil.example/x"));
  assert.ok(!isSafePhotoUri("javascript:alert(1)"));
  assert.ok(!isSafePhotoUri(undefined));
});

test("an unexpected link from Google is a 502, never passed on", async () => {
  for (const photoUri of ["https://evil.example/x", `${GOOD_URI}?key=fake-places-key`, undefined]) {
    const { fn } = fakeFetch(new Response(JSON.stringify({ photoUri })));
    const res = await handle(request({ photoName: NAME }), env, fn);
    assert.equal(res.status, 502, String(photoUri));
    assert.ok(!(await res.text()).includes("fake-places-key"));
  }
});

test("Google errors and network failures are a 502 that doesn't echo Google", async () => {
  const { fn } = fakeFetch(new Response('{"error":"key fake-places-key invalid"}', { status: 403 }));
  const res = await handle(request({ photoName: NAME }), env, fn);
  assert.equal(res.status, 502);
  assert.ok(!(await res.text()).includes("fake-places-key"));
  assert.equal((await handle(request({ photoName: NAME }), env, fakeFetch(new Error("offline")).fn)).status, 502);
});
