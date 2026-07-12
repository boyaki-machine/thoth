<div align="center">
  <img src="./Resources/clipy_logo.png" width="400">
</div>

<br>

![CI](https://github.com/Clipy/Clipy/workflows/CI/badge.svg)
[![Release version](https://img.shields.io/github/release/Clipy/Clipy.svg)](https://github.com/Clipy/Clipy/releases/latest)
[![OpenCollective](https://opencollective.com/clipy/backers/badge.svg)](#backers)
[![OpenCollective](https://opencollective.com/clipy/sponsors/badge.svg)](#sponsors)

Clipy は macOS 向けのクリップボード拡張アプリです。

---

__要件__: macOS 10.13 High Sierra 以降 · Apple Silicon (arm64 のみ対応)

__配布サイト__: <https://clipy-app.com>

<img src="http://clipy-app.com/img/screenshot1.png" width="400">

### Secure Menu — クリップボードに残さずに認証情報を貼り付ける

Secure Menu を使うと、パスワードやその他の機密情報を、クリップボードに一度も置かずに、任意のアプリへ直接貼り付けることができます。項目は macOS のキーチェーンに暗号化して保存され、メニューを開くたびに Touch ID / パスワード認証が行われます。

#### 機能

| 機能 | 詳細 |
|---------|--------|
| **キーチェーン保存** | すべての値は `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` で保存され、iCloud には同期されません |
| **生体認証ロック** | メニューを表示する前に Touch ID（またはログインパスワード）の認証が必要です |
| **2段階メニュー** | 親アイテム（例: "GitHub"）を選択した後、具体的な項目（例: "Password"）を選びます |
| **直接貼り付け** | 選択した値は、クリップボードを触ることなく、最前面のアプリへ貼り付けられます |
| **続けて貼り付けモード** | 30 秒以内にメニューを再度開くと、前回選択した項目が自動でハイライトされます |
| **キーボード操作** | メニュー内では矢印キーや vim 風の `hjkl` キーも利用できます |

#### 使い方

**ステップ 1 — 認証情報を登録する**

メニューバーのアイコンを開き、**Manage Secure Items…** を選択するか、**Preferences → Shortcuts** から表示されるショートカットを使います。

管理ウィンドウで **+** を押して新しい項目を追加します。

1. **Title** を入力します（例: "GitHub", "AWS Console"）
2. フィールド一覧の **+** をクリックして項目を追加します
3. **Label**（例: "Password"）と **Value** を入力します
4. 値をマスクしたい場合は 🔒 をチェックします
5. **Save** をクリックします

**ステップ 2 — 認証情報を貼り付ける**

1. 対象アプリのパスワード入力欄にカーソルを合わせます
2. ホットキーを押します（デフォルト: **⌘⇧-**）すると、Touch ID / パスワード認証ダイアログが表示されます
3. 認証後、2段階メニューが開きます
4. 親アイテムを選択した後、貼り付けたい項目を選びます

ホットキーは **Preferences → Shortcuts → Secure Menu** で変更できます。

#### セキュリティに関する注意

- 値は認証時にのみキーチェーンから読み込まれ、クリップボードへ書き込まれることはありません
- キーチェーン項目には `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` が付与されるため、ロック画面ではアクセスできず、iCloud にバックアップされません

---

### 暗号化ファイルの復旧 — Clipy が無い環境での復号

Clipy で暗号化したファイル（`.enc`）は **openssl 互換コンテナ**を採用しているため、Clipy がインストールされていない Mac でも、標準搭載の `openssl` コマンドだけで復号できます。

ファイル構造は「45 バイトの Clipy ヘッダー（マジック + フラグ + PBKDF2 反復回数 + HMAC-SHA256 タグ）」+「標準の `openssl enc` 出力（`Salted__` + salt + AES-256-CBC 暗号文、鍵導出は PBKDF2-HMAC-SHA256）」です。

**重要: ファイルをそのまま `openssl enc -d` に渡すと `bad magic number` エラーになります。先頭 45 バイトのヘッダーを `tail -c +46` で取り除いてから渡してください。**

```sh
# 先頭 45 バイトのヘッダーを取り除いて openssl で復号（反復回数の既定値は 200000）
tail -c +46 secret.txt.enc | openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 \
  -pass pass:パスワード -out secret.txt

# フォルダを暗号化したファイルの場合、出力は tar アーカイブになる:
tail -c +46 myfolder.enc | openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 \
  -pass pass:パスワード -out myfolder.tar && tar -xf myfolder.tar
```

補足:

- Clipy 内での復号は、ヘッダー内の HMAC-SHA256 タグを事前検証（Encrypt-then-MAC）するため、改竄や誤パスワードを確実に検知します。openssl CLI での復号はこの検証を通りません（誤パスワードの大半は CBC パディングエラーで検出されます）
- 旧バージョンの Clipy で暗号化したファイル（8 バイトのマーカー + openssl enc 出力、反復回数 100000）も同様に `tail -c +9` と `-iter 100000` で復号できます
- 暗号化完了時にウィンドウに表示される復号コマンド例をそのままコピーして使えます

---

### 開発環境
* macOS 26 (Apple Silicon)
* Xcode 26 系（26.6 で動作確認済み）
* Swift 5.3（プロジェクト設定の Swift バージョン）
* SwiftLint（Homebrew 版 0.65 系で動作確認済み）

### ビルド方法
0. プロジェクトのルートディレクトリへ移動します
1. `bundle install --path=vendor/bundle && bundle exec pod install`
2. 環境をクリーンします（Xcode の場合: **Product → Clean Build Folder**（⇧⌘K））
3. Xcode で `Clipy.xcworkspace` を開きます
4. ビルドします

> **注意**: `pod install` を実行すると `Pods/LoginServiceKit` への手動修正（macOS 13 以降で `SMAppService` を使用する対応）が上書きされます。`pod install` 後はビルドエラー・動作を確認し、必要に応じて修正を再適用してください。

#### CLI でのビルド（成功確認済みの手順）

以下は、この環境で実際に CLI ビルドが成功することを確認した手順です。現行の Apple Silicon 環境では、SwiftLint の実行スクリプトが失敗するため、CLI ビルド時には `SKIP_SWIFTLINT=1` を付けて実行します。

1. Xcode Command Line Tools をインストールします。

```bash
xcode-select --install
```

2. Homebrew が未導入の場合はインストールします。

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

3. SwiftLint をインストールします（必須ではありませんが、環境を整えるために実行します）。

```bash
brew install swiftlint
swiftlint --version
```

4. 依存関係をインストールします。Ruby 3.x 系の環境で実行してください（この環境では Ruby 4.0 系では一部の Gem が失敗しました）。

```bash
export PATH="/opt/homebrew/opt/ruby@3.2/bin:$PATH"
export GEM_HOME="$HOME/.gem/ruby"
export GEM_PATH="$HOME/.gem/ruby"
gem install base64 bundler -v 2.7.2
bundle _2.7.2_ install --path=vendor/bundle
bundle _2.7.2_ exec pod install
```

5. ビルドの前段として、環境をクリーンします。

```bash
# ビルド中間生成物のクリーン
SKIP_SWIFTLINT=1 xcodebuild -workspace Clipy.xcworkspace -scheme Clipy -configuration Debug clean
SKIP_SWIFTLINT=1 xcodebuild -workspace Clipy.xcworkspace -scheme Clipy -configuration Release clean

# -derivedDataPath を指定してビルドしている場合は、その出力先も削除
rm -rf build/DerivedData
```

依存ライブラリ（Pods）の変更が疑われる場合など、完全にクリーンな状態から始めたいときは DerivedData ごと削除します。

```bash
rm -rf ~/Library/Developer/Xcode/DerivedData/Clipy-*
```

6. CLI からビルドします。

デバッグビルド:

```bash
SKIP_SWIFTLINT=1 xcodebuild -workspace Clipy.xcworkspace -scheme Clipy -configuration Debug build
```

リリースビルド:

```bash
SKIP_SWIFTLINT=1 xcodebuild -workspace Clipy.xcworkspace -scheme Clipy -configuration Release build
```

7. 生成物の出力先を明示したい場合は、以下のように指定できます。

```bash
SKIP_SWIFTLINT=1 xcodebuild -workspace Clipy.xcworkspace -scheme Clipy -configuration Debug build -derivedDataPath build/DerivedData
```

この場合、成果物は `build/DerivedData/Build/Products/Debug/` 配下に出力されます。通常、実行可能なアプリ本体は `Clipy.app` として生成されます。

8. 生成されたアプリを起動するには、以下を実行します。

```bash
open build/DerivedData/Build/Products/Debug/Clipy.app
```

または、既存のアプリを置き換える場合は、Applications フォルダへコピーします。

```bash
cp -R build/DerivedData/Build/Products/Debug/Clipy.app /Applications/
```

#### セキュアアイテムと再ビルド（コード署名に関する注意）

セキュアアイテムは macOS のログインキーチェーンに保存され、キーチェーン項目の ACL（アクセス制御リスト）は「作成したアプリのコード署名」に紐付きます。

**ad-hoc 署名（証明書なしのローカルビルド）の場合、再ビルドのたびにバイナリのハッシュが変わり、キーチェーンからは「別のアプリ」と判定されます。** そのままでは、バージョンアップや再ビルド後に既存のセキュアアイテムを読み出せなくなります。

#### 起動時の自動再署名

この問題に対応するため、アプリは起動時に自身の署名を確認し、デバイス固有の証明書で自動的に再署名します（`CodeSignService`）。ユーザーが証明書を意識する必要はありません。

1. 起動時、自身が証明書「**Clipy Local Signing**」で署名済みかを確認します（署名済みなら何もしません）
2. 未署名（ad-hoc）の場合、ログインキーチェーンから証明書を探します。**過去の起動で生成済みならそれを再利用**し、なければ自己署名のコード署名証明書を生成してキーチェーンに保存します（デバイスごとに一度だけ生成）
3. 自身の .app バンドルを再署名し、アプリを自動で再起動します

同じデバイス上では常に同じ証明書で署名されるため、**アプリのバージョンが変わってもキーチェーンの ACL が一致し、セキュアアイテムを読み出せます**。

注意事項:

- デバイスで**初回のみ** macOS の確認ダイアログが表示されることがあります（証明書の信頼設定、署名鍵の使用許可）。「常に許可」を選択してください
- 署名が変わるため、初回の再署名後は**アクセシビリティ権限の再付与**が必要です（以後のバージョンアップでは不要になります）
- 再署名を無効化したい場合は `--clipy-skip-resign` 引数を付けて起動してください
- いずれかの手順が失敗した場合は ad-hoc 署名のまま起動を続けます（ログは Console.app で `CodeSignService` を検索）

#### アクセシビリティ権限のエントリについて

macOS のアクセシビリティ（TCC）はアプリを「バンドル ID + コード署名要件」で識別するため、ad-hoc 署名のままビルドを重ねると、システム設定のアクセシビリティ一覧に Clipy のエントリが増殖します。

本アプリは再署名が**完了してから**アクセシビリティ確認を行うようになっており（再署名前の ad-hoc バイナリは TCC に登録されません）、「Clipy Local Signing」で署名された状態で一度権限を許可すれば、**以後のバージョンでも同じエントリが再利用されます**。

過去のビルドで増えた古いエントリは自動では消せないため、一度だけ以下でリセットしてから、新しく起動した Clipy に権限を付与し直してください。

```bash
tccutil reset Accessibility com.clipy-app.Clipy
```

また、起動場所（パス）が変わるとエントリが分かれて見えることがあるため、アプリは毎回同じ場所（例: `/Applications` または `~/Applications`）に配置して起動することを推奨します。

なお、読み出しに失敗した状態で保存すると既存データを上書きしてしまうため、アプリ側では読み出し失敗を検出した場合に保存を拒否し、警告を表示するようになっています。データ移行には Manage Secure Items ウィンドウの Export / Import 機能も利用できます。

### 試験方法（成功確認済みの手順）

ユニットテスト（`ClipyTests` ターゲット / Quick + Nimble）は、スキームの Test アクション（Debug 構成）で実行します。

```bash
SKIP_SWIFTLINT=1 xcodebuild -workspace Clipy.xcworkspace -scheme Clipy -destination 'platform=macOS,arch=arm64' test
```

末尾に `** TEST SUCCEEDED **` と表示されれば成功です。Xcode 上では **Product → Test**（⌘U）でも実行できます。

- テスト対象: DraggedDataSpec / FolderSpec / HotKeyServiceSpec / SnippetSpec / SecureMenuItemSpec / SecureMenuServiceSpec / PasswordGenerateServiceSpec / SecureItemEditSpec / CryptoServiceSpec（計 78 テスト）
- テストは Realm のインメモリ DB・UserDefaults・キーチェーン（テスト専用エントリ `com.clipy-app.ClipyTests.SecureMenu` を使用し、本番データには触れません）を使用するため、追加のセットアップは不要です
- `ClipyTests` は `@testable import Clipy` を使用するため、Test アクション（Debug 構成）以外で実行する場合は `ENABLE_TESTABILITY=YES` が必要です

### コード規約チェック方法（成功確認済みの手順）

コード規約は SwiftLint（設定ファイル: `.swiftlint.yml`）でチェックします。対象は `Clipy/Sources` と `ClipyTests` です。

```bash
brew install swiftlint   # 未導入の場合
swiftlint                # プロジェクトのルートディレクトリで実行
```

`Done linting! Found 0 violations` と表示されれば規約違反はありません。

> **注意**: CocoaPods 経由の `Pods/SwiftLint`（0.31 系）は現行の Apple Silicon 環境では動作しません（sourcekitd の読み込みに失敗します）。必ず Homebrew 版の `swiftlint` を使用してください。Xcode ビルド時のスクリプトフェーズは `SKIP_SWIFTLINT=1` でスキップできます。

主な規約値（`.swiftlint.yml` より）:

| 項目 | 制限 |
|------|------|
| 1 行の長さ | 300 文字以下 |
| ファイルの長さ | 500 行以下（警告）/ 1000 行以下（エラー） |
| 型本体の長さ | 300 行以下（警告）/ 400 行以下（エラー） |
| 関数本体の長さ | 100 行以下（警告）/ 200 行以下（エラー） |

### 貢献について
1. フォークします（https://github.com/Clipy/Clipy/fork）
2. 機能用ブランチを作成します（`git checkout -b my-new-feature`）
3. 変更内容をコミットします（`git commit -am 'Add some feature'`）
4. ブランチをプッシュします（`git push origin my-new-feature`）
5. Pull Request を作成します

### ローカライズ貢献者募集
Clipy ではローカライズ貢献者を募集しています。  
協力できる場合は [CONTRIBUTING.md](https://github.com/Clipy/Clipy/blob/master/.github/CONTRIBUTING.md) をご覧ください。

### 配布について
派生作品を配布する場合、特に Mac App Store で配布する場合は、次の 2 つのルールに従ってください。

1. 製品名として `Clipy` と `ClipMenu` を使用しないでください
2. MIT ライセンスの条件に従ってください

ご協力ありがとうございます。

### バッカーズ

月額の寄付で支援し、活動を続けられるようにしてください。 [[バッカーになる](https://opencollective.com/clipy#backer)]

<a href="https://opencollective.com/clipy/backer/0/website" target="_blank"><img src="https://opencollective.com/clipy/backer/0/avatar.svg"></a>
<a href="https://opencollective.com/clipy/backer/1/website" target="_blank"><img src="https://opencollective.com/clipy/backer/1/avatar.svg"></a>
<a href="https://opencollective.com/clipy/backer/2/website" target="_blank"><img src="https://opencollective.com/clipy/backer/2/avatar.svg"></a>
<a href="https://opencollective.com/clipy/backer/3/website" target="_blank"><img src="https://opencollective.com/clipy/backer/3/avatar.svg"></a>
<a href="https://opencollective.com/clipy/backer/4/website" target="_blank"><img src="https://opencollective.com/clipy/backer/4/avatar.svg"></a>
<a href="https://opencollective.com/clipy/backer/5/website" target="_blank"><img src="https://opencollective.com/clipy/backer/5/avatar.svg"></a>
<a href="https://opencollective.com/clipy/backer/6/website" target="_blank"><img src="https://opencollective.com/clipy/backer/6/avatar.svg"></a>
<a href="https://opencollective.com/clipy/backer/7/website" target="_blank"><img src="https://opencollective.com/clipy/backer/7/avatar.svg"></a>
<a href="https://opencollective.com/clipy/backer/8/website" target="_blank"><img src="https://opencollective.com/clipy/backer/8/avatar.svg"></a>
<a href="https://opencollective.com/clipy/backer/9/website" target="_blank"><img src="https://opencollective.com/clipy/backer/9/avatar.svg"></a>
<a href="https://opencollective.com/clipy/backer/10/website" target="_blank"><img src="https://opencollective.com/clipy/backer/10/avatar.svg"></a>
<a href="https://opencollective.com/clipy/backer/11/website" target="_blank"><img src="https://opencollective.com/clipy/backer/11/avatar.svg"></a>
<a href="https://opencollective.com/clipy/backer/12/website" target="_blank"><img src="https://opencollective.com/clipy/backer/12/avatar.svg"></a>
<a href="https://opencollective.com/clipy/backer/13/website" target="_blank"><img src="https://opencollective.com/clipy/backer/13/avatar.svg"></a>
<a href="https://opencollective.com/clipy/backer/14/website" target="_blank"><img src="https://opencollective.com/clipy/backer/14/avatar.svg"></a>
<a href="https://opencollective.com/clipy/backer/15/website" target="_blank"><img src="https://opencollective.com/clipy/backer/15/avatar.svg"></a>
<a href="https://opencollective.com/clipy/backer/16/website" target="_blank"><img src="https://opencollective.com/clipy/backer/16/avatar.svg"></a>
<a href="https://opencollective.com/clipy/backer/17/website" target="_blank"><img src="https://opencollective.com/clipy/backer/17/avatar.svg"></a>
<a href="https://opencollective.com/clipy/backer/18/website" target="_blank"><img src="https://opencollective.com/clipy/backer/18/avatar.svg"></a>
<a href="https://opencollective.com/clipy/backer/19/website" target="_blank"><img src="https://opencollective.com/clipy/backer/19/avatar.svg"></a>
<a href="https://opencollective.com/clipy/backer/20/website" target="_blank"><img src="https://opencollective.com/clipy/backer/20/avatar.svg"></a>
<a href="https://opencollective.com/clipy/backer/21/website" target="_blank"><img src="https://opencollective.com/clipy/backer/21/avatar.svg"></a>
<a href="https://opencollective.com/clipy/backer/22/website" target="_blank"><img src="https://opencollective.com/clipy/backer/22/avatar.svg"></a>
<a href="https://opencollective.com/clipy/backer/23/website" target="_blank"><img src="https://opencollective.com/clipy/backer/23/avatar.svg"></a>
<a href="https://opencollective.com/clipy/backer/24/website" target="_blank"><img src="https://opencollective.com/clipy/backer/24/avatar.svg"></a>
<a href="https://opencollective.com/clipy/backer/25/website" target="_blank"><img src="https://opencollective.com/clipy/backer/25/avatar.svg"></a>
<a href="https://opencollective.com/clipy/backer/26/website" target="_blank"><img src="https://opencollective.com/clipy/backer/26/avatar.svg"></a>
<a href="https://opencollective.com/clipy/backer/27/website" target="_blank"><img src="https://opencollective.com/clipy/backer/27/avatar.svg"></a>
<a href="https://opencollective.com/clipy/backer/28/website" target="_blank"><img src="https://opencollective.com/clipy/backer/29/avatar.svg"></a>

### スポンサー

スポンサーになって、GitHub の README にロゴとサイトリンクを掲載しましょう。 [[スポンサーになる](https://opencollective.com/clipy#sponsor)]

<a href="https://opencollective.com/clipy/sponsor/0/website" target="_blank"><img src="https://opencollective.com/clipy/sponsor/0/avatar.svg"></a>
<a href="https://opencollective.com/clipy/sponsor/1/website" target="_blank"><img src="https://opencollective.com/clipy/sponsor/1/avatar.svg"></a>
<a href="https://opencollective.com/clipy/sponsor/2/website" target="_blank"><img src="https://opencollective.com/clipy/sponsor/2/avatar.svg"></a>
<a href="https://opencollective.com/clipy/sponsor/3/website" target="_blank"><img src="https://opencollective.com/clipy/sponsor/3/avatar.svg"></a>
<a href="https://opencollective.com/clipy/sponsor/4/website" target="_blank"><img src="https://opencollective.com/clipy/sponsor/5/avatar.svg"></a>
<a href="https://opencollective.com/clipy/sponsor/6/website" target="_blank"><img src="https://opencollective.com/clipy/sponsor/6/avatar.svg"></a>
<a href="https://opencollective.com/clipy/sponsor/7/website" target="_blank"><img src="https://opencollective.com/clipy/sponsor/7/avatar.svg"></a>
<a href="https://opencollective.com/clipy/sponsor/8/website" target="_blank"><img src="https://opencollective.com/clipy/sponsor/8/avatar.svg"></a>
<a href="https://opencollective.com/clipy/sponsor/9/website" target="_blank"><img src="https://opencollective.com/clipy/sponsor/9/avatar.svg"></a>
<a href="https://opencollective.com/clipy/sponsor/10/website" target="_blank"><img src="https://opencollective.com/clipy/sponsor/10/avatar.svg"></a>
<a href="https://opencollective.com/clipy/sponsor/11/website" target="_blank"><img src="https://opencollective.com/clipy/sponsor/12/avatar.svg"></a>
<a href="https://opencollective.com/clipy/sponsor/13/website" target="_blank"><img src="https://opencollective.com/clipy/sponsor/13/avatar.svg"></a>
<a href="https://opencollective.com/clipy/sponsor/14/website" target="_blank"><img src="https://opencollective.com/clipy/sponsor/14/avatar.svg"></a>
<a href="https://opencollective.com/clipy/sponsor/15/website" target="_blank"><img src="https://opencollective.com/clipy/sponsor/15/avatar.svg"></a>
<a href="https://opencollective.com/clipy/sponsor/16/website" target="_blank"><img src="https://opencollective.com/clipy/sponsor/16/avatar.svg"></a>
<a href="https://opencollective.com/clipy/sponsor/17/website" target="_blank"><img src="https://opencollective.com/clipy/sponsor/17/avatar.svg"></a>
<a href="https://opencollective.com/clipy/sponsor/18/website" target="_blank"><img src="https://opencollective.com/clipy/sponsor/18/avatar.svg"></a>
<a href="https://opencollective.com/clipy/sponsor/19/website" target="_blank"><img src="https://opencollective.com/clipy/sponsor/19/avatar.svg"></a>
<a href="https://opencollective.com/clipy/sponsor/20/website" target="_blank"><img src="https://opencollective.com/clipy/sponsor/20/avatar.svg"></a>
<a href="https://opencollective.com/clipy/sponsor/21/website" target="_blank"><img src="https://opencollective.com/clipy/sponsor/21/avatar.svg"></a>
<a href="https://opencollective.com/clipy/sponsor/22/website" target="_blank"><img src="https://opencollective.com/clipy/sponsor/22/avatar.svg"></a>
<a href="https://opencollective.com/clipy/sponsor/23/website" target="_blank"><img src="https://opencollective.com/clipy/sponsor/23/avatar.svg"></a>
<a href="https://opencollective.com/clipy/sponsor/24/website" target="_blank"><img src="https://opencollective.com/clipy/sponsor/24/avatar.svg"></a>
<a href="https://opencollective.com/clipy/sponsor/25/website" target="_blank"><img src="https://opencollective.com/clipy/sponsor/25/avatar.svg"></a>
<a href="https://opencollective.com/clipy/sponsor/26/website" target="_blank"><img src="https://opencollective.com/clipy/sponsor/26/avatar.svg"></a>
<a href="https://opencollective.com/clipy/sponsor/27/website" target="_blank"><img src="https://opencollective.com/clipy/sponsor/27/avatar.svg"></a>
<a href="https://opencollective.com/clipy/sponsor/28/website" target="_blank"><img src="https://opencollective.com/clipy/sponsor/28/avatar.svg"></a>
<a href="https://opencollective.com/clipy/sponsor/29/website" target="_blank"><img src="https://opencollective.com/clipy/sponsor/29/avatar.svg"></a>

### ライセンス
Clipy は MIT ライセンスのもとで提供されています。詳細は LICENSE ファイルをご覧ください。

アイコンの著作権は、それぞれの作者に帰属します。

### スペシャル・サンクス
__[@naotaka](https://github.com/naotaka) が OSS として [ClipMenu](https://github.com/naotaka/ClipMenu) を公開してくれたことに感謝します。__
