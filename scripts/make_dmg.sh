#!/bin/bash
#
# Thoth の配布用 DMG を作成する（自分・身内用の署名なしビルド）。
#
# 使い方:
#   ./scripts/make_dmg.sh
#
# 生成物:
#   build/Thoth-<version>.dmg   （/Applications へドラッグしてインストール）
#
# 注意:
#   - ad-hoc 署名（Developer ID 署名・公証なし）のため、配布先の Mac では
#     初回起動時に Gatekeeper のブロックが出る。右クリック →「開く」、または
#     `xattr -dr com.apple.quarantine /Applications/Thoth.app` で回避する。
#   - Apple Silicon (arm64) 専用ビルド。
#   - macOS 標準の hdiutil のみ使用（追加インストール不要）。
#
set -euo pipefail

# リポジトリルートへ移動（scripts/ の 1 つ上）
cd "$(cd "$(dirname "$0")/.." && pwd)"

WORKSPACE="Thoth.xcworkspace"
SCHEME="Thoth"
APP_NAME="Thoth.app"
BUILD_DIR="build"
DERIVED="$BUILD_DIR/DerivedData"
INFO_PLIST="Thoth/Supporting Files/Info.plist"

# バージョンを Info.plist（CFBundleShortVersionString）から取得
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"

echo "==> Release ビルド (Thoth v$VERSION)"
# SwiftLint はビルド時に走るが、配布ビルドを速くするためスキップする
SKIP_SWIFTLINT=1 xcodebuild \
  -workspace "$WORKSPACE" \
  -scheme "$SCHEME" \
  -configuration Release \
  -derivedDataPath "$DERIVED" \
  build

APP_PATH="$DERIVED/Build/Products/Release/$APP_NAME"
if [ ! -d "$APP_PATH" ]; then
  echo "エラー: ビルド成果物が見つかりません: $APP_PATH" >&2
  exit 1
fi

# DMG 用のステージング（Thoth.app + /Applications へのシンボリックリンク）
STAGING="$BUILD_DIR/dmg_staging"
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R "$APP_PATH" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

DMG_PATH="$BUILD_DIR/Thoth-$VERSION.dmg"
rm -f "$DMG_PATH"

echo "==> DMG 作成: $DMG_PATH"
# UDZO: 圧縮 read-only。-ov: 既存を上書き
hdiutil create \
  -volname "Thoth $VERSION" \
  -srcfolder "$STAGING" \
  -fs HFS+ \
  -format UDZO \
  -ov \
  "$DMG_PATH"

rm -rf "$STAGING"

echo ""
echo "==> 完成: $DMG_PATH"
echo "    DMG を開き、Thoth.app を Applications へドラッグしてください。"
echo "    配布先の初回起動でブロックされたら、右クリック→「開く」で許可します。"
