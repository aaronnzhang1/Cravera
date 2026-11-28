# TASK-UI-4 · Smart restaurant card

**Goal.** The pick opens into a detail page that tells the guest about the place and why Cravera picked it, so the app is more than search-and-display. Everything shown comes from Google Places; Gemini only writes the cited "Why this pick" claims ([ADR 0005](adr/0005-traceable-ai-summaries.md)). Background and the maintainer's words: [the smart card plan](plans/v0.3-smart-card.md).

**Release:** moved ahead of TASK-004 by the maintainer (2026-11-27: "move onto the next part first"). TASK-UI-3 is merged (#35); its criterion 6 (tab slide) is unit-tested but not yet checked in the app (see CURRENT.md).
**Approved:** 2026-11-27 (maintainer: "approve"), as written. Claude may work any criterion below without asking again; anything outside this file's scope still needs approval.
**Review level:** L3: new Places data and SKUs, a new Gemini call fed with review text, Google attribution rules, a new Edge Function path.

## Acceptance criteria

Tick a box only after checking it in the running app. Never delete or reword a criterion. Propose any change to the maintainer instead.

- [ ] Tapping the pick opens a scrollable detail page. Details load only then, with one Places Details request through an Edge Function (key server-side); search makes no extra Places calls and keeps its 11 s budget.
- [ ] Photo gallery: up to 5 Places photos, each fetched only as the guest swipes to it, each with its author attribution; a place with no photos shows the placeholder.
- [ ] Up to 5 Places reviews, each with author name, photo, rating, relative time and a link (Google's attribution rules), plus Google's `editorialSummary` and review summary when Places has them.
- [ ] Attributes from Places only (for example takeout, delivery, dine-in, vegetarian, outdoor seating, good for groups, beer/wine); an attribute Places doesn't report is not shown.
- [ ] Menu and more: buttons to the restaurant's `websiteUri` (when present) and its Google Maps page; Places has no menu items, so none are shown.
- [ ] "Why this pick": up to 3 short claims from Gemini, given only the craving and that place's Places fields and reviews. Each claim cites its source field or review; the function drops any claim whose citation is missing or not in the input. If Gemini fails or nothing survives, the page shows today's Places-only reasons (Budget-friendly, Close by, Highly rated).
- [ ] Failure paths: a details request that fails or times out shows the card's existing facts with a "Couldn't load more about this place" message and Try again; No and Yes keep working from the detail page.
- [ ] Function tests for the citation check, the fallback and input validation (place ID format, publishable-key check, no logging of the craving or place); `flutter analyze` and `flutter test` pass, with widget tests for the loaded, partial (no photos/reviews) and failed states, and the accessibility guidelines at 1x and 2x text.
- [ ] Checked in the app on Android and iPhone: a real craving → pick → detail page with photos, reviews and cited claims; key scan of the built app finds no Google key.

## Out of scope

- Menu items or dishes (Places has none), using reviews in search ranking (the search rework), saving reviews, the paid Gemini tier switch (a release gate, not this task).
