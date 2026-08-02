import Quick
import Nimble
@testable import Thoth

// MARK: - SecureInfoEditor Tests
//
// セキュア情報確認ウィンドウの UI 非依存な状態（一覧の絞り込み・選択追従・
// 作業コピーの編集・保存判定）。AppKit 抜きで挙動を固定できる。

// BDD スペックは多数の it ブロックを含み型本体が長くなるため型長ルールを緩める
// swiftlint:disable:next type_body_length
class SecureInfoEditorSpec: QuickSpec {

    override class func spec() {
        filterSpecs()
        searchableTextSpecs()
        selectionSpecs()
        draftEditingSpecs()
        commitOutcomeSpecs()
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

    // MARK: - Draft editing

    private static func draftEditingSpecs() {
        describe("作業コピーの編集") {

            func editorEditingFirstItem() -> SecureInfoEditor {
                let editor = makeEditor()
                editor.selectRow(0)
                editor.beginEditing(itemID: "github")
                return editor
            }

            it("編集開始時は未変更で、選択アイテムの内容を持つ") {
                let editor = editorEditingFirstItem()
                expect(editor.isDirty) == false
                expect(editor.draft?.itemID) == "github"
                expect(editor.draft?.title) == "GitHub"
            }

            it("タイトルを変えると作業コピーだけが変わる") {
                let editor = editorEditingFirstItem()
                expect(editor.updateTitle("GitHub Enterprise")) == true
                expect(editor.isDirty) == true
                expect(editor.draft?.title) == "GitHub Enterprise"
                // 保存前なので一覧側は元のまま
                expect(editor.items.first?.title) == "GitHub"
            }

            it("同じ値を入れ直しても変更扱いにしない") {
                let editor = editorEditingFirstItem()
                expect(editor.updateTitle("GitHub")) == false
                expect(editor.isDirty) == false
            }

            it("フィールドの値とラベルを変えられる") {
                let editor = editorEditingFirstItem()
                guard let fieldID = editor.draft?.fields.first?.fieldID else {
                    fail("field not found")
                    return
                }
                expect(editor.updateField(fieldID: fieldID, value: "bob")) == true
                expect(editor.draft?.fields.first?.value) == "bob"
                expect(editor.updateField(fieldID: fieldID, label: "User")) == true
                expect(editor.draft?.fields.first?.label) == "User"
                // 指定しなかった項目は維持される
                expect(editor.draft?.fields.first?.value) == "bob"
            }

            // 安定 ID と作成日時が編集で失われると履歴の追従と TOTP の登録日時が壊れる
            it("編集しても fieldID と createdAt は変わらない") {
                let editor = editorEditingFirstItem()
                guard let original = editor.draft?.fields.first else {
                    fail("field not found")
                    return
                }
                _ = editor.updateField(fieldID: original.fieldID, value: "changed")
                let updated = editor.draft?.fields.first
                expect(updated?.fieldID) == original.fieldID
                expect(updated?.createdAt) == original.createdAt
                expect(updated?.kind) == original.kind
            }

            it("存在しない fieldID の更新は無視される") {
                let editor = editorEditingFirstItem()
                expect(editor.updateField(fieldID: "no-such-field", value: "x")) == false
                expect(editor.isDirty) == false
            }

            it("選択が無ければ編集できない") {
                let editor = makeEditor()
                editor.beginEditing(itemID: nil)
                expect(editor.draft?.itemID) == nil
                expect(editor.updateTitle("x")) == false
                expect(editor.isDirty) == false
            }

            it("読み取り専用モードでは編集を受け付けない") {
                let editor = editorEditingFirstItem()
                editor.isReadOnly = true
                expect(editor.updateTitle("x")) == false
                guard let fieldID = editor.draft?.fields.first?.fieldID else { return }
                expect(editor.updateField(fieldID: fieldID, value: "x")) == false
                expect(editor.isDirty) == false
            }

            // 操作シーケンス: 別アイテムへ移ると作業コピーが差し替わる
            it("編集対象を切り替えると未変更状態に戻る") {
                let editor = editorEditingFirstItem()
                _ = editor.updateTitle("changed")
                expect(editor.isDirty) == true

                editor.beginEditing(itemID: "aws")
                expect(editor.isDirty) == false
                expect(editor.draft?.itemID) == "aws"
                expect(editor.draft?.title) == "AWS Console"
            }
        }
    }

    // MARK: - Commit

    private static func commitOutcomeSpecs() {
        describe("保存の要否と可否") {

            func editorEditingFirstItem() -> SecureInfoEditor {
                let editor = makeEditor()
                editor.beginEditing(itemID: "github")
                return editor
            }

            it("変更が無ければ保存不要") {
                expect(editorEditingFirstItem().commitOutcome()) == SecureInfoEditor.CommitOutcome.notNeeded
            }

            it("選択が無ければ保存不要") {
                let editor = makeEditor()
                editor.beginEditing(itemID: nil)
                expect(editor.commitOutcome()) == SecureInfoEditor.CommitOutcome.notNeeded
            }

            it("変更があれば保存内容を返す") {
                let editor = editorEditingFirstItem()
                _ = editor.updateTitle("GitHub Enterprise")
                guard case .ready(let payload) = editor.commitOutcome() else {
                    fail("expected ready")
                    return
                }
                expect(payload.itemID) == "github"
                expect(payload.title) == "GitHub Enterprise"
            }

            // 境界値: タイトルが空・空白のみでは保存できない。編集内容は破棄しない
            it("タイトルが空なら保存できないと知らせる") {
                let editor = editorEditingFirstItem()
                _ = editor.updateTitle("")
                expect(editor.commitOutcome()) == SecureInfoEditor.CommitOutcome.titleRequired
                _ = editor.updateTitle("   ")
                expect(editor.commitOutcome()) == SecureInfoEditor.CommitOutcome.titleRequired
                // 作業コピーは失われていない
                expect(editor.draft?.fields.count) == 2
            }

            it("タイトルの前後空白は取り除いて保存する") {
                let editor = editorEditingFirstItem()
                _ = editor.updateTitle("  GitHub  ")
                guard case .ready(let payload) = editor.commitOutcome() else {
                    fail("expected ready")
                    return
                }
                expect(payload.title) == "GitHub"
            }

            // 既存の編集シートと同じ規則
            it("ラベルも値も空のフィールドは保存対象から外す") {
                let editor = editorEditingFirstItem()
                guard let fieldID = editor.draft?.fields.first?.fieldID else { return }
                _ = editor.updateField(fieldID: fieldID, label: "", value: "")
                guard case .ready(let payload) = editor.commitOutcome() else {
                    fail("expected ready")
                    return
                }
                expect(payload.fields.count) == 1
                expect(payload.fields.first?.label) == "Password"
            }

            it("ラベルだけ・値だけが残っているフィールドは保存する") {
                let editor = editorEditingFirstItem()
                guard let fieldID = editor.draft?.fields.first?.fieldID else { return }
                _ = editor.updateField(fieldID: fieldID, label: "ID", value: "")
                guard case .ready(let payload) = editor.commitOutcome() else {
                    fail("expected ready")
                    return
                }
                expect(payload.fields.count) == 2
            }

            it("保存を記録すると未変更に戻り、一覧側も更新される") {
                let editor = editorEditingFirstItem()
                _ = editor.updateTitle("Renamed")
                guard case .ready(let payload) = editor.commitOutcome() else {
                    fail("expected ready")
                    return
                }
                editor.markCommitted(payload)
                expect(editor.isDirty) == false
                expect(editor.commitOutcome()) == SecureInfoEditor.CommitOutcome.notNeeded
                expect(editor.items.first?.title) == "Renamed"
                expect(editor.draft?.title) == "Renamed"
            }

            it("保存記録後も選択と並び順は変わらない") {
                let editor = editorEditingFirstItem()
                editor.selectRow(0)
                _ = editor.updateTitle("Renamed")
                guard case .ready(let payload) = editor.commitOutcome() else { return }
                editor.markCommitted(payload)
                expect(editor.items.map { $0.itemID }) == ["github", "aws", "accounting"]
                expect(editor.selectedItem?.itemID) == "github"
            }
        }
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
