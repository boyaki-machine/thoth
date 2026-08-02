import Quick
import Nimble
@testable import Thoth

// MARK: - SecureInfoEditor Tests
//
// セキュア情報確認ウィンドウの一覧絞り込みと選択追従。
// UI 非依存の状態オブジェクトなので、AppKit 抜きで挙動を固定できる。

// BDD スペックは多数の it ブロックを含み型本体が長くなるため型長ルールを緩める
// swiftlint:disable:next type_body_length
class SecureInfoEditorSpec: QuickSpec {

    override class func spec() {
        filterSpecs()
        searchableTextSpecs()
        selectionSpecs()
        viewIntegrationSpecs()
        fieldRowSpecs()
        openableURLSpecs()
        detailRowBuildingSpecs()
    }

    // MARK: - Field row rendering

    /// 行ビューが「値をどう見せるか」。TOTP secret とマスク値を
    /// 画面へ出さないことを固定する
    private static func fieldRowSpecs() {
        describe("フィールド行の表示") {
            typealias Row = SecureFieldRowView

            it("通常フィールドは値をそのまま表示する") {
                let field = SecureMenuItem.Field(label: "ID", value: "alice")
                expect(Row.displayedValue(for: field, isRevealed: false)) == "alice"
            }

            it("マスク指定は伏せ字にし、表示切替で平文になる") {
                let field = SecureMenuItem.Field(label: "PW", value: "s3cr3t", isPassword: true)
                expect(Row.displayedValue(for: field, isRevealed: false)) == Row.maskedPlaceholder
                expect(Row.displayedValue(for: field, isRevealed: true)) == "s3cr3t"
            }

            // TOTP は secret を決して画面に出さない。表示はその時点のコードだけ
            it("TOTP は表示切替に関係なく値を出さない") {
                let field = SecureMenuItem.Field(label: "TOTP", value: "JBSWY3DPEHPK3PXP", kind: .totp)
                expect(Row.displayedValue(for: field, isRevealed: false)) == ""
                expect(Row.displayedValue(for: field, isRevealed: true)) == ""
            }

            it("URL とメモは値をそのまま表示する") {
                let url = SecureMenuItem.Field(label: "URL", value: "https://example.com", kind: .url)
                let note = SecureMenuItem.Field(label: "Memo", value: "line1\nline2", kind: .note)
                expect(Row.displayedValue(for: url, isRevealed: false)) == "https://example.com"
                expect(Row.displayedValue(for: note, isRevealed: false)) == "line1\nline2"
            }

            it("マスク指定のメモも伏せ字になる") {
                let field = SecureMenuItem.Field(label: "Memo", value: "hidden", isPassword: true, kind: .note)
                expect(Row.displayedValue(for: field, isRevealed: false)) == Row.maskedPlaceholder
                expect(Row.displayedValue(for: field, isRevealed: true)) == "hidden"
            }

            it("TOTP の表示は桁区切りと残り秒数を含む") {
                expect(Row.totpDisplayString(code: "123456", remainingSeconds: 18)) == "123 456 · 18s"
                expect(Row.totpDisplayString(code: "12345678", remainingSeconds: 5)) == "1234 5678 · 5s"
            }

            // 境界値: secret を解釈できない場合でも画面が壊れない
            it("コードを生成できない TOTP はプレースホルダーを表示する") {
                expect(Row.totpDisplayString(code: nil, remainingSeconds: 0)) == "------"
            }

            it("マスクを持つ行だけ表示切替が効く") {
                let masked = SecureFieldRowView(field: SecureMenuItem.Field(label: "PW", value: "s3cr3t", isPassword: true))
                masked.toggleReveal()
                expect(masked.isRevealed) == true
                expect(masked.valueField.stringValue) == "s3cr3t"
                masked.hideRevealedValue()
                expect(masked.isRevealed) == false
                expect(masked.valueField.stringValue) == SecureFieldRowView.maskedPlaceholder

                // マスク指定の無いフィールドでは切り替わらない
                let plain = SecureFieldRowView(field: SecureMenuItem.Field(label: "ID", value: "alice"))
                plain.toggleReveal()
                expect(plain.isRevealed) == false
                expect(plain.valueField.stringValue) == "alice"
            }

            // 押せないボタンは並べない（TOTP に表示切替、URL 以外に「開く」を出さない）
            it("種別に応じたボタンだけを並べる") {
                func buttonCount(_ field: SecureMenuItem.Field) -> Int {
                    let row = SecureFieldRowView(field: field)
                    return [row.revealButton, row.openButton, row.copyButton]
                        .filter { $0.superview is NSStackView }.count
                }
                expect(buttonCount(SecureMenuItem.Field(label: "ID", value: "a"))) == 1
                expect(buttonCount(SecureMenuItem.Field(label: "PW", value: "a", isPassword: true))) == 2
                expect(buttonCount(SecureMenuItem.Field(label: "URL", value: "a", kind: .url))) == 2
                expect(buttonCount(SecureMenuItem.Field(label: "T", value: "a", kind: .totp))) == 1
                expect(buttonCount(SecureMenuItem.Field(label: "M", value: "a", kind: .note))) == 1
            }

            it("メモは複数行ビュー、それ以外は単一行ビューに値が入る") {
                let note = SecureFieldRowView(field: SecureMenuItem.Field(label: "M", value: "a\nb", kind: .note))
                expect(note.noteTextView.string) == "a\nb"
                expect(note.noteTextView.isEditable) == false

                let plain = SecureFieldRowView(field: SecureMenuItem.Field(label: "ID", value: "alice"))
                expect(plain.valueField.stringValue) == "alice"
            }

            // メモ内の URL を自動リンク化すると、クリックだけで外部アプリが開いてしまう
            it("メモの自動リンク検出は無効にする") {
                let note = SecureFieldRowView(field: SecureMenuItem.Field(label: "M", value: "https://example.com", kind: .note))
                expect(note.noteTextView.isAutomaticLinkDetectionEnabled) == false
            }

            // コード生成の NSTextView はスクロールビューへの載せ方を自前で設定しないと
            // 本文が折り返されず、行数に応じたスクロールもできない
            it("メモのテキストビューが折り返しと縦スクロールの設定を持つ") {
                let note = SecureFieldRowView(field: SecureMenuItem.Field(label: "M", value: "a\nb", kind: .note))
                expect(note.noteTextView.isVerticallyResizable) == true
                expect(note.noteTextView.isHorizontallyResizable) == false
                expect(note.noteTextView.textContainer?.widthTracksTextView) == true
            }

            it("マスク指定のメモは複数行ビュー側で伏せ字になり、表示切替で戻る") {
                let field = SecureMenuItem.Field(label: "M", value: "line1\nline2", isPassword: true, kind: .note)
                let row = SecureFieldRowView(field: field)
                expect(row.noteTextView.string) == SecureFieldRowView.maskedPlaceholder
                row.toggleReveal()
                expect(row.noteTextView.string) == "line1\nline2"
                row.hideRevealedValue()
                expect(row.noteTextView.string) == SecureFieldRowView.maskedPlaceholder
            }

            // マスク指定の URL では表示切替・開く・コピーの 3 つが並ぶ
            it("マスク指定の URL では 3 つのボタンが並ぶ") {
                let field = SecureMenuItem.Field(label: "URL", value: "https://example.com", isPassword: true, kind: .url)
                let row = SecureFieldRowView(field: field)
                let shown = [row.revealButton, row.openButton, row.copyButton]
                    .filter { $0.superview is NSStackView }
                expect(shown.count) == 3
                // マスク中でも「開く」対象は実際の値
                expect(row.valueField.stringValue) == SecureFieldRowView.maskedPlaceholder
                expect(CPYSecureInfoDetailViewController.openableURL(from: row.field.value)?.host) == "example.com"
            }
        }
    }

    // MARK: - URL opening

    /// ボタン 1 つで外部アプリが起動するため、開いてよいスキームを厳密に絞る
    private static func openableURLSpecs() {
        describe("URL を開く判定") {
            typealias Detail = CPYSecureInfoDetailViewController

            it("http と https を許可する") {
                expect(Detail.openableURL(from: "https://example.com")?.absoluteString) == "https://example.com"
                expect(Detail.openableURL(from: "http://example.com/login")?.absoluteString) == "http://example.com/login"
            }

            it("大文字のスキームも許可する") {
                expect(Detail.openableURL(from: "HTTPS://example.com")?.scheme?.lowercased()) == "https"
            }

            it("前後の空白を無視する") {
                expect(Detail.openableURL(from: "  https://example.com \n")?.host) == "example.com"
            }

            // 特殊値: インポートしたデータや打ち間違いで危険なスキームが入りうる
            it("file:// や独自スキームは拒否する") {
                expect(Detail.openableURL(from: "file:///etc/passwd")) == nil
                expect(Detail.openableURL(from: "ftp://example.com")) == nil
                expect(Detail.openableURL(from: "javascript:alert(1)")) == nil
                expect(Detail.openableURL(from: "mailto:someone@example.com")) == nil
                expect(Detail.openableURL(from: "x-apple-script://run")) == nil
            }

            it("ホスト名の無い URL は拒否する") {
                expect(Detail.openableURL(from: "https://")) == nil
                expect(Detail.openableURL(from: "http://")) == nil
            }

            it("スキームの無い文字列や空文字は拒否する") {
                expect(Detail.openableURL(from: "example.com")) == nil
                expect(Detail.openableURL(from: "")) == nil
                expect(Detail.openableURL(from: "   ")) == nil
                expect(Detail.openableURL(from: "not a url at all")) == nil
            }

            it("クエリやポートを含む URL は許可する") {
                expect(Detail.openableURL(from: "https://example.com:8443/path?a=1&b=2")?.port) == 8443
            }
        }
    }

    // MARK: - Detail pane rows

    private static func detailRowBuildingSpecs() {
        describe("詳細ペインの行構築") {

            func makeDetail() -> CPYSecureInfoDetailViewController {
                let detailViewController = CPYSecureInfoDetailViewController()
                _ = detailViewController.view
                return detailViewController
            }

            it("フィールドの数だけ行を並べる（メモも含む）") {
                let detail = makeDetail()
                detail.show(item: sampleItems()[2])
                expect(detail.fieldRows.count) == 2
                expect(detail.fieldRows.map { $0.field.label }) == ["ID", "メモ"]
            }

            it("選択なしでは行を出さない") {
                let detail = makeDetail()
                detail.show(item: nil)
                expect(detail.fieldRows.isEmpty) == true
                expect(detail.displayedItem?.itemID) == nil
            }

            // 操作シーケンス: アイテムを切り替えても前のアイテムの行が残らない
            it("アイテムを切り替えると行が作り直される") {
                let detail = makeDetail()
                detail.show(item: sampleItems()[0])
                expect(detail.fieldRows.count) == 2
                detail.show(item: sampleItems()[1])
                expect(detail.fieldRows.map { $0.field.label }) == ["Login ID", "TOTP"]
            }

            // 行ビューを使い捨てにしている理由そのもの。
            // 再利用があると「表示中のパスワードが別アイテムの行に残る」事故になる
            it("アイテムを切り替えると表示中の平文が残らない") {
                let detail = makeDetail()
                detail.show(item: sampleItems()[0])
                detail.fieldRows[1].toggleReveal()
                expect(detail.fieldRows[1].isRevealed) == true

                detail.show(item: sampleItems()[0])
                expect(detail.fieldRows[1].isRevealed) == false
                expect(detail.fieldRows[1].valueField.stringValue) == SecureFieldRowView.maskedPlaceholder
            }

            it("表示中の平文をまとめて伏せ字に戻せる") {
                let detail = makeDetail()
                detail.show(item: sampleItems()[0])
                detail.fieldRows[1].toggleReveal()
                detail.hideAllRevealedValues()
                expect(detail.fieldRows.allSatisfy { !$0.isRevealed }) == true
            }

            // コピー対象: TOTP は secret ではなくその時点のコード
            it("TOTP のコピー対象は 6 桁のコードで secret ではない") {
                let detail = makeDetail()
                let secret = "otpauth://totp/AWS?secret=JBSWY3DPEHPK3PXP"
                let field = SecureMenuItem.Field(label: "TOTP", value: secret, kind: .totp)
                let copied = detail.copyableValue(of: field)
                expect(copied?.count) == 6
                expect(copied) != secret
            }

            it("通常フィールドのコピー対象は値そのもの") {
                let detail = makeDetail()
                let field = SecureMenuItem.Field(label: "PW", value: "s3cr3t", isPassword: true)
                expect(detail.copyableValue(of: field)) == "s3cr3t"
            }

            it("解釈できない TOTP はコピー対象を返さない") {
                let detail = makeDetail()
                let field = SecureMenuItem.Field(label: "TOTP", value: "not-a-secret!!!", kind: .totp)
                expect(detail.copyableValue(of: field)) == nil
            }

            it("TOTP 行は現在のコードと残り秒数を表示する") {
                let detail = makeDetail()
                detail.show(item: sampleItems()[1])
                detail.refreshTOTPRows()
                let totpRow = detail.fieldRows.first { $0.field.isTOTP }
                expect(totpRow?.valueField.stringValue).to(match(#"^\d{3} \d{3} · \d{1,2}s$"#))
                // secret は画面に出ない
                expect(totpRow?.valueField.stringValue).toNot(contain("JBSWY3DPEHPK3PXP"))
            }

            it("フィールドを持たないアイテムでも破綻しない") {
                let detail = makeDetail()
                detail.show(item: SecureMenuItem(title: "Empty"))
                expect(detail.fieldRows.isEmpty) == true
                expect(detail.titleLabel.stringValue) == "Empty"
                expect(detail.placeholderLabel.isHidden) == true
            }
        }
    }

    // MARK: - View integration
    //
    // ウィンドウを実際に表示せず、ビューの組み立てとエディタとの連携だけを検証する。
    // Keychain には触れず、エディタへ直接アイテムを流し込む
    private static func viewIntegrationSpecs() {
        describe("ビューの組み立て") {

            it("2 ペイン構成でサイドバーは折りたためない") {
                let splitViewController = CPYSecureInfoSplitViewController()
                _ = splitViewController.view
                expect(splitViewController.splitViewItems.count) == 2
                // 折りたためると右ペインだけになり、アイテムを選び直せなくなる
                expect(splitViewController.splitViewItems[0].canCollapse) == false
                expect(splitViewController.splitViewItems[0].minimumThickness) == 180
            }

            it("一覧に表示対象の件数が並び、絞り込みに追従する") {
                let editor = makeEditor()
                let listViewController = CPYSecureInfoListViewController(editor: editor)
                _ = listViewController.view
                listViewController.reload()
                expect(listViewController.tableView.numberOfRows) == 3

                editor.setQuery("github")
                listViewController.reload()
                expect(listViewController.tableView.numberOfRows) == 1
            }

            it("再読み込みで先頭が選択され、詳細へ通知される") {
                let editor = makeEditor()
                let listViewController = CPYSecureInfoListViewController(editor: editor)
                _ = listViewController.view
                var notified: [String?] = []
                listViewController.onSelectionChange = { notified.append($0?.itemID) }

                listViewController.reload()
                expect(notified.last.flatMap { $0 }) == "github"
                expect(listViewController.tableView.selectedRow) == 0
            }

            // 操作シーケンス: j / k 相当の移動。端では動かない
            it("選択を上下に動かせて端では止まる") {
                let editor = makeEditor()
                let listViewController = CPYSecureInfoListViewController(editor: editor)
                _ = listViewController.view
                listViewController.reload()

                listViewController.moveSelection(by: 1)
                expect(editor.selectedItem?.itemID) == "aws"
                listViewController.moveSelection(by: -1)
                expect(editor.selectedItem?.itemID) == "github"
                listViewController.moveSelection(by: -1)
                expect(editor.selectedItem?.itemID) == "github"

                listViewController.moveSelection(by: 2)
                expect(editor.selectedItem?.itemID) == "accounting"
                listViewController.moveSelection(by: 1)
                expect(editor.selectedItem?.itemID) == "accounting"
            }

            it("アイテムが 0 件でも移動操作で破綻しない") {
                let editor = SecureInfoEditor()
                let listViewController = CPYSecureInfoListViewController(editor: editor)
                _ = listViewController.view
                listViewController.reload()
                listViewController.moveSelection(by: 1)
                expect(listViewController.tableView.numberOfRows) == 0
                expect(editor.selectedItem?.itemID) == nil
            }

            it("詳細ペインは選択なしでプレースホルダー、選択ありでタイトルを表示する") {
                let detailViewController = CPYSecureInfoDetailViewController()
                _ = detailViewController.view

                expect(detailViewController.titleLabel.isHidden) == true
                expect(detailViewController.placeholderLabel.isHidden) == false

                detailViewController.show(item: sampleItems()[1])
                expect(detailViewController.titleLabel.isHidden) == false
                expect(detailViewController.titleLabel.stringValue) == "AWS Console"
                expect(detailViewController.placeholderLabel.isHidden) == true

                // 絞り込みで選択が隠れた場合は再びプレースホルダーへ戻る
                detailViewController.show(item: nil)
                expect(detailViewController.titleLabel.isHidden) == true
                expect(detailViewController.placeholderLabel.isHidden) == false
            }
        }
    }

    // MARK: - Fixtures

    private static func sampleItems() -> [SecureMenuItem] {
        return [
            SecureMenuItem(itemID: "github", title: "GitHub", fields: [
                SecureMenuItem.Field(label: "ID", value: "alice"),
                SecureMenuItem.Field(label: "Password", value: "s3cr3t", isPassword: true)
            ]),
            SecureMenuItem(itemID: "aws", title: "AWS Console", fields: [
                SecureMenuItem.Field(label: "Login ID", value: "bob"),
                SecureMenuItem.Field(label: "TOTP", value: "otpauth://totp/AWS?secret=JBSWY3DPEHPK3PXP", kind: .totp)
            ]),
            SecureMenuItem(itemID: "accounting", title: "経理システム", fields: [
                SecureMenuItem.Field(label: "ID", value: "carol"),
                SecureMenuItem.Field(label: "メモ", value: "契約番号: 12345-678\nサポート: 03-0000-0000", kind: .note)
            ])
        ]
    }

    private static func makeEditor() -> SecureInfoEditor {
        let editor = SecureInfoEditor()
        editor.setItems(sampleItems())
        return editor
    }

    private static func titles(_ items: [SecureMenuItem]) -> [String] {
        return items.map { $0.title }
    }

    // MARK: - Filtering

    private static func filterSpecs() {
        describe("一覧の絞り込み") {

            it("空クエリでは全件を返す") {
                let editor = makeEditor()
                expect(titles(editor.visibleItems)) == ["GitHub", "AWS Console", "経理システム"]
            }

            // 特殊値: 空白だけのクエリは「絞り込みなし」として扱う
            it("空白だけのクエリでは全件を返す") {
                let editor = makeEditor()
                editor.setQuery("   \n ")
                expect(editor.visibleItems.count) == 3
            }

            it("タイトルの部分一致でヒットする（大文字小文字無視）") {
                let editor = makeEditor()
                editor.setQuery("github")
                expect(titles(editor.visibleItems)) == ["GitHub"]
            }

            it("フィールドのラベルでもヒットする") {
                let editor = makeEditor()
                editor.setQuery("totp")
                expect(titles(editor.visibleItems)) == ["AWS Console"]
            }

            // メモ本文で探せると「契約番号でどのアカウントか探す」使い方ができる
            it("メモ本文でもヒットする") {
                let editor = makeEditor()
                editor.setQuery("12345-678")
                expect(titles(editor.visibleItems)) == ["経理システム"]
            }

            it("メモの改行をまたいだ語でもそれぞれヒットする") {
                let editor = makeEditor()
                editor.setQuery("契約番号 サポート")
                expect(titles(editor.visibleItems)) == ["経理システム"]
            }

            // 選択パネルと違い、語がタイトルとラベルにまたがって一致してもよい
            it("複数語はタイトルとラベルをまたいで AND 一致する") {
                let editor = makeEditor()
                editor.setQuery("github password")
                expect(titles(editor.visibleItems)) == ["GitHub"]
            }

            it("一語でも外れると除外される") {
                let editor = makeEditor()
                editor.setQuery("github totp")
                expect(editor.visibleItems.isEmpty) == true
            }

            it("日本語のタイトルでもヒットする") {
                let editor = makeEditor()
                editor.setQuery("経理")
                expect(titles(editor.visibleItems)) == ["経理システム"]
            }

            it("ヒットしないクエリでは空になる") {
                let editor = makeEditor()
                editor.setQuery("no-such-item")
                expect(editor.visibleItems.isEmpty) == true
            }

            it("アイテムが 0 件でも破綻しない") {
                let editor = SecureInfoEditor()
                expect(editor.visibleItems.isEmpty) == true
                editor.setQuery("anything")
                expect(editor.visibleItems.isEmpty) == true
            }
        }
    }

    // MARK: - Searchable text

    /// 検索対象に「入れてはいけないもの」を明示的に固定する。
    /// パスワードや TOTP secret が検索対象に入ると、値の断片を検索窓へ
    /// 打たせる動機を作ってしまう
    private static func searchableTextSpecs() {
        describe("検索対象テキスト") {

            it("タイトルとラベルを含む") {
                let text = SecureInfoEditor.searchableText(of: sampleItems()[0])
                expect(text).to(contain("github"))
                expect(text).to(contain("password"))
            }

            it("パスワードの値は含まない") {
                let text = SecureInfoEditor.searchableText(of: sampleItems()[0])
                expect(text).toNot(contain("s3cr3t"))
            }

            it("通常フィールドの値も含まない") {
                let text = SecureInfoEditor.searchableText(of: sampleItems()[0])
                expect(text).toNot(contain("alice"))
            }

            it("TOTP secret は含まない") {
                let text = SecureInfoEditor.searchableText(of: sampleItems()[1])
                expect(text).toNot(contain("jbswy3dpehpk3pxp"))
            }

            it("メモ本文は含む") {
                let text = SecureInfoEditor.searchableText(of: sampleItems()[2])
                expect(text).to(contain("契約番号"))
            }

            // マスク指定のメモは秘匿したい内容なので検索対象から外す
            it("マスク指定のメモ本文は含まない") {
                let item = SecureMenuItem(title: "T", fields: [
                    SecureMenuItem.Field(label: "Memo", value: "hidden-content", isPassword: true, kind: .note)
                ])
                let text = SecureInfoEditor.searchableText(of: item)
                expect(text).to(contain("memo"))
                expect(text).toNot(contain("hidden-content"))
            }
        }
    }

    // MARK: - Selection

    private static func selectionSpecs() {
        describe("選択の追従") {

            it("初期状態では何も選択されていない") {
                let editor = makeEditor()
                expect(editor.selectedItemID) == nil
                expect(editor.selectedItem?.itemID) == nil
                expect(editor.selectedRow) == nil
            }

            it("行番号で選択できる") {
                let editor = makeEditor()
                editor.selectRow(1)
                expect(editor.selectedItem?.itemID) == "aws"
                expect(editor.selectedRow) == 1
            }

            // 境界値: 範囲外の行を指定しても選択は変わらない
            it("範囲外の行番号は無視される") {
                let editor = makeEditor()
                editor.selectRow(0)
                editor.selectRow(99)
                expect(editor.selectedItem?.itemID) == "github"
                editor.selectRow(-1)
                expect(editor.selectedItem?.itemID) == "github"
            }

            it("選択が無いときは先頭を選び直す") {
                let editor = makeEditor()
                expect(editor.selectFirstVisibleIfNeeded()) == true
                expect(editor.selectedItem?.itemID) == "github"
                // すでに選択済みなら変更しない
                expect(editor.selectFirstVisibleIfNeeded()) == false
            }

            it("アイテムが無ければ先頭選択も起きない") {
                let editor = SecureInfoEditor()
                expect(editor.selectFirstVisibleIfNeeded()) == false
                expect(editor.selectedItem?.itemID) == nil
            }

            // 操作シーケンス: 選択したまま絞り込むと選択が隠れる。
            // ID は保持したままなので、クエリを消すと選択が戻る
            it("絞り込みで隠れた選択は詳細に出さないが ID は保持する") {
                let editor = makeEditor()
                editor.selectRow(0)
                expect(editor.selectedItem?.itemID) == "github"

                editor.setQuery("aws")
                expect(editor.selectedItem?.itemID) == nil
                expect(editor.selectedRow) == nil
                expect(editor.selectedItemID) == "github"

                editor.setQuery("")
                expect(editor.selectedItem?.itemID) == "github"
                expect(editor.selectedRow) == 0
            }

            it("絞り込み後は表示対象での行番号になる") {
                let editor = makeEditor()
                editor.setQuery("id")
                // "ID" ラベルを持つ GitHub と経理システム、"Login ID" を持つ AWS が残る
                expect(editor.visibleItems.count) == 3
                editor.selectRow(2)
                expect(editor.selectedItem?.itemID) == "accounting"

                editor.setQuery("経理")
                expect(editor.selectedRow) == 0
            }

            // 操作シーケンス: 別画面で削除された結果、選択中のアイテムが消える
            it("再読み込みで選択中アイテムが消えたら選択は外れる") {
                let editor = makeEditor()
                editor.selectRow(1)
                expect(editor.selectedItem?.itemID) == "aws"

                editor.setItems(sampleItems().filter { $0.itemID != "aws" })
                expect(editor.selectedItem?.itemID) == nil
                // 先頭を選び直せる
                expect(editor.selectFirstVisibleIfNeeded()) == true
                expect(editor.selectedItem?.itemID) == "github"
            }

            it("再読み込みしても同じ ID なら選択は保たれる") {
                let editor = makeEditor()
                editor.selectRow(2)
                expect(editor.selectedItem?.itemID) == "accounting"

                // 並び順が変わっても ID で追従する
                editor.setItems(sampleItems().reversed())
                expect(editor.selectedItem?.itemID) == "accounting"
                expect(editor.selectedRow) == 0
            }

            it("選択を明示的に外せる") {
                let editor = makeEditor()
                editor.selectRow(0)
                editor.selectItem(itemID: nil)
                expect(editor.selectedItem?.itemID) == nil
                expect(editor.selectedRow) == nil
            }
        }
    }
}
