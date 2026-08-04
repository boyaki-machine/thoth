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
        selectionSpecs()
        draftEditingSpecs()
        commitOutcomeSpecs()
        fieldStructureSpecs()
        itemReorderSpecs()
        fieldTemplateSpecs()
    }

    // MARK: - Field structure (add / remove / move)

    private static func fieldStructureSpecs() {
        describe("フィールドの追加・削除・並べ替え") {

            func editorEditingFirstItem() -> SecureInfoEditor {
                let editor = makeEditor()
                editor.beginEditing(itemID: "github")
                return editor
            }

            it("末尾にフィールドを追加できる") {
                let editor = editorEditingFirstItem()
                let added = editor.addField(kind: .url, label: "URL")
                expect(added?.kind) == SecureMenuItem.Field.Kind.url
                expect(editor.draft?.fields.map { $0.label }) == ["ID", "Password", "URL"]
                expect(editor.isDirty) == true
            }

            it("追加したフィールドには新しい fieldID が振られる") {
                let editor = editorEditingFirstItem()
                let first = editor.addField(kind: .note, label: "Memo")
                let second = editor.addField(kind: .note, label: "Memo")
                expect(first?.fieldID) != second?.fieldID
                expect(UUID(uuidString: first?.fieldID ?? "")) != nil
            }

            it("マスク指定つきで追加できる") {
                let editor = editorEditingFirstItem()
                let added = editor.addField(kind: .plain, label: "PW", isPassword: true)
                expect(added?.isPassword) == true
            }

            it("フィールドを削除できる") {
                let editor = editorEditingFirstItem()
                guard let fieldID = editor.draft?.fields.first?.fieldID else {
                    fail("作業コピーにフィールドが無い（beginEditing が効いていない）")
                    return
                }
                expect(editor.removeField(fieldID: fieldID)) == true
                expect(editor.draft?.fields.map { $0.label }) == ["Password"]
                expect(editor.isDirty) == true
            }

            it("存在しないフィールドの削除は無視される") {
                let editor = editorEditingFirstItem()
                expect(editor.removeField(fieldID: "no-such-field")) == false
                expect(editor.isDirty) == false
            }

            it("最後の 1 件まで削除できる") {
                let editor = editorEditingFirstItem()
                for field in editor.draft?.fields ?? [] {
                    expect(editor.removeField(fieldID: field.fieldID)) == true
                }
                expect(editor.draft?.fields.isEmpty) == true
            }

            it("フィールドを上下に動かせる") {
                let editor = editorEditingFirstItem()
                guard let fieldID = editor.draft?.fields.first?.fieldID else {
                    fail("作業コピーにフィールドが無い（beginEditing が効いていない）")
                    return
                }
                expect(editor.moveField(fieldID: fieldID, by: 1)) == true
                expect(editor.draft?.fields.map { $0.label }) == ["Password", "ID"]
                expect(editor.moveField(fieldID: fieldID, by: -1)) == true
                expect(editor.draft?.fields.map { $0.label }) == ["ID", "Password"]
            }

            // 境界値: 端を越える移動は行わず、変更扱いにもしない
            it("端を越える移動は無視される") {
                let editor = editorEditingFirstItem()
                guard let firstID = editor.draft?.fields.first?.fieldID,
                      let lastID = editor.draft?.fields.last?.fieldID else {
                    fail("作業コピーにフィールドが無い（beginEditing が効いていない）")
                    return
                }
                expect(editor.moveField(fieldID: firstID, by: -1)) == false
                expect(editor.moveField(fieldID: lastID, by: 1)) == false
                expect(editor.isDirty) == false
                expect(editor.draft?.fields.map { $0.label }) == ["ID", "Password"]
            }

            it("移動量 0 は無視される") {
                let editor = editorEditingFirstItem()
                guard let fieldID = editor.draft?.fields.first?.fieldID else {
                    fail("作業コピーにフィールドが無い（beginEditing が効いていない）")
                    return
                }
                expect(editor.moveField(fieldID: fieldID, by: 0)) == false
                expect(editor.isDirty) == false
            }

            // 並べ替えで値や種別が入れ替わると、TOTP secret が別ラベルに付いてしまう
            it("並べ替えてもフィールドの中身は保たれる") {
                let editor = makeEditor()
                editor.beginEditing(itemID: "aws")
                guard let totpID = editor.draft?.fields.last?.fieldID else {
                    fail("作業コピーに TOTP フィールドが無い")
                    return
                }
                let before = editor.draft?.fields.last
                expect(editor.moveField(fieldID: totpID, by: -1)) == true
                let after = editor.draft?.fields.first
                expect(after?.fieldID) == before?.fieldID
                expect(after?.value) == before?.value
                expect(after?.kind) == SecureMenuItem.Field.Kind.totp
                expect(after?.createdAt) == before?.createdAt
            }

            it("読み取り専用モードでは追加・削除・並べ替えができない") {
                let editor = editorEditingFirstItem()
                editor.isReadOnly = true
                expect(editor.addField(kind: .url, label: "URL")?.label) == nil
                guard let fieldID = editor.draft?.fields.first?.fieldID else {
                    fail("作業コピーにフィールドが無い（beginEditing が効いていない）")
                    return
                }
                expect(editor.removeField(fieldID: fieldID)) == false
                expect(editor.moveField(fieldID: fieldID, by: 1)) == false
                expect(editor.isDirty) == false
            }

            it("選択が無ければ追加できない") {
                let editor = makeEditor()
                editor.beginEditing(itemID: nil)
                expect(editor.addField(kind: .plain, label: "X")?.label) == nil
                expect(editor.isDirty) == false
            }
        }
    }

    // MARK: - Item reordering

    private static func itemReorderSpecs() {
        describe("アイテムの並べ替え") {

            func ids(_ items: [SecureMenuItem]?) -> [String]? {
                return items?.map { $0.itemID }
            }

            it("下へ動かせる") {
                let moved = SecureInfoEditor.reordered(sampleItems(), movingItemID: "github", by: 1)
                expect(ids(moved)) == ["aws", "github", "accounting"]
            }

            it("上へ動かせる") {
                let moved = SecureInfoEditor.reordered(sampleItems(), movingItemID: "accounting", by: -1)
                expect(ids(moved)) == ["github", "accounting", "aws"]
            }

            // 境界値: 端を越える移動と移動量 0 は nil
            it("端を越える移動と移動量 0 は nil を返す") {
                expect(SecureInfoEditor.reordered(sampleItems(), movingItemID: "github", by: -1)) == nil
                expect(SecureInfoEditor.reordered(sampleItems(), movingItemID: "accounting", by: 1)) == nil
                expect(SecureInfoEditor.reordered(sampleItems(), movingItemID: "github", by: 0)) == nil
            }

            it("存在しない ID は nil を返す") {
                expect(SecureInfoEditor.reordered(sampleItems(), movingItemID: "missing", by: 1)) == nil
            }

            it("1 件だけ・0 件では動かせない") {
                let single = [SecureMenuItem(itemID: "only", title: "Only")]
                expect(SecureInfoEditor.reordered(single, movingItemID: "only", by: 1)) == nil
                expect(SecureInfoEditor.reordered([], movingItemID: "only", by: 1)) == nil
            }

            it("並べ替えで件数と中身は変わらない") {
                guard let moved = SecureInfoEditor.reordered(sampleItems(), movingItemID: "github", by: 2) else {
                    fail("expected reorder")
                    return
                }
                expect(moved.count) == 3
                expect(Set(moved.map { $0.itemID })) == Set(["github", "aws", "accounting"])
                expect(ids([moved.last!])) == ["github"]
            }
        }
    }

    // MARK: - Field templates

    /// 追加メニューの雛形。初期ラベルが空だと「ラベルも値も空のフィールドは
    /// 保存しない」規則で保存時に消えてしまうため、空でないことを担保する
    private static func fieldTemplateSpecs() {
        describe("フィールド追加の雛形") {

            it("種別とマスク指定が対応する") {
                expect(SecureInfoFieldTemplate.text.kind) == SecureMenuItem.Field.Kind.plain
                expect(SecureInfoFieldTemplate.text.isPassword) == false
                expect(SecureInfoFieldTemplate.password.kind) == SecureMenuItem.Field.Kind.plain
                expect(SecureInfoFieldTemplate.password.isPassword) == true
                expect(SecureInfoFieldTemplate.url.kind) == SecureMenuItem.Field.Kind.url
                expect(SecureInfoFieldTemplate.note.kind) == SecureMenuItem.Field.Kind.note
                expect(SecureInfoFieldTemplate.note.isPassword) == false
            }

            it("初期ラベルが空でない") {
                for template in SecureInfoFieldTemplate.allCases {
                    expect(template.defaultLabel).toNot(beEmpty())
                    expect(template.menuTitle).toNot(beEmpty())
                }
            }

            // TOTP は取り込みが必要なので雛形には含めない
            it("雛形に TOTP は含まれない") {
                expect(SecureInfoFieldTemplate.allCases.contains { $0.kind == .totp }) == false
                expect(SecureInfoFieldTemplate.allCases.count) == 4
            }

            it("雛形から追加したフィールドは保存対象になる") {
                let editor = makeEditor()
                editor.beginEditing(itemID: "github")
                for template in SecureInfoFieldTemplate.allCases {
                    editor.addField(kind: template.kind, label: template.defaultLabel,
                                    isPassword: template.isPassword)
                }
                guard case .ready(let payload) = editor.commitOutcome() else {
                    fail("expected ready")
                    return
                }
                // 値が空でもラベルがあるので落とされない
                expect(payload.fields.count) == 6
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
                guard let fieldID = editor.draft?.fields.first?.fieldID else {
                    fail("作業コピーにフィールドが無い（beginEditing が効いていない）")
                    return
                }
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

            // v1.2 以前の編集シートから引き継いだ規則
            it("ラベルも値も空のフィールドは保存対象から外す") {
                let editor = editorEditingFirstItem()
                guard let fieldID = editor.draft?.fields.first?.fieldID else {
                    fail("作業コピーにフィールドが無い（beginEditing が効いていない）")
                    return
                }
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
                guard let fieldID = editor.draft?.fields.first?.fieldID else {
                    fail("作業コピーにフィールドが無い（beginEditing が効いていない）")
                    return
                }
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
                guard case .ready(let payload) = editor.commitOutcome() else {
                    fail("タイトルを変えたので .ready を期待したが違った: \(editor.commitOutcome())")
                    return
                }
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

            // v1.3.0 まではラベルとメモ本文しか見ておらず、テキスト・URL の
            // 内容で検索してもヒットしなかった。
            // 検索条件そのものは `SecureItemSearchSpec` が固定している。
            // ここで見るのは「エディタが共通ロジックに繋がっていること」
            it("テキストフィールドの値でもヒットする") {
                let editor = makeEditor()
                editor.setQuery("carol")
                expect(titles(editor.visibleItems)) == ["経理システム"]
            }

            it("マスクを掛けた値では検索できない") {
                let editor = makeEditor()
                editor.setQuery("s3cr3t")
                expect(editor.visibleItems).to(beEmpty())
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
                expect(editor.visibleItems).to(beEmpty())
            }

            it("日本語のタイトルでもヒットする") {
                let editor = makeEditor()
                editor.setQuery("経理")
                expect(titles(editor.visibleItems)) == ["経理システム"]
            }

            it("ヒットしないクエリでは空になる") {
                let editor = makeEditor()
                editor.setQuery("no-such-item")
                expect(editor.visibleItems).to(beEmpty())
            }

            it("アイテムが 0 件でも破綻しない") {
                let editor = SecureInfoEditor()
                expect(editor.visibleItems).to(beEmpty())
                editor.setQuery("anything")
                expect(editor.visibleItems).to(beEmpty())
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
