# Product

Cravera removes food indecision. A guest tells the app what they're craving in plain language and gets **one** nearby restaurant that is open now, instead of working through clunky filters. Over time, bookmarks and ratings teach it the user's taste.

Sources merged here: the original Notion "Project Hub" (`Project - AI Food Concierge.pdf`), `Project-Overview.md`, the HTML prototype, and `mobile/Cravera/cursorrules`, all kept outside the repo in `C:\Developer\Cravera Docs` except the last. This file is now the single home for scope and roadmap.

## Core loop (Phase 1)

1. Location: the device's current location by default, or a location the user types.
2. The user types a craving (voice later).
3. Gemini turns it into search filters only. Google Places finds a restaurant that is **open now** (see AGENTS.md).
4. The card shows the name, photo, cuisine, price ($–$$$$), distance and address when available, plus a link to the restaurant page.
5. **Yes** opens directions (Google Maps, or Apple Maps on iOS).
6. **No** shows another pick, or lets the user refine the craving. If refinement still doesn't satisfy them, the manual filter panel (cuisine, price, distance) is the fallback.

Distance matters a lot to users: offer presets such as 0.5 / 1 / 3 / 10 mi, or walk / short drive / far drive.

## Out of scope until its phase

Accounts before Phase 1.5; anything stored in the database before Phase 1.5/2; social features before Phase 3.

## Roadmap

Status as of 2026-11-26 (audit evidence in docs/CURRENT.md). "UI only" means screens exist on demo data with no backend.

| Phase | Delivers | Status |
|---|---|---|
| Prephase | Wireframes, design system: cool near-black theme, violet accent, sage secondary, soft white text; Fraunces headings, Outfit text. Colors live only in `lib/core/app_colors.dart` | Done (rehauled 2026-11-26; orange replaced by violet + sage at the maintainer's request) |
| **1 · Guest MVP** | Guest mode, location (current + manual), craving (typed or a quick-pick chip) → Gemini filters → Places (open now), result card, Yes → maps, No → next/refine | UI only: 4 hardcoded demo restaurants, all services are stubs |
| 1.5 · Accounts | Supabase sign up/sign in, profiles, security hardening | UI only: sign-in accepts anything, nothing persisted |
| 2 · Bookmarks & preferences | Bookmarks saved to the DB, 1–5 ratings, preference memory feeding the AI, working manual filters | UI only: bookmarks/ratings in memory; filter sheet discards its values |
| 2.5 · Hardening | UI rehaul, test cases, RLS, API key handling, input validation, bug fixes, privacy and data-storage review | Not started |
| 3 · Social | Friends (search by username, request/accept/decline/remove, mutual only), view friends' bookmarks read-only and copy to your own, "Send to friend" recs, recs inbox with Save/Dismiss and a badge on the bell (bottom sheet, not an iframe) | Placeholder screens only |
| 4 · Beta | Friends-and-family testing, a website to collect feedback | Not started |
| Final | App Store / Play Store release | Not started |

## Releases

A release ships when its tasks are merged, its exit criteria are checked on `main`, and the maintainer tags it (see [CONTRIBUTING.md](../CONTRIBUTING.md#releases)). Task IDs match NEXT-TASK.md, branch names (`feat/task-NNN-…`) and PR titles (`TASK-NNN: …`).

| Release | Tasks | Exit criteria | Status |
|---|---|---|---|
| v0.1.0 · Guest MVP (Phase 1) | TASK-001 guest search on Places; TASK-UI-1 UI rehaul and Cravera rename; TASK-002 Gemini craving parsing | On an Android emulator and an iPhone: a guest types a craving and gets a real open place nearby; No/refine work; Yes opens directions to that exact place; no Google or Gemini key in the app bundle | In progress |
| v0.2.0 · Accounts (Phase 1.5) | not yet specified | Supabase sign-up/sign-in; RLS denial-path tests | Not started |

## Idea backlog (unscheduled)

Ideas captured in the planning docs that no phase owns yet. Promote one by giving it a phase here.

| Idea | Source | Notes |
|---|---|---|
| Trending Spots Hub: a page of newly opened/trending places within a user-set radius | Project-Overview.md | TikTok has no free API and scraping may break its ToS; compare TikTok Research/Display API, Google Places, Yelp, Instagram. Likely after Phase 2. Refresh by scheduled Supabase job or on open |
| Deals: tell the user about Groupon or delivery-app discounts for the chosen restaurant | PDF p.4, cursorrules | Nice-to-have |
| See how friends ranked places they went to | PDF p.4 | Extends Phase 3 shared bookmarks with ratings |
| Dietary preferences screen | HTML prototype | Could feed Phase 2 preference memory |
| Notification settings and location settings screens | HTML prototype, Profile screen | Location settings row exists with no action |
| Home background cards show real, well-reviewed places near the user, not just any place with a 5-star rating | Maintainer, 2026-11-26 | Needs TASK-001's Places search. Take them from Places only (open now, near the search location) and filter for quality: proposed rating ≥ 4.5 **and** at least ~200 reviews, so a 5.0 from three reviews never shows. Until then the cards show cuisines only |
| Voice input | PDF, home screen mic button ("coming soon") | |
| Call the restaurant / share from the navigate screen | navigate_screen.dart ("coming soon") | |

## Open decisions

| # | Decision | Needed by |
|---|---|---|
| 3 | Guest search abuse protection (rate limiting on the Edge Functions) | Before Phase 4 |
| 4 | Data source for the Trending Spots Hub | If it's scheduled |
