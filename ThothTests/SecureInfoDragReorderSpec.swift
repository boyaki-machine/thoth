import Quick
import Nimble
import AppKit
@testable import Thoth

// MARK: - Drag & Drop Reordering Tests
//
// マウスでの並べ替え。左ペイン（アイテム）は NSTableView 標準の仕組み、
// 右ペイン（フィールド）は NSStackView なので挿入位置の判定を自前で持つ。
// どちらも「ドロップ位置 → 移動後の添字」の変換を純粋関数に切り出してある。

class SecureInfoDragReorderSpec: QuickSpec {

    override class func spec() {
        dropDestinationSpecs()
        reorderGuardSpecs()
        itemReorderSpecs()
        fieldReorderSpecs()
        insertionGapSpecs()
        rowDragSourceSpecs()
    }

    // MARK: - Drop index conversion

    /// NSTableView の `proposedRow` は**取り除く前の配列**に対する挿入位置。
    /// 下へ動かすときは自分が抜けたぶんずれる。ここを間違えると 1 行ずつ狂う
    private static func dropDestinationSpecs() {
        describe("ドロップ位置の変換") {

            it("下へ動かすときは 1 つ手前になる") {
                // [A B C] の A を C の下（proposedRow 3）へ → 移動後は添字 2
                expect(SecureInfoEditor.dropDestinationIndex(fromRow: 0, proposedRow: 3)) == 2
                expect(SecureInfoEditor.dropDestinationIndex(fromRow: 0, proposedRow: 1)) == 0
            }

            it("上へ動かすときはそのまま") {
                expect(SecureInfoEditor.dropDestinationIndex(fromRow: 2, proposedRow: 0)) == 0
                expect(SecureInfoEditor.dropDestinationIndex(fromRow: 2, proposedRow: 1)) == 1
            }

            // 自分のすぐ上／すぐ下へのドロップは動かないのと同じ
            it("その場に落とすと元の位置になる") {
                expect(SecureInfoEditor.dropDestinationIndex(fromRow: 1, proposedRow: 1)) == 1
                expect(SecureInfoEditor.dropDestinationIndex(fromRow: 1, proposedRow: 2)) == 1
            }
        }
    }

    // MARK: - Reorder guard

    private static func reorderGuardSpecs() {
        describe("並べ替えを許す条件") {

            // 絞り込み中は見えている順と保存順が食い違い、行番号から移動先を決められない
            it("絞り込み中は並べ替えられない") {
                expect(SecureInfoEditor.canReorderItems(query: "", isReadOnly: false)) == true
                expect(SecureInfoEditor.canReorderItems(query: "git", isReadOnly: false)) == false
            }

            // 空白だけの検索文字列は絞り込みとして働かない（filter も同じ扱い）
            it("空白だけの検索は絞り込みとみなさない") {
                expect(SecureInfoEditor.canReorderItems(query: "   ", isReadOnly: false)) == true
                expect(SecureInfoEditor.canReorderItems(query: "\n", isReadOnly: false)) == true
            }

            it("読み取り専用では並べ替えられない") {
                expect(SecureInfoEditor.canReorderItems(query: "", isReadOnly: true)) == false
            }
        }
    }

    // MARK: - Item reorder

    private static func itemReorderSpecs() {
        describe("アイテムを添字で動かす") {

            func ids(_ items: [SecureMenuItem]?) -> [String]? {
                return items?.map { $0.itemID }
            }

            it("末尾へ動かせる") {
                let moved = SecureInfoEditor.reordered(sampleItems(), movingItemID: "github", toIndex: 2)
                expect(ids(moved)) == ["aws", "accounting", "github"]
            }

            it("先頭へ動かせる") {
                let moved = SecureInfoEditor.reordered(sampleItems(), movingItemID: "accounting", toIndex: 0)
                expect(ids(moved)) == ["accounting", "github", "aws"]
            }

            it("範囲外・同じ位置・未知の ID は nil を返す") {
                expect(SecureInfoEditor.reordered(sampleItems(), movingItemID: "github", toIndex: -1)) == nil
                expect(SecureInfoEditor.reordered(sampleItems(), movingItemID: "github", toIndex: 3)) == nil
                expect(SecureInfoEditor.reordered(sampleItems(), movingItemID: "github", toIndex: 0)) == nil
                expect(SecureInfoEditor.reordered(sampleItems(), movingItemID: "missing", toIndex: 1)) == nil
            }

            // 移動量版は添字版に委譲している。両者の結果が食い違ってはいけない
            it("移動量で指定しても結果が一致する") {
                let byOffset = SecureInfoEditor.reordered(sampleItems(), movingItemID: "github", by: 2)
                let byIndex = SecureInfoEditor.reordered(sampleItems(), movingItemID: "github", toIndex: 2)
                expect(ids(byOffset)) == ids(byIndex)
            }
        }
    }

    // MARK: - Field reorder

    private static func fieldReorderSpecs() {
        describe("フィールドを添字で動かす") {

            func editorEditingItem() -> SecureInfoEditor {
                let editor = SecureInfoEditor()
                editor.setItems([
                    SecureMenuItem(itemID: "s1", title: "GitHub", fields: [
                        SecureMenuItem.Field(fieldID: "f1", label: "ID", value: "a"),
                        SecureMenuItem.Field(fieldID: "f2", label: "PW", value: "b"),
                        SecureMenuItem.Field(fieldID: "f3", label: "URL", value: "c", kind: .url)
                    ])
                ])
                editor.beginEditing(itemID: "s1")
                return editor
            }

            it("末尾へ動かせる") {
                let editor = editorEditingItem()
                expect(editor.moveField(fieldID: "f1", toIndex: 2)) == true
                expect(editor.draft?.fields.map { $0.fieldID }) == ["f2", "f3", "f1"]
                expect(editor.isDirty) == true
            }

            it("先頭へ動かせる") {
                let editor = editorEditingItem()
                expect(editor.moveField(fieldID: "f3", toIndex: 0)) == true
                expect(editor.draft?.fields.map { $0.fieldID }) == ["f3", "f1", "f2"]
            }

            it("範囲外・同じ位置・未知の ID では動かさない") {
                let editor = editorEditingItem()
                expect(editor.moveField(fieldID: "f1", toIndex: -1)) == false
                expect(editor.moveField(fieldID: "f1", toIndex: 3)) == false
                expect(editor.moveField(fieldID: "f1", toIndex: 0)) == false
                expect(editor.moveField(fieldID: "missing", toIndex: 1)) == false
                expect(editor.isDirty) == false
            }

            it("読み取り専用では動かさない") {
                let editor = editorEditingItem()
                editor.isReadOnly = true
                expect(editor.moveField(fieldID: "f1", toIndex: 2)) == false
            }

            it("移動量で指定しても結果が一致する") {
                let byOffset = editorEditingItem()
                let byIndex = editorEditingItem()
                expect(byOffset.moveField(fieldID: "f1", by: 2)) == true
                expect(byIndex.moveField(fieldID: "f1", toIndex: 2)) == true
                expect(byOffset.draft?.fields.map { $0.fieldID }) == byIndex.draft?.fields.map { $0.fieldID }
            }
        }
    }

    // MARK: - Insertion gap

    /// 右ペインは NSStackView なので、ドロップ位置から「どのすき間か」を自分で求める。
    /// 座標は上下反転（上端が y = 0）
    private static func insertionGapSpecs() {
        describe("挿入位置の判定") {

            /// 高さ 20・間隔 0 で 3 行並べた状態
            let frames = (0..<3).map { NSRect(x: 0, y: CGFloat($0) * 20, width: 100, height: 20) }

            it("先頭行の上半分なら 0 番目のすき間") {
                expect(SecureFieldDropView.insertionGapIndex(dropY: 0, rowFrames: frames)) == 0
                expect(SecureFieldDropView.insertionGapIndex(dropY: 9, rowFrames: frames)) == 0
            }

            it("行の中点を越えるとその行の下のすき間になる") {
                expect(SecureFieldDropView.insertionGapIndex(dropY: 11, rowFrames: frames)) == 1
                expect(SecureFieldDropView.insertionGapIndex(dropY: 29, rowFrames: frames)) == 1
                expect(SecureFieldDropView.insertionGapIndex(dropY: 31, rowFrames: frames)) == 2
            }

            // 境界値: 中点ちょうどは「下側」に倒す（< 判定なので index は進む）
            it("中点ちょうどは下側のすき間になる") {
                expect(SecureFieldDropView.insertionGapIndex(dropY: 10, rowFrames: frames)) == 1
                expect(SecureFieldDropView.insertionGapIndex(dropY: 30, rowFrames: frames)) == 2
            }

            it("最下行より下なら末尾のすき間") {
                expect(SecureFieldDropView.insertionGapIndex(dropY: 60, rowFrames: frames)) == 3
                expect(SecureFieldDropView.insertionGapIndex(dropY: 999, rowFrames: frames)) == 3
            }

            it("行が無ければ常に 0") {
                expect(SecureFieldDropView.insertionGapIndex(dropY: 0, rowFrames: [])) == 0
                expect(SecureFieldDropView.insertionGapIndex(dropY: 500, rowFrames: [])) == 0
            }

            // 行の高さが揃わない（メモは 84pt）状態でも中点で判定できる
            it("高さがまちまちでも中点で判定する") {
                let mixed = [NSRect(x: 0, y: 0, width: 100, height: 20),
                             NSRect(x: 0, y: 20, width: 100, height: 84)]
                expect(SecureFieldDropView.insertionGapIndex(dropY: 9, rowFrames: mixed)) == 0
                expect(SecureFieldDropView.insertionGapIndex(dropY: 40, rowFrames: mixed)) == 1
                expect(SecureFieldDropView.insertionGapIndex(dropY: 70, rowFrames: mixed)) == 2
            }
        }
    }

    // MARK: - Row as drag source

    private static func rowDragSourceSpecs() {
        describe("行のドラッグ元としての振る舞い") {

            it("並べ替えできる行には掴み手が付く") {
                let row = SecureFieldRowView(field: SecureMenuItem.Field(label: "ID", value: "a"))
                expect(row.dragHandle.superview) === row
            }

            it("読み取り専用では掴み手を出さない") {
                let row = SecureFieldRowView(field: SecureMenuItem.Field(label: "ID", value: "a"), isReadOnly: true)
                expect(row.dragHandle.superview) == nil
            }

            // NSImageView は NSControl の一員なので、素のままだと掴み手が
            // mouseDown を自分で握ってしまいドラッグが始まらない
            it("掴み手の上のクリックは行が受け取る") {
                let row = SecureFieldRowView(field: SecureMenuItem.Field(label: "ID", value: "a"))
                let container = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 24))
                container.addSubview(row)
                row.frame = container.bounds
                row.layoutSubtreeIfNeeded()

                let onHandle = NSPoint(x: row.dragHandle.frame.midX, y: row.dragHandle.frame.midY)
                expect(row.hitTest(onHandle)) === row
                // 値欄の上は従来どおり（テキスト選択のためフィールド側へ渡す）
                // 掴み手の外は従来どおり中のビューへ渡す（ボタンやテキスト選択を邪魔しない）。
                // ボタンはスタックの中にいるので、行の座標系へ直してから指す
                let copyRect = row.copyButton.convert(row.copyButton.bounds, to: row)
                expect(row.hitTest(NSPoint(x: copyRect.midX, y: copyRect.midY))) === row.copyButton
            }

            // 行を他のアプリへ引き出せると、ペイストボード経由で機微情報が渡る
            it("アプリの外へは引き出せない") {
                let row = SecureFieldRowView(field: SecureMenuItem.Field(label: "ID", value: "a"))
                let session = NSDraggingSession()
                expect(row.draggingSession(session, sourceOperationMaskFor: .withinApplication)) == NSDragOperation.move
                expect(row.draggingSession(session, sourceOperationMaskFor: .outsideApplication)) == NSDragOperation()
            }
        }
    }

    // MARK: - Fixtures

    private static func sampleItems() -> [SecureMenuItem] {
        return [
            SecureMenuItem(itemID: "github", title: "GitHub", displayOrder: 0),
            SecureMenuItem(itemID: "aws", title: "AWS Console", displayOrder: 1),
            SecureMenuItem(itemID: "accounting", title: "経理システム", displayOrder: 2)
        ]
    }
}
