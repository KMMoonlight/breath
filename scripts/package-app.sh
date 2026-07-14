#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VERSION=${VERSION:?Set VERSION, for example 1.0.0}
BUILD_NUMBER=${BUILD_NUMBER:-1}
SPARKLE_FEED_URL=${SPARKLE_FEED_URL:?Set SPARKLE_FEED_URL to an HTTPS appcast URL}
SPARKLE_PUBLIC_KEY=${SPARKLE_PUBLIC_KEY:?Set SPARKLE_PUBLIC_KEY to the Sparkle Ed25519 public key}
OUTPUT_DIR=${OUTPUT_DIR:-"$ROOT/dist"}
PACKAGE_NAME="Breath-$VERSION"
APP="$OUTPUT_DIR/$PACKAGE_NAME.app"
ARCHIVE="$OUTPUT_DIR/$PACKAGE_NAME.zip"
ARM_SCRATCH="$ROOT/.build/release-arm64"
INTEL_SCRATCH="$ROOT/.build/release-x86_64"

case "$SPARKLE_FEED_URL" in
    https://*) ;;
    *) echo "SPARKLE_FEED_URL must use HTTPS" >&2; exit 2 ;;
esac

if [ -e "$APP" ] || [ -e "$ARCHIVE" ]; then
    echo "Release output already exists for $PACKAGE_NAME" >&2
    exit 2
fi

mkdir -p "$OUTPUT_DIR" "$APP/Contents/MacOS" "$APP/Contents/Frameworks"

swift build \
    --package-path "$ROOT" \
    --configuration release \
    --triple arm64-apple-macosx14.0 \
    --scratch-path "$ARM_SCRATCH" \
    --product Breath
swift build \
    --package-path "$ROOT" \
    --configuration release \
    --triple x86_64-apple-macosx14.0 \
    --scratch-path "$INTEL_SCRATCH" \
    --product Breath

ARM_BIN=$(swift build --package-path "$ROOT" --configuration release --triple arm64-apple-macosx14.0 --scratch-path "$ARM_SCRATCH" --show-bin-path)
INTEL_BIN=$(swift build --package-path "$ROOT" --configuration release --triple x86_64-apple-macosx14.0 --scratch-path "$INTEL_SCRATCH" --show-bin-path)

lipo -create "$ARM_BIN/Breath" "$INTEL_BIN/Breath" -output "$APP/Contents/MacOS/Breath"
ditto "$ARM_BIN/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
install_name_tool -add_rpath @executable_path/../Frameworks "$APP/Contents/MacOS/Breath"

ditto "$ROOT/Resources/Info.plist.in" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :SUFeedURL $SPARKLE_FEED_URL" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :SUPublicEDKey $SPARKLE_PUBLIC_KEY" "$APP/Contents/Info.plist"

if [ -n "${CODE_SIGN_IDENTITY:-}" ]; then
    SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
    codesign --force --options runtime --timestamp --sign "$CODE_SIGN_IDENTITY" "$SPARKLE/XPCServices/Installer.xpc"
    codesign --force --options runtime --timestamp --preserve-metadata=entitlements --sign "$CODE_SIGN_IDENTITY" "$SPARKLE/XPCServices/Downloader.xpc"
    codesign --force --options runtime --timestamp --sign "$CODE_SIGN_IDENTITY" "$SPARKLE/Autoupdate"
    codesign --force --options runtime --timestamp --sign "$CODE_SIGN_IDENTITY" "$SPARKLE/Updater.app"
    codesign --force --options runtime --timestamp --sign "$CODE_SIGN_IDENTITY" "$APP/Contents/Frameworks/Sparkle.framework"
    codesign --force --options runtime --timestamp --sign "$CODE_SIGN_IDENTITY" "$APP/Contents/MacOS/Breath"
    codesign --force --options runtime --timestamp --sign "$CODE_SIGN_IDENTITY" "$APP"
else
    codesign --force --sign - "$APP/Contents/MacOS/Breath"
    codesign --force --sign - "$APP"
fi

codesign --verify --deep --strict --verbose=2 "$APP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ARCHIVE"

if [ "${NOTARIZE:-0}" = "1" ]; then
    : "${APPLE_ID:?Set APPLE_ID when NOTARIZE=1}"
    : "${APPLE_APP_SPECIFIC_PASSWORD:?Set APPLE_APP_SPECIFIC_PASSWORD when NOTARIZE=1}"
    : "${APPLE_TEAM_ID:?Set APPLE_TEAM_ID when NOTARIZE=1}"
    xcrun notarytool submit "$ARCHIVE" \
        --apple-id "$APPLE_ID" \
        --password "$APPLE_APP_SPECIFIC_PASSWORD" \
        --team-id "$APPLE_TEAM_ID" \
        --wait
    xcrun stapler staple "$APP"
    TEMP_ARCHIVE=$(mktemp "$OUTPUT_DIR/.Breath-notarized.XXXXXX.zip")
    ditto -c -k --sequesterRsrc --keepParent "$APP" "$TEMP_ARCHIVE"
    mv -f "$TEMP_ARCHIVE" "$ARCHIVE"
    xcrun stapler validate "$APP"
fi

lipo -archs "$APP/Contents/MacOS/Breath"
echo "$APP"
echo "$ARCHIVE"
