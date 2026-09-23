import Foundation
import Quick
import Nimble
@testable import Thoth

/// 編集の確定・絞り込み・選択
extension SecureInfoEditorSpec {

    // MARK: - Commit

    static func commitOutcomeSpecs() {
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

    static func filterSpecs() {
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

    static func selectionSpecs() {
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
