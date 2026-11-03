#!/bin/bash
# 编译 Go2Shell（原生 arm64）并组装 .app
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Go2Shell"
BUILD_DIR="build"
APP="$BUILD_DIR/$APP_NAME.app"
HELPER="$APP/Contents/MacOS/Go2ShellHelper.app"
SDK="$(xcrun --show-sdk-path)"
TARGET="arm64-apple-macos12.0"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
mkdir -p "$HELPER/Contents/MacOS" "$HELPER/Contents/Resources"

echo "==> 编译主程序"
xcrun swiftc -O -target "$TARGET" -sdk "$SDK" Sources/Go2Shell.swift \
	-o "$APP/Contents/MacOS/Go2Shell"

echo "==> 编译 Helper"
xcrun swiftc -O -target "$TARGET" -sdk "$SDK" Sources/Go2ShellHelper.swift \
	-o "$HELPER/Contents/MacOS/Go2ShellHelper"

cp Resources/Icon.icns "$APP/Contents/Resources/Icon.icns"
cp Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

cp Resources/moj.icns "$HELPER/Contents/Resources/moj.icns"
cp HelperInfo.plist "$HELPER/Contents/Info.plist"
printf 'APPL????' > "$HELPER/Contents/PkgInfo"

echo "==> ad-hoc 签名"
codesign --force --sign - "$HELPER"
codesign --force --sign - "$APP"

echo "完成：$APP"
lipo -info "$APP/Contents/MacOS/Go2Shell"
