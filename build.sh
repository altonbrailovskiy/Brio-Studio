#!/bin/zsh
# Builds Studio Cam Controls.app and the brio-probe CLI.
#
#   ./build.sh             Local build, ad-hoc signed (default)
#   ./build.sh --sandbox   Local build with App Sandbox on, to test App Store compatibility
#   ./build.sh --release   Developer ID signed, hardened runtime, ready for ./notarize.sh
#   ./build.sh --appstore  Apple Distribution signed .pkg for upload with Transporter
#
# Optional environment variables:
#   BUNDLE_ID          Override the bundle identifier (default: value in Info.plist)
#   BUILD_NUMBER       Override CFBundleVersion. Each App Store upload needs a higher one
#   DEVELOPER_ID       Signing identity for --release, e.g.
#                      "Developer ID Application: Alton Brailovskiy (TEAMID)".
#                      If unset, the first Developer ID Application identity in
#                      your keychain is used.
#   DISTRIBUTION_ID    Signing identity for --appstore (default: first "Apple Distribution")
#   INSTALLER_ID       Installer identity for --appstore (default: first
#                      "3rd Party Mac Developer Installer" / "Mac Installer Distribution")
#   PROVISIONING_PROFILE  Mac App Store profile for --appstore
#                      (default: ./StudioCamControls_AppStore.provisionprofile)
set -euo pipefail
cd "${0:A:h}"

MODE="local"
case "${1:-}" in
  "") ;;
  --sandbox) MODE="sandbox" ;;
  --release) MODE="release" ;;
  --appstore) MODE="appstore" ;;
  -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) print -u2 "Unknown option: $1 (use --sandbox, --release, --appstore, or no option)"; exit 64 ;;
esac

APP="build/Studio Cam Controls.app"
PLIST="$APP/Contents/Info.plist"
ARCHS=(-arch arm64 -arch x86_64)

find_identity() {
  # Prints the first valid code-signing identity whose name starts with any of the given prefixes.
  local prefix line
  for prefix in "$@"; do
    line=$(security find-identity -v -p codesigning 2>/dev/null | sed -n "s/.*\"\(${prefix}[^\"]*\)\".*/\1/p" | head -n 1)
    if [[ -n "$line" ]]; then print -r -- "$line"; return 0; fi
  done
  return 1
}

find_installer_identity() {
  # Installer certificates aren't code-signing identities, so search the basic policy.
  local prefix line
  for prefix in "$@"; do
    line=$(security find-identity -v 2>/dev/null | sed -n "s/.*\"\(${prefix}[^\"]*\)\".*/\1/p" | head -n 1)
    if [[ -n "$line" ]]; then print -r -- "$line"; return 0; fi
  done
  return 1
}

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

xcrun clang -fobjc-arc -O2 -Wall -Wextra -Wno-unused-parameter -Wno-deprecated-declarations \
  -mmacosx-version-min=14.0 "${ARCHS[@]}" \
  Sources/Camera.m Sources/PreviewTools.m Sources/Optimizer.m Sources/main.m \
  -framework Cocoa -framework AVFoundation -framework Vision -framework CoreImage \
  -framework CoreMedia -framework CoreVideo -framework IOKit \
  -o "$APP/Contents/MacOS/StudioCamControls"

cp Assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Assets/PrivacyInfo.xcprivacy "$APP/Contents/Resources/PrivacyInfo.xcprivacy"
cp Info.plist "$PLIST"
if [[ -n "${BUNDLE_ID:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$PLIST"
fi
if [[ -n "${BUILD_NUMBER:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$PLIST"
fi
# Downloaded files (icons, profiles) can carry com.apple.quarantine and other
# extended attributes, which the App Store rejects (ITMS-91109).
strip_attributes() { xattr -cr "$APP"; }
APP_BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$PLIST")
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST")
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PLIST")

case "$MODE" in
  local)
    strip_attributes
    codesign --force --sign - "$APP"
    ;;

  sandbox)
    strip_attributes
    codesign --force --sign - --entitlements Entitlements/StudioCamControls-AppStore.entitlements "$APP"
    ;;

  release)
    IDENTITY="${DEVELOPER_ID:-$(find_identity "Developer ID Application: " || true)}"
    if [[ -z "$IDENTITY" ]]; then
      print -u2 "No Developer ID Application certificate found in your keychain."
      print -u2 "Create one in Xcode > Settings > Accounts > Manage Certificates, or set DEVELOPER_ID."
      exit 1
    fi
    print "Signing with: $IDENTITY"
    strip_attributes
    codesign --force --options runtime --timestamp \
      --entitlements Entitlements/StudioCamControls-DeveloperID.entitlements \
      --sign "$IDENTITY" "$APP"
    codesign --verify --deep --strict --verbose=2 "$APP"
    ;;

  appstore)
    PROFILE="${PROVISIONING_PROFILE:-StudioCamControls_AppStore.provisionprofile}"
    if [[ ! -f "$PROFILE" ]]; then
      print -u2 "Provisioning profile not found: $PROFILE"
      print -u2 "Download your Mac App Store profile from developer.apple.com and save it here as"
      print -u2 "StudioCamControls_AppStore.provisionprofile, or set PROVISIONING_PROFILE."
      exit 1
    fi

    PROFILE_PLIST="build/profile.plist"
    security cms -D -i "$PROFILE" > "$PROFILE_PLIST"
    TEAM_ID=$(/usr/libexec/PlistBuddy -c "Print :TeamIdentifier:0" "$PROFILE_PLIST")
    PROFILE_APP_ID=$(/usr/libexec/PlistBuddy -c "Print :Entitlements:com.apple.application-identifier" "$PROFILE_PLIST")
    if [[ "$PROFILE_APP_ID" != "$TEAM_ID.$APP_BUNDLE_ID" ]]; then
      print -u2 "The profile is for $PROFILE_APP_ID, but the app is $TEAM_ID.$APP_BUNDLE_ID."
      print -u2 "Create the profile for the $APP_BUNDLE_ID app ID, or set BUNDLE_ID to match it."
      exit 1
    fi

    DIST_IDENTITY="${DISTRIBUTION_ID:-$(find_identity "Apple Distribution: " "3rd Party Mac Developer Application: " || true)}"
    INSTALLER_IDENTITY="${INSTALLER_ID:-$(find_installer_identity "3rd Party Mac Developer Installer: " "Mac Installer Distribution: " || true)}"
    if [[ -z "$DIST_IDENTITY" ]]; then
      print -u2 "No Apple Distribution certificate found. Create one in Xcode > Settings > Accounts > Manage Certificates."
      exit 1
    fi
    if [[ -z "$INSTALLER_IDENTITY" ]]; then
      print -u2 "No Mac Installer Distribution certificate found. Create one in Xcode > Settings > Accounts > Manage Certificates."
      exit 1
    fi

    cp "$PROFILE" "$APP/Contents/embedded.provisionprofile"
    strip_attributes

    ENTITLEMENTS="build/StudioCamControls-AppStore.signed.entitlements"
    cp Entitlements/StudioCamControls-AppStore.entitlements "$ENTITLEMENTS"
    /usr/libexec/PlistBuddy -c "Add :com.apple.application-identifier string $TEAM_ID.$APP_BUNDLE_ID" "$ENTITLEMENTS"
    /usr/libexec/PlistBuddy -c "Add :com.apple.developer.team-identifier string $TEAM_ID" "$ENTITLEMENTS"

    print "Signing app with: $DIST_IDENTITY"
    codesign --force --timestamp --entitlements "$ENTITLEMENTS" --sign "$DIST_IDENTITY" "$APP"
    codesign --verify --deep --strict --verbose=2 "$APP"

    PKG="build/Studio-Cam-Controls-$VERSION-$BUILD.pkg"
    rm -f "$PKG"
    print "Signing installer with: $INSTALLER_IDENTITY"
    productbuild --component "$APP" /Applications --sign "$INSTALLER_IDENTITY" "$PKG"
    rm -f "$PROFILE_PLIST"
    printf 'Built %s. Upload it with the Transporter app.\n' "$PKG"
    ;;
esac

xcrun clang -fobjc-arc -O2 -Wno-deprecated-declarations -mmacosx-version-min=14.0 "${ARCHS[@]}" \
  Sources/Camera.m Sources/probe.m -framework Foundation -framework IOKit \
  -o build/brio-probe

printf 'Built %s %s (%s), %s, %s mode\n' "$APP" "$VERSION" "$BUILD" "$APP_BUNDLE_ID" "$MODE"
