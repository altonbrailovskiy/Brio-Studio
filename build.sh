#!/bin/zsh
# Builds Brio Studio.app and the brio-probe CLI.
#
#   ./build.sh             Local build, ad-hoc signed (default)
#   ./build.sh --sandbox   Local build with App Sandbox on, to test App Store compatibility
#   ./build.sh --release   Developer ID signed, hardened runtime, ready for ./notarize.sh
#
# Optional environment variables:
#   BUNDLE_ID          Override the bundle identifier (default: value in Info.plist)
#   DEVELOPER_ID       Signing identity for --release, e.g.
#                      "Developer ID Application: Alton Brailovskiy (TEAMID)".
#                      If unset, the first Developer ID Application identity in
#                      your keychain is used.
set -euo pipefail
cd "${0:A:h}"

MODE="local"
case "${1:-}" in
  "") ;;
  --sandbox) MODE="sandbox" ;;
  --release) MODE="release" ;;
  -h|--help) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) print -u2 "Unknown option: $1 (use --sandbox, --release, or no option)"; exit 64 ;;
esac

APP="build/Brio Studio.app"
ARCHS=(-arch arm64 -arch x86_64)

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

xcrun clang -fobjc-arc -O2 -Wall -Wextra -Wno-unused-parameter -Wno-deprecated-declarations \
  -mmacosx-version-min=14.0 "${ARCHS[@]}" \
  Sources/Camera.m Sources/PreviewTools.m Sources/Optimizer.m Sources/main.m \
  -framework Cocoa -framework AVFoundation -framework Vision -framework CoreImage \
  -framework CoreMedia -framework CoreVideo -framework IOKit \
  -o "$APP/Contents/MacOS/BrioStudio"

cp Assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Info.plist "$APP/Contents/Info.plist"
if [[ -n "${BUNDLE_ID:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP/Contents/Info.plist"
fi

case "$MODE" in
  local)
    codesign --force --sign - "$APP"
    ;;
  sandbox)
    codesign --force --sign - --entitlements Entitlements/BrioStudio-AppStore.entitlements "$APP"
    ;;
  release)
    IDENTITY="${DEVELOPER_ID:-}"
    if [[ -z "$IDENTITY" ]]; then
      IDENTITY=$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -n 1)
    fi
    if [[ -z "$IDENTITY" ]]; then
      print -u2 "No Developer ID Application certificate found in your keychain."
      print -u2 "Create one in Xcode > Settings > Accounts > Manage Certificates, or set DEVELOPER_ID."
      exit 1
    fi
    print "Signing with: $IDENTITY"
    codesign --force --options runtime --timestamp \
      --entitlements Entitlements/BrioStudio-DeveloperID.entitlements \
      --sign "$IDENTITY" "$APP"
    codesign --verify --deep --strict --verbose=2 "$APP"
    ;;
esac

xcrun clang -fobjc-arc -O2 -Wno-deprecated-declarations -mmacosx-version-min=14.0 "${ARCHS[@]}" \
  Sources/Camera.m Sources/probe.m -framework Foundation -framework IOKit \
  -o build/brio-probe

printf 'Built %s (%s)\n' "$APP" "$MODE"
