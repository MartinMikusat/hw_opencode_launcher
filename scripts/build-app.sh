#!/bin/zsh
# Build OpenPad.app: swift release build → .app bundle → Developer ID sign.
set -euo pipefail
cd "$(dirname "$0")/.."

APP=build/OpenPad.app
IDENTITY="Developer ID Application: Martin Mikusat (5242LK8KGW)"
swift build -c release

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp .build/release/OpenPad "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/"

# Sparkle ships as an XCFramework binary artifact — embed the macOS slice.
SPARKLE=$(find .build/artifacts -name Sparkle.framework -path "*macos*" | head -1)
cp -R "$SPARKLE" "$APP/Contents/Frameworks/"

codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP/Contents/Frameworks/Sparkle.framework"
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
echo "built $APP"
