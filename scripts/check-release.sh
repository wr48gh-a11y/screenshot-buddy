#!/bin/zsh
# Pre-submit guard: fail (or warn) if the App Store signing placeholders are still unfilled.
#
# Use in two modes:
#   ./scripts/check-release.sh            # hard fail — run before `archive.sh`
#   ./scripts/check-release.sh --warn-only # non-zero exit skipped — used by build.sh during iteration
#
# Fills the gap between "iterate locally" (no Apple account needed) and "submit to the App
# Store" (a real Team ID is mandatory). Prevents shipping a build that can't be signed.
set -u
cd "$(dirname "$0")/.."

WARN_ONLY=0
[ "${1:-}" = "--warn-only" ] && WARN_ONLY=1

emit() {   # 1 = severity (ERROR/WARNING), 2 = message
  if [ "$1" = "ERROR" ] && [ "$WARN_ONLY" -eq 0 ]; then
    echo "✗ $2" >&2
  else
    echo "⚠ $2" >&2
  fi
}

PROBLEMS=0

# 1. project.yml: DEVELOPMENT_TEAM must be a real Team ID (10 alphanumeric chars).
TEAM="$(awk -F'"' '/DEVELOPMENT_TEAM:/ {print $2}' project.yml 2>/dev/null | tr -d '[:space:]')"
if [ -z "$TEAM" ]; then
  emit ERROR "project.yml: DEVELOPMENT_TEAM is empty. Set it to your Apple Team ID."
  PROBLEMS=$((PROBLEMS + 1))
fi

# 2. exportOptions.plist: teamID must not still be the placeholder.
if grep -q "REPLACE_WITH_TEAM_ID" exportOptions.plist 2>/dev/null; then
  emit ERROR "exportOptions.plist: teamID is still 'REPLACE_WITH_TEAM_ID'. Set it to your Apple Team ID."
  PROBLEMS=$((PROBLEMS + 1))
fi

if [ "$PROBLEMS" -gt 0 ]; then
  if [ "$WARN_ONLY" -eq 0 ]; then
    echo "Refusing to proceed: $PROBLEMS signing issue(s). Edit project.yml and exportOptions.plist, then re-run." >&2
    exit 1
  else
    echo "(Iteration build only — $PROBLEMS signing issue(s) will block submission. Ignoring for now.)" >&2
  fi
fi

# ---------------------------------------------------------------------------
# Drag regression guards. These are NOT signing checks, so --warn-only does not
# soften them: shipping this bug again is worse than a blocked build.
#
# This block used to sit below an `exit 0` and had therefore never run once. If
# you add a check, add it above the final exit and re-run the script to confirm
# it actually executes.
# ---------------------------------------------------------------------------
DRAG_FAIL=0

# 3. Cell hit area must stay clipped. `clipShape` clips drawing but NOT hit testing, so an
#    aspect-fill screenshot stays interactive far outside its 172pt cell and covers the
#    neighbouring cell. That is the real cause of "can't drag the newest screenshot".
for MODIFIER in ".clipped()" ".contentShape("; do
  if ! grep -qF -- "$MODIFIER" Source/Thumbnail.swift 2>/dev/null; then
    echo "✗ Source/Thumbnail.swift: missing '$MODIFIER'. The thumbnail's interactive area must" >&2
    echo "  be clipped to the cell or it steals presses from the neighbouring cell." >&2
    echo "  See CellHitTestingTests and HANDOFF.md 'The newest screenshot will not drag'." >&2
    DRAG_FAIL=1
  fi
done

# 4. The drag view must stay pinned to the thumbnail's size. Without sizeThatFits an
#    NSViewRepresentable takes the whole proposed row width and covers its neighbour.
if ! grep -q "func sizeThatFits" Source/FileDragSource.swift 2>/dev/null; then
  echo "✗ Source/FileDragSource.swift: missing sizeThatFits. The drag view must be pinned to" >&2
  echo "  the thumbnail's size, or SwiftUI stretches it across the whole row." >&2
  DRAG_FAIL=1
fi

# 5. The panel grid stays eager and drag stays in AppKit. Lazy containers recycle cells and
#    SwiftUI's own drag modifiers ride on hit-testing we do not control.
# Comment lines are excluded: the history of this bug is documented in the source, and naming
# the banned APIs in a comment must not trip the guard.
BANNED=$(grep -rn "LazyVGrid\|\.onDrag\|\.draggable" Source/ \
  | grep -vE "^[^:]+:[0-9]+:[[:space:]]*//" || true)
if [ -n "$BANNED" ]; then
  echo "✗ banned pattern in Source/ (wrong-cell drag regression risk):" >&2
  echo "$BANNED" >&2
  DRAG_FAIL=1
fi

# 6. The regression tests themselves must exist and pass. The greps above only check that the
#    modifiers are present; only the tests prove the hit area is actually correct.
if [ ! -f Tests/ScreenshotBuddyTests/CellHitTestingTests.swift ]; then
  echo "✗ Tests/ScreenshotBuddyTests/CellHitTestingTests.swift is missing. Do not delete it." >&2
  DRAG_FAIL=1
fi

if [ "$DRAG_FAIL" -ne 0 ]; then
  echo "Refusing to proceed: drag hit-testing guard failed." >&2
  exit 1
fi

if [ "${SKIP_TESTS:-0}" != "1" ]; then
  echo "Running hit-testing regression tests…"
  TEST_OK=0
  xcodebuild -project ScreenshotBuddy.xcodeproj -scheme ScreenshotBuddy \
    -configuration Debug test \
    -only-testing:ScreenshotBuddyTests/CellHitTestingTests >/dev/null 2>&1 || TEST_OK=1

  # `xcodebuild test` leaves a Debug .app in DerivedData and registers it with LaunchServices,
  # creating a second bundle claiming com.hugh.screenshotbuddy. Clean up after ourselves, or
  # this guard leaves the machine in the exact state verify-install.sh exists to catch.
  BUILT_DEBUG="$(xcodebuild -project ScreenshotBuddy.xcodeproj -scheme ScreenshotBuddy \
    -configuration Debug -showBuildSettings 2>/dev/null \
    | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $2; exit}')/ScreenshotBuddy.app"
  if [ -d "$BUILT_DEBUG" ]; then
    LSREG="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"
    "$LSREG" -u "$BUILT_DEBUG" 2>/dev/null || true
    rm -rf "$BUILT_DEBUG"
  fi

  if [ "$TEST_OK" -ne 0 ]; then
    echo "✗ CellHitTestingTests failed. The newest screenshot's cell is not receiving presses." >&2
    echo "  Run them directly to see why:" >&2
    echo "  xcodebuild -project ScreenshotBuddy.xcodeproj -scheme ScreenshotBuddy -configuration Debug test -only-testing:ScreenshotBuddyTests/CellHitTestingTests" >&2
    exit 1
  fi
fi

exit 0
