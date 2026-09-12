#!/bin/zsh
# Cut a release: bump version → build → zip → appcast → gh release → push.
# Usage: scripts/release.sh 0.2.0
set -euo pipefail
cd "$(dirname "$0")/.."

VER=${1:?usage: release.sh <version>}
REPO=MartinMikusat/hw_opencode_launcher
TOOLS=.build/sparkle-tools/bin

# Version bump in Info.plist (both keys track the semver).
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VER" Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VER" Info.plist

scripts/build-app.sh

# Zip with ditto (preserves signature + metadata) into the releases pool.
mkdir -p releases
ZIP="releases/OpenPad-$VER.zip"
rm -f "$ZIP"
ditto -ck --sequesterRsrc --keepParent build/OpenPad.app "$ZIP"

# generate_appcast signs the zip (EdDSA key lives in the Keychain) and
# rewrites appcast.xml with every archive in releases/.
"$TOOLS/generate_appcast" \
    --download-url-prefix "https://github.com/$REPO/releases/download/v$VER/" \
    releases/
mv releases/appcast.xml appcast.xml

gh release create "v$VER" "$ZIP" --repo "$REPO" --title "OpenPad $VER" --generate-notes
git add Info.plist appcast.xml
git commit -m "Release $VER"
git push
echo "released v$VER"
