#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
APP="build/Brio Studio.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
xcrun clang -fobjc-arc -O2 -Wall -Wextra -Wno-unused-parameter -Wno-deprecated-declarations -mmacosx-version-min=14.0 Sources/Camera.m Sources/PreviewTools.m Sources/Optimizer.m Sources/main.m -framework Cocoa -framework AVFoundation -framework Vision -framework CoreImage -framework CoreMedia -framework CoreVideo -framework IOKit -o "$APP/Contents/MacOS/BrioStudio"
cp Assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
xcrun clang -fobjc-arc -O2 -Wno-deprecated-declarations Sources/Camera.m Sources/probe.m -framework Foundation -framework IOKit -o build/brio-probe
printf 'Built %s\n' "$APP"
