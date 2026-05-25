#!/bin/bash
set -e

rm *.dmg

APP="build/macos/Build/Products/Release/Task Reporter.app"
ENTITLEMENTS="macos/Runner/Release.entitlements"

flutter clean
flutter build macos --release

rm -f "$APP/Contents/embedded.provisionprofile"

# Re-sign every embedded framework / dylib ad-hoc so they end up with the
# same (empty) Team ID as the main binary. Without this, dyld rejects them
# at launch: "mapping process and mapped file ... have different Team IDs".
# `codesign --deep` is unreliable for nested Swift frameworks (e.g. OrderedSet),
# so we sign each one explicitly instead.
find "$APP/Contents/Frameworks" -maxdepth 1 -mindepth 1 \
  \( -name "*.framework" -o -name "*.dylib" \) \
  -print 2>/dev/null \
  | while IFS= read -r f; do
      codesign --force --sign - --timestamp=none "$f"
    done

# Sign the main bundle with our entitlements (sandbox + network).
# Intentionally no `--options runtime`: hardened runtime triggers library
# validation, which fails against ad-hoc (empty-team) frameworks. We're not
# notarizing this build, so hardened runtime offers no value here.
codesign --force --sign - \
  --entitlements "$ENTITLEMENTS" \
  --timestamp=none \
  "$APP"

# Sanity checks: sandbox is actually embedded, and the whole bundle verifies.
codesign -d --entitlements :- "$APP" 2>&1 | grep -q "com.apple.security.app-sandbox" \
  || { echo "ERROR: sandbox entitlement missing from signed app"; exit 1; }
codesign --verify --deep --strict --verbose=2 "$APP" \
  || { echo "ERROR: signature verification failed"; exit 1; }

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
nvm use --lts
npm install --global create-dmg
create-dmg "$APP" --overwrite
