# 0005 · Traceable AI summaries on the card

- **Status:** Accepted (maintainer, 2026-11-27)
- **Date:** 2026-11-27

## Context

ADR 0002 and AGENTS.md let Gemini only turn a craving into search filters and reorder Places results. The smart restaurant card (TASK-UI-4) wants a "Why this pick" that explains, in sentences, how a place matches the craving. Those sentences are about a restaurant, so they come close to "the LLM produces restaurant data", which the rule forbids because a model can invent facts (a dish, an hour, a price) that the guest then trusts.

## Decision

Gemini chooses evidence; it never writes restaurant facts. For each of up to 3 "Why this pick" items, Gemini returns only a claim kind from a fixed list, a reference to the Places field or review it rests on, and, for a review, a short quote from it. The Edge Function checks each item in code against the actual Places data: an attribute item needs that attribute to be `true` (for example `takeout`), a rating or price item needs that field present, and a review quote must appear word for word in the cited review. The words on screen come from server-owned templates ("Offers takeout", "Rated 4.6 on Google") or are the verified quote with its reviewer's name; Gemini's own wording is never shown. Any item that fails a check is dropped. If Gemini fails, or no item survives, the card shows the Places-only reasons (Budget-friendly, Close by, Highly rated). Everything else on the card still comes straight from Places.

Cost and data rules decided with it (maintainer, 2026-11-27):

- Place details (reviews, attributes, summaries) and the Gemini call load only when the guest opens a card, never during search; the daily Places quota cap stays.
- Up to 5 photos per opened card, loaded as the guest swipes. This replaces "keep photos free, first pick only" for opened cards; search still fetches one photo.
- Gemini's free tier is used while testing, though Google may use the review text sent to it. Switching to the paid tier is a gate before any build leaves the maintainer.

## Alternatives

- **No AI text on the card:** Places facts and reviews only. Safest, but loses what makes the card more than search-and-display. Rejected.
- **Free-form AI summary with no citations:** easiest, but no way to catch invented facts. Rejected.
- **Gemini-written sentences with a citation:** a citation proves the source exists, not that the sentence is true (a claim about a dish can cite a review that never mentions it). Rejected after Codex's adversarial review of PR #39.

## Consequences

- AGENTS.md's rule gets one narrow exception, pointing here.
- A new server path (place details + Gemini explain) needs its own time budget, tests for the citation check and the fallback, and Google's review attribution on screen.
- The details path (`place-details` and the explanation call) and the paid Gemini tier join the release gates in CURRENT.md.
