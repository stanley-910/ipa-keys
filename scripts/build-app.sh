#!/bin/sh
# Build a release binary, wrap it in dist/ipa-keys.app, and sign it.
#
# Signing identity: IPA_KEYS_SIGN_IDENTITY names a code-signing certificate
# in the login keychain (default ipa-keys-dev, then dictate-dev if that is
# the one this Mac has; scripts/make-cert.sh makes one). A stable identity
# keeps the Accessibility grant across rebuilds. Without one the app is
# signed ad hoc and macOS asks for Accessibility again after every build.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
BUNDLE_ID="cc.stanleywang.ipa-keys"
APP="$ROOT/dist/ipa-keys.app"
has_identity() { security find-identity -v -p codesigning 2>/dev/null | grep -q "\"$1\""; }
if [ -n "${IPA_KEYS_SIGN_IDENTITY:-}" ]; then IDENTITY="$IPA_KEYS_SIGN_IDENTITY"
elif has_identity ipa-keys-dev; then IDENTITY=ipa-keys-dev
else IDENTITY=dictate-dev; fi

mkdir -p dist
echo "building (the first time takes a few minutes)"
if ! swift build -c release >dist/build.log 2>&1; then
  tail -20 dist/build.log >&2
  echo "build failed (full output: $ROOT/dist/build.log)" >&2
  exit 1
fi
tail -1 dist/build.log
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/release/ipa-keys" "$APP/Contents/MacOS/ipa-keys"
cp "Resources/Info.plist" "$APP/Contents/Info.plist"
# Which commit this is, and where the source lives (for the Update menu item).
COMMIT="$(git describe --always --dirty 2>/dev/null || echo unknown)"
/usr/libexec/PlistBuddy -c "Add :IPAKeysCommit string $COMMIT" -c "Add :IPAKeysSource string $ROOT" "$APP/Contents/Info.plist"

if has_identity "$IDENTITY"; then
  codesign --force --sign "$IDENTITY" --identifier "$BUNDLE_ID" "$APP"
  echo "signed with $IDENTITY"
else
  codesign --force --sign - --identifier "$BUNDLE_ID" "$APP"
  echo "ad-hoc signed (no '$IDENTITY' certificate; the Accessibility grant will not survive rebuilds)"
fi
codesign --verify --verbose=1 "$APP"
echo "built $APP ($COMMIT)"
