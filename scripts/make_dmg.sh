#!/bin/bash
#
# Thoth の配布用 DMG を作成する（自分・身内用の署名なしビルド）。
#
# 使い方:
#   ./scripts/make_dmg.sh              # ビルドから DMG 作成まで
#   ./scripts/make_dmg.sh --dmg-only   # ビルド済みの Thoth.app から DMG だけ作り直す（見た目の調整用）
#
# 生成物:
#   build/Thoth-<version>.dmg   （/Applications へドラッグしてインストール）
#
# 注意:
#   - ad-hoc 署名（Developer ID 署名・公証なし）のため、配布先の Mac では
#     初回起動時に Gatekeeper のブロックが出る。右クリック →「開く」、または
#     `xattr -dr com.apple.quarantine /Applications/Thoth.app` で回避する。
#   - Apple Silicon (arm64) 専用ビルド。
#   - macOS 標準の hdiutil・osascript のみ使用（追加インストール不要）。
#   - DMG を開いたときのウィンドウ（大きさ・背景の矢印・アイコンの位置）は Finder に
#     AppleScript で設定させる。初回はターミナルから Finder の操作を許可するダイアログが出る。
#     許可しない・失敗した場合は、見た目の設定なしの DMG を作る（中身は同じ）。
#
set -euo pipefail

# リポジトリルートへ移動（scripts/ の 1 つ上）
cd "$(cd "$(dirname "$0")/.." && pwd)"

DMG_ONLY=0
if [ "${1:-}" = "--dmg-only" ]; then
  DMG_ONLY=1
fi

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
# DMG のウィンドウ。寸法とアイコンの中心は scripts/make-dmg-background.swift の定数と揃える。
# 高さは、macOS 27 の Finder が下端に出すバー（ボリューム名の表示。約 27pt。DMG 側からは消せない）が
# 重なっても、案内文（上端から約 315pt まで）が隠れないようにしてある
DMG_WINDOW_WIDTH=560
DMG_WINDOW_HEIGHT=370
DMG_ICON_SIZE=128
DMG_ICON_Y=160
DMG_APP_X=150
DMG_APPLICATIONS_X=410

RELEASE_DATE="$(git for-each-ref --format='%(taggerdate:short)' "refs/tags/v.$VERSION" 2>/dev/null | head -1)"
if [ -z "$RELEASE_DATE" ]; then
  echo "警告: タグ v.$VERSION が見つかりません。リリース日は未設定でビルドします。" >&2
  echo "      （通常は develop を main へマージし v.$VERSION タグを付けた後に実行します）" >&2
else
  echo "==> リリース日: $RELEASE_DATE (タグ v.$VERSION より)"
fi

APP_PATH="$DERIVED/Build/Products/Release/$APP_NAME"

if [ "$DMG_ONLY" = 0 ]; then
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
fi

if [ ! -d "$APP_PATH" ]; then
  echo "エラー: ビルド成果物が見つかりません: $APP_PATH" >&2
  exit 1
fi

# DMG 用のステージング（Thoth.app + /Applications へのシンボリックリンク + 背景画像）
STAGING="$BUILD_DIR/dmg_staging"
rm -rf "$STAGING"
mkdir -p "$STAGING/.background"
cp -R "$APP_PATH" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

echo "==> 背景画像を作成 (scripts/make-dmg-background.swift)"
# 通常用と Retina 用を描き、1 つの TIFF にまとめる（Finder が画面に合う方を使う）
scripts/make-dmg-background.swift "$BUILD_DIR/dmg_background.png" 1
scripts/make-dmg-background.swift "$BUILD_DIR/dmg_background@2x.png" 2
tiffutil -cathidpicheck "$BUILD_DIR/dmg_background.png" "$BUILD_DIR/dmg_background@2x.png" \
  -out "$STAGING/.background/background.tiff" >/dev/null

DMG_PATH="$BUILD_DIR/Thoth-$VERSION.dmg"
DMG_RW="$BUILD_DIR/Thoth-$VERSION.rw.dmg"
VOLUME_NAME="Thoth $VERSION"
rm -f "$DMG_PATH" "$DMG_RW"

# 同じ名前のボリュームが開いていると Finder が取り違えるので、先に取り外す
if [ -d "/Volumes/$VOLUME_NAME" ]; then
  hdiutil detach "/Volumes/$VOLUME_NAME" -quiet || hdiutil detach "/Volumes/$VOLUME_NAME" -force -quiet || true
fi

echo "==> 書き込み可能な DMG を作成し、ウィンドウの見た目を設定"
# 一度 UDRW（読み書き可）で作ってマウントし、Finder に .DS_Store を書かせてから圧縮する
hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING" \
  -fs HFS+ \
  -format UDRW \
  -ov \
  "$DMG_RW" >/dev/null
MOUNT_DIR="$(hdiutil attach "$DMG_RW" -readwrite -noverify -noautoopen | awk -F'\t' '/\/Volumes\//{print $NF}' | tail -1)"
if [ -z "$MOUNT_DIR" ]; then
  echo "エラー: DMG をマウントできません: $DMG_RW" >&2
  exit 1
fi

# Finder の座標はウィンドウ左上が原点。bounds はタイトルバーを含むので、その分を足す
# （macOS 27 のタイトルバーは約 32pt。足りないと下端の案内文が見切れる）
TITLE_BAR_HEIGHT=32
WINDOW_LEFT=200
WINDOW_TOP=120
if osascript <<APPLESCRIPT
tell application "Finder"
  tell disk "$VOLUME_NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {$WINDOW_LEFT, $WINDOW_TOP, $((WINDOW_LEFT + DMG_WINDOW_WIDTH)), $((WINDOW_TOP + DMG_WINDOW_HEIGHT + TITLE_BAR_HEIGHT))}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to $DMG_ICON_SIZE
    set text size of viewOptions to 13
    set background picture of viewOptions to file ".background:background.tiff"
    set position of item "$APP_NAME" of container window to {$DMG_APP_X, $DMG_ICON_Y}
    set position of item "Applications" of container window to {$DMG_APPLICATIONS_X, $DMG_ICON_Y}
    -- 閉じるときに .DS_Store へ書かれる。閉じてから開き直すと、書き込み前の既定の寸法で上書きされることがある
    update without registering applications
    delay 1
    close
  end tell
end tell
APPLESCRIPT
then
  # Finder が .DS_Store を書き終えるのを待つ（最大 10 秒）
  for _ in $(seq 1 20); do
    [ -f "$MOUNT_DIR/.DS_Store" ] && break
    sleep 0.5
  done
  if [ ! -f "$MOUNT_DIR/.DS_Store" ]; then
    echo "警告: ウィンドウの設定（.DS_Store）が書き込まれませんでした。見た目の設定なしで続けます。" >&2
  fi
else
  echo "警告: Finder でウィンドウの見た目を設定できませんでした（Finder の操作が許可されていない等）。" >&2
  echo "      見た目の設定なしで続けます。システム設定 > プライバシーとセキュリティ > オートメーション で許可できます。" >&2
fi
# 隠しファイルを表示する設定の Finder でも背景のフォルダが見えないようにする
chflags hidden "$MOUNT_DIR/.background"
# Finder が作る .fseventsd などは DMG に不要
rm -rf "$MOUNT_DIR/.fseventsd"
sync
hdiutil detach "$MOUNT_DIR" -quiet || hdiutil detach "$MOUNT_DIR" -force -quiet

echo "==> 圧縮 DMG を作成: $DMG_PATH"
# UDZO: 圧縮 read-only
hdiutil convert "$DMG_RW" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH" >/dev/null

rm -f "$DMG_RW"
rm -rf "$STAGING"

echo ""
echo "==> 完成: $DMG_PATH"
echo "    DMG を開き、Thoth.app を Applications へドラッグしてください。"
echo "    配布先の初回起動でブロックされたら、右クリック→「開く」で許可します。"
