#!/bin/zsh
# Builds build/MacIsland.app from the Swift package (no Xcode project required).
set -euo pipefail
cd "$(dirname "$0")/.."
# Version comes from Resources/version.env (the single source); the build is always release.
source Resources/version.env
# Universal (arm64 + x86_64). `swift build --arch a --arch b` needs Xcode's XCBuild, which Command Line
# Tools lack, so build each slice for its own triple and merge them with lipo.
SLICES=()
for ARCH in arm64 x86_64; do
  TRIPLE="$ARCH-apple-macosx14.0"
  swift build -c release --triple "$TRIPLE"
  SLICES+=("$(swift build -c release --triple "$TRIPLE" --show-bin-path)/MacIsland")
done
BIN="build/MacIsland-universal"
mkdir -p build
lipo -create "${SLICES[@]}" -output "$BIN"
APP="build/MacIsland.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MacIsland"
rm -f "$BIN"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $MARKETING_VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "Built $APP ($MARKETING_VERSION build $BUILD_NUMBER, release)"
