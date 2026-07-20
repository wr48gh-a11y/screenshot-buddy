# Screenshot Buddy — Session Log

**Date:** 2026-07-17 → 2026-07-18
**Outcome:** Built a native macOS menu bar app from scratch and got it App Store–ready, pending only Apple account activation.

---

## What we built

A native macOS menu bar app (SwiftUI/AppKit) that manages a screenshots folder: view thumbnails, Quick Look, drag out, rename in place, and permanently clear the whole folder in one click. Two states — no folder connected (floating welcome window) and folder connected (the menu bar panel).

- **Source of truth:** `Source/ScreenshotBuddyApp.swift` (single-file app)
- **App installed at:** `~/Applications/Screenshot Buddy.app` (from `build.sh`, fast iteration)
- **Bundle ID:** `com.hugh.screenshotbuddy`

## Naming history
SnapSweep → Screenshot Daddy → Screenshot Auntie → **Screenshot Buddy**
(Renamed for App Store suitability; "Buddy" is the final, review-safe name. Settings migrate across all prior bundle IDs so a saved folder is never lost.)

## Design journey
- Started from an "if Apple built it" brief; explored 6 directions (CleanMyMac, CleanShot X, Raycast, Things 3, Notion, Spotify) → chose **CleanMyMac** (dark cosmic purple, glowing orb, health ring, gradient pill buttons).
- Signature color: **#7B4DFF** (gradient runs to #B44DFF).
- Custom spiral logo mark (`BuddyMark`, drawn from `icon-kit/mark.svg`) used in the menu bar (tight-cropped to full height), the About window, the empty state, and the Sweep button.
- Welcome interstitial: explored 4 concepts → chose **Concept C (cinematic)**, later refined to a bare gradient-stroked mark + single headline ("Welcome to Screenshot Buddy"). Type dialed back from an over-large 68pt to 36pt after a design review.
- Sweep button size treatment: chose the **pill-chip** style (reclaim size in a translucent chip on the right). Fixed a padding bug where the chip bled past the capsule edge.

## Key UX decisions
- **Delete evolution** — started as permanent-delete-only with a confirmation dialog → dialog removed (tedious) → 5-second Undo toast added → final design (2026-07-18): **two buttons**. "Sweep to Trash" is the gradient hero (recoverable via macOS Trash, no Undo needed); "Delete Forever" is a smaller outlined red secondary (permanent, keeps the 5s Undo toast, purges on quit). Chosen from 7 mockups (sweep-two-button-options.html, option 1: 60/40 side-by-side). This virtually eliminates the App Store review risk around destructive actions.
- Removed "Reset Folder" (redundant with "Change Folder").
- Reclaim size shown once (button chip), not duplicated in the header.

## App Store readiness (completed this session)
- ✅ **App Sandbox** + `user-selected.read-write` entitlements. Reworked folder access from a raw path to a **security-scoped bookmark** (survives relaunch — verified).
- ✅ **Real Xcode project** via XcodeGen (`project.yml`) with `Assets.xcassets` (app icon), Hardened Runtime, sandbox entitlements. Builds via `xcodebuild`.
- ✅ **Privacy manifest** (`Source/PrivacyInfo.xcprivacy`) — no tracking, no data collection, required-reason APIs declared.
- ✅ **Undo safety net** (above).
- ✅ **Listing copy** (`store-listing.md`) + **privacy policy** / **support page** text.
- ✅ **Marketing screenshots** — four 2560×1600 retina shots (`marketing/`, regenerable via `gen.py`).
- ✅ **Archive pipeline** (`archive.sh` + `exportOptions.plist`) — one command to archive + export a signed `.pkg`.

## Code-review fixes (2026-07-18, pre-launch pass)
Addressed an external re-review. Fixed:
- **Per-file delete now goes to the Trash** (`moveToTrash`, `trashItem`), renamed menu item "Move to Trash" — was the last permanent-delete-without-undo path; now consistent with the safe bulk design.
- **Welcome dead-end trap fixed** — the no-folder menu bar panel is now a real, escapable `setupPanel` (Connect button + gear with Quit) instead of an auto-dismiss loop. Users can always quit.
- **Lost-folder-access state** — `refresh()` now distinguishes "unreachable" from "empty" (do/catch + `accessLost`); the panel shows a "Can't Reach This Folder / Reconnect" view instead of a false "All Clear".
- **Undo made robust** — the permanent-sweep purge moved to a store-owned `DispatchWorkItem` timer, so it fires deterministically even if the panel closes (no more temp-file limbo). Trash confirmation toast lengthened 2s → 4s.
- Reviewer's "sweep over-reports the count" (P4) was a misread — the count only increments on success, so it's already accurate. Noted the real (smaller) gap: partial trash failures are silent.
- Deferred (post-launch, non-blocking): file split, debounce refresh, cache formatter, collapse the two build pipelines, rename-failure feedback.

## Pricing
**$2.99** one-time (decided 2026-07-18). Enroll in Apple's free Small Business Program for the 15% commission tier. Optional launch discount to $0.99 for week one to seed reviews. Changeable any time.

## Blocker / next steps
- ⏳ **Apple Developer Program** — enrolled 2026-07-18 as an Individual ($99, order W1628426331, receipt filed in `admin/`). Awaiting activation.
- When active: paste the **Team ID** into `project.yml` (DEVELOPMENT_TEAM) and `exportOptions.plist` (teamID) → run `archive.sh` → upload the `.pkg` via Transporter → create the App Store Connect record (copy from `store-listing.md`, upload the 4 screenshots, add privacy/support URLs) → submit.
- Plan to migrate from Individual to an LLC later (CA LLC = ~$900/yr incl. $800 franchise tax; deferred until the app has traction).

## Repo layout
```
screenshot-buddy/
├── Source/            ScreenshotBuddyApp.swift, Info.plist, entitlements, PrivacyInfo.xcprivacy
├── Assets.xcassets/   compiled app icon
├── icon-kit/          source icon art (mark.svg, appiconset, menu bar templates)
├── marketing/         4 App Store screenshots + gen.py
├── admin/             business paperwork (Apple receipt)
├── project.yml        XcodeGen spec (source of truth for the .xcodeproj)
├── build.sh           fast swiftc build → ~/Applications
├── archive.sh         archive + export for the App Store
├── exportOptions.plist
├── store-listing.md, privacy-policy.md, support-page.md
└── *.html             design exploration mockups
```

## Build commands
- Iterate: `./build.sh` (installs to ~/Applications, ad-hoc signed)
- Submit: set Team ID, then `./archive.sh`
