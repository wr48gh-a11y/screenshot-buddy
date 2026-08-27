#!/bin/zsh
# Answer one question: is the app I am looking at on screen the code that is in this repo?
#
# Run this FIRST whenever a bug is reported that the source says is already fixed. A stale
# install has twice made a fixed bug look alive: the repo had the fix, ~/Applications did not,
# and the session went hunting through code that was already correct.
#
# Usage: ./scripts/verify-install.sh
set -u
cd "$(dirname "$0")/.."

DEST="$HOME/Applications/Screenshot Buddy.app"
PROBLEMS=0

# 1. Only one bundle may claim the bundle ID. More than one and macOS can hand the running
#    slot, and the login-item record, to a copy you are not editing.
#
#    Checked against the filesystem, not Spotlight: mdfind's index lags for a minute or so
#    after an install and will transiently report zero copies, which is not a real problem.
#    Spotlight is still consulted for copies in places we would not think to look.
STRAYS=$(find "$HOME/Library/Developer/Xcode/DerivedData" /Applications "$HOME/Applications" \
  -maxdepth 6 -name "ScreenshotBuddy.app" -o -maxdepth 6 -name "Screenshot Buddy.app" 2>/dev/null \
  | grep -vFx "$DEST" || true)
INDEXED=$(mdfind "kMDItemCFBundleIdentifier == 'com.hugh.screenshotbuddy'" 2>/dev/null \
  | grep -vFx "$DEST" || true)
EXTRA=$(printf '%s\n%s\n' "$STRAYS" "$INDEXED" | grep . | sort -u || true)
if [ -n "$EXTRA" ]; then
  echo "✗ More than one copy claims com.hugh.screenshotbuddy. Extras:" >&2
  printf '%s\n' "$EXTRA" >&2
  echo "  Delete them, then re-run ./scripts/install-local.sh" >&2
  echo "  (A Spotlight-only hit right after an install can be a stale index; re-run in a minute.)" >&2
  PROBLEMS=$((PROBLEMS + 1))
fi

if [ ! -d "$DEST" ]; then
  echo "✗ No app installed at $DEST. Run ./scripts/install-local.sh" >&2
  exit 1
fi

# 2. The installed copy must be built from the current commit.
HEAD_SHA=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
BUILT_SHA=$(cat "$DEST/Contents/Resources/BUILD_COMMIT" 2>/dev/null || echo "unstamped")
if [ "$BUILT_SHA" = "unstamped" ]; then
  echo "⚠ Installed copy predates commit stamping — assume it is stale." >&2
  echo "  Run ./scripts/install-local.sh before trusting anything you see on screen." >&2
  PROBLEMS=$((PROBLEMS + 1))
elif [ "$BUILT_SHA" != "$HEAD_SHA" ]; then
  echo "✗ STALE INSTALL. You are testing code that is not in your working tree." >&2
  echo "  installed: $BUILT_SHA" >&2
  echo "  HEAD:      $HEAD_SHA" >&2
  echo "  Run ./scripts/install-local.sh, then retest before debugging anything." >&2
  PROBLEMS=$((PROBLEMS + 1))
fi

# 3. Uncommitted source changes are not in the installed copy either.
if [ -n "$(git status --porcelain Source/ 2>/dev/null)" ]; then
  echo "⚠ Uncommitted changes under Source/ — the installed copy does not contain them" >&2
  echo "  unless you have run ./scripts/install-local.sh since editing." >&2
fi

# 4. Which process is actually running, and from where.
RUNNING_PID=$(pgrep -x ScreenshotBuddy 2>/dev/null | head -1 || true)
RUNNING=$([ -n "$RUNNING_PID" ] && ps -o command= -p "$RUNNING_PID" 2>/dev/null || true)
if [ -z "$RUNNING" ]; then
  echo "⚠ ScreenshotBuddy is not running." >&2
else
  case "$RUNNING" in
    *"$DEST"*) : ;;
    *)
      echo "✗ The running process is NOT the installed copy:" >&2
      echo "  $RUNNING" >&2
      PROBLEMS=$((PROBLEMS + 1))
      ;;
  esac
fi

if [ "$PROBLEMS" -gt 0 ]; then
  echo "" >&2
  echo "$PROBLEMS problem(s). Fix these before debugging app behaviour." >&2
  exit 1
fi

echo "✓ One copy installed, built from HEAD ($HEAD_SHA), and it is the process running."
exit 0
