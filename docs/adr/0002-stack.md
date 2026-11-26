# 0002 · Stack

- **Status:** Accepted
- **Date:** 2026-11-26 (records choices made in April 2026)

## Decision

- **App:** Flutter, pinned to 3.41.9 stable (Dart 3.11.5) in CI. go_router for navigation, geolocator for location, url_launcher for maps.
- **Backend and database:** Supabase (Postgres, Auth, Edge Functions, RLS).
- **Craving parsing:** Gemini, chosen by the maintainer on 2026-11-26. It returns search filters only.
- **Restaurant data:** Google Places.

## Context

- Places: Yelp was considered but costs money; Google offered a monthly free credit. Check Google's current Places pricing before launch, because the free-credit model has changed over time.
- LLM: Claude and GPT were considered. Gemini has a free tier for the MVP, and the code was already scaffolded for it (`gemini_service.dart`). The role is narrow (text → JSON filters), so swapping providers later only touches one service.

## Consequences

Upgrading Flutter is a deliberate change: update CI and this record together.
