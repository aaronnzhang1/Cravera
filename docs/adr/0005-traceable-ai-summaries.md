# 0005 · Traceable AI summaries on the card

- **Status:** Accepted (maintainer, 2026-11-27)
- **Date:** 2026-11-27

## Context

ADR 0002 and AGENTS.md let Gemini only turn a craving into search filters and reorder Places results. The smart restaurant card (TASK-UI-4) wants a "Why this pick" that explains, in sentences, how a place matches the craving. Those sentences are about a restaurant, so they come close to "the LLM produces restaurant data", which the rule forbids because a model can invent facts (a dish, an hour, a price) that the guest then trusts.

## Decision

Gemini may write short "Why this pick" claims, only from Google Places facts and reviews that the server passes to it for that place. Each claim must cite the Places field or review it came from. The Edge Function checks every citation in code and drops any claim whose source is missing or wasn't in the input. If Gemini fails, or no claim survives, the card shows the Places-only reasons (Budget-friendly, Close by, Highly rated). Everything else on the card (name, photos, address, price, hours, distance, attributes, review text) still comes straight from Places, never from Gemini.

Cost and data rules decided with it (maintainer, 2026-11-27):

- Place details (reviews, attributes, summaries) and the Gemini call load only when the guest opens a card, never during search; the daily Places quota cap stays.
- Up to 5 photos per opened card, loaded as the guest swipes. This replaces "keep photos free, first pick only" for opened cards; search still fetches one photo.
- Gemini's free tier is used while testing, though Google may use the review text sent to it. Switching to the paid tier is a gate before any build leaves the maintainer.

## Alternatives

- **No AI text on the card:** Places facts and reviews only. Safest, but loses what makes the card more than search-and-display. Rejected.
- **Free-form AI summary with no citations:** easiest, but no way to catch invented facts. Rejected.

## Consequences

- AGENTS.md's rule gets one narrow exception, pointing here.
- A new server path (place details + Gemini explain) needs its own time budget, tests for the citation check and the fallback, and Google's review attribution on screen.
- The paid Gemini tier joins the release gates in CURRENT.md.
