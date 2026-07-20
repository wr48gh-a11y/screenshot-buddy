#!/bin/zsh
# Builds Screenshot Buddy.app (Debug) into ~/Applications.
#
# Uses the SAME Xcode project (XcodeGen → project.yml) as archive.sh, so the app you
# iterate on locally is byte-for-byte the same target you ship to the App Store.
# Difference: Debug config + ad-hoc signing here, Release + App Store signing in archive.sh.
set -e
cd "$(dirname "$0")"

# Fail fast if the team-id placeholders haven't been filled — see scripts/check-release.sh.
if [ -f scripts/check-release.sh ]; then ./scripts/check-release.sh --warn-only; fi

DEST="$HOME/Applications/Screenshot Buddy.app"
DERIVED="$(mktemp -d -t screenshotbuddy-build)"

echo "› Regenerating Xcode project from project.yml…"
xcodegen generate

echo "› Building (Debug)…"
xcodebuild \
  -project ScreenshotBuddy.xcodeproj \
  -scheme ScreenshotBuddy \
  -configuration Debug \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$DERIVED" \
  build >/dev/null

BUILT_APP="$DERIVED/Build/Products/Debug/ScreenshotBuddy.app"
if [ ! -d "$BUILT_APP" ]; then
  echo "✗ Build succeeded but $BUILT_APP is missing." >&2
  exit 1
fi

rm -rf "$DEST"
cp -R "$BUILT_APP" "$DEST"

# Ad-hoc sign so the app launches without a paid developer identity during local iteration.
codesign --force --sign - --entitlements Source/ScreenshotBuddy.entitlements "$DEST"

echo "Built: $DEST"
