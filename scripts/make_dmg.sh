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

PROJECT="Thoth.xcodeproj"
SCHEME="Thoth"
APP_NAME="Thoth.app"
BUILD_DIR="build"
DERIVED="$BUILD_DIR/DerivedData"
# Swift Package の取得先。ライセンス一覧の生成と共有して、同じものを 2 回取得しない
SOURCE_PACKAGES="$BUILD_DIR/SourcePackages"
INFO_PLIST="Thoth/Supporting Files/Info.plist"

# バージョンを Info.plist（CFBundleShortVersionString）から取得
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"

# リリース日 = バージョンタグ v<version> をつけた日（注釈タグの tagger 日付）。
# バージョンタブに表示するため THOTH_RELEASE_DATE としてビルドへ注入する。
# タグが未作成の場合は空（＝リリース日ラベルは表示されない）。
RELEASE_DATE="$(git for-each-ref --format='%(taggerdate:short)' "refs/tags/v.$VERSION" 2>/dev/null | head -1)"
if [ -z "$RELEASE_DATE" ]; then
  echo "警告: タグ v.$VERSION が見つかりません。リリース日は未設定でビルドします。" >&2
  echo "      （通常は develop を main へマージし v.$VERSION タグを付けた後に実行します）" >&2
else
  echo "==> リリース日: $RELEASE_DATE (タグ v.$VERSION より)"
fi

echo "==> 開発ツールを用意 (scripts/tool.sh --install)"
# SwiftGen・BartyCrouch はビルドフェーズで使う。取得済みなら何もしない
scripts/tool.sh --install

echo "==> サードパーティライセンス一覧を作り直す (scripts/update-acknowledgements.swift)"
# Swift Package を取得し、その LICENSE から Acknowledgements.md と NOTICE を作る。
# 配布物に同梱する一覧を、固定しているパッケージの版と確実に揃えるため、毎回実行する
scripts/update-acknowledgements.swift
if ! git diff --quiet -- Thoth/Resources/Acknowledgements.md NOTICE; then
  echo "警告: ライセンス一覧が更新されました。Thoth/Resources/Acknowledgements.md と NOTICE をコミットしてください。" >&2
fi

echo "==> Release ビルド (Thoth v$VERSION)"
# SwiftLint はビルド時に走るが、配布ビルドを速くするためスキップする。
# ARCHS はコマンドラインで渡すと Swift Package のターゲットにも効く
# （プロジェクトの ARCHS = arm64 はパッケージには引き継がれず、x86_64 も入ってしまう）
SKIP_SWIFTLINT=1 xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -derivedDataPath "$DERIVED" \
  -clonedSourcePackagesDirPath "$SOURCE_PACKAGES" \
  ARCHS=arm64 \
  THOTH_RELEASE_DATE="$RELEASE_DATE" \
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
