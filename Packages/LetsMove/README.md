# LetsMove（Thoth 同梱版）

起動したアプリを「アプリケーション」フォルダへ移動するよう促すライブラリ
[LetsMove](https://github.com/potionfactory/LetsMove) 1.25（コミット `70c5772`）を、
Swift Package として取り込んだもの。本家は Swift Package Manager に対応していないため、
Thoth v1.5.1 で CocoaPods をやめたときにリポジトリへ置いた。

## ライセンス

各ファイルの冒頭にあるとおり、パブリックドメイン（"The contents of this file are
dedicated to the public domain."）。作者は Andy Kim（Potion Factory LLC）。

## 本家からの変更

- 取り込んだのは `PFMoveApplication.h` / `PFMoveApplication.m` と、各言語の
  `MoveApplication.strings` だけ（サンプルアプリ・Xcode プロジェクトは除く）
- 翻訳を読むバンドルを、Swift Package のモジュール用バンドル（`SWIFTPM_MODULE_BUNDLE`）に
  変えた。CocoaPods ではフレームワークの中に翻訳が入っていたため `bundleForClass:` で
  見つかったが、Swift Package では別のバンドルに入るため
- 本家の Podspec と同じく ARC を使わずにコンパイルする（`-fno-objc-arc`）
