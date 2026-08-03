import Quick
import Nimble
@testable import Thoth

// MARK: - SecureInfoUndoStack / Snapshot Tests
//
// 取り消しの土台。積む単位は「Keychain へ 1 回書き込むごと」で、
// スナップショットは「書き込む直前の保存済み状態」。
// AppKit も Keychain も要らない純粋な部分なので、ここで挙動を固定する。

class SecureInfoUndoSpec: QuickSpec {

    override class func spec() {
        pushSpecs()
        undoRedoSpecs()
        actionNameSpecs()
        clearSpecs()
        committedSnapshotSpecs()
        restoreSpecs()
    }

    // MARK: - Push

    private static func pushSpecs() {
        describe("変更前の状態を積む") {

            it("積んだ分だけ取り消せる") {
                let stack = SecureInfoUndoStack()
                expect(stack.canUndo) == false
                stack.push(snapshot(titles: ["A"]))
                expect(stack.canUndo) == true
                expect(stack.undoSnapshots.count) == 1
            }

            // 20 秒のフォールバック保存などで中身の変わらない保存が走ったとき、
            // 押しても何も起きない取り消し世代を作らないための抑止
            it("直前と内容が同じなら積まない") {
                let stack = SecureInfoUndoStack()
                expect(stack.push(snapshot(titles: ["A", "B"]))) == true
                expect(stack.push(snapshot(titles: ["A", "B"]))) == false
                expect(stack.undoSnapshots.count) == 1
            }

            // 内容が同じかどうかだけを見る。操作名の違いで世代が増えてはいけない
            it("操作名が違っても内容が同じなら積まない") {
                let stack = SecureInfoUndoStack()
                stack.push(snapshot(titles: ["A"], action: .edit))
                expect(stack.push(snapshot(titles: ["A"], action: .deleteItem))) == false
            }

            it("内容が変われば積む") {
                let stack = SecureInfoUndoStack()
                stack.push(snapshot(titles: ["A"]))
                stack.push(snapshot(titles: ["A", "B"]))
                expect(stack.undoSnapshots.count) == 2
            }

            it("選択が変わっただけでも別の状態として積む") {
                let stack = SecureInfoUndoStack()
                stack.push(snapshot(titles: ["A", "B"], selectedItemID: "item-0"))
                expect(stack.push(snapshot(titles: ["A", "B"], selectedItemID: "item-1"))) == true
            }

            // 平文を保持するので世代数は頭打ちにする
            it("上限を超えると古いものから捨てる") {
                let stack = SecureInfoUndoStack()
                for index in 0..<(SecureInfoUndoStack.maxDepth + 5) {
                    stack.push(snapshot(titles: ["item\(index)"]))
                }
                expect(stack.undoSnapshots.count) == SecureInfoUndoStack.maxDepth
                // 最古の 5 件が押し出され、先頭が item5 になっている
                expect(stack.undoSnapshots.first?.items.first?.title) == "item5"
                expect(stack.undoSnapshots.last?.items.first?.title) == "item\(SecureInfoUndoStack.maxDepth + 4)"
            }
        }
    }

    // MARK: - Undo / Redo

    private static func undoRedoSpecs() {
        describe("取り消しとやり直し") {

            it("取り消すと積んだ状態が返り、現在の状態がやり直しへ移る") {
                let stack = SecureInfoUndoStack()
                let before = snapshot(titles: ["A"])
                let after = snapshot(titles: ["A", "B"])
                stack.push(before)

                let restored = stack.undo(current: after)
                expect(restored?.items.map { $0.title }) == ["A"]
                expect(stack.canUndo) == false
                expect(stack.canRedo) == true

                let redone = stack.redo(current: before)
                expect(redone?.items.map { $0.title }) == ["A", "B"]
                expect(stack.canUndo) == true
                expect(stack.canRedo) == false
            }

            it("戻せるものが無ければ nil を返す") {
                let stack = SecureInfoUndoStack()
                expect(stack.undo(current: snapshot(titles: ["A"]))) == nil
                expect(stack.redo(current: snapshot(titles: ["A"]))) == nil
            }

            it("連続して取り消すと 1 回につき 1 世代ずつ戻る") {
                let stack = SecureInfoUndoStack()
                stack.push(snapshot(titles: ["A"]))
                stack.push(snapshot(titles: ["A", "B"]))
                let current = snapshot(titles: ["A", "B", "C"])

                let first = stack.undo(current: current)
                expect(first?.items.map { $0.title }) == ["A", "B"]
                guard let first = first else { return }
                let second = stack.undo(current: first)
                expect(second?.items.map { $0.title }) == ["A"]
                expect(stack.canUndo) == false
            }

            // 取り消したあとに別の変更をしたら、やり直しの枝は消える（一般的な Undo の作法）
            it("新しい変更を積むとやり直しは消える") {
                let stack = SecureInfoUndoStack()
                stack.push(snapshot(titles: ["A"]))
                _ = stack.undo(current: snapshot(titles: ["A", "B"]))
                expect(stack.canRedo) == true

                stack.push(snapshot(titles: ["A", "Z"]))
                expect(stack.canRedo) == false
            }

            it("やり直しの世代も上限で頭打ちになる") {
                let stack = SecureInfoUndoStack()
                for index in 0..<(SecureInfoUndoStack.maxDepth + 5) {
                    stack.push(snapshot(titles: ["item\(index)"]))
                }
                var current = snapshot(titles: ["current"])
                while let restored = stack.undo(current: current) { current = restored }
                expect(stack.redoSnapshots.count) == SecureInfoUndoStack.maxDepth
            }
        }
    }

    // MARK: - Action names

    private static func actionNameSpecs() {
        describe("メニューに出す操作名") {

            it("次に取り消される操作の名前を返す") {
                let stack = SecureInfoUndoStack()
                expect(stack.undoAction) == nil
                stack.push(snapshot(titles: ["A"], action: .deleteItem))
                expect(stack.undoAction) == SecureInfoUndoAction.deleteItem
            }

            // やり直しの表示名は「取り消した操作」。現在の状態が持っている
            // 操作名（さらに前の操作）をそのまま使うと、ひとつずれた名前が出る
            it("やり直しには取り消した操作の名前を引き継ぐ") {
                let stack = SecureInfoUndoStack()
                stack.push(snapshot(titles: ["A"], action: .deleteItem))
                _ = stack.undo(current: snapshot(titles: [], action: .edit))
                expect(stack.redoAction) == SecureInfoUndoAction.deleteItem
            }

            it("取り消しの表示名もやり直しから戻したときに保たれる") {
                let stack = SecureInfoUndoStack()
                stack.push(snapshot(titles: ["A"], action: .reorderItems))
                let restored = stack.undo(current: snapshot(titles: ["B"], action: .edit))
                _ = stack.redo(current: restored ?? snapshot(titles: ["A"]))
                expect(stack.undoAction) == SecureInfoUndoAction.reorderItems
            }
        }
    }

    // MARK: - Clear

    private static func clearSpecs() {
        describe("破棄") {

            // スタックは削除・編集前の平文を保持している。
            // ウィンドウを閉じたあとにメモリへ残り続けてはいけない
            it("clear で取り消しもやり直しも空になる") {
                let stack = SecureInfoUndoStack()
                stack.push(snapshot(titles: ["A"]))
                _ = stack.undo(current: snapshot(titles: ["A", "B"]))
                stack.push(snapshot(titles: ["C"]))

                stack.clear()
                expect(stack.canUndo) == false
                expect(stack.canRedo) == false
                expect(stack.undoSnapshots).to(beEmpty())
                expect(stack.redoSnapshots).to(beEmpty())
            }
        }
    }

    // MARK: - committedSnapshot

    private static func committedSnapshotSpecs() {
        describe("保存済み状態の切り出し") {

            // 変更する直前に控えるものなので、draft は「編集中の作業コピー」ではなく
            // items の中の保存済みの姿でなければならない。ここを取り違えると
            // 取り消しても編集後の内容が戻ってきてしまう
            it("編集中の作業コピーではなく保存済みの姿を控える") {
                let editor = makeEditor()
                editor.selectItem(itemID: "github")
                editor.beginEditing(itemID: "github")
                editor.updateTitle("GitHub (編集中)")

                let snapshot = editor.committedSnapshot(action: .edit)
                expect(snapshot.draft?.title) == "GitHub"
                expect(snapshot.items.first { $0.itemID == "github" }?.title) == "GitHub"
                expect(snapshot.selectedItemID) == "github"
                expect(snapshot.action) == SecureInfoUndoAction.edit
            }

            it("未選択なら draft は nil になる") {
                let editor = makeEditor()
                editor.selectItem(itemID: nil)
                expect(editor.committedSnapshot(action: .edit).draft) == nil
            }

            it("選択中アイテムが一覧に無ければ draft は nil になる") {
                let editor = makeEditor()
                editor.selectItem(itemID: "unknown")
                expect(editor.committedSnapshot(action: .edit).draft) == nil
            }
        }
    }

    // MARK: - restore

    private static func restoreSpecs() {
        describe("状態の復元") {

            it("一覧・作業コピー・選択が戻り、未保存フラグが下りる") {
                let editor = makeEditor()
                editor.selectItem(itemID: "github")
                editor.beginEditing(itemID: "github")
                let snapshot = editor.committedSnapshot(action: .edit)

                editor.updateTitle("書き換えた")
                editor.setItems([])
                editor.selectItem(itemID: nil)
                expect(editor.isDirty) == true

                editor.restore(snapshot)
                expect(editor.items.count) == 3
                expect(editor.draft?.title) == "GitHub"
                expect(editor.selectedItemID) == "github"
                expect(editor.isDirty) == false
            }

            // 復元後に絞り込み結果が古いままだと、消えたはずの行が一覧に残る
            it("復元で絞り込みのキャッシュが作り直される") {
                let editor = makeEditor()
                editor.setQuery("github")
                expect(editor.visibleItems.count) == 1

                let snapshot = SecureInfoSnapshot(items: [], draft: nil, selectedItemID: nil, action: .deleteItem)
                editor.restore(snapshot)
                expect(editor.visibleItems).to(beEmpty())
            }
        }
    }

    // MARK: - Fixtures

    private static func snapshot(titles: [String],
                                 selectedItemID: String? = nil,
                                 action: SecureInfoUndoAction = .edit) -> SecureInfoSnapshot {
        let items = titles.enumerated().map { index, title in
            SecureMenuItem(itemID: "item-\(index)", title: title, displayOrder: index)
        }
        return SecureInfoSnapshot(items: items, draft: nil, selectedItemID: selectedItemID, action: action)
    }

    private static func makeEditor() -> SecureInfoEditor {
        let editor = SecureInfoEditor()
        editor.setItems([
            SecureMenuItem(itemID: "github", title: "GitHub", fields: [
                SecureMenuItem.Field(label: "ID", value: "alice")
            ], displayOrder: 0),
            SecureMenuItem(itemID: "aws", title: "AWS Console", displayOrder: 1),
            SecureMenuItem(itemID: "accounting", title: "経理システム", displayOrder: 2)
        ])
        return editor
    }
}
