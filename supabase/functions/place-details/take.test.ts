// Run from the repo root: node --test supabase/functions/place-details/take.test.ts
// Fictional data only. Gemini is faked; nothing calls Google.
import { test } from "node:test";
import assert from "node:assert/strict";
import { checkFacts, checkTake, explain, orderReviews, parseTakeInput, templateTake } from "./take.ts";
import { handle, type Details } from "./logic.ts";

const details = (over: Partial<Details> = {}): Details => ({
  placeId: "fake-1",
  photos: [],
  reviews: [
    { authorName: "A", authorUri: null, authorPhotoUri: null, rating: 5, relativeTime: null, text: "Great broth", mapsUri: null },
    { authorName: "B", authorUri: null, authorPhotoUri: null, rating: 2, relativeTime: null, text: "Too salty", mapsUri: null },
  ],
  editorialSummary: "A fictional ramen spot.",
  reviewSummary: null,
  websiteUri: null,
  mapsUri: null,
  attributes: { takeout: false, delivery: true, dineIn: true },
  rating: 4.4,
  priceLevel: 2,
  typeName: "Ramen Restaurant",
  ...over,
});
const noRange = { craving: "cozy ramen", priceLevels: [] };
const cheap = { craving: "cheap ramen", priceLevels: [1, 2] };

test("facts: only supported references, worded by us, at most 3", () => {
  const d = details();
  assert.deepEqual(checkFacts(["dineIn", "rating"], d, noRange).map((f) => f.text), ["Dine-in", "Rated 4.4 on Google"]);
  // takeout false while delivery is true: no takeout item
  assert.deepEqual(checkFacts(["takeout"], d, noRange), []);
  // absent attribute, unknown field, review number, free text: all dropped
  assert.deepEqual(checkFacts(["outdoorSeating", "menu", 1, "Great broth", { field: "dineIn" }], d, noRange), []);
  // duplicates and the cap
  assert.equal(checkFacts(["dineIn", "dineIn", "delivery", "rating", "priceLevel"], d, cheap).length, 3);
  assert.equal(checkFacts("dineIn", d, noRange).length, 0);
});

test("facts: a price is a reason only inside a requested range", () => {
  const d = details();
  assert.deepEqual(checkFacts(["priceLevel"], d, noRange), []); // no range asked
  assert.deepEqual(checkFacts(["priceLevel"], d, { craving: null, priceLevels: [1] }), []); // outside
  assert.deepEqual(checkFacts(["priceLevel"], d, cheap).map((f) => f.text), ["Moderate ($$)"]);
  assert.deepEqual(checkFacts(["rating"], details({ rating: null }), noRange), []);
});

test("take: a clean note passes", () => {
  assert.equal(checkTake("  Cozy spot with rich broth.  You can eat in, which suits a slow night. "), "Cozy spot with rich broth. You can eat in, which suits a slow night.");
});

test("take: anything we can't check is dropped", () => {
  for (const bad of [
    "Rated 4.4 by guests.", // digit
    "Dinner is 20 for two.", // number copied from a craving
    "Dinner is twenty for two.", // number word
    "Ramen for under twenty.",
    "Great value at $$.", // currency sign
    "Mains are about fifteen dollars.", // price word
    "A cheap price for great ramen.",
    "Open late, so no rush.", // hours
    "It closes soon, go now.",
    "See https://example.com for the menu.", // link
    "Menu at example.com.",
    "A. B. C. D.", // too many sentences
    "x".repeat(281), // too long
    "",
    42,
    null,
  ]) {
    assert.equal(checkTake(bad), null, String(bad));
  }
});

test("template take: checked fields only, no numbers, prices or hours, and no claim of a fit", () => {
  const t = templateTake(details(), noRange);
  assert.equal(t, "Here's a ramen restaurant where you can eat in. Have a look at what Google and its reviewers say below.");
  assert.equal(checkTake(t), t);
  assert.ok(!/fit|craving/i.test(t));
  // the craving never reaches the template (it could carry a number)
  assert.ok(!/\d/.test(templateTake(details(), { craving: "ramen under 20", priceLevels: [] })));
  // nothing known: still safe
  assert.equal(templateTake(details({ typeName: null, attributes: {} }), { craving: null, priceLevels: [] }), "Here's a place. Have a look at what Google and its reviewers say below.");
  // a type name that breaks the rules is left out
  assert.equal(templateTake(details({ typeName: "Open 24 Hours Diner", attributes: {} }), noRange), "Here's what Google and its reviewers say about this place.");
});

test("review order: only numbers we sent; the rest keep Google's order", () => {
  assert.deepEqual(orderReviews(["a", "b", "c"], [3, 3, 9, 0, "1", 2.5]), ["c", "a", "b"]);
  assert.deepEqual(orderReviews(["a", "b"], null), ["a", "b"]);
});

test("input: craving and price levels are optional and checked", () => {
  assert.deepEqual(parseTakeInput({ craving: "  tacos ", priceLevels: [1, 1, 5, "2", 2] }), { craving: "tacos", priceLevels: [1, 2] });
  assert.deepEqual(parseTakeInput({ craving: "x".repeat(201) }), { craving: null, priceLevels: [] });
  assert.deepEqual(parseTakeInput(null), { craving: null, priceLevels: [] });
});

function geminiAnswer(payload: unknown) {
  return new Response(JSON.stringify({
    status: "completed",
    steps: [{ type: "model_output", content: [{ type: "text", text: JSON.stringify(payload) }] }],
  }));
}

test("explain: a checked Gemini answer is used; a bad take falls back to the template", async () => {
  const good = { key: "fake-gemini", model: "gemini-3.5-flash-lite", fetchFn: async () => geminiAnswer({ take: "Rich broth and a cozy room.", facts: ["dineIn", "takeout"], reviewOrder: [2] }) };
  const r = await explain(good, details(), noRange, 5000);
  assert.deepEqual(r.take, { text: "Rich broth and a cozy room.", source: "ai" });
  assert.deepEqual(r.why.map((f) => f.field), ["dineIn"]);

  const bad = { ...good, fetchFn: async () => geminiAnswer({ take: "Open till midnight, mains 15.", facts: [], reviewOrder: [] }) };
  assert.equal((await explain(bad, details(), noRange, 5000)).take.source, "template");

  const down = { ...good, fetchFn: async () => new Response("", { status: 503 }) };
  const f = await explain(down, details(), noRange, 5000);
  assert.equal(f.take.source, "template");
  assert.deepEqual(f.why, []);

  // no time left: Gemini isn't called
  let called = false;
  await explain({ ...good, fetchFn: async () => { called = true; return geminiAnswer({}); } }, details(), noRange, 100);
  assert.equal(called, false);
});

test("handle: the craving is never logged", async () => {
  const logged: unknown[] = [];
  const orig = console.error;
  console.error = (...a: unknown[]) => logged.push(...a);
  try {
    const fetchFn = async (url: string) =>
      url.includes("places.googleapis.com") ? new Response(JSON.stringify({ id: "fake-1" })) : new Response("", { status: 500 });
    const res = await handle(
      new Request("http://localhost/place-details", {
        method: "POST",
        headers: { "Content-Type": "application/json", apikey: "k" },
        body: JSON.stringify({ placeId: "fake-1", craving: "secret fictional craving" }),
      }),
      { placesKey: "p", publishableKeys: "k", geminiKey: "g" },
      fetchFn,
    );
    assert.equal(res.status, 200);
    assert.equal((await res.json()).take.source, "template");
  } finally {
    console.error = orig;
  }
  assert.ok(!logged.some((v) => String(v).includes("secret")));
});
