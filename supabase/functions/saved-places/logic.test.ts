// Run from the repo root: node --test supabase/functions/saved-places/logic.test.ts
// Fictional data only. The network is faked; nothing calls Google.
import { test } from "node:test";
import assert from "node:assert/strict";
import { cityOf, FIELD_MASK, handle, mapBasics, MAX_PLACES } from "./logic.ts";

const KEY = "sb_publishable_test_key";
const env = { placesKey: "fake-places-key", publishableKeys: JSON.stringify({ default: KEY }) };

function request(body: unknown, headers: Record<string, string> = { apikey: KEY }, method = "POST") {
  return new Request("http://localhost/saved-places", {
    method,
    headers: { "Content-Type": "application/json", ...headers },
    body: method === "POST" ? JSON.stringify(body) : undefined,
  });
}
const neverCalled = async () => {
  throw new Error("Google must not be called");
};
const place = (id: string) => ({
  id,
  displayName: { text: `Test Place ${id}` },
  formattedAddress: "1 Fictional St, Testville",
  location: { latitude: 10, longitude: 20 },
  addressComponents: [{ longText: "Testville", types: ["locality", "political"] }],
});

test("needs POST and a known publishable key, before any Google call", async () => {
  assert.equal((await handle(request({}, {}, "GET"), env, neverCalled)).status, 405);
  assert.equal((await handle(request({ placeIds: ["a"] }, {}), env, neverCalled)).status, 401);
  assert.equal((await handle(request({ placeIds: ["a"] }), { ...env, placesKey: undefined }, neverCalled)).status, 500);
});

test("only 1 to 50 well-formed place IDs", async () => {
  for (const placeIds of [undefined, [], "a", ["a/b"], ["ok", 5], Array.from({ length: MAX_PLACES + 1 }, (_, i) => `p${i}`)]) {
    assert.equal((await handle(request({ placeIds }), env, neverCalled)).status, 400, JSON.stringify(placeIds)?.slice(0, 40));
  }
});

test("one Pro-tier request per place, key in a header; failures stay per place", async () => {
  const calls: { url: string; init: RequestInit }[] = [];
  const fetchFn = async (url: string, init: RequestInit) => {
    calls.push({ url, init });
    if (url.endsWith("/gone")) return new Response("", { status: 404 });
    if (url.endsWith("/down")) return new Response("", { status: 500 });
    return new Response(JSON.stringify(place(url.split("/").pop()!)));
  };
  const res = await handle(request({ placeIds: ["a", "gone", "down", "a"] }), env, fetchFn);
  assert.equal(res.status, 200);
  const { places } = await res.json();
  assert.equal(calls.length, 3); // duplicate asked once
  for (const c of calls) {
    const h = c.init.headers as Record<string, string>;
    assert.equal(h["X-Goog-FieldMask"], FIELD_MASK);
    assert.equal(h["X-Goog-Api-Key"], "fake-places-key");
    assert.ok(!c.url.includes("fake-places-key"));
  }
  assert.deepEqual(places[0], { placeId: "a", name: "Test Place a", address: "1 Fictional St, Testville", city: "Testville", latitude: 10, longitude: 20 });
  assert.deepEqual(places[1], { placeId: "gone", error: "not_found" });
  assert.deepEqual(places[2], { placeId: "down", error: "unavailable" });
});

test("the field mask stays basic: no ratings, photos, reviews or hours", () => {
  for (const f of ["rating", "photos", "reviews", "regularOpeningHours", "priceLevel"]) assert.ok(!FIELD_MASK.includes(f), f);
});

test("mapping: no name is unavailable; bad coordinates are dropped together", () => {
  assert.deepEqual(mapBasics({}, "x"), { placeId: "x", error: "unavailable" });
  const b = mapBasics({ displayName: { text: "N" }, location: { latitude: 200, longitude: 1 } }, "x");
  assert.equal((b as { latitude: unknown }).latitude, null);
  assert.equal((b as { longitude: unknown }).longitude, null);
});

test("city: locality, else postal town, else county", () => {
  assert.equal(cityOf([{ longText: "Testshire", types: ["administrative_area_level_2"] }, { longText: "Testford", types: ["postal_town"] }]), "Testford");
  assert.equal(cityOf([{ longText: "Testshire", types: ["administrative_area_level_2"] }]), "Testshire");
  assert.equal(cityOf(null), null);
});
