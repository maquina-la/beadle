#!/bin/bash
set -euo pipefail

PROJECT_ROOT=$(cd "$(dirname "$0")/.." && pwd)
APP_NAME="Beads Status Bar"
EXECUTABLE_NAME="BeadsStatusBar"
VERSION=${VERSION:-0.1.0}
BUILD_NUMBER=${BUILD_NUMBER:-1}
APP_BUNDLE="$PROJECT_ROOT/dist/$APP_NAME.app"

cd "$PROJECT_ROOT"
swift build -c release --product "$EXECUTABLE_NAME"

mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
cp ".build/release/$EXECUTABLE_NAME" "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"
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
