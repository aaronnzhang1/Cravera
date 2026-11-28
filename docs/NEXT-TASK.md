# TASK-002 · Craving intelligence

**Goal.** The app understands what the guest is asking for, not just the words, and picks the open place that fits best. Nothing is hardcoded: no keyword tables, no canned answers. Gemini reads the craving and the candidates; Google Places stays the only source of restaurant facts (AGENTS.md).

**Release:** v0.1.0 · Guest MVP ([PRODUCT.md](PRODUCT.md#releases)). TASK-001 is done (all criteria checked in the app, 2026-11-26).
**Approved:** 2026-11-26 (maintainer), as specified in [the concierge plan](plans/v0.1-concierge.md#task-002--craving-intelligence-spec-for-approval): Gemini inside `places-search`, two Gemini calls per search (understand, then curate). Claude may work any criterion below without asking again; anything outside this file's scope still needs approval, including deploying the Edge Function.
**Review level:** L3. A new external AI integration fed with untrusted input.

## How it works

Inside `places-search`, still one call from the app:

1. **Understand.** Gemini turns the craving (plus the previous intent when refining, and the local time of day) into a validated JSON intent: `textQuery` (short and Places-friendly), an optional `includedType` from an allowed list, `priceLevels`, a distance hint ("quick" means nearer, capped by the existing radius limits), `wants` and `avoids`.
2. **Search.** Places Text Search (New) with that intent: always open now, inside the radius, restaurants only.
3. **Curate.** Gemini ranks the candidates against the intent, using only what Places returned, and returns an ordered list of place IDs. IDs it didn't receive are dropped; missing ones are appended in Places order. It never writes restaurant facts.
4. **Explain.** The card's "why this pick" line combines the intent's `wants` that the place matches with Places facts, never free text about the restaurant from the model.

## Acceptance criteria

Tick a box only after checking it in the running app. Never delete or reword a criterion. Propose any change to the maintainer instead.

- [x] "I just finished at the gym, I want something healthy and high protein but not too expensive and quick, something fast food like Chipotle" returns a fitting open place near the test location (healthy fast casual, $–$$), checked on the emulator.
- [x] Varied phrasings give sensible intents (for example "something warm for a rainy night", "cheap late-night tacos", "quiet date spot, not too pricey"), covered by recorded fixtures in tests and spot-checked live.
- [x] Refining from a result changes the intent instead of restarting: "cheaper" lowers the price, "no seafood" avoids seafood places.
- [x] Curation returns only place IDs from the Places answer; every field shown still comes from Places.
- [x] If Gemini fails, times out or returns invalid JSON, search still works with the raw text and Places order (tested).
- [x] Prompt-injection attempts in the craving can't change open-now, the radius cap, the data source or the output shape (tested).
- [x] The Gemini key exists only in Supabase secrets; the built app contains no key (APK scan).
- [x] `flutter analyze`, `flutter test` and the function tests pass, with tests for intent validation, curation validation and the fallback (network faked).

## Out of scope

- Reviews, embeddings, other data sources, voice, the redesign (TASK-UI-2).

## Cost

Two Gemini calls per search on a Flash-class model. Confirm the current model and its free tier when building. Places calls don't change.
