# Plan: search that finds the right kind of place (search rework)

Status: **ideas for the maintainer, not approved for building.** Asked for on 2026-11-27 ("in the future, what are some ways we can implement a structure to how it can intelligently find stuff, and safeguards not just for gemini but any other ai API"). Turn into a task spec (new ID) when the maintainer picks it up. Delete after that task merges.

## What goes wrong today

- **"thai food" returns non-Thai places.** `places-search` sends Gemini's text to Google Text Search with `includedType: "restaurant"` only (`logic.ts` `buildRequestBody`). Text Search matches the words anywhere Google indexes them (menus, reviews, names), so a burger place that mentions "Thai tea" can rank. Gemini's cuisine type only steers curation; nothing in code checks it.
- **"like Dave's" loses the brand** (CURRENT.md, Search quality): the intent drops it, and one search of 20 places is too thin to recover.

## A structure for finding things: understand → retrieve → verify → rank → explain

Each step has one job, and only the first and fourth use AI. Code owns every rule that must hold.

1. **Understand (AI).** Craving → a structured intent: cuisine as a Places type (`thai_restaurant`), dishes ("pad see ew"), must-haves (takeout, vegetarian), price range, distance, references ("like Dave's Hot Chicken" → "Nashville hot chicken, fast casual"), exclusions ("not Dave's"). Validated against allow-lists, as today.
2. **Retrieve (code).** Build Places requests from the intent, not from free text:
   - A named cuisine becomes `includedType` with `strictTypeFiltering: true`, so only real Thai restaurants come back. If that finds nothing open, one relaxed search runs and the card says so ("No Thai place is open nearby; here's the closest match"), like the Cheaper retry in TASK-005.
   - A dish or reference becomes a second, text query; results are merged and de-duplicated by place ID.
   - Exclusions ("not Dave's") are dropped in code by name or place ID.
3. **Verify (code).** Every candidate is checked against the intent's hard rules using Places fields: cuisine type in `types`, takeout/vegetarian from attributes, price inside the range, open now, inside the radius. Failing candidates never reach ranking.
4. **Rank (AI, optional).** The model orders only verified candidate refs (as `curate` does today). If it fails, a deterministic score orders them (type match, distance, rating, price fit).
5. **Explain (AI, checked).** Cravera's take and checked facts on the card (ADR 0005, done in TASK-UI-4).

**Measure it.** A golden set of real cravings (start from `recorded-intents.json`) with assertions a test can check: "thai food" → every result has `thai_restaurant`; "not Dave's" → no Dave's; "cheap tacos" → price ≤ $$. Run it before and after every search change (it spends Places quota, so run it by hand, a few cravings at a time).

**Cost.** Two queries per search doubles Text Search use; keep the second query only for dishes and references, and cache intents for repeated cravings.

## Safeguards for any AI provider (Gemini today, others later)

1. **One provider interface on the server.** `understand`, `rank`, `explain` behind a small interface in the Edge Functions, one adapter per provider (Gemini, Claude, OpenAI). The model and provider come from Supabase secrets. The app never calls an AI API and never holds its key (ADR 0003).
2. **Structured output only, validated in code.** Every call asks for JSON against a schema; every answer is re-validated in our code (allow-lists, references to what we sent, lengths, the take's word checks). The same validators run whatever the provider, so switching providers can't loosen a rule.
3. **The AI decides, code enforces.** Open-now, radius, cuisine type, exclusions, price range and every fact shown are set or checked in code. A model can reorder or pick; it can't add a place or a fact.
4. **Treat all text as data.** Cravings, place names and reviews go in as data; no tools, no links followed, no output executed. Prompt-injection in a review can at worst produce an answer that fails validation.
5. **Budgets and fallbacks.** A timeout per call, a total request budget, at most one retry, and a deterministic path when the AI is down or slow (already true for search and the take). A kill switch secret turns AI off entirely.
6. **Privacy by default.** Send the minimum: no user ID, no account data, coarse location only (CURRENT.md privacy item), `store: false` where the API offers it, no content in logs. Before switching providers or leaving test, check the provider's data-use terms (paid tiers usually don't train on inputs).
7. **Cost limits.** Server-side rate limit per caller, provider quotas, and a budget alert; the same limits apply to every provider.
8. **Same tests for every provider.** The function tests fake the provider; the golden set runs against the real one. A new provider ships only after it passes the golden set and the validators' denial tests.

## Suggested order

1. Strict cuisine type with the relaxed retry and an honest message (fixes "thai food"; small, one function).
2. Verify step in code with Places fields (needs a few more search fields; check the SKU cost).
3. Provider interface and kill switch (a refactor of `gemini.ts`, no behavior change).
4. References and exclusions ("like Dave's", "not Dave's"), second query, golden set.
