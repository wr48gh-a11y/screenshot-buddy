# Screenshot Buddy — Handoff (2026-08-27)

## READ THIS FIRST if the report is "I can't drag the newest screenshot"

This bug has been "fixed" four times and diagnosed wrong three of them. Before touching
any code, run these two commands in order.

```
./scripts/verify-install.sh
```

If it reports a stale install, **stop**. Run `./scripts/install-local.sh` and retest. Half of
the 2026-08-27 session went into debugging correct code because `~/Applications` held a build
from before the previous fix. The source having the fix tells you nothing about what is on
screen.

```
xcodebuild -project ScreenshotBuddy.xcodeproj -scheme ScreenshotBuddy -configuration Debug test -only-testing:ScreenshotBuddyTests/CellHitTestingTests
```

If those pass and a real press still fails, it is a NEW bug. Do not re-litigate the old one.

### The actual cause (found 2026-08-27, after 9 sessions)

`ThumbnailView` draws screenshots with `.aspectRatio(contentMode: .fill)` inside a 172x108
cell. A screenshot is much wider than that, so the image overflows sideways. `clipShape`
clips **drawing** but **not hit testing**, so that overflow stayed interactive and lay on top
of the cell next to it. In a `GridRow` the right-hand cell is hit-tested first, so its
invisible overflow covered the newest screenshot at top-left and swallowed every press on it.

That is why it looked like it "drifted" with nobody touching the app: the overlap was always
there, it only ever bites the top-left cell, and it only becomes visible when a new file
arrives and makes a *new* newest screenshot.

**Fix:** `.clipped()` and `.contentShape(RoundedRectangle(cornerRadius: 10))` on
`ThumbnailView`, plus `sizeThatFits` on `FileDragSource` so the AppKit drag view cannot
stretch past its cell either.

**Locks:**
- `Tests/ScreenshotBuddyTests/CellHitTestingTests.swift` builds a real two-cell `GridRow` with
  an over-wide image and asserts a press at the left cell's centre reaches the left cell's own
  drag view. Verified to fail when the clipping is removed. Do not delete this file.
- `scripts/check-release.sh` greps for the modifiers and then runs those tests.

### Why the earlier diagnoses were wrong

`LazyVGrid` recycling was blamed and the grid was rewritten to an eager `Grid`. Keep the eager
`Grid`, it is fine, but it was not the cause. Every earlier fix changed *which view won a hit
test that was rigged from the start*, so each one appeared to work until the next screenshot
landed. The `.onDrag` to `.draggable` to AppKit `FileDragSource` migration has the same story.

Also worth knowing: the regression guard the previous session added to `check-release.sh` was
written **below an `exit 0`** and had therefore never run once. It is now above the exit and
verified to execute. If you add a guard, run the script and confirm it actually fires.

### How to debug this class of bug

The claim in an older version of this file that "GUI automation cannot drive this app" is
wrong. It can:

```
# open the panel
osascript -e 'tell application "System Events" to tell process "ScreenshotBuddy" to click menu bar item 1 of menu bar 2'
# window geometry
osascript -e 'tell application "System Events" to tell process "ScreenshotBuddy" to get {position, size} of window 1'
```

Synthesise clicks and drags with `CGEvent` from a small Swift binary. To find who is actually
receiving a press, add a temporary `NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown)`
that logs `window.contentView?.hitTest(event.locationInWindow)`. Note `hitTest` takes a point
in the receiver's **superview** coordinates, so pass `locationInWindow` unconverted. That probe
is what finally identified the real cause; everything before it was inference.

---


## Current state
- **Live on App Store:** 1.0 (build 2)
- **In review:** 1.0.1 (build 4), submitted 2026-08-24. Apple emails on outcome (up to 48h).
- **main branch:** clean, pushed, single branch. Do not work on side branches — a stranded fix was the root cause of one bug recurrence.

## The drag bug
See "READ THIS FIRST" at the top of this file. The short version: the cause was the
thumbnail's unclipped aspect-fill overflow covering the neighbouring cell, not `LazyVGrid`
and not the drag API. Fixed 2026-08-27 and covered by `CellHitTestingTests`.

**Drag logging:** every drag logs the filename to the unified log:
```
/usr/bin/log show --predicate 'subsystem == "com.hugh.screenshotbuddy"'
```
Note: plain `log` is shadowed in this shell and returns "too many arguments" — always use the full path `/usr/bin/log`.

## Install workflow
Always use the canonical script, never raw `xcodebuild + cp`:
```
./scripts/install-local.sh    # builds, installs, stamps the commit, then verifies
./scripts/verify-install.sh   # cheap standalone check — run before debugging any app behaviour
```
Raw builds auto-register the DerivedData `.app` with LaunchServices, causing a duplicate entry
in Launchpad/Spotlight. `xcodebuild test` does the same with a Debug `.app`. The script
unregisters and deletes both build copies after installing.

`install-local.sh` writes the current commit to `Contents/Resources/BUILD_COMMIT`, and
`verify-install.sh` fails if the installed copy is not built from HEAD, if more than one bundle
claims the ID, or if the running process is not the installed copy. Trust that script over
your assumptions about what is on screen.

## App Store upload workflow
```
# 1. Bump CURRENT_PROJECT_VERSION in project.yml (ASC rejects reused build numbers)
# 2. Regenerate xcodeproj (it is gitignored, project.yml is the source of truth)
xcodegen generate
# 3. Release guard
./scripts/check-release.sh
# 4. Archive
xcodebuild -project ScreenshotBuddy.xcodeproj -scheme ScreenshotBuddy -configuration Release archive -archivePath build/ScreenshotBuddy.xcarchive -allowProvisioningUpdates
# 5. Upload
# ExportOptions.plist with method=app-store-connect, destination=upload, teamID=GN7N7785WD
xcodebuild -exportArchive -archivePath build/ScreenshotBuddy.xcarchive -exportOptionsPlist build/ExportOptions.plist -allowProvisioningUpdates
# 6. In App Store Connect: create new version if needed, attach build, add release notes, Add for Review
# 7. Clean up
rm -rf build
```

## App Store Connect quirks (learned the hard way)
- To swap a build on a rejected version: Distribution > App Review > open submission > ACTION column to remove. Version flips to "Developer Rejected" (normal). Then attach new build.
- Export compliance declared in `Source/Info.plist` (`ITSAppUsesNonExemptEncryption=false`) — no dialog prompt from build 3 onward.
- Contact fields (name, phone, email) are on the version page, not the App Review sidebar.
- "Add for Review" appears instead of "Resubmit" when attaching to a new submission.

## Architecture notes
- Menu bar only (`LSUIElement`). No Dock icon. GUI automation *can* drive it, via System Events
  against the menu bar item plus synthesised `CGEvent`s — see "How to debug this class of bug".
- Drag lives in `Source/FileDragSource.swift` (AppKit `NSViewRepresentable` overlay on each thumbnail). Handles click (select), double-click (open), drag (copy only to outside app). Right-click falls through to SwiftUI `.contextMenu`.
- Store layer (`Source/ScreenshotStore.swift`) is clean and fully testable headlessly — see memory for harness details.
- `~/Applications/Screenshot Buddy.app` is the one canonical install. Verify with `mdfind "kMDItemCFBundleIdentifier == 'com.hugh.screenshotbuddy'"` — must list exactly one path.

## If 1.0.1 gets rejected
Share the rejection reason. Most likely vectors given history:
- **2.1(a):** app appears to not launch — check `applicationShouldHandleReopen` still present in `ScreenshotBuddyApp.swift` and `WelcomeWindow.showIfNeeded` fires.
- **metadata:** nothing in `Source/` references Finder or system UI in a way that misrepresents the app.
