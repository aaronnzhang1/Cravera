// Run from the repo root: node --test supabase/functions/place-details/logic.test.ts
// Fictional data only. The network is faked; nothing calls Google.
import { test } from "node:test";
import assert from "node:assert/strict";
import { cleanText, FIELD_MASK, handle, mapDetails, MAX_PHOTOS, MAX_REVIEWS, webUrl } from "./logic.ts";

const KEY = "sb_publishable_test_key";
const env = { placesKey: "fake-places-key", publishableKeys: JSON.stringify({ default: KEY }) };
const PLACE = "fake-place_1";

function request(body: unknown, headers: Record<string, string> = { apikey: KEY }, method = "POST") {
  return new Request("http://localhost/place-details", {
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

const author = { displayName: "Test Author", uri: "https://maps.google.com/contrib/1", photoUri: "//lh3.googleusercontent.com/a/x" };

const sample = {
  id: PLACE,
  photos: Array.from({ length: 7 }, (_, i) => ({
    name: `places/${PLACE}/photos/p${i}`,
    authorAttributions: [author],
    googleMapsUri: "https://www.google.com/maps/photo",
  })),
  reviews: Array.from({ length: 6 }, (_, i) => ({
    rating: 4,
    relativePublishTimeDescription: "a week ago",
    text: { text: `Fictional review ${i}`, languageCode: "en" },
    authorAttribution: author,
    googleMapsUri: "https://www.google.com/maps/reviews/1",
  })),
  editorialSummary: { text: "A fictional chicken spot." },
  reviewSummary: { text: { text: "People like the fries." }, disclosureText: { text: "Summarized with Gemini" } },
  websiteUri: "http://example.com/menu",
  googleMapsUri: "https://maps.google.com/?cid=1",
  takeout: true,
  delivery: false,
  servesBeer: "yes",
};

test("needs POST and a known publishable key, before any Google call", async () => {
  assert.equal((await handle(request({}, {}, "GET"), env, neverCalled)).status, 405);
  assert.equal((await handle(request({ placeId: PLACE }, {}), env, neverCalled)).status, 401);
  assert.equal((await handle(request({ placeId: PLACE }, { apikey: "other" }), env, neverCalled)).status, 401);
});

test("rejects anything that isn't a place ID, so no other Google path is reachable", async () => {
  for (const placeId of [undefined, "", 5, "a/b", "../places:searchText", "x".repeat(301), "id?key=1"]) {
    const res = await handle(request({ placeId }), env, neverCalled);
    assert.equal(res.status, 400, String(placeId));
  }
});

test("fails closed without the Places key", async () => {
  const res = await handle(request({ placeId: PLACE }), { ...env, placesKey: undefined }, neverCalled);
  assert.equal(res.status, 500);
});

test("asks Google for one place with a field mask and the key in a header", async () => {
  const { fn, calls } = fakeFetch(new Response(JSON.stringify(sample)));
  const res = await handle(request({ placeId: PLACE }), env, fn);
  assert.equal(res.status, 200);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].url, `https://places.googleapis.com/v1/places/${PLACE}`);
  const headers = calls[0].init.headers as Record<string, string>;
  assert.equal(headers["X-Goog-Api-Key"], "fake-places-key");
  assert.equal(headers["X-Goog-FieldMask"], FIELD_MASK);
  assert.ok(!calls[0].url.includes("fake-places-key"));
  const body = await res.text();
  assert.ok(!body.includes("fake-places-key"));
  // No Gemini key here: the template take, no extra facts.
  const answer = JSON.parse(body);
  assert.equal(answer.take.source, "template");
  assert.deepEqual(answer.why, []);
});

test("maps Google's failures to 502 or 404 and logs no place ID", async () => {
  const logged: unknown[] = [];
  const orig = console.error;
  console.error = (...a: unknown[]) => logged.push(...a);
  try {
    assert.equal((await handle(request({ placeId: PLACE }), env, fakeFetch(new Error("x")).fn)).status, 502);
    assert.equal((await handle(request({ placeId: PLACE }), env, fakeFetch(new Response("", { status: 500 })).fn)).status, 502);
    assert.equal((await handle(request({ placeId: PLACE }), env, fakeFetch(new Response("not json")).fn)).status, 502);
    assert.equal((await handle(request({ placeId: PLACE }), env, fakeFetch(new Response("", { status: 404 })).fn)).status, 404);
  } finally {
    console.error = orig;
  }
  assert.ok(!logged.some((v) => String(v).includes(PLACE)));
});

test("caps photos and reviews, keeps attribution, and passes only Places facts", () => {
  const d = mapDetails(sample, PLACE);
  assert.equal(d.photos.length, MAX_PHOTOS);
  assert.equal(d.reviews.length, MAX_REVIEWS);
  assert.deepEqual(d.photos[0].authors[0], { name: "Test Author", uri: author.uri, avatarUri: "https://lh3.googleusercontent.com/a/x" });
  assert.equal(d.reviews[0].authorName, "Test Author");
  assert.equal(d.reviews[0].rating, 4);
  assert.equal(d.reviews[0].relativeTime, "a week ago");
  assert.equal(d.editorialSummary, "A fictional chicken spot.");
  assert.deepEqual(d.reviewSummary, { text: "People like the fries.", disclosure: "Summarized with Gemini" });
  assert.equal(d.websiteUri, "http://example.com/menu");
  // Only booleans Places reported: "yes" is dropped, missing ones are absent.
  assert.deepEqual(d.attributes, { takeout: true, delivery: false });
});

test("drops unsafe or unattributed items instead of guessing", () => {
  const d = mapDetails({
    photos: [
      { name: "places/x/photos/1" },
      { name: "https://evil.example/p", authorAttributions: [author] },
    ],
    reviews: [
      { text: { text: "no author" } },
      { authorAttribution: { displayName: "A", uri: "javascript:alert(1)", photoUri: "https://evil.example/a.png" }, text: { text: "ok" }, rating: 9 },
    ],
    websiteUri: "javascript:alert(1)",
    googleMapsUri: "https://evil.example/maps",
  }, PLACE);
  assert.equal(d.photos.length, 0);
  assert.equal(d.reviews.length, 1);
  assert.equal(d.reviews[0].authorUri, null);
  assert.equal(d.reviews[0].authorPhotoUri, null);
  assert.equal(d.reviews[0].rating, null);
  assert.equal(d.websiteUri, null);
  assert.equal(d.mapsUri, null);
  assert.equal(d.editorialSummary, null);
  assert.equal(d.reviewSummary, null);
});

test("an empty answer is a valid, empty card", () => {
  const d = mapDetails({}, PLACE);
  assert.deepEqual(d, {
    placeId: PLACE, photos: [], reviews: [], editorialSummary: null, reviewSummary: null,
    websiteUri: null, mapsUri: null, attributes: {}, rating: null, priceLevel: null, typeName: null,
  });
});

test("text helpers trim, cap and reject non-web links", () => {
  assert.equal(cleanText("  hi  "), "hi");
  assert.equal(cleanText("   "), null);
  assert.equal(cleanText("abcdef", 4), "abc…");
  assert.equal(webUrl("ftp://x"), null);
  assert.equal(webUrl("https://example.com"), "https://example.com/");
});

test("reviews are kept whole, never cut", () => {
  const long = "Fictional opening. ".repeat(120) + "But not for vegans.";
  const d = mapDetails({ reviews: [{ authorAttribution: { displayName: "A" }, text: { text: long } }] }, PLACE);
  assert.equal(d.reviews[0].text, long.trim());
});
