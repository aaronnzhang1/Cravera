# 0003 · API key handling

- **Status:** Accepted (maintainer, 2026-11-26)
- **Date:** 2026-11-26

## Context

`pubspec.yaml` lists `.env` as a Flutter asset, so every value in it ships inside the app, and anyone can unzip the APK/IPA and read it. A Gemini or Places key there could be used by anyone, and the usage would be billed to us. Places photo URLs also need the key.

## Decision

The app never holds Google or Gemini keys. It calls Supabase Edge Functions (for example `search-restaurants`, later `parse-craving`), which hold the keys as Supabase secrets and call Places and Gemini server-side. The app holds only the Supabase URL and anon key (Supabase now calls it the publishable key, `sb_publishable_…`), which are public by design: what they can reach is limited by RLS and by what the functions allow. Photos are fetched through the function too, or by a URL that doesn't contain the key.

## Alternatives

- **Keys in the app with platform restrictions** (Android package + SHA-1, iOS bundle ID): no backend work, but keys can still be extracted, and Gemini keys can't be restricted the same way. Rejected.

## Consequences

- Phase 1 needs a `supabase/functions/` folder, the Supabase CLI and a deploy step.
- Guest calls are unauthenticated, so the functions are callable by anyone with the anon key: add rate limiting before a public release (PRODUCT.md open decision 3).
- `.env` then holds only public values; keep it out of Git anyway.
