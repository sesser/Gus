#!/bin/sh
# Builds the app with SwiftPM and assembles an ad-hoc signed .app bundle in build/.
# Every brand-dependent value comes from Branding.xcconfig, the same way an Xcode
# project would use it, so this script never names the product.
#
#   CONFIGURATION=debug Scripts/build-app.sh   builds a debug bundle

set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
CONFIGURATION=${CONFIGURATION:-release}

# setting KEY FILE: prints the last "KEY = value" assignment in an xcconfig file.
setting() {
    sed -n -e "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*//p" "$2" | sed -e 's/[[:space:]]*$//' | tail -n 1
}

BRANDING="$ROOT/Branding.xcconfig"
VERSIONS="$ROOT/Support/Version.xcconfig"
PRODUCT_NAME=$(setting PRODUCT_NAME "$BRANDING")
PRODUCT_DISPLAY_NAME=$(setting PRODUCT_DISPLAY_NAME "$BRANDING")
PRODUCT_BUNDLE_IDENTIFIER=$(setting PRODUCT_BUNDLE_IDENTIFIER "$BRANDING")
PRODUCT_URL_SCHEME=$(setting PRODUCT_URL_SCHEME "$BRANDING")
MARKETING_VERSION=$(setting MARKETING_VERSION "$VERSIONS")
CURRENT_PROJECT_VERSION=$(setting CURRENT_PROJECT_VERSION "$VERSIONS")
EXECUTABLE_NAME=$PRODUCT_NAME

for name in PRODUCT_NAME PRODUCT_DISPLAY_NAME PRODUCT_BUNDLE_IDENTIFIER PRODUCT_URL_SCHEME \
            MARKETING_VERSION CURRENT_PROJECT_VERSION; do
    eval "value=\${$name}"
    if [ -z "$value" ]; then
        echo "error: $name is not set in Branding.xcconfig or Support/Version.xcconfig" >&2
        exit 1
    fi
done

cd "$ROOT"
swift build -c "$CONFIGURATION" --product PhotoApp
swift build -c "$CONFIGURATION" --product catalog-strings
swift build -c "$CONFIGURATION" --product app-icon
BIN=$(swift build -c "$CONFIGURATION" --show-bin-path)

APP="$ROOT/build/$PRODUCT_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/PhotoApp" "$APP/Contents/MacOS/$EXECUTABLE_NAME"
for bundle in "$BIN"/*.bundle "$BIN"/*.resources; do
    if [ -d "$bundle" ]; then
        cp -R "$bundle" "$APP/Contents/Resources/"
    fi
done

# Escapes a value for use as a sed replacement with "|" as the delimiter.
escape() {
    printf '%s' "$1" | sed -e 's/[\\|&]/\\&/g'
}

sed -e 's|\$(PRODUCT_NAME)|'"$(escape "$PRODUCT_NAME")"'|g' \
    -e 's|\$(PRODUCT_DISPLAY_NAME)|'"$(escape "$PRODUCT_DISPLAY_NAME")"'|g' \
    -e 's|\$(PRODUCT_BUNDLE_IDENTIFIER)|'"$(escape "$PRODUCT_BUNDLE_IDENTIFIER")"'|g' \
    -e 's|\$(PRODUCT_URL_SCHEME)|'"$(escape "$PRODUCT_URL_SCHEME")"'|g' \
    -e 's|\$(EXECUTABLE_NAME)|'"$(escape "$EXECUTABLE_NAME")"'|g' \
    -e 's|\$(MARKETING_VERSION)|'"$(escape "$MARKETING_VERSION")"'|g' \
    -e 's|\$(CURRENT_PROJECT_VERSION)|'"$(escape "$CURRENT_PROJECT_VERSION")"'|g' \
    "$ROOT/Support/Info.plist" > "$APP/Contents/Info.plist"
if grep -q '\$(' "$APP/Contents/Info.plist"; then
    echo "error: unresolved build variable in Info.plist:" >&2
    grep '\$(' "$APP/Contents/Info.plist" >&2
    exit 1
fi
plutil -lint -s "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

"$BIN/catalog-strings" "$ROOT/Sources/PhotoApp/Resources/Localizable.xcstrings" "$APP/Contents/Resources"

ICONSET="$ROOT/build/AppIcon.iconset"
"$BIN/app-icon" "$ROOT/Support/AppIcon.png" "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

codesign --force --sign - --timestamp=none "$APP"
# Finder and the Dock cache icons by bundle; a fresh date makes them look again.
touch "$APP"
echo "$APP"
