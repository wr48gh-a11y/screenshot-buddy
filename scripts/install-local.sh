#!/bin/zsh
# Build Screenshot Buddy and install the one canonical copy to ~/Applications.
#
# Why this exists: `xcodebuild` auto-registers the DerivedData .app with LaunchServices, so
# after a plain build macOS shows TWO "Screenshot Buddy" entries in Launchpad/Spotlight — the
# real install and the leftover build product. This script always removes and unregisters that
# build copy after installing, so exactly one copy ever exists on the machine.
#
# Usage: ./scripts/install-local.sh
set -eu
cd "$(dirname "$0")/.."

APP_NAME="Screenshot Buddy.app"
DEST="$HOME/Applications/$APP_NAME"
LSREG="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"

echo "Building Release…"
xcodebuild -project ScreenshotBuddy.xcodeproj -scheme ScreenshotBuddy -configuration Release build >/dev/null

BUILT="$(xcodebuild -project ScreenshotBuddy.xcodeproj -scheme ScreenshotBuddy -configuration Release -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $2; exit}')/ScreenshotBuddy.app"
[ -d "$BUILT" ] || { echo "error: build product not found at $BUILT" >&2; exit 1; }

echo "Quitting any running instance…"
osascript -e 'tell application "Screenshot Buddy" to quit' 2>/dev/null || true
sleep 1; pkill -x ScreenshotBuddy 2>/dev/null || true; sleep 1

echo "Installing to $DEST…"
rm -rf "$DEST"
cp -R "$BUILT" "$DEST"

# Both configurations, not just the one we built. `xcodebuild test` produces a Debug .app and
# registers it too, so running the test suite silently creates a second copy claiming the
# bundle ID.
echo "Removing the DerivedData build copies so they can't show as duplicates…"
DERIVED="$(dirname "$(dirname "$BUILT")")"
for CONFIG in Debug Release; do
  STRAY="$DERIVED/$CONFIG/ScreenshotBuddy.app"
  [ -d "$STRAY" ] || continue
  "$LSREG" -u "$STRAY" 2>/dev/null || true
  rm -rf "$STRAY"
done

# Stamp the commit this copy was built from. Without it there is no way to tell a current
# install from one built weeks ago, and testing against a stale install has burned a whole
# session before — the bug looked fixed in the repo and broken on screen. `verify-install.sh`
# reads this back.
git rev-parse HEAD > "$DEST/Contents/Resources/BUILD_COMMIT" 2>/dev/null || true

echo "Launching the installed copy…"
open "$DEST"

echo "Done. Registered copies:"
mdfind "kMDItemCFBundleIdentifier == 'com.hugh.screenshotbuddy'"

exec "$(dirname "$0")/verify-install.sh"
