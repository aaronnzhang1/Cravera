# 0005 · AI on the restaurant card: checked facts and Cravera's take

- **Status:** Accepted (maintainer, 2026-11-27)
- **Date:** 2026-11-27

## Context

ADR 0002 and AGENTS.md let Gemini only turn a craving into search filters and reorder Places results, because a model can invent facts (a dish, an hour, a price) that the guest then trusts. The smart restaurant card (TASK-UI-4) needs more: the maintainer wants Cravera to feel like an assistant helping you search, "as if i asked chat gpt and it gave me a response, but this is backed with the restaurant data" (2026-11-27), mixing what the AI thinks with accurate restaurant information. A first version of this record allowed no Gemini wording at all; the maintainer chose the mix instead, accepting the residual risk below.

## Decision

The card has two AI parts, kept visibly apart.

**1. Checked facts ("Why this pick").** Gemini returns only references to Places field names from a fixed list (for example `takeout`, `rating`, `priceLevel`). The Edge Function checks each in code: an attribute counts only if Places reports it `true`, a rating only if present, a price only if the guest asked for a price range and it lies inside it (with no requested range, price is never a reason); anything else is ignored. The words come only from the server's template for that field ("Offers takeout", "Rated 4.6 on Google"). Reviews are never reasons (a review can say the opposite of what the guest wants); Gemini may only order the reviews section. If Gemini fails or nothing survives, the Places-only reasons show (Budget-friendly only when the guest asked for a price range and the price is inside it).

**2. Cravera's take.** Gemini writes a short note in Cravera's voice (at most 3 sentences, 280 characters) on how the place fits the craving and what it thinks of it, given only the craving and that place's Places fields and reviews. Guardrails, in code:

- The note is labelled as Cravera's AI take on Google data and reviews, and always shows next to the checked facts and Google's own content, never in place of them.
- It is dropped if it contains any digit or number word, any currency sign or price word (for example dollar, bucks, cents, price), a link, or anything about opening hours or being open. Quantities (rating, price, distance) appear only in the server's wording of checked fields, never in Gemini's prose; open-now comes only from the search, in code.
- If Gemini fails, times out or the note is dropped, the server builds the take from a template in the same voice, under the same rules (no numbers, prices or hours), from checked fields only ("For your cozy ramen craving, this ramen spot looks like a good fit, and you can eat in."). Quantities and open-now stay in the card's own fact rows.

Everything else on the card (name, photos, address, price, hours, distance, attributes, Google's summaries, reviews) comes straight from Places.

Cost and data rules (maintainer, 2026-11-27):

- Details and the Gemini call load automatically for each place as it is shown (the first pick and each place after No), never for places the guest hasn't reached; search itself makes no details call. One automatic attempt per shown place; only Try again after a failure may spend another request; repeated taps and rebuilds share a request already on its way. About 1,000 Place Details requests a month are free, then $25 per 1,000; the daily quota the maintainer set caps it.
- Up to 5 photos per card, each loaded only when swiped to; the search photo is reused.
- `place-details` is deployed only with a daily quota on Place Details set in Google Cloud (anyone with the public publishable key can call it).
- Gemini's free tier is used while testing, though Google may use the review text sent to it. Switching to the paid tier is a gate before any build leaves the maintainer.

## Residual risk (accepted by the maintainer, 2026-11-27)

The take's wording can still misdescribe something the checks can't catch (a dish, the atmosphere, a review's tone). Mitigations: it may only use the place's own Google data and reviews, it is labelled as an AI take, it sits beside the checked facts and the full reviews, and it can't state numbers, prices or hours at all.

## Alternatives

- **No AI wording on the card** (this record's first version, after Codex's adversarial review of PR #39): safest, but the card reads like a search result, not an assistant. Superseded by the maintainer's decision.
- **Free-form AI text with no checks:** rejected; nothing would catch invented numbers or hours.
- **Gemini-written reasons with citations, review excerpts, reviews as reasons:** rejected for the checked-facts part (a citation proves a source exists, not that the sentence is true; an excerpt can drop a "not").

## Consequences

- AGENTS.md's rule gets one exception, pointing here.
- The details path needs its own time budget, tests for the fact check, the note's checks and both fallbacks, and Google's review attribution on screen.
- The details path (`place-details` and the Gemini call) and the paid Gemini tier are in the release gates in CURRENT.md.
