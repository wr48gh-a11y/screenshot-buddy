#!/bin/zsh
# Archives Screenshot Buddy for App Store submission.
# PREREQ: Apple Developer account approved, and DEVELOPMENT_TEAM set in project.yml
#         (and teamID in exportOptions.plist). Enforced by scripts/check-release.sh.
# Steps: guard -> regenerate project -> archive -> export for App Store -> (upload via Transporter or `xcrun altool`).
set -e
cd "$(dirname "$0")"

echo "› Pre-submit check…"
./scripts/check-release.sh

DERIVED="/tmp/screenshotbuddy-archive"
ARCHIVE="$DERIVED/ScreenshotBuddy.xcarchive"

echo "› Regenerating Xcode project from project.yml…"
xcodegen generate

echo "› Archiving (Release)…"
xcodebuild -project ScreenshotBuddy.xcodeproj \
  -scheme ScreenshotBuddy \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE" \
  archive

echo "› Archive created at: $ARCHIVE"

echo "› Exporting for the App Store…"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist exportOptions.plist \
  -exportPath "$DERIVED/export"

echo ""
echo "✓ Done. Signed package is in: $DERIVED/export"
echo "  Upload it with Transporter.app (free on the Mac App Store), or:"
echo "  xcrun altool --upload-app -f \"$DERIVED/export/ScreenshotBuddy.pkg\" -t macos -u <apple-id> -p <app-specific-password>"
echo ""
echo "  PREREQ: set your Team ID in BOTH project.yml (DEVELOPMENT_TEAM) and exportOptions.plist (teamID)."
