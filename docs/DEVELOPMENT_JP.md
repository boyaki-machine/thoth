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
| SwiftLint / SwiftGen / BartyCrouch | 0.65.1 / 6.6.3 / 4.15.0（`scripts/tool.sh` が取得。別途のインストールは不要） |

### 主要ライブラリ（Swift Package Manager）

| ライブラリ | 用途 |
|---|---|
| RxSwift / RxCocoa | リアクティブなイベント処理・設定監視 |
| Magnet / KeyHolder | グローバルホットキーの登録・表示 |
| Sauce | キーボードレイアウト非依存のキーコード解決 |
| AEXML | スニペットの XML インポート/エクスポート |
| LetsMove | 初回起動時の Applications フォルダへの移動促進（`Packages/LetsMove` に取り込んだローカルパッケージ） |
| SwiftHEXColors | HEX カラープレビュー |
| Quick / Nimble | ユニットテスト（BDD スタイル） |

開発ツール（SwiftLint / SwiftGen / BartyCrouch）はパッケージではなく、`scripts/tool.sh` が公式リリースの zip を版と SHA-256 を固定して取得し、`.tools/`（git 管理外）に置きます。用途はコード規約・コード生成（L10n / アセット）・XIB の文言の同期（BartyCrouch の設定は `.bartycrouch.toml`）です。

### 依存ライブラリの管理

v1.5.1 で CocoaPods から Swift Package Manager へ移しました（CocoaPods のスペックリポジトリが 2026-12-02 に読み取り専用になるため）。Ruby・`pod install` は不要です。

- **版は完全に固定する（Exact Version）。** 固定した版は `Thoth.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` に記録され、コミット対象です。Xcode がプロジェクトを開いたとき・ビルド時に自動で取得します。
- **パッケージを足したり版を変えたりしたら、`scripts/update-acknowledgements.swift` を実行して、サードパーティライセンス一覧（`Thoth/Resources/Acknowledgements.md` と `NOTICE`）を作り直してコミットする。** 忘れると `AcknowledgementsSpec` が落ちます。テストだけで使うパッケージは一覧に載せません（スクリプト冒頭の `testOnlyPackages`）。一覧の先頭には元になった Clipy・ClipMenu の `LICENSE`・`LICENSE_CLIPMENU` を、各パッケージには `LICENSE` に加えて `NOTICE` / `THIRD-PARTY-NOTICES` と、パッケージが取り込んでいる第三者コードのライセンス（`vendoredLicenses`。v1.6.2 までは realm-core の jsonsl。いまは無し）を載せます。
- **動的フレームワークはありません**（すべて静的リンク）。v1.6.2 までは RealmSwift だけが動的で、アプリの「Embed Frameworks」に登録して `.app` に同梱していました。動的な製品を足すときは同じ登録が要ります（無いと `.app` に入らず、配布版が起動時に落ちる）。
- **LetsMove は本家が SPM に対応していないため、1.25 を `Packages/LetsMove` に取り込んでいます。** 変更点（翻訳を読むバンドルなど）は `Packages/LetsMove/README.md` を参照。
- CocoaPods のフレームワークは AppKit などを暗黙に取り込んでいたため、その頃のファイルには `import Cocoa` / `import Foundation` が抜けているものがありました。SPM では暗黙には入らないので、使うフレームワークは各ファイルで明示的に import します。

### アーキテクチャの前提

- **依存性注入**: `AppEnvironment.current` を通じてサービス群（`Environment`）へアクセスします。テストでは `AppEnvironment.push/popLast` でモック環境に差し替えられます。
- **コード生成**: `L10n.*`（ローカライズ文字列）と `Asset.*`（画像）は SwiftGen がビルド時に自動生成します。文言・アセットを追加する場合は `Thoth/Resources/*.lproj/Localizable.strings` などの元ファイルを編集すれば、ビルド時に `Thoth/Generated/` 以下が再生成されます（生成ファイルの手編集は不要）。SwiftGen・BartyCrouch のビルドフェーズはコンパイルより前に走るため、文言を足した直後のビルドでもそのまま使えます。

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
│   │   ├── Models/                  保存層のレコード型（LibraryRecords）、CPYClipData、
│   │   │                            SecureMenuItem、SecureUserData
│   │   ├── Preferences/             環境設定ウィンドウと各パネル
│   │   ├── Services/                ビジネスロジック（下表参照）
│   │   ├── Snippets/                スニペットエディタ（レガシー NIB ベース）
│   │   ├── Utility/                 CPYUtilities / ClipDataStore / ClipThumbnail /
│   │   │                            保存層（LibraryStore / SwiftDataLibraryStore /
│   │   │                            FieldCipher / LibraryProvider / LibraryMigrator）
│   │   └── Views/                   各種ウィンドウ・パネル（暗号化・パスワード生成・
│   │       │                        セキュアピッカー等）
│   │       └── SecureInfo/          セキュア情報確認ウィンドウ（2 ペイン）
│   ├── Resources/                   *.lproj（ローカライズ）、画像アセット
│   ├── Generated/                   SwiftGen 生成ファイル（L10n / Asset / Colors）
│   └── Supporting Files/            Info.plist など
├── ThothTests/                      ユニットテスト（Quick + Nimble）
├── Packages/LetsMove/               LetsMove を取り込んだローカルパッケージ
├── scripts/                         tool.sh（開発ツールの実行）、update-acknowledgements.swift
│                                    （ライセンス一覧の生成）、make_dmg.sh（配布用 DMG の作成）、
│                                    make-dmg-background.swift（DMG のウィンドウ背景の描画）
├── NOTICE                           サードパーティライセンス一覧（Acknowledgements.md と同じ内容）
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
| `PasteService` | ペースト操作（通常コピー / 秘匿コピー / キー直接入力の3経路）。秘匿値を貼り付けた後、クリップボードを元の内容へ戻す（`PasteboardSnapshot`） |
| `CallerAppActivator` | パネルで選んだ値を貼り付ける前に、貼り付け先のアプリ（ホットキーを押した時点の最前面）を前面へ戻し、前面に来たのを確かめてから送る |
| `ScreenshotWatcher` | ベータ機能「スクリーンショットを履歴に保存」。保存先フォルダを FSEvents で見張り、拡張属性 `kMDItemIsScreenCapture` でスクリーンショットを判定する（Spotlight を使わない） |
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
- `SwiftDataLibraryStore` / `LibraryStoreSchema` — 保存層の本番実装（SwiftData）とスキーマ。`ModelContext` は専用の直列キューの中でだけ使う
- `FieldCipher` — 保存層の項目暗号化（AES-256-GCM）と内容キー（HMAC）。鍵は `.data` 用の鍵から HKDF で導出する
- `LibraryProvider` — 起動時に保存層を用意する（新規インストールならストアを作る・鍵が使えないときの扱い・移行済みなら旧 Realm のファイルを消す）
- `LibraryMigrator` — ストアの作成（書き込んだ内容を照合してから完了の印を書く）。v1.6.2 までは Realm からの移行もここで行っていた
- `ClipThumbnail` — サムネイルの生成（縮小した PNG）・表示・移行後の作り直し
- `AppKeyStore` — アプリ生成鍵（app-keys）の管理。`.data` の鍵（保存層の鍵の導出元）を読む。キーチェーンの形式は変えないこと
- `ClipDataStore` — クリップ実データ（`.data` ファイル）の暗号化読み書き

---

## 3. 試験方法（CLI）

ユニットテスト（`ThothTests` ターゲット / Quick + Nimble）はスキームの Test アクション（Debug 構成）で実行します。

```bash
SKIP_SWIFTLINT=1 xcodebuild -project Thoth.xcodeproj -scheme Thoth \
  -configuration Debug test -destination 'platform=macOS,arch=arm64' ENABLE_TESTABILITY=YES
```

末尾に `** TEST SUCCEEDED **` と表示されれば成功です（Xcode 上では **Product → Test**（⌘U）でも可）。

### テストの前提

- テストはメモリ上の保存層（SwiftData）・UserDefaults・キーチェーン（テスト専用 service `io.github.boyaki-machine.ThothTests.SecureMenu` を使用し本番データには触れない）を使うため、追加のセットアップは不要です。
- `ThothTests` は `@testable import Thoth` を使うため、Test アクション（Debug 構成）以外で実行する場合は `ENABLE_TESTABILITY=YES` が必要です。
- 暗号化・クリップデータ暗号化のテストは、テスト実行時（`XCTestConfigurationFilePath` 環境変数が存在する場合）にキーチェーン鍵の生成をスキップするよう設計されています。

### 主なテストスペック（`ThothTests/`）

| 分類 | スペック |
|---|---|
| クリップボード | `DraggedDataSpec`（ドラッグデータの安全な復元・並べ替え）、`ClipboardConcealSpec`、`ConcealedPasteRestoreSpec`（秘匿値の貼り付け後にクリップボードを元へ戻す）、`CallerAppActivatorSpec`（貼り付け先のアプリへ戻す）、`ScreenshotWatcherSpec`（スクリーンショットの検知） |
| モデル | `SecureMenuItemSpec` |
| 保存層 | `SwiftDataLibraryStoreSpec`（保存層の契約 `LibraryStoreContract`・ファイルに平文が現れないこと）、`DataCleanServiceSpec`（上限超過で消す範囲） |
| 暗号化（保存層） | `FieldCipherSpec`（鍵の導出・暗号文の形式・改ざんと取り違えの検出。固定値は Swift の実装とは独立に計算） |
| 起動時の判断 | `LibraryMigrationSpec`（ストアの作成と照合・起動時の判断・移行済みなら旧 Realm のファイルを消し、未移行なら残すこと）、`LibraryUnavailableSpec`（暗号鍵が使えないときの扱い） |
| サムネイル | `ClipThumbnailSpec`（実際に縮小されること・保存層との出し入れ・移行後の作り直し） |
| セキュアアイテム | `SecureMenuServiceSpec`、`SecureItemsTransferSpec`（インポート／エクスポート）、`SecureItemSearchSpec`（絞り込みの共通条件・確認ウィンドウと選択パネルの一致） |
| セキュアアイテム選択パネル | `CPYSecurePickerPanelSpec`（絞り込み・行構成・サブパネル・ページング・`s` キーの導線） |
| 履歴パネル | `CPYHistoryPickerPanelSpec`（行構造・設定連動・サブパネルのキー操作）、`ClipFullTextIndexerSpec`（全文検索インデックスと検索フィルタ） |
| 環境設定ウィンドウ | `PreferencesLayoutSpec`（全タブの配置: 部品がはみ出さない・重ならない・文字が収まる。Xib の翻訳は全言語）、`CPYPreferencesWindowControllerSpec`（Esc の閉じる判定）、`CPYVersionPreferenceViewControllerSpec`（バージョンタブのレイアウト不変条件）、`CPYUpdatesPreferenceViewControllerSpec`（ライセンスボタンが全言語で見切れない） |
| 履歴からの除外 | `ClipboardConcealSpec`（秘匿マーカー）、`ExcludeAppServiceSpec`（除外アプリ判定・永続化） |
| セキュア情報ウィンドウ | `SecureInfoEditorSpec`（一覧の絞り込み・編集状態）、`SecureInfoViewSpec`（行の表示・編集可否）、`SecureInfoCommitFlowSpec`（実 Keychain を通した保存フロー）、`SecureInfoKeyActionSpec`（キー割り当て）、`SecureInfoUndoSpec` / `SecureInfoUndoFlowSpec`（取り消し）、`SecureFieldRowInteractionSpec`（削除ボタンの分離・右クリックメニュー）、`SecureInfoDragReorderSpec`（ドラッグ&ドロップ並べ替え）、`SecureInfoActionMenuSpec`（⚙ メニュー・閉じるボタン）、`SecureInfoHistorySpec`（変更履歴の参照）、`SecureFieldRowLifecycleSpec`（捨てた行の書き戻し防止） |
| TOTP | `TOTPServiceSpec`、`TOTPRegistrationFlowSpec`、`PasteServiceTOTPSpec` |
| 暗号化 | `CryptoServiceSpec`、`ClipDataStoreSpec`、`CryptoPasswordQRCodecSpec`（指紋パスワードの QR 共有） |
| 依存ライブラリ | `AcknowledgementsSpec`（同梱するライセンス一覧が `Package.resolved` と食い違っていないこと・`NOTICE` と同じであること・Clipy / ClipMenu の表示を含むこと）、`LetsMoveBundleSpec`（LetsMove が翻訳をモジュール用のバンドルから読むこと） |
| その他 | `DebugLogSpec`（デバッグ情報はオンのときだけ・文字列を持たない出来事だけを記録する・権限・削除）、`HotKeyServiceSpec`、`PasswordGenerateServiceSpec`、`LoginItemServiceSpec`（ログイン項目の同期判定） |

特定スペックだけ実行する場合は `-only-testing:ThothTests/CryptoServiceSpec` のように指定できます。

### 利用者の環境での調査（デバッグ情報）

貼り付け先への前面化・⌘V の送出・セキュアメニューの表示（ホットキー → 認証 → パネル）は、手元では再現しにくい不具合が出やすい流れです。その各段階を、**利用者が環境設定 > ベータ機能 >「デバッグ情報を保存する」をオンにしたときだけ** `DebugLog`（`Thoth/Sources/Utility/DebugLog.swift`）が `~/Library/Logs/Thoth/debug.log` に記録します。調べるときは、利用者にこれをオンにして再現してもらい、ファイルを見せてもらいます（設定画面の「表示」で Finder に出ます）。

セキュアな情報を扱う OSS として、利用者が知らないうちに行動を記録しないための約束です。

- **既定はオフ。オフの間は何も書かない**（ファイルにも macOS の統合ログにも）。オフに戻すと保存済みのファイルを消す（起動時にオフなら前回の残りも消す）
- 書けるのは `DebugEvent` に挙げた出来事と、真偽値・数値・時刻だけ。**文字列を受け取るケースを作らない**ことで、コピーした内容・セキュアアイテムの値や項目名・使ったアプリの名前やバンドル ID が型の上で入り込めないようにしている（`DebugLogSpec` が、どのケースも文字列を持たないことを確かめる）
- 何を保存し何を保存しないかは、チェックボックスの下にその場で書いてある
- ファイルは本人だけが読める権限（フォルダ 0700・ファイル 0600）で、512KB を超えたら 1 世代だけ残して新しく始める

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
- **ファイル冒頭に、何を・どんな前提で確かめるスペックかを書く。** 共有状態（UserDefaults・キーチェーン・一時フォルダ）を使う場合は、その後始末の約束もここに書きます。
- **新しいテストは「実装を意図的に戻すと落ちる」ことまで確認してから積む。** 何も検出しないテストが紛れ込むのを防ぎます。
- **画面の配置は、座標の直値ではなく不変条件で確かめる。** 環境設定のタブは `PreferencesLayoutSpec` が「はみ出さない・重ならない・文字が収まる」をまとめて検査します。タブを足したら `CPYPreferencesWindowController.makeTabViewControllers()` に足すだけで対象になります。Xib の文言を訳したら、その言語で枠に収まるかもここで分かります（収まらないときは枠を広げるか、訳を短くする）。

---

## 4. ビルド方法（CLI）

### 4-0. 事前準備（初回のみ）

1. **Xcode 本体（27 系）をインストールする。** `xcodebuild` は Xcode 本体が必要で、Command Line Tools だけでは動きません。
2. **使う Xcode を選び、初回の準備を済ませる。**

   ```bash
   # 使う Xcode を確認（/Applications/Xcode.app/Contents/Developer と出ればよい）
   xcode-select -p
   # Command Line Tools が選ばれている場合は Xcode 本体に切り替える
   sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
   # ライセンスへの同意と追加コンポーネントのインストール（Xcode を一度起動しても同じ）
   sudo xcodebuild -license accept
   xcodebuild -runFirstLaunch
   ```

3. **初回のビルドはネットワークに接続した状態で行う。** 依存ライブラリ（Swift Package）は Xcode・`xcodebuild` が、開発ツール（SwiftLint / SwiftGen / BartyCrouch）は `scripts/tool.sh` が、ビルド時に自動で取得します。先に取得だけしておく場合は次を実行します。

   ```bash
   xcodebuild -resolvePackageDependencies -project Thoth.xcodeproj -scheme Thoth   # Swift Package
   scripts/tool.sh --install                                                     # 開発ツール
   ```

Homebrew・Ruby・CocoaPods（`bundle exec pod install`）は不要です。Xcode で開くのは `Thoth.xcodeproj` です（`Thoth.xcworkspace` はありません）。

> **CocoaPods 時代（v1.5.0 まで）の作業コピーから切り替えた場合:** 残っている `Pods/`・`vendor/`・`.bundle/` は使いません（いずれも git 管理外なので削除して構いません。ただし v1.5.0 以前のコミットをビルドし直すときは `bundle exec pod install` が再び必要です）。`Thoth.xcworkspace` のフォルダが残っていても開かず、`Thoth.xcodeproj` を開いてください。

### 4-1. ユニットテスト（ビルド前の確認）

上記「3. 試験方法」のコマンドを実行し、`** TEST SUCCEEDED **` を確認します。

### 4-2. コード規約チェック

SwiftLint（設定: `.swiftlint.yml`、対象: `Thoth/Sources` と `ThothTests`）を実行します。

```bash
scripts/tool.sh swiftlint   # プロジェクトのルートで実行
```

最後に `Done linting! Found <件数> violations, <件数> serious in <ファイル数> files.` と表示されます。

- **違反は 0 件であること。** v1.6.2 で既存の警告（70 件）をすべて解消し、`.swiftlint.yml` の `strict: true` で**警告もエラーとして扱う**ようにしました。違反が 1 件でもあれば `serious` に数えられ、ビルドのスクリプトフェーズも失敗します。
- どうしても規約に合わせられない箇所は、その行に `// swiftlint:disable:this <ルール名>` を付け、直前のコメントに理由を書きます（例: `SecureMenuItem.Field.Kind` の `nesting`。保存形式と一体の型なので外に出さない）。ファイルや型が長くなったときは、規約値を緩めずに関心ごとに extension のファイルへ分けます（例: `SecureMenuService+Keychain.swift`・`SecureMenuServiceSpec+Storage.swift`）。

> **補足:** Xcode ビルドのスクリプトフェーズでも、同じ SwiftLint（`scripts/tool.sh` が取得する 0.65.1）でリントが実行されます。ビルドを速くしたい場合など、スクリプトフェーズは環境変数 `SKIP_SWIFTLINT=1` でスキップできます。

主な規約値（`.swiftlint.yml`）:

| 項目 | 制限 |
|---|---|
| 1 行の長さ | 300 文字以下 |
| ファイルの長さ | 500 行以下（警告）/ 1000 行以下（エラー） |
| 型本体の長さ | 300 行以下（警告）/ 400 行以下（エラー） |
| 関数本体の長さ | 100 行以下（警告）/ 200 行以下（エラー） |

### 4-3. ビルド（デバッグ / リリース）

リントはビルド時に実行されます。CLI ビルドを速くしたい場合は `SKIP_SWIFTLINT=1` を付けてスキップできます。SwiftGen（`Thoth/Generated/` の生成）と BartyCrouch（XIB の文言の同期）もビルドのたびにコンパイルより前に走ります。

```bash
# クリーン（必要に応じて）
SKIP_SWIFTLINT=1 xcodebuild -project Thoth.xcodeproj -scheme Thoth -configuration Debug clean
SKIP_SWIFTLINT=1 xcodebuild -project Thoth.xcodeproj -scheme Thoth -configuration Release clean
# 完全にクリーンな状態から始めたい場合は DerivedData も削除
# （Swift Package の取得分も消えるため、次のビルドで取得し直す。ネットワークが必要）
rm -rf ~/Library/Developer/Xcode/DerivedData/Thoth-*
# 下の -derivedDataPath build/DerivedData や make_dmg.sh で作ったものは build/ にある
rm -rf build

# デバッグビルド
SKIP_SWIFTLINT=1 xcodebuild -project Thoth.xcodeproj -scheme Thoth -configuration Debug build

# リリースビルド
SKIP_SWIFTLINT=1 xcodebuild -project Thoth.xcodeproj -scheme Thoth -configuration Release build
```

成果物の出力先を明示する場合:

```bash
SKIP_SWIFTLINT=1 xcodebuild -project Thoth.xcodeproj -scheme Thoth \
  -configuration Release build -derivedDataPath build/DerivedData ARCHS=arm64
# → build/DerivedData/Build/Products/Release/Thoth.app に生成される
```

`ARCHS=arm64` はコマンドラインで渡すと Swift Package のターゲットにも効き、パッケージも arm64 だけでビルドされます（プロジェクトの `ARCHS` はパッケージに引き継がれない。`make_dmg.sh` と同じ指定）。

生成アプリの起動 / 配置:

```bash
open build/DerivedData/Build/Products/Release/Thoth.app

# または Applications へ配置（起動中の Thoth を終了し、古いアプリを削除してから複製する）
osascript -e 'quit app "Thoth"'
rm -rf /Applications/Thoth.app
cp -R build/DerivedData/Build/Products/Release/Thoth.app /Applications/
```

> **古いアプリを消してから複製する理由:** `cp -R` は既存の `Thoth.app` を置き換えず、中身を混ぜ合わせます。v1.5.0 以前（CocoaPods）の `Thoth.app` には今は使わないフレームワークが `Contents/Frameworks/` に入っているため、それが残ってアプリの署名が壊れます。アプリを削除しても、履歴・スニペット・セキュアアイテム（`~/Library/Application Support/`・キーチェーン）は消えません。

### 4-4. 配布用 DMG の作成（自分・身内用）

Release ビルドと DMG 化を 1 コマンドで行うスクリプトを用意しています。

```bash
./scripts/make_dmg.sh
```

**動作内容:**

1. 開発ツールを用意（`scripts/tool.sh --install`。取得済みなら何もしない）
2. Swift Package を `build/SourcePackages` へ取得し、サードパーティライセンス一覧を作り直す（`scripts/update-acknowledgements.swift`。一覧が変わったらコミットするよう警告を出す）
3. `Release` 構成でビルド（`build/DerivedData` へ出力。`ARCHS=arm64` を渡し、パッケージも arm64 だけでビルドする）
4. `Thoth.app`、`/Applications` へのシンボリックリンク、ウィンドウの背景をステージング（背景は `scripts/make-dmg-background.swift` が矢印と案内文を通常用・Retina 用に描き、1 つの TIFF にまとめる）
5. `hdiutil` で書き込み可能な DMG を作ってマウントし、Finder（AppleScript）にウィンドウを設定させる: 大きさ 560 × 370（macOS 27 の Finder が下端に出すバーが重なっても案内文が隠れない高さ）・ツールバーなし・アイコン 128pt・矢印の左に `Thoth.app`、右に `Applications`。Finder がこれを DMG の `.DS_Store` に書く
6. 圧縮 DMG（UDZO）に変換

初回は、ターミナルから Finder を操作する許可を求められます（システム設定 > プライバシーとセキュリティ > オートメーション）。許可しない・失敗した場合は、ウィンドウの設定なしの DMG を作ります（中身は同じ）。見た目だけを調整するときは、`./scripts/make_dmg.sh --dmg-only` でビルドを省き、既存の `build/DerivedData/…/Release/Thoth.app` から DMG だけを作り直せます。macOS 27 では `hdiutil` が非推奨の警告を出しますが、動作します。

**出力先:** `build/Thoth-<version>.dmg`（バージョンは `Info.plist` の `CFBundleShortVersionString` から自動取得。`build/` は `.gitignore` 済みのためコミットされない）

**リリース日について:** バージョンタブに表示されるリリース日は、`main` に付けた
バージョンタグ `v.<version>`（例: `v.1.5.1`）の付与日（注釈タグの tagger 日付）から自動的に決まる。
`make_dmg.sh` がその日付を取得し、ビルド設定 `THOTH_RELEASE_DATE` として
`Info.plist` の `ThothReleaseDate` に注入する（手動更新は不要）。そのため、
**`develop` を `main` へマージしてタグを付けた後に** `make_dmg.sh` を実行すること。
タグの無い開発ビルドでは空になり、リリース日は表示されない。

**実行条件:**

- macOS + Xcode 本体（`xcodebuild`。4-0 の準備を済ませておく）。`hdiutil`・`osascript` は macOS 標準のため追加インストール不要
- 初回はネットワーク接続（開発ツールを `.tools/` へ、Swift Package を `build/SourcePackages` へ取得する）
- Apple Silicon (arm64) 専用ビルド
- 署名は ad-hoc（Developer ID 署名・公証なし）

**利用方法:** 起動中の Thoth を終了してから、生成された DMG を開き、`Thoth.app` を `Applications` へドラッグする（既に入っている場合は「置き換える」を選ぶ。Finder の置き換えは古いアプリを丸ごと入れ替えるため、`cp -R` のような混ざりは起きない）。

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
