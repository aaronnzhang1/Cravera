# 0006 · A restricted Maps SDK key in the app

- **Status:** Accepted (maintainer, 2026-11-27)
- **Date:** 2026-11-27

## Context

ADR 0003 keeps every Google key out of the app. The Saved hub (TASK-004) needs a real Google map with pins for saved places: Google's terms allow showing Places content on a map only on a Google map, and the native Maps SDKs for Android and iOS need a key on the device. Google lists Maps SDK map loads as free with no usage cap (pricing list, checked 2026-11-27); only Street View, which Cravera doesn't use, is billed.

## Decision

The app holds one Google key: a Maps SDK key, restricted in Google Cloud to the Cravera Android app (package `com.cravera.app` plus the debug and release signing SHA-1s) and the iOS bundle ID, and allowed to call only Maps SDK for Android and Maps SDK for iOS. It lives in the platform config the SDKs read (Android manifest placeholder, iOS `AppDelegate`), filled from a local, untracked file at build time, never from `.env` and never committed. The Places, Places photos and Gemini keys stay server-side (ADR 0003 unchanged for them).

## Alternatives

- **A static map image from the server:** keeps every key server-side, but Static Maps is billed per load and isn't interactive. Rejected.
- **Saved as a list only:** no key in the app, but loses the map the maintainer asked for (v0.2 plan). Rejected.

## Consequences

- The APK/IPA key scan changes: exactly one `AIza…` string is expected (the Maps SDK key), and it must show the app and API restrictions in Google Cloud; any other Google key in the bundle is still a P1.
- A leaked Maps key can only load maps inside an app signed with our certificate; Street View must stay off.
- Setting up a new machine needs the local key file (HOW_TO_RUN.md, when TASK-004 adds it).
