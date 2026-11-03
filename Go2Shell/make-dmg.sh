#!/bin/bash
# 编译并打包为 dmg（输出到仓库根目录）
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Go2Shell"
DMG="$APP_NAME-2.5-arm64.dmg"
STAGE="$(mktemp -d)"

./build.sh

cp -R "build/$APP_NAME.app" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"

echo "==> 生成 $DMG"
hdiutil create -volname "$APP_NAME 2.5" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"

echo "完成：$(pwd)/$DMG"
