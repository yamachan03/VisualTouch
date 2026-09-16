#!/bin/bash
# VisualTouch.app（GUI）と、同梱の vtouch（CLI）をビルドする
set -euo pipefail
cd "$(dirname "$0")"

APP="VisualTouch.app"
MIN_OS="13.0"
ARCH="$(uname -m)"
TARGET="${ARCH}-apple-macos${MIN_OS}"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "GUI をビルド中..."
swiftc -O -target "$TARGET" \
    -framework SwiftUI -framework AppKit \
    -o "$APP/Contents/MacOS/VisualTouch" \
    Sources/Core/*.swift Sources/App/*.swift

echo "vtouch をビルド中..."
swiftc -O -target "$TARGET" \
    -o "$APP/Contents/MacOS/vtouch" \
    Sources/Core/*.swift Sources/CLI/main.swift

cp Info.plist "$APP/Contents/Info.plist"
cp -R Resources/*.lproj "$APP/Contents/Resources/"
codesign --force --sign - "$APP/Contents/MacOS/vtouch"
codesign --force --sign - "$APP"

echo "ビルド完了: $(pwd)/$APP"
echo "vtouch を入れるには: ./install-cli.sh（またはアプリのメニューから）"
