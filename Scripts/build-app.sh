#!/bin/sh
# Builds an app with SwiftPM and assembles an ad-hoc signed .app bundle in build/.
# Every brand-dependent value comes from Branding.xcconfig, the same way an Xcode
# project would use it, so this script never names the product.
#
#   Scripts/build-app.sh                       the library app
#   Scripts/build-app.sh importer              the standalone importer
#   Scripts/build-app.sh all                   both
#   CONFIGURATION=debug Scripts/build-app.sh   builds a debug bundle

set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
CONFIGURATION=${CONFIGURATION:-release}
KIND=${1:-library}

case $KIND in
    all)
        "$0" library
        "$0" importer
        exit 0
        ;;
    library)
        PREFIX=
        SWIFT_PRODUCT=PhotoApp
        INFO_TEMPLATE="$ROOT/Support/Info.plist"
        ;;
    importer)
        PREFIX=IMPORTER_
        SWIFT_PRODUCT=PhotoImporter
        INFO_TEMPLATE="$ROOT/Support/Importer-Info.plist"
        ;;
    *)
        echo "usage: $0 [library|importer|all]" >&2
        exit 2
        ;;
esac

# setting KEY FILE: prints the last "KEY = value" assignment in an xcconfig file.
setting() {
    sed -n -e "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*//p" "$2" | sed -e 's/[[:space:]]*$//' | tail -n 1
}

BRANDING="$ROOT/Branding.xcconfig"
VERSIONS="$ROOT/Support/Version.xcconfig"
PRODUCT_NAME=$(setting "${PREFIX}PRODUCT_NAME" "$BRANDING")
PRODUCT_DISPLAY_NAME=$(setting "${PREFIX}PRODUCT_DISPLAY_NAME" "$BRANDING")
PRODUCT_BUNDLE_IDENTIFIER=$(setting "${PREFIX}PRODUCT_BUNDLE_IDENTIFIER" "$BRANDING")
PRODUCT_URL_SCHEME=$(setting PRODUCT_URL_SCHEME "$BRANDING")
PRESET_FILE_EXTENSION=$(setting PRESET_FILE_EXTENSION "$BRANDING")
MARKETING_VERSION=$(setting MARKETING_VERSION "$VERSIONS")
CURRENT_PROJECT_VERSION=$(setting CURRENT_PROJECT_VERSION "$VERSIONS")
EXECUTABLE_NAME=$PRODUCT_NAME

for name in PRODUCT_NAME PRODUCT_DISPLAY_NAME PRODUCT_BUNDLE_IDENTIFIER PRODUCT_URL_SCHEME \
            PRESET_FILE_EXTENSION MARKETING_VERSION CURRENT_PROJECT_VERSION; do
    eval "value=\${$name}"
    if [ -z "$value" ]; then
        echo "error: $name is not set in Branding.xcconfig or Support/Version.xcconfig" >&2
        exit 1
    fi
done

cd "$ROOT"

# The SDK an app links against, not its minimum, decides which design macOS
# runs it in: built with the macOS 26 SDK or later it gets the current one.
# Swift Build (SwiftPM's default build system) links through swiftc, which
# hands clang the SDK as --sysroot, and clang reads the SDK version only from
# -isysroot or SDKROOT, which Swift Build does not pass on. Without -isysroot
# the executable records its minimum (15.0) as its SDK.
SDK_PATH=$(xcrun --sdk macosx --show-sdk-path)
swift_build() {
    swift build -c "$CONFIGURATION" \
        -Xswiftc -Xclang-linker -Xswiftc -isysroot -Xswiftc -Xclang-linker -Xswiftc "$SDK_PATH" "$@"
}

swift_build --product "$SWIFT_PRODUCT"
swift_build --product catalog-strings
swift_build --product app-icon
BIN=$(swift_build --show-bin-path)

LINKED_SDK=$(vtool -show-build "$BIN/$SWIFT_PRODUCT" | awk '$1 == "sdk" { print $2; exit }')
case ${LINKED_SDK%%.*} in
    ''|*[!0-9]*) LINKED_MAJOR=0 ;;
    *) LINKED_MAJOR=${LINKED_SDK%%.*} ;;
esac
if [ "$LINKED_MAJOR" -lt 26 ]; then
    echo "error: $SWIFT_PRODUCT links the macOS ${LINKED_SDK:-unknown} SDK; the app needs the macOS 26 SDK or later" \
         "(Xcode 26 or later, selected with xcode-select)" >&2
    exit 1
fi

APP="$ROOT/build/$PRODUCT_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/$SWIFT_PRODUCT" "$APP/Contents/MacOS/$EXECUTABLE_NAME"
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
    -e 's|\$(PRESET_FILE_EXTENSION)|'"$(escape "$PRESET_FILE_EXTENSION")"'|g' \
    -e 's|\$(EXECUTABLE_NAME)|'"$(escape "$EXECUTABLE_NAME")"'|g' \
    -e 's|\$(MARKETING_VERSION)|'"$(escape "$MARKETING_VERSION")"'|g' \
    -e 's|\$(CURRENT_PROJECT_VERSION)|'"$(escape "$CURRENT_PROJECT_VERSION")"'|g' \
    "$INFO_TEMPLATE" > "$APP/Contents/Info.plist"
if grep -q '\$(' "$APP/Contents/Info.plist"; then
    echo "error: unresolved build variable in Info.plist:" >&2
    grep '\$(' "$APP/Contents/Info.plist" >&2
    exit 1
fi
plutil -lint -s "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

"$BIN/catalog-strings" "$ROOT/Sources/PhotoUI/Resources/Localizable.xcstrings" "$APP/Contents/Resources"

ICONSET="$ROOT/build/$SWIFT_PRODUCT.iconset"
"$BIN/app-icon" "$ROOT/Support/AppIcon.png" "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

codesign --force --sign - --timestamp=none "$APP"
# Finder and the Dock cache icons by bundle; a fresh date makes them look again.
touch "$APP"
echo "$APP"
