# TASK-001 · A guest gets a real open restaurant near them

**Goal.** Without an account, a user shares or types a location, types a craving, and sees one real restaurant from Google Places that is open now. Yes takes them to that exact place in maps; No shows another real one.

**Release:** v0.1.0 · Guest MVP ([PRODUCT.md](PRODUCT.md#releases)).
**Approved:** 2026-11-26 (maintainer). Claude may work any criterion below without asking again; anything outside this file's scope still needs approval.
**Review level:** L3. It adds a sensitive integration (API keys, Edge Functions) and the first backend code.

**Needs before starting:** a Google Cloud project with the Places API (New) enabled and a key; Supabase CLI access to deploy Edge Functions. Keys follow [ADR 0003](adr/0003-api-key-handling.md).

## Acceptance criteria

Tick a box only after checking it in the running app. Never delete or reword a criterion. Propose any change to the maintainer instead.

- [x] The sign-in screen offers "Continue as guest", which opens the home screen without an account.
- [ ] The app asks for location permission and searches around the device location. If permission is denied or location fails, the user can type a place or address and search around that.
- [x] A typed craving returns one real restaurant from Google Places that is open now and within the search radius. The craving text is the Places text query (Gemini parsing is TASK-002).
- [x] The card shows name, photo, cuisine, price, distance and address from Places. A missing field is hidden, never filled with demo data.
- [x] No shows the next result from the same search without a new request; when results run out, the user is told and asked to refine. The refine prompt runs a new search with the added text.
- [x] Yes opens directions to that exact place (place ID or coordinates), not a search by name.
- [x] No API key for Google or Gemini is in the app, `.env` or the built bundle; the app only calls the Edge Function with the Supabase URL and anon key.
- [ ] No results, no network and a failing function each show a clear message, and the user can try again.
- [x] `flutter analyze` and `flutter test` pass, with tests for the result parsing and the No/next logic (the network is faked).

## Out of scope

- Gemini craving parsing (TASK-002), manual filters wired to search, accounts, saving anything to the database, the Cravio → Cravera code rename, voice input.

## Demo and evidence

On an Android emulator with a mocked location: deny then allow location, search "ramen", reject twice, accept the third, confirm maps opens to that place. Record screenshots and the exact check output in the PR.
