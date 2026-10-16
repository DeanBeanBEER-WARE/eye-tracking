#!/bin/bash
# Fetches the pinned MediaPipe runtime into Vendor/mediapipe/:
# - libmediapipe.dylib: the MediaPipe Tasks C API from the PyPI wheel (there is no official macOS Swift SDK);
#   its install name is rewritten to @rpath/libmediapipe.dylib and it is signed ad hoc so tests can load it
#   (scripts/build.sh signs it again with the app identity).
# - face_landmarker.task: the face landmarker model bundle.
# Both downloads are verified against pinned SHA-256 checksums. Runs only when the files are missing or stale.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR_DIR="$PROJECT_DIR/Vendor/mediapipe"

MEDIAPIPE_VERSION="1.1.1"
WHEEL_URL="https://files.pythonhosted.org/packages/23/22/d113d29c97a4c9459ece90d9b70e81e790550f4ee7d0574042b0b9306ff9/mediapipe-1.1.1-py3-none-macosx_11_0_arm64.whl"
WHEEL_SHA256="b22892847fbc6201959d20b2b9a1c9c34cda991e072f58ab0c38008dc789d4b1"
MODEL_URL="https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task"
MODEL_SHA256="64184e229b263107bc2b804c6625db1341ff2bb731874b0bcc2fe6544e0bc9ff"
STAMP="$MEDIAPIPE_VERSION $WHEEL_SHA256 $MODEL_SHA256"

if [ -f "$VENDOR_DIR/libmediapipe.dylib" ] && [ -f "$VENDOR_DIR/face_landmarker.task" ] \
    && [ "$(cat "$VENDOR_DIR/.stamp" 2>/dev/null)" = "$STAMP" ]; then
    echo "MediaPipe $MEDIAPIPE_VERSION already present."
    exit 0
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

verify() {
    local file="$1" expected="$2"
    local actual
    actual="$(shasum -a 256 "$file" | awk '{print $1}')"
    if [ "$actual" != "$expected" ]; then
        echo "ERROR: checksum mismatch for $(basename "$file"): $actual (expected $expected)"
        exit 1
    fi
}

echo "Downloading MediaPipe $MEDIAPIPE_VERSION wheel..."
curl -fsSL -o "$TMP_DIR/mediapipe.whl" "$WHEEL_URL"
verify "$TMP_DIR/mediapipe.whl" "$WHEEL_SHA256"
unzip -q -o "$TMP_DIR/mediapipe.whl" "mediapipe/tasks/c/libmediapipe.dylib" -d "$TMP_DIR/wheel"

echo "Downloading the face landmarker model..."
curl -fsSL -o "$TMP_DIR/face_landmarker.task" "$MODEL_URL"
verify "$TMP_DIR/face_landmarker.task" "$MODEL_SHA256"

mkdir -p "$VENDOR_DIR"
cp "$TMP_DIR/wheel/mediapipe/tasks/c/libmediapipe.dylib" "$VENDOR_DIR/libmediapipe.dylib"
chmod 644 "$VENDOR_DIR/libmediapipe.dylib"
install_name_tool -id "@rpath/libmediapipe.dylib" "$VENDOR_DIR/libmediapipe.dylib"
codesign --force --sign - "$VENDOR_DIR/libmediapipe.dylib"
cp "$TMP_DIR/face_landmarker.task" "$VENDOR_DIR/face_landmarker.task"
echo "$STAMP" > "$VENDOR_DIR/.stamp"
echo "MediaPipe $MEDIAPIPE_VERSION installed in Vendor/mediapipe."
