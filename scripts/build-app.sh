#!/bin/zsh
# Build OpenPad.app: swift release build → .app bundle → ad-hoc sign.
set -euo pipefail
cd "$(dirname "$0")/.."

APP=build/OpenPad.app
swift build -c release

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/OpenPad "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/"

codesign --force --sign - "$APP"
echo "built $APP"
