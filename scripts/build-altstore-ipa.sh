#!/usr/bin/env bash
#
# Build an unsigned .ipa of gterm for sideloading via AltStore / SideStore.
# AltStore re-signs the bundle on install with the user's own Apple ID, so we
# ship the Payload unsigned — no provisioning profile, no cert.
#
# Usage:
#   ./scripts/build-altstore-ipa.sh [output-dir]
#
# Output:
#   <output-dir>/gterm-<version>-<build>.ipa
#   <output-dir>/gterm-<version>-<build>.ipa.sha256
#   <output-dir>/gterm-<version>-<build>.size
#
# Defaults: output-dir = build/altstore
#
# The version/build come from project.yml; pass MARKETING_VERSION=/CURRENT_PROJECT_VERSION=
# on the env to override (mirroring how TestFlight builds are stamped).

set -euo pipefail

cd "$(dirname "$0")/.."
OUT="${1:-build/altstore}"
DERIVED="build/altstore-derived"

[ -e GhosttyKit.xcframework ] || {
  echo "GhosttyKit.xcframework is missing — run scripts/build-ghostty-xcframework.sh first." >&2
  exit 1
}

# Regenerate the Xcode project so it reflects the current project.yml.
if command -v xcodegen >/dev/null 2>&1; then
  xcodegen generate >/dev/null
fi

rm -rf "$DERIVED" "$OUT"
mkdir -p "$OUT"

# Build Release for iOS device, unsigned (AltStore signs at install time).
# We don't archive; archives require a signing identity. A direct Release build
# into a fresh DerivedData with CODE_SIGNING_ALLOWED=NO gives us a clean .app.
xcodebuild \
  -project gterm.xcodeproj \
  -scheme gterm \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGN_ENTITLEMENTS="" \
  EXPANDED_CODE_SIGN_IDENTITY="" \
  ${MARKETING_VERSION:+MARKETING_VERSION="$MARKETING_VERSION"} \
  ${CURRENT_PROJECT_VERSION:+CURRENT_PROJECT_VERSION="$CURRENT_PROJECT_VERSION"} \
  build

APP="$DERIVED/Build/Products/Release-iphoneos/gterm.app"
[ -d "$APP" ] || { echo "build did not produce $APP" >&2; exit 1; }

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Info.plist")
IPA="$OUT/gterm-${VERSION}-${BUILD}.ipa"

# Strip any leftover signing/provisioning so the bundle is cleanly unsigned —
# AltStore expects to handle signing itself.
rm -f "$APP/embedded.mobileprovision"
rm -rf "$APP/_CodeSignature"

# Assemble Payload/gterm.app and zip it into an .ipa.
STAGE="$(mktemp -d)"
mkdir -p "$STAGE/Payload"
cp -R "$APP" "$STAGE/Payload/"
( cd "$STAGE" && zip -qr "$OLDPWD/$IPA" Payload )
rm -rf "$STAGE"

# Metadata the AltStore source manifest needs.
SIZE=$(stat -f%z "$IPA")
SHA=$(shasum -a 256 "$IPA" | awk '{print $1}')
printf '%s' "$SIZE" > "$IPA.size"
printf '%s' "$SHA"  > "$IPA.sha256"

echo "==========================================="
echo "AltStore IPA built (unsigned, ready to sideload):"
echo "  $IPA"
echo "  version: $VERSION ($BUILD)"
echo "  size:    $SIZE bytes"
echo "  sha256:  $SHA"
echo
echo "Next steps:"
echo "  1. Create a GitHub release with this .ipa attached."
echo "  2. Update docs/altstore.json — paste the version, buildVersion,"
echo "     downloadURL, size, and sha256 into the 'versions' array."
echo "  3. Commit & push so GitHub Pages serves the refreshed manifest."
