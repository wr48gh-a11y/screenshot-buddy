# Screenshot Buddy

macOS menu bar app: shows the screenshots in a chosen folder, lets you drag them out to other
apps, and sweeps them to the Trash in bulk.

Read [HANDOFF.md](HANDOFF.md) before anything else. [SESSION-LOG.md](SESSION-LOG.md) is
newest-first history; its July 2026 sections are stale by design (single-file app, `build.sh`,
old repo layout) and are kept only as a record. Never take working instructions from them.

## If the report is "I can't drag the newest screenshot"

Do not start reading drag code. This exact bug has been diagnosed wrong three times.

1. `./scripts/verify-install.sh` — if the install is stale, reinstall and retest first. A build
   older than the repo has cost two sessions of debugging code that was already correct.
2. Run `CellHitTestingTests`. If they pass and a real press still fails, it is a new bug.

The cause, found 2026-08-27: `ThumbnailView` renders screenshots with
`.aspectRatio(contentMode: .fill)`, and `clipShape` clips drawing but **not hit testing**, so
each cell's image stayed interactive far outside its 172pt cell and covered its neighbour. In a
`GridRow` the right-hand cell is hit-tested first, so its invisible overflow swallowed presses
on the newest screenshot at top-left. Fixed with `.clipped()` + `.contentShape(...)`.

It was never `LazyVGrid` and never the drag API, despite what older commit messages say.

## Commands

```bash
./scripts/install-local.sh     # build + install the one canonical copy, then verify
./scripts/verify-install.sh    # is the app on screen the code in this repo?
./scripts/check-release.sh     # signing + drag-regression guards, runs the hit-test tests
xcodegen generate              # after adding or removing a source file
xcodebuild -project ScreenshotBuddy.xcodeproj -scheme ScreenshotBuddy -configuration Debug test
```

`Neatly.xcodeproj` equivalent applies here: `ScreenshotBuddy.xcodeproj` is generated from
`project.yml`. Never hand-edit it.

## Conventions

- One bundle may claim `com.hugh.screenshotbuddy`. `xcodebuild test` and raw builds both leave
  a registered `.app` in DerivedData; `install-local.sh` removes them.
- Drag lives in AppKit (`Source/FileDragSource.swift`), not SwiftUI's drag modifiers.
  `check-release.sh` bans `LazyVGrid`, `.onDrag`, and `.draggable` in `Source/`.
- The panel grid stays an eager `Grid`. Do not reintroduce lazy containers there.
- Logging goes to `os.Logger` under subsystem `com.hugh.screenshotbuddy`. Read it with the full
  path, plain `log` is shadowed in this shell:
  `/usr/bin/log show --predicate 'subsystem == "com.hugh.screenshotbuddy"'`
- Tests live in `Tests/ScreenshotBuddyTests/`. Add to the existing suites rather than starting
  new ones for related logic.
- No em dashes in code comments, commit messages, or docs. Use commas, periods, or parentheses.

## Guard hygiene

`check-release.sh` once had its entire regression-guard block sitting below an `exit 0`, so it
never ran, and the bug it was meant to catch came back. If you add a guard, run the script and
confirm it actually fires.
