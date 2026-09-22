#!/bin/bash
#
# 開発ツール（SwiftLint / SwiftGen / BartyCrouch）を、決まった版で実行する。
# Xcode のビルドフェーズからも、手元のターミナルからも使う。
#
# 使い方:
#   scripts/tool.sh swiftlint [引数...]
#   scripts/tool.sh swiftgen config run
#   scripts/tool.sh bartycrouch update
#   scripts/tool.sh --install        （3 つとも取得だけする）
#
# 初めて使うときに公式リリースの zip を取得し、SHA-256 を確かめてから
# .tools/<名前>-<版>/ に展開する（.tools/ は git 管理外）。2 回目以降は取得しない。
# v1.5.1 で CocoaPods をやめるまで Pod として入れていたのと同じ配布物・同じ版。
#
# 版を上げるときは、下の tool_spec の版・URL・SHA-256 を書き換える。
# SHA-256 は `curl -sSfL -o x.zip <URL> && shasum -a 256 x.zip` で求める。
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOOLS_DIR="$ROOT/.tools"
ALL_TOOLS="swiftlint swiftgen bartycrouch"

# 版|URL|SHA-256|zip 内の実行ファイルの位置
tool_spec() {
  case "$1" in
    swiftlint)
      echo "0.65.1|https://github.com/realm/SwiftLint/releases/download/0.65.1/portable_swiftlint.zip|c1e429b0599cf1b516f369a2d9ec04eaf0e436f3c12b637df8851fa52ff694d0|swiftlint" ;;
    swiftgen)
      echo "6.6.3|https://github.com/SwiftGen/SwiftGen/releases/download/6.6.3/swiftgen-6.6.3.zip|94391c1b5a845150284be69fa9499fb2600231ac8f6a3ea5da53a4b55ee174df|bin/swiftgen" ;;
    bartycrouch)
      echo "4.15.0|https://github.com/FlineDev/BartyCrouch/releases/download/4.15.0/portable_bartycrouch.zip|733ef0a80fd74297b953baa09e856ad87dbbda5648bd7dfd4d6d8fc01721dd07|bartycrouch" ;;
    *)
      return 1 ;;
  esac
}

# zip を取得し、SHA-256 を確かめてから展開する。
# サブシェルで動かし、途中で失敗しても作業用のフォルダを残さない
install_tool() (
  name="$1" version="$2" url="$3" sha256="$4" binary="$5" dest="$6"
  work="$(mktemp -d "${TMPDIR:-/tmp}/thoth-tool.XXXXXX")"
  trap 'rm -rf "$work"' EXIT

  echo "$name $version を取得します: $url" >&2
  if ! curl -sSfL --retry 2 -o "$work/tool.zip" "$url"; then
    echo "error: $name を取得できませんでした（ネットワークを確認して、もう一度実行してください）" >&2
    exit 1
  fi
  actual="$(shasum -a 256 "$work/tool.zip" | awk '{print $1}')"
  if [ "$actual" != "$sha256" ]; then
    echo "error: $name の SHA-256 が一致しません（期待: $sha256 / 実際: ${actual}）。展開せずに中止します" >&2
    exit 1
  fi
  mkdir -p "$work/unpacked"
  unzip -q "$work/tool.zip" -d "$work/unpacked"
  if [ ! -x "$work/unpacked/$binary" ]; then
    echo "error: $name の zip に $binary がありません" >&2
    exit 1
  fi
  mkdir -p "$(dirname "$dest")"
  rm -rf "$dest"
  mv "$work/unpacked" "$dest"
)

# 実行ファイルのパスを出力する。まだ取得していなければ先に取得する
ensure_tool() {
  local name="$1" spec version url sha256 binary dest
  if ! spec="$(tool_spec "$name")"; then
    echo "error: 知らないツールです: ${name}（$ALL_TOOLS のどれか）" >&2
    return 1
  fi
  IFS='|' read -r version url sha256 binary <<< "$spec"
  dest="$TOOLS_DIR/$name-$version"
  if [ ! -x "$dest/$binary" ]; then
    # コマンド置換の中では set -e が効かないため、失敗は明示して返す
    install_tool "$name" "$version" "$url" "$sha256" "$binary" "$dest" || return 1
  fi
  echo "$dest/$binary"
}

if [ $# -eq 0 ]; then
  echo "使い方: $0 <$(echo $ALL_TOOLS | tr ' ' '|')> [引数...] / $0 --install" >&2
  exit 64
fi

if [ "$1" = "--install" ]; then
  for name in $ALL_TOOLS; do
    ensure_tool "$name" > /dev/null || exit 1
  done
  exit 0
fi

name="$1"
shift
tool_path="$(ensure_tool "$name")"
exec "$tool_path" "$@"
