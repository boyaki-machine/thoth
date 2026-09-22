# 開発者向け情報

本アプリの開発環境・プロジェクト構成・試験方法・ビルド方法をまとめます。
アプリの使い方は [../README_JP.md](../README_JP.md) を、データ形式・暗号仕様・設計方針は [DESIGN_JP.md](DESIGN_JP.md) を参照してください。

> For English, see [DEVELOPMENT.md](DEVELOPMENT.md).

---

## 1. 開発環境・動作条件・利用ライブラリ

### 動作条件

| 項目 | 値 |
|---|---|
| 対応 OS | macOS 15.0 以降 |
| アーキテクチャ | Apple Silicon (arm64) のみ |
| デプロイターゲット | `MACOSX_DEPLOYMENT_TARGET = 15.0` |

macOS 15.0 を最低要件としているのは、Apple のセキュリティ更新が続いている OS に限るためです（v1.4.0 で macOS 11.0 から引き上げ。macOS 13 はサポートが終了し、14 も終了が近い）。本アプリはパスワードや TOTP を扱うため、脆弱性の修正が届かない OS での利用は想定しません。ビルドは Apple Silicon 向けの arm64 のみで、Intel Mac は対象外です（macOS 15 自体は一部の Intel Mac でも動くため、Intel を除外しているのは `ARCHS = arm64` の設定です）。

### 開発環境（動作確認済み）

| ツール | バージョン |
|---|---|
| macOS | 27 系（Apple Silicon） |
| Xcode | 27 系（27.0 で確認） |
| Swift | 5.3（プロジェクト設定の Swift バージョン） |
| SwiftLint | Homebrew 版 0.65 系 |
| Ruby | 4.0 系（CocoaPods 実行用。Homebrew の `ruby`） |

### 主要ライブラリ（CocoaPods）

| ライブラリ | 用途 |
|---|---|
| RealmSwift | v1.4.x までの履歴・スニペットの保存先。v1.5 では移行元の読み出しだけに使う（v1.6.x で削除予定） |
| RxSwift / RxCocoa | リアクティブなイベント処理・設定監視 |
| Magnet / KeyHolder | グローバルホットキーの登録・表示 |
| Sauce | キーボードレイアウト非依存のキーコード解決 |
| RxScreeen | スクリーンショット監視 |
| AEXML | スニペットの XML インポート/エクスポート |
| LetsMove | 初回起動時の Applications フォルダへの移動促進 |
| SwiftHEXColors | HEX カラープレビュー |
| SwiftLint / SwiftGen / BartyCrouch | コード規約・コード生成（L10n / アセット）・ローカライズ補助（BartyCrouch の設定は `.bartycrouch.toml`） |
| Quick / Nimble | ユニットテスト（BDD スタイル） |

### アーキテクチャの前提

- **依存性注入**: `AppEnvironment.current` を通じてサービス群（`Environment`）へアクセスします。テストでは `AppEnvironment.push/popLast` でモック環境に差し替えられます。
- **コード生成**: `L10n.*`（ローカライズ文字列）と `Asset.*`（画像）は SwiftGen がビルド時に自動生成します。文言・アセットを追加する場合は `Thoth/Resources/*.lproj/Localizable.strings` などの元ファイルを編集すれば、ビルド時に `Thoth/Generated/` 以下が再生成されます（生成ファイルの手編集は不要）。

---

## 2. プロジェクトのファイル・フォルダ構成

```
（リポジトリルート）
├── Thoth/
│   ├── Sources/
│   │   ├── AppDelegate.swift        アプリのエントリポイント・起動シーケンス統括
│   │   ├── Constants.swift          UserDefaults キー・ペーストボード型などの定数
│   │   ├── Enums/                   MenuType など
│   │   ├── Environments/            DI コンテナ（Environment / AppEnvironment）
│   │   ├── Extensions/              Swift/Cocoa 拡張（NSAlert+Thoth 等）
│   │   ├── Managers/                MenuManager（+MenuBuilding / +Popup に分割）
│   │   ├── Models/                  Realm モデル（CPYClip/CPYSnippet/CPYFolder）、
│   │   │                            CPYClipData、SecureMenuItem
│   │   ├── Preferences/             環境設定ウィンドウと各パネル
│   │   ├── Services/                ビジネスロジック（下表参照）
│   │   ├── Snippets/                スニペットエディタ（レガシー NIB ベース）
│   │   ├── Utility/                 CPYUtilities / RealmProvider / ClipDataStore /
│   │   │                            保存層（LibraryStore / RealmLibraryStore）
│   │   └── Views/                   各種ウィンドウ・パネル（暗号化・パスワード生成・
│   │       │                        セキュアピッカー等）
│   │       └── SecureInfo/          セキュア情報確認ウィンドウ（2 ペイン）
│   ├── Resources/                   *.lproj（ローカライズ）、画像アセット
│   ├── Generated/                   SwiftGen 生成ファイル（L10n / Asset / Colors）
│   └── Supporting Files/            Info.plist など
├── ThothTests/                      ユニットテスト（Quick + Nimble）
├── Podfile                          CocoaPods 依存定義
├── .swiftlint.yml                   コード規約設定
├── README_JP.md                     利用者向け説明
└── docs/
    ├── DEVELOPMENT_JP.md            本ファイル
    └── DESIGN_JP.md                 データ形式・暗号仕様・設計方針
```

### Services レイヤー（`Thoth/Sources/Services/`）

ビジネスロジックはサービス層に集約されます。状態を持つものは `AppEnvironment.current.xxxService` から取得し、状態を持たないもの（`SecureItemSearch` / `SecureItemsTransfer` / `QRDecodeService` / `CryptoPasswordQRCodec` / `LoginItemService`）は型に直接生えた静的メソッドとして呼びます。

| サービス | 責務 |
|---|---|
| `ClipService` | クリップボードの監視（100ms ポーリング）と履歴の保存・削除 |
| `PasteService` | ペースト操作（通常コピー / 秘匿コピー / キー直接入力の3経路） |
| `SecureMenuService` | セキュアアイテム・指紋パスワードのキーチェーン管理と生体認証 |
| `SecureItemSearch` | セキュアアイテムの絞り込み（確認ウィンドウと選択パネルで共通の検索条件） |
| `SecureItemsTransfer` | セキュアアイテムの JSON インポート／エクスポート |
| `ClipFullTextIndexer` | 履歴の全文検索インデックスと検索フィルタ |
| `CryptoPasswordQRCodec` | 指紋パスワードの QR エンコード／デコード |
| `CryptoService` | ファイル・フォルダの暗号化 / 復号（インプロセス実装） |
| `TOTPService` | TOTP コード生成・otpauth URI / Base32 のパース |
| `QRDecodeService` | QR コードからの otpauth URI 取り込み（Vision 使用） |
| `PasswordGenerateService` | 条件付きランダムパスワード生成 |
| `HotKeyService` | グローバルホットキーの登録 |
| `DataCleanService` | 履歴の定期クリーンアップ（上限超過・孤児ファイル削除） |
| `ExcludeAppService` | 除外アプリケーションの管理 |
| `AccessibilityService` | アクセシビリティ権限の確認・誘導 |
| `LoginItemService` | ログイン項目（ログイン時の自動起動）を設定値に揃える（`SMAppService`。揃っていれば何もしない。システム設定で利用者がオフにした項目は上書きしない） |
| `CodeSignService` | 起動時の自己署名安定化（後述） |

補助的な永続化ユーティリティ（`Thoth/Sources/Utility/`）:

- `LibraryStore` — 履歴・スニペットの保存層のプロトコル（`HistoryStore` / `SnippetStore`）。UI・サービスは値型（`ClipRecord` / `SnippetFolderRecord` / `SnippetRecord`）だけを扱い、保存先には直接触れない。`AppEnvironment.current.historyStore` / `snippetStore` から取得する
- `RealmLibraryStore` — 保存層の Realm 版
- `RealmProvider` — Realm 構成・スキーマ移行・暗号化・アプリ生成鍵の管理
- `ClipDataStore` — クリップ実データ（`.data` ファイル）の暗号化読み書き

---

## 3. 試験方法（CLI）

ユニットテスト（`ThothTests` ターゲット / Quick + Nimble）はスキームの Test アクション（Debug 構成）で実行します。

```bash
SKIP_SWIFTLINT=1 xcodebuild -workspace Thoth.xcworkspace -scheme Thoth \
  -configuration Debug test -destination 'platform=macOS,arch=arm64' ENABLE_TESTABILITY=YES
```

末尾に `** TEST SUCCEEDED **` と表示されれば成功です（Xcode 上では **Product → Test**（⌘U）でも可）。

### テストの前提

- テストは Realm のインメモリ DB・UserDefaults・キーチェーン（テスト専用 service `io.github.boyaki-machine.ThothTests.SecureMenu` を使用し本番データには触れない）を使うため、追加のセットアップは不要です。
- `ThothTests` は `@testable import Thoth` を使うため、Test アクション（Debug 構成）以外で実行する場合は `ENABLE_TESTABILITY=YES` が必要です。
- 暗号化・クリップデータ暗号化のテストは、テスト実行時（`XCTestConfigurationFilePath` 環境変数が存在する場合）にキーチェーン鍵の生成をスキップし、インメモリ Realm と併用できるよう設計されています。

### 主なテストスペック（`ThothTests/`）

| 分類 | スペック |
|---|---|
| クリップボード | `DraggedDataSpec`、`ClipboardConcealSpec` |
| モデル | `SecureMenuItemSpec` |
| 保存層 | `RealmLibraryStoreSpec`（保存層の契約 `LibraryStoreContract` を Realm 版で確かめる）、`DataCleanServiceSpec`（上限超過で消す範囲） |
| セキュアアイテム | `SecureMenuServiceSpec`、`SecureItemsTransferSpec`（インポート／エクスポート）、`SecureItemSearchSpec`（絞り込みの共通条件・確認ウィンドウと選択パネルの一致） |
| セキュアアイテム選択パネル | `CPYSecurePickerPanelSpec`（絞り込み・行構成・サブパネル・ページング・`s` キーの導線） |
| 履歴パネル | `CPYHistoryPickerPanelSpec`（行構造・設定連動・サブパネルのキー操作）、`ClipFullTextIndexerSpec`（全文検索インデックスと検索フィルタ） |
| 環境設定ウィンドウ | `CPYPreferencesWindowControllerSpec`（Esc の閉じる判定）、`CPYVersionPreferenceViewControllerSpec`（バージョンタブのレイアウト不変条件） |
| 履歴からの除外 | `ClipboardConcealSpec`（秘匿マーカー）、`ExcludeAppServiceSpec`（除外アプリ判定・永続化） |
| セキュア情報ウィンドウ | `SecureInfoEditorSpec`（一覧の絞り込み・編集状態）、`SecureInfoViewSpec`（行の表示・編集可否）、`SecureInfoCommitFlowSpec`（実 Keychain を通した保存フロー）、`SecureInfoKeyActionSpec`（キー割り当て）、`SecureInfoUndoSpec` / `SecureInfoUndoFlowSpec`（取り消し）、`SecureFieldRowInteractionSpec`（削除ボタンの分離・右クリックメニュー）、`SecureInfoDragReorderSpec`（ドラッグ&ドロップ並べ替え）、`SecureInfoActionMenuSpec`（⚙ メニュー・閉じるボタン）、`SecureInfoHistorySpec`（変更履歴の参照）、`SecureFieldRowLifecycleSpec`（捨てた行の書き戻し防止） |
| TOTP | `TOTPServiceSpec`、`TOTPRegistrationFlowSpec`、`PasteServiceTOTPSpec` |
| 暗号化 | `CryptoServiceSpec`、`RealmEncryptionSpec`、`ClipDataStoreSpec`、`CryptoPasswordQRCodecSpec`（指紋パスワードの QR 共有） |
| その他 | `HotKeyServiceSpec`、`PasswordGenerateServiceSpec`、`LoginItemServiceSpec`（ログイン項目の同期判定） |

特定スペックだけ実行する場合は `-only-testing:ThothTests/CryptoServiceSpec` のように指定できます。

### 失敗したテストの読み方

失敗すると標準出力に次の 3 つが出ます。ログは長いので `grep -E "error:|Failing tests" -A 20` で拾うと早いです。

1. **失敗した箇所と、期待と実際** — ファイル:行 / スペック名 / describe 名 / it 名 / 期待値 / 実際の値:

   ```
   /Users/…/ThothTests/SecureItemSearchSpec.swift:188: error: -[ThothTests.SecureItemSearchSpec 絞り込み, マスクを掛けた値では探せない] : expected to be empty, got <[GitHub, AWS Console, 社内ポータル]>
   ```

2. **落ちたテストの一覧**（ログ末尾）:

   ```
   Failing tests:
       SecureItemSearchSpec.絞り込み, マスクを掛けた値では探せない()
   ```

3. **件数の集計** — `Executed 728 tests, with 1 failure (0 unexpected)` と `** TEST FAILED **`

### スペックを書くときの約束

上の出力が役に立つかどうかは、スペックの書き方でほぼ決まります。

- **`it` の名前は「条件 → 期待結果」で書く。** 失敗の一覧を見ただけで何が壊れたか分かるようにします。
  良い例:「マスクを掛けた値では探せない」「10 件ちょうどではページ送りが出ない」。
  避ける例:「検索」「Save key combos」のように対象を示すだけの名前。
- **前提が崩れたら `fail(...)` で落とす。** `guard let x = … else { return }` と書くと、前提が崩れたときにテストが**何も検証せずに緑**になります。
- **真偽値ではなく中身を表明する。** `expect(items.isEmpty) == true` は失敗しても `expected to equal <true>, got <false>` としか出ません。`expect(items).to(beEmpty())` なら実際の中身が出ます
  （ただし主語が Optional のときは `beEmpty()` が nil を「空ではない」と扱うため、`expect(x?.isEmpty) == false` のままにします）。
- **ループの中で表明するときは `description:` に反復対象を入れる。** どの入力で落ちたかが出ます
  （例: `SecureItemSearchSpec` の「画面間で条件が揃っていること」）。
- **ファイル冒頭に、何を・どんな前提で確かめるスペックかを書く。** 共有状態（UserDefaults・キーチェーン・Realm）を使う場合は、その後始末の約束もここに書きます。
- **新しいテストは「実装を意図的に戻すと落ちる」ことまで確認してから積む。** 何も検出しないテストが紛れ込むのを防ぎます。

---

## 4. ビルド方法（CLI）

### 4-0. 事前準備（初回のみ）

```bash
# Xcode Command Line Tools
xcode-select --install

# Homebrew（未導入の場合）
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# SwiftLint（コード規約チェック用）
brew install swiftlint

# 依存関係（Homebrew の ruby 4.0 系で実行する）
brew install ruby
export PATH="/opt/homebrew/opt/ruby/bin:$PATH"
bundle config set --local path vendor/bundle
bundle install
bundle exec pod install
```

### 4-1. ユニットテスト（ビルド前の確認）

上記「3. 試験方法」のコマンドを実行し、`** TEST SUCCEEDED **` を確認します。

### 4-2. コード規約チェック

SwiftLint（設定: `.swiftlint.yml`、対象: `Thoth/Sources` と `ThothTests`）を実行します。

```bash
swiftlint   # プロジェクトのルートで実行
```

`Done linting! Found 0 violations` と表示されれば規約違反はありません。

> **補足:** CocoaPods 経由の `Pods/SwiftLint`（0.65 系）は Apple Silicon で正常に動作するため、Xcode ビルドのスクリプトフェーズでリントが実行されます。Homebrew 版 `swiftlint` でも同じ設定を単体実行できます。ビルドを速くしたい場合など、スクリプトフェーズは環境変数 `SKIP_SWIFTLINT=1` でスキップできます。

主な規約値（`.swiftlint.yml`）:

| 項目 | 制限 |
|---|---|
| 1 行の長さ | 300 文字以下 |
| ファイルの長さ | 500 行以下（警告）/ 1000 行以下（エラー） |
| 型本体の長さ | 300 行以下（警告）/ 400 行以下（エラー） |
| 関数本体の長さ | 100 行以下（警告）/ 200 行以下（エラー） |

### 4-3. ビルド（デバッグ / リリース）

リントはビルド時に実行されます。CLI ビルドを速くしたい場合は `SKIP_SWIFTLINT=1` を付けてスキップできます。

```bash
# クリーン（必要に応じて）
SKIP_SWIFTLINT=1 xcodebuild -workspace Thoth.xcworkspace -scheme Thoth -configuration Debug clean
SKIP_SWIFTLINT=1 xcodebuild -workspace Thoth.xcworkspace -scheme Thoth -configuration Release clean
# 完全にクリーンな状態から始めたい場合は DerivedData も削除
rm -rf ~/Library/Developer/Xcode/DerivedData/Thoth-*

# デバッグビルド
SKIP_SWIFTLINT=1 xcodebuild -workspace Thoth.xcworkspace -scheme Thoth -configuration Debug build

# リリースビルド
SKIP_SWIFTLINT=1 xcodebuild -workspace Thoth.xcworkspace -scheme Thoth -configuration Release build
```

成果物の出力先を明示する場合:

```bash
SKIP_SWIFTLINT=1 xcodebuild -workspace Thoth.xcworkspace -scheme Thoth \
  -configuration Release build -derivedDataPath build/DerivedData
# → build/DerivedData/Build/Products/Release/Thoth.app に生成される
```

生成アプリの起動 / 配置:

```bash
open build/DerivedData/Build/Products/Release/Thoth.app
# または Applications へ配置
cp -R build/DerivedData/Build/Products/Release/Thoth.app /Applications/
```

### 4-4. 配布用 DMG の作成（自分・身内用）

Release ビルドと DMG 化を 1 コマンドで行うスクリプトを用意しています。

```bash
./scripts/make_dmg.sh
```

**動作内容:**

1. `Release` 構成でビルド（`build/DerivedData` へ出力）
2. `Thoth.app` と `/Applications` へのシンボリックリンクをステージング
3. macOS 標準の `hdiutil` で圧縮 DMG（UDZO）を作成

**出力先:** `build/Thoth-<version>.dmg`（バージョンは `Info.plist` の `CFBundleShortVersionString` から自動取得。`build/` は `.gitignore` 済みのためコミットされない）

**リリース日について:** バージョンタブに表示されるリリース日は、`main` に付けた
バージョンタグ `v<version>` の付与日（注釈タグの tagger 日付）から自動的に決まる。
`make_dmg.sh` がその日付を取得し、ビルド設定 `THOTH_RELEASE_DATE` として
`Info.plist` の `ThothReleaseDate` に注入する（手動更新は不要）。そのため、
**`develop` を `main` へマージしてタグを付けた後に** `make_dmg.sh` を実行すること。
タグの無い開発ビルドでは空になり、リリース日は表示されない。

**実行条件:**

- macOS + Xcode（`xcodebuild`）。`hdiutil` は macOS 標準のため追加インストール不要
- Apple Silicon (arm64) 専用ビルド
- 署名は ad-hoc（Developer ID 署名・公証なし）

**利用方法:** 生成された DMG を開き、`Thoth.app` を `Applications` へドラッグする。

> **注意（配布先での初回起動）:** ad-hoc 署名のため Gatekeeper にブロックされる。
> 配布先の Mac で、右クリック →「開く」で初回のみ許可するか、次のコマンドで
> 検疫属性を除去する:
>
> ```bash
> xattr -dr com.apple.quarantine /Applications/Thoth.app
> ```
>
> 一般配布（他者の Mac で警告なく動かす）には Apple Developer Program による
> Developer ID 署名 + 公証（notarization）が別途必要。

---

## 5. コード署名とアクセシビリティ権限

### 自動再署名（`CodeSignService`）

セキュアアイテムは macOS のログインキーチェーンに保存され、キーチェーン項目の ACL は「作成したアプリのコード署名」に紐付きます。ad-hoc 署名（証明書なしのローカルビルド）では再ビルドのたびにバイナリのハッシュが変わり、キーチェーンから「別アプリ」と判定されて既存アイテムを読めなくなります。

これを避けるため、アプリは起動時に自身の署名を確認し、デバイス固有の証明書「**Thoth Local Signing**」で自動的に再署名します。

1. 起動時、自身がこの証明書で署名済みかを確認（署名済みなら何もしない）
2. 未署名（ad-hoc）なら、ログインキーチェーンから証明書を探す（過去に生成済みなら再利用、なければ自己署名証明書を生成して保存。デバイスごとに一度だけ）
3. 自身の `.app` バンドルを再署名し、アプリを自動で再起動

同一デバイスでは常に同じ証明書で署名されるため、バージョンが変わってもキーチェーン ACL が一致します。

注意事項:

- デバイスで**初回のみ** macOS の確認ダイアログ（証明書の信頼・署名鍵の使用許可）が出ることがあります。「常に許可」を選択してください。
- 署名変更に伴い、初回の再署名後は**アクセシビリティ権限の再付与**が必要です（以後のバージョンアップでは不要）。
- 再署名を無効化するには `--thoth-skip-resign` 引数を付けて起動します。
- いずれかの手順が失敗した場合は ad-hoc 署名のまま起動を続けます（ログは Console.app で `CodeSignService` を検索）。この場合、データベース・クリップの暗号化鍵の生成は次回の安定署名時まで保留されます（詳細は [DESIGN_JP.md](DESIGN_JP.md)）。

### アクセシビリティ権限のエントリ増殖について

macOS のアクセシビリティ（TCC）はアプリを「バンドル ID + 署名要件」で識別するため、ad-hoc 署名のままビルドを重ねると、システム設定の一覧に Thoth のエントリが増えます。

本アプリは再署名が**完了してから**アクセシビリティ確認を行うため（再署名前の ad-hoc バイナリは TCC に登録されない）、「Thoth Local Signing」で署名された状態で一度権限を許可すれば、以後のバージョンでも同じエントリが再利用されます。

過去のビルドで増えた古いエントリは自動では消せないため、一度だけ以下でリセットしてから、新しく起動した Thoth に権限を付与し直してください。

```bash
tccutil reset Accessibility io.github.boyaki-machine.Thoth
```

また、起動場所（パス）が変わるとエントリが分かれて見えることがあるため、アプリは毎回同じ場所（例: `/Applications` または `~/Applications`）に配置して起動することを推奨します。
