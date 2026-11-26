// Run from the repo root: node --test supabase/functions/places-search/logic.test.ts
// Fictional data only. The network is faked; nothing calls Google.
import { test } from "node:test";
import assert from "node:assert/strict";
import {
  buildRequestBody,
  DEFAULT_RADIUS_M,
  handle,
  mapPlaces,
  MAX_RADIUS_M,
  parseInput,
  parsePublishableKeys,
} from "./logic.ts";

const KEY = "sb_publishable_test_key";
const env = { placesKey: "fake-places-key", publishableKeys: JSON.stringify({ default: KEY }) };
const here = { latitude: 37.0, longitude: -122.0 };
const input = { query: "ramen", ...here, radiusMeters: 5000 };

function place(overrides: Record<string, unknown> = {}) {
  return {
    id: "fake-place-1",
    displayName: { text: "Test Noodle House" },
    formattedAddress: "1 Example St, Testville",
    location: { latitude: 37.001, longitude: -122.001 },
    priceLevel: "PRICE_LEVEL_MODERATE",
    rating: 4.4,
    primaryTypeDisplayName: { text: "Ramen Restaurant" },
    photos: [{ name: "places/fake-place-1/photos/abc" }],
    currentOpeningHours: { openNow: true },
    ...overrides,
  };
}

function request(body: unknown, headers: Record<string, string> = { apikey: KEY }, method = "POST") {
  return new Request("http://localhost/places-search", {
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
  throw new Error("Places must not be called");
};

// --- access ---

test("rejects a request with no apikey and never calls Places", async () => {
  const res = await handle(request({ query: "ramen", ...here }, {}), env, neverCalled);
  assert.equal(res.status, 401);
});

test("rejects a wrong apikey", async () => {
  const res = await handle(request({ query: "ramen", ...here }, { apikey: "sb_publishable_other" }), env, neverCalled);
  assert.equal(res.status, 401);
});

test("fails closed when no publishable keys are configured", async () => {
  const res = await handle(request({ query: "ramen", ...here }), { ...env, publishableKeys: undefined }, neverCalled);
  assert.equal(res.status, 401);
});

test("rejects non-POST", async () => {
  const res = await handle(request(null, { apikey: KEY }, "GET"), env, neverCalled);
  assert.equal(res.status, 405);
});

test("returns 500 without calling Places when the Places key is missing", async () => {
  const res = await handle(request({ query: "ramen", ...here }), { ...env, placesKey: undefined }, neverCalled);
  assert.equal(res.status, 500);
});

test("parses publishable keys as object, array or plain string", () => {
  assert.deepEqual(parsePublishableKeys('{"default":"a","other":"b"}'), ["a", "b"]);
  assert.deepEqual(parsePublishableKeys('["a"]'), ["a"]);
  assert.deepEqual(parsePublishableKeys("a, b"), ["a", "b"]);
  assert.deepEqual(parsePublishableKeys(undefined), []);
});

// --- input ---

test("validates query and coordinates", () => {
  assert.equal(typeof parseInput({ query: "  ", ...here }), "string");
  assert.equal(typeof parseInput({ query: "x".repeat(201), ...here }), "string");
  assert.equal(typeof parseInput({ query: "ramen", latitude: 91, longitude: 0 }), "string");
  assert.equal(typeof parseInput({ query: "ramen", latitude: "37", longitude: 0 }), "string");
  assert.equal(typeof parseInput(null), "string");
});

test("defaults and clamps the radius", () => {
  assert.equal((parseInput({ query: "ramen", ...here }) as { radiusMeters: number }).radiusMeters, DEFAULT_RADIUS_M);
  assert.equal(
    (parseInput({ query: "ramen", ...here, radiusMeters: 1e9 }) as { radiusMeters: number }).radiusMeters,
    MAX_RADIUS_M,
  );
});

test("a bad body is a 400 and never calls Places", async () => {
  const res = await handle(request({ query: "", ...here }), env, neverCalled);
  assert.equal(res.status, 400);
});

// --- request to Places ---

test("always asks Places for open-now restaurants inside a box around the user", () => {
  const body = buildRequestBody(input);
  assert.equal(body.openNow, true);
  assert.equal(body.includedType, "restaurant");
  assert.equal(body.textQuery, "ramen");
  const { low, high } = body.locationRestriction.rectangle;
  assert.ok(low.latitude < 37 && high.latitude > 37);
  assert.ok(low.longitude < -122 && high.longitude > -122);
});

test("sends the Places key only in the header to Google", async () => {
  const { fn, calls } = fakeFetch(new Response(JSON.stringify({ places: [place()] })));
  const res = await handle(request({ query: "ramen", ...here }), env, fn);
  assert.equal(res.status, 200);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].url, "https://places.googleapis.com/v1/places:searchText");
  assert.equal((calls[0].init.headers as Record<string, string>)["X-Goog-Api-Key"], "fake-places-key");
  assert.ok(!(await res.clone().text()).includes("fake-places-key"));
});

// --- results ---

test("maps a Places result to card data", () => {
  const [r] = mapPlaces({ places: [place()] }, input);
  assert.equal(r.placeId, "fake-place-1");
  assert.equal(r.name, "Test Noodle House");
  assert.equal(r.cuisine, "Ramen Restaurant");
  assert.equal(r.priceLevel, 2);
  assert.equal(r.rating, 4.4);
  assert.equal(r.photoName, "places/fake-place-1/photos/abc");
  assert.ok(r.distanceMeters > 100 && r.distanceMeters < 200);
});

test("drops closed places and places with unknown open status", () => {
  const results = mapPlaces({
    places: [
      place({ id: "closed", currentOpeningHours: { openNow: false } }),
      place({ id: "unknown", currentOpeningHours: undefined }),
      place({ id: "open" }),
    ],
  }, input);
  assert.deepEqual(results.map((r) => r.placeId), ["open"]);
});

test("drops places outside the search circle (box corners)", () => {
  const corner = place({ id: "far", location: { latitude: 37.04, longitude: -122.05 } });
  assert.deepEqual(mapPlaces({ places: [corner] }, input), []);
});

test("missing optional fields become null, never demo data", () => {
  const [r] = mapPlaces({
    places: [place({ formattedAddress: undefined, priceLevel: undefined, rating: undefined, photos: undefined, primaryTypeDisplayName: undefined })],
  }, input);
  assert.equal(r.address, null);
  assert.equal(r.priceLevel, null);
  assert.equal(r.rating, null);
  assert.equal(r.photoName, null);
  assert.equal(r.cuisine, null);
});

test("no places is an empty list, not an error", async () => {
  const { fn } = fakeFetch(new Response("{}"));
  const res = await handle(request({ query: "ramen", ...here }), env, fn);
  assert.equal(res.status, 200);
  assert.deepEqual(await res.json(), { results: [] });
});

// --- failures ---

test("a Places error is a 502 that doesn't echo the upstream body", async () => {
  const { fn } = fakeFetch(new Response('{"error":"API key fake-places-key invalid"}', { status: 403 }));
  const res = await handle(request({ query: "ramen", ...here }), env, fn);
  assert.equal(res.status, 502);
  assert.ok(!(await res.text()).includes("fake-places-key"));
});

test("a network failure is a 502", async () => {
  const { fn } = fakeFetch(new Error("offline"));
  const res = await handle(request({ query: "ramen", ...here }), env, fn);
  assert.equal(res.status, 502);
});
