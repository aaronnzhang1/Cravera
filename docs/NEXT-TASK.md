# TASK-UI-4 · Smart restaurant card

**Goal.** The pick opens into a detail page that tells the guest about the place and why Cravera picked it, so the app is more than search-and-display. Everything shown comes from Google Places; for "Why this pick" Gemini only chooses which Places fields to show, by reference, and the server words them ([ADR 0005](adr/0005-traceable-ai-summaries.md)). Background and the maintainer's words: [the smart card plan](plans/v0.3-smart-card.md).

**Release:** moved ahead of TASK-004 by the maintainer (2026-11-27: "move onto the next part first"). TASK-UI-3 is merged (#35); its criterion 6 (tab slide) is unit-tested but not yet checked in the app (see CURRENT.md).
**Approved:** 2026-11-27 (maintainer: "approve"); the "Why this pick" criterion and its tests were then tightened after Codex's adversarial review of PR #39 (evidence checked in code, no Gemini wording on screen), for the maintainer to confirm on the PR. Claude may work any criterion below without asking again; anything outside this file's scope still needs approval.
**Review level:** L3: new Places data and SKUs, a new Gemini call fed with review text, Google attribution rules, a new Edge Function path.

## Acceptance criteria

Tick a box only after checking it in the running app. Never delete or reword a criterion. Propose any change to the maintainer instead.

- [x] Before `place-details` is first deployed, a daily quota on Place Details is set in Google Cloud (maintainer) and the deploy is recorded with it.
- [x] Tapping the pick opens a scrollable detail page. Details load only then, with one Places Details request through an Edge Function (key server-side); search makes no extra Places calls and keeps its 11 s budget.
- [ ] Photo gallery: up to 5 Places photos, each fetched only as the guest swipes to it, each with its author attribution; a place with no photos shows the placeholder.
- [ ] Up to 5 Places reviews, each with author name, photo, rating, relative time and a link (Google's attribution rules), plus Google's `editorialSummary` and review summary when Places has them.
- [ ] Attributes from Places only (for example takeout, delivery, dine-in, vegetarian, outdoor seating, good for groups, beer/wine); an attribute Places doesn't report is not shown.
- [ ] Menu and more: buttons to the restaurant's `websiteUri` (when present) and its Google Maps page; Places has no menu items, so none are shown.
- [ ] "Why this pick": up to 3 items. Gemini, given only the craving and that place's Places fields and reviews, returns only references to Places field names from a fixed list (and, separately, review numbers to order the reviews section). The function checks each field in code (attribute `true`, rating present, price inside the search's price range), ignores anything else in the answer, and drops the rest; the screen shows the server's wording for that field, never Gemini's text and never a review as a reason. If Gemini fails or nothing survives, the page shows today's Places-only reasons (Budget-friendly, Close by, Highly rated), with Budget-friendly only when the price is inside the originally requested range (also after a relaxed retry).
- [ ] Failure paths: a details request that fails or times out shows the card's existing facts with a "Couldn't load more about this place" message and Try again; No and Yes keep working from the detail page.
- [ ] Function tests for the evidence check (including denial cases: a review number given as a reason, a true price outside the requested price range, a review number not in the input (ordering ignores it), an attribute that is `false` or absent (`takeout` false while `delivery` is true shows no takeout item), a field name not on the list, and an answer carrying a claim label or free text next to a valid reference producing only that reference's own item), the fallback and input validation (place ID format, publishable-key check, no logging of the craving or place); `flutter analyze` and `flutter test` pass, with widget tests for the loaded, partial (no photos/reviews) and failed states, and the accessibility guidelines at 1x and 2x text.
- [ ] Checked in the app on Android and iPhone: a real craving → pick → detail page with photos, reviews and cited claims; key scan of the built app finds no Google key.

## Checked

- 2026-11-27 ~21:25 PST, `Pixel_10_Pro`, San Francisco: the maintainer set the Place Details daily quota, then `place-details` was deployed. "Cozy ramen nearby" → Nojo Ramen Tavern; search made no details call; "More about this place" loaded Google's description in place (the pick becomes the longer, scrolling page; No/Yes stay in the footer); No → next place with details closed.

## Out of scope

- Menu items or dishes (Places has none), using reviews in search ranking (the search rework), saving reviews, the paid Gemini tier switch (a release gate, not this task).
