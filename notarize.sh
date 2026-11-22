#!/bin/zsh
# Notarizes and staples a --release build, then zips it for GitHub Releases.
#
# One-time setup (stores your Apple ID credentials in the keychain):
#   xcrun notarytool store-credentials brio-notary \
#     --apple-id "you@example.com" --team-id "TEAMID" --password "app-specific-password"
#
# Then:
#   ./build.sh --release
#   ./notarize.sh
#
# Optional: NOTARY_PROFILE overrides the keychain profile name (default: brio-notary).
set -euo pipefail
cd "${0:A:h}"

APP="build/Studio Cam Controls.app"
PROFILE="${NOTARY_PROFILE:-brio-notary}"

if [[ ! -d "$APP" ]]; then
  print -u2 "$APP not found. Run ./build.sh --release first."
  exit 1
fi
SIGNATURE=$(codesign -dv --verbose=2 "$APP" 2>&1 || true)
if [[ "$SIGNATURE" != *"Authority=Developer ID Application"* ]]; then
  print -u2 "$APP is not Developer ID signed. Run ./build.sh --release first."
  exit 1
fi

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
UPLOAD="build/StudioCamControls-notarize.zip"
OUT="build/Studio-Cam-Controls-$VERSION.zip"

rm -f "$UPLOAD" "$OUT"
ditto -c -k --keepParent "$APP" "$UPLOAD"

print "Submitting to Apple's notary service (usually a few minutes)..."
xcrun notarytool submit "$UPLOAD" --keychain-profile "$PROFILE" --wait

xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=2 "$APP"

ditto -c -k --keepParent "$APP" "$OUT"
rm -f "$UPLOAD"
printf 'Notarized. Upload %s to a GitHub Release.\n' "$OUT"
