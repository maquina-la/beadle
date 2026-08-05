#!/bin/bash
set -euo pipefail

PROJECT_ROOT=$(cd "$(dirname "$0")/.." && pwd)
APP_NAME="Beads Status Bar"
EXECUTABLE_NAME="BeadsStatusBar"
VERSION=${VERSION:-0.1.0}
BUILD_NUMBER=${BUILD_NUMBER:-1}
APP_BUNDLE="$PROJECT_ROOT/dist/$APP_NAME.app"
UNIVERSAL=${UNIVERSAL:-0}

cd "$PROJECT_ROOT"

if [[ "$UNIVERSAL" == "1" ]]; then
    ARM_SCRATCH="$PROJECT_ROOT/.build/release-arm64"
    INTEL_SCRATCH="$PROJECT_ROOT/.build/release-x86_64"
    UNIVERSAL_EXECUTABLE="$PROJECT_ROOT/.build/universal/$EXECUTABLE_NAME"

    swift build -c release --product "$EXECUTABLE_NAME" \
        --scratch-path "$ARM_SCRATCH" \
        --triple arm64-apple-macosx14.0
    swift build -c release --product "$EXECUTABLE_NAME" \
        --scratch-path "$INTEL_SCRATCH" \
        --triple x86_64-apple-macosx14.0

    ARM_BIN=$(swift build -c release --scratch-path "$ARM_SCRATCH" \
        --triple arm64-apple-macosx14.0 --show-bin-path)
    INTEL_BIN=$(swift build -c release --scratch-path "$INTEL_SCRATCH" \
        --triple x86_64-apple-macosx14.0 --show-bin-path)
    mkdir -p "$(dirname "$UNIVERSAL_EXECUTABLE")"
    lipo -create \
        "$ARM_BIN/$EXECUTABLE_NAME" \
        "$INTEL_BIN/$EXECUTABLE_NAME" \
        -output "$UNIVERSAL_EXECUTABLE"
    BUILT_EXECUTABLE="$UNIVERSAL_EXECUTABLE"
else
    swift build -c release --product "$EXECUTABLE_NAME"
    BUILT_EXECUTABLE="$PROJECT_ROOT/.build/release/$EXECUTABLE_NAME"
fi

mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
cp "$BUILT_EXECUTABLE" "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"
cp "packaging/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP_BUNDLE/Contents/Info.plist"

codesign --force --deep --sign "${CODE_SIGN_IDENTITY:--}" "$APP_BUNDLE"

mkdir -p "$PROJECT_ROOT/dist"
rm -f "$PROJECT_ROOT/dist/beads-status-bar-$VERSION.zip"
ditto -c -k --sequesterRsrc --keepParent \
    "$APP_BUNDLE" \
    "$PROJECT_ROOT/dist/beads-status-bar-$VERSION.zip"

echo "$APP_BUNDLE"
