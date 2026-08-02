import Quick
import Nimble
@testable import Thoth

// MARK: - SecureInfoEditor Tests
//
// セキュア情報確認ウィンドウの一覧絞り込みと選択追従。
// UI 非依存の状態オブジェクトなので、AppKit 抜きで挙動を固定できる。

class SecureInfoEditorSpec: QuickSpec {

    override class func spec() {
        filterSpecs()
        searchableTextSpecs()
        selectionSpecs()
        viewIntegrationSpecs()
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
