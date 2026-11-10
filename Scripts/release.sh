#!/bin/zsh
# build -> sign -> verify -> DMG (-> optional notarize). No credentials live here.
#   SIGN_IDENTITY   codesign identity (default "Mac Island Signing"; use a Developer ID for notarization)
#   NOTARY_PROFILE  optional notarytool keychain profile; when set, the DMG is notarized and stapled
set -euo pipefail
cd "$(dirname "$0")/.."
source Resources/version.env
IDENTITY="${SIGN_IDENTITY:-Mac Island Signing}"
APP="build/MacIsland.app"
ENT="Resources/MacIsland.entitlements"
DMG="build/MacIsland-$MARKETING_VERSION.dmg"
VOL="Mac Island"

echo "==> Build"
Scripts/build_app.sh

echo "==> Sign app as '$IDENTITY'"
# A secure timestamp needs Apple's server and is required for notarization; otherwise sign offline-safe.
if [[ -n "${NOTARY_PROFILE:-}" ]]; then TS="--timestamp"; else TS="--timestamp=none"; fi
# The bundle has no nested code (single executable), so one signing pass is enough. No --deep.
codesign --force --sign "$IDENTITY" --options runtime $TS --entitlements "$ENT" "$APP"

echo "==> Verify app"
codesign --verify --strict --verbose=2 "$APP"
codesign -d --entitlements - "$APP"
lipo -info "$APP/Contents/MacOS/MacIsland"
spctl --assess --type execute -vv "$APP" || echo "(spctl rejection is expected without notarization)"

echo "==> Create DMG"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/Mac Island.app"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "$VOL" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
codesign --force --sign "$IDENTITY" $TS "$DMG"
codesign --verify --verbose=2 "$DMG"

echo "==> Verify DMG contents"
MNT="$(mktemp -d)"
hdiutil attach "$DMG" -mountpoint "$MNT" -nobrowse -readonly -quiet
trap 'hdiutil detach "$MNT" -quiet >/dev/null 2>&1 || true; rm -rf "$STAGE" "$MNT"' EXIT
codesign --verify --strict --verbose=2 "$MNT/Mac Island.app"
[[ -L "$MNT/Applications" ]] || { echo "Applications link missing" >&2; exit 1; }
hdiutil detach "$MNT" -quiet

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  if xcrun --find notarytool >/dev/null 2>&1; then
    echo "==> Notarize"
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
  else
    echo "notarytool unavailable (needs Xcode or recent Command Line Tools); skipping notarization."
  fi
fi
echo "Done: $DMG"
