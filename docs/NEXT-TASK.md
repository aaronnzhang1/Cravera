# TASK-UI-3 · Profile and Friends

**Goal.** Profile becomes a real, tidy account page whose settings save to the person's own `profiles` row, and Friends stops looking like a ghost town: an inviting preview of what friends will do in Cravera, never a fake list. From [the v0.2 plan](plans/v0.2-hub.md) (task 3).

**Release:** v0.2.0 · Accounts. TASK-002 is done (all 8 criteria checked in the app, 2026-11-27; see git history of this file). TASK-003 is merged (#30).
**Approved:** 2026-11-27 (maintainer), as written. Claude may work any criterion below without asking again; anything outside this file's scope still needs approval.
**Review level:** L3 (raised from L2 after Codex round 3 on PR #35: CONTRIBUTING lists personal data and data isolation as L3). The app now reads and writes personal data (home city, dietary preferences) in the person's own `profiles` row, and closes popups when the account on the device changes. No migration, no Edge Function change: RLS and column grants are TASK-003's. One new dependency, `share_plus` (system share sheet for Invite; maintainer approved 2026-11-27).

## Acceptance criteria

Tick a box only after checking it in the running app. Never delete or reword a criterion. Propose any change to the maintainer instead.

- [x] Profile is in sections: **Account** (name, email, edit display name, sign out, delete account), **Preferences** (dietary preferences, home city, default search distance), **About** (privacy, help). No "coming soon" rows: a row works or is removed.
- [x] A signed-in person can change display name, home city, dietary preferences (pick from a short list) and default distance (e.g. 1, 2, 5, 10 km); changes save to their own `profiles` row, survive an app restart, and show on another sign-in. Invalid input (empty or over-long name) shows a clear message; a failed save says so and keeps the old value.
- [x] The default distance is used as the search radius for new searches (within the server's existing cap). Dietary preferences are stored only; using them in search is a later task.
- [x] A guest sees Preferences disabled with a "Create an account to save preferences" prompt that promises only what exists.
- [x] Friends shows a designed preview (sharing picks, seeing where friends eat) with an **Invite** button that opens the system share sheet with a short invite text; the demo people list is gone.
- [ ] Fast tab taps (Home → Saved → Friends) no longer make a page jump sides as it leaves (deferred P2 from PR #22): it starts its exit from its current offset.
- [x] Profile and Friends pass the tap-target, label and contrast guideline tests, also at 2x text on a 320 x 568 phone.
- [x] `flutter analyze` and `flutter test` pass, with tests for saving each preference (fake service), a failed save, and the guest state; checked on the Android emulator signed in and as a guest.

## Checked

- 2026-11-27, `Pixel_10_Pro`, guest: Profile shows Account/Preferences/About sections with Preferences off and "Create an account to save preferences."; Privacy & data and Help open; Friends shows the preview, no fake people; **Invite opens the Android share sheet** with the invite text (`share_plus`, approved by the maintainer).
- Accessibility guideline tests pass for Profile (signed in, guest) and Friends, at the top and scrolled, also at 2x text on 320 x 568.
- 2026-11-27 ~19:05 PST, `Pixel_10_Pro`, signed in (maintainer's account, values restored afterwards): Profile loads name/email/preferences from the server; Search distance → 2 km, Dietary → Vegetarian + Halal, Home city → Oakland, Name → "Aaron Test", each "Saved."; after closing and reopening the app all four are still there, and a read-only query on the live `profiles` row shows the same values. "ramen" then found only places within 2 km (0.3–1.6 km). Everything set back (name Aaron Zhang, no diet, no city, 5 km; checked in the row). Found and fixed on the way: the sheets opened under the nav bar; the dietary sheet lost picks when it rebuilt.
- Still to check in the app: the tab slide (criterion 6; unit-tested in `tab_slide_test.dart`).

## Out of scope

- Real friends, invites that create links between accounts, notifications settings, a profile photo, Saved hub (TASK-004), using dietary preferences in search.
