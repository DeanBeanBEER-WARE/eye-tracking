#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST_DIR="$PROJECT_DIR/dist"
BUILD_DIR="$PROJECT_DIR/build"
APP_NAME="EyeTracking"
VOLUME_NAME="Eye Tracking"
ENTITLEMENTS="$PROJECT_DIR/Config/EyeTracking.entitlements"
SIGN_IDENTITY="${SIGN_IDENTITY:-WhisperApp Dev Signing}"

APP_VERSION="$(sed -n 's/^MARKETING_VERSION *= *\(.*\)$/\1/p' "$PROJECT_DIR/Config/Version.xcconfig" | tr -d '[:space:]')"
if [ -z "$APP_VERSION" ]; then
    echo "ERROR: MARKETING_VERSION not found in Config/Version.xcconfig"
    exit 1
fi

echo "=== Eye Tracking Build ==="
echo "Project: $PROJECT_DIR"
echo "Version: $APP_VERSION"

rm -rf "$DIST_DIR" "$BUILD_DIR"
mkdir -p "$DIST_DIR"

cd "$PROJECT_DIR"
"$SCRIPT_DIR/fetch_mediapipe.sh"
xcodegen generate --quiet

CERT_HASH="$(security find-identity -v -p codesigning 2>/dev/null \
    | grep "\"$SIGN_IDENTITY\"" | head -n 1 | awk '{print $2}' || true)"
if [ -n "$CERT_HASH" ]; then
    echo "Signing with identity '$SIGN_IDENTITY' ($CERT_HASH)..."
    SIGN_ARG="$CERT_HASH"
else
    echo "WARNING: identity '$SIGN_IDENTITY' not found."
    echo "         Falling back to ad-hoc signing (TCC grants will reset)."
    SIGN_ARG="-"
fi

xcodebuild \
    -project "$APP_NAME.xcodeproj" \
    -scheme "$APP_NAME" \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -derivedDataPath "$BUILD_DIR" \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=NO \
    CODE_SIGNING_ALLOWED=NO \
    -quiet \
    build

BUILT_APP="$BUILD_DIR/Build/Products/Release/$APP_NAME.app"
if [ ! -d "$BUILT_APP" ]; then
    echo "ERROR: app bundle not found at $BUILT_APP"
    exit 1
fi

APP_PATH="$DIST_DIR/$APP_NAME.app"
ditto "$BUILT_APP" "$APP_PATH"
echo "Architectures: $(lipo -archs "$APP_PATH/Contents/MacOS/$APP_NAME")"

MEDIAPIPE="$APP_PATH/Contents/Frameworks/libmediapipe.dylib"
if [ ! -f "$MEDIAPIPE" ] || [ ! -f "$APP_PATH/Contents/Resources/face_landmarker.task" ]; then
    echo "ERROR: MediaPipe library or model missing in the app bundle"
    exit 1
fi
codesign --force --options runtime --timestamp=none --sign "$SIGN_ARG" "$MEDIAPIPE"

RESOURCES="$APP_PATH/Contents/Resources"
cp "$PROJECT_DIR/LICENSE" "$RESOURCES/LICENSE.txt"
cp "$PROJECT_DIR/THIRD_PARTY_NOTICES.md" "$RESOURCES/THIRD_PARTY_NOTICES.md"
cp "$PROJECT_DIR/Vendor/mediapipe/LICENSE" "$RESOURCES/MediaPipe-LICENSE.txt"
cp "$PROJECT_DIR/Vendor/mediapipe/NOTICE" "$RESOURCES/MediaPipe-NOTICE.txt"

codesign --force --options runtime --timestamp=none \
    --entitlements "$ENTITLEMENTS" \
    --sign "$SIGN_ARG" \
    "$APP_PATH"
codesign --verify --strict --verbose=2 "$APP_PATH"

DMG_PATH="$DIST_DIR/$APP_NAME-$APP_VERSION.dmg"
STAGING="$BUILD_DIR/dmg_staging"
rm -rf "$STAGING"
mkdir -p "$STAGING"
ditto "$APP_PATH" "$STAGING/$APP_NAME.app"
ln -s /Applications "$STAGING/Applications"
cp "$PROJECT_DIR/LICENSE" "$STAGING/LICENSE.txt"
cp "$PROJECT_DIR/THIRD_PARTY_NOTICES.md" "$STAGING/THIRD_PARTY_NOTICES.md"
hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGING" \
    -ov \
    -format UDZO \
    "$DMG_PATH" > /dev/null
rm -rf "$STAGING"

echo ""
echo "=== Build Complete ==="
echo "App: $APP_PATH"
ls -lh "$DMG_PATH"
