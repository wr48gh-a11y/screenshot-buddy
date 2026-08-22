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

echo "Removing the DerivedData build copy so it can't show as a duplicate…"
"$LSREG" -u "$BUILT" 2>/dev/null || true
rm -rf "$BUILT"

echo "Launching the installed copy…"
open "$DEST"

echo "Done. Registered copies:"
mdfind "kMDItemCFBundleIdentifier == 'com.hugh.screenshotbuddy'"
