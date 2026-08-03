import Quick
import Nimble
import AppKit
@testable import Thoth

// MARK: - Secure Info Window Key Mapping Tests
//
// `CPYSecureInfoSplitViewController.keyAction(...)` はキー入力から操作を決める純粋関数。
// 実際のハンドラはこの写像に従って分岐するだけなので、ここを固定すれば
// キー操作の仕様をウィンドウ無しで担保できる。

class SecureInfoKeyActionSpec: QuickSpec {

    private typealias Action = SecureInfoKeyAction

    /// テスト対象の写像。省略値は「修飾キーなし・入力中でない」
    private static func action(_ keyCode: UInt16, character: String? = nil,
                               modifiers: NSEvent.ModifierFlags = [],
                               editing: Bool = false) -> Action? {
        return CPYSecureInfoSplitViewController.keyAction(keyCode: keyCode, character: character,
                                                          modifiers: modifiers, isEditingText: editing)
    }

    override class func spec() {
        commandShortcutSpecs()
        vimKeySpecs()
        escapeSpecs()
        editingGuardSpecs()
        unmappedSpecs()
    }

    // MARK: - Command shortcuts

    private static func commandShortcutSpecs() {
        describe("⌘ 付きのショートカット") {

            it("検索・保存・追加・クローズを割り当てる") {
                expect(action(0, character: "f", modifiers: .command)) == Action.focusSearch
                expect(action(0, character: "s", modifiers: .command)) == Action.save
                expect(action(0, character: "n", modifiers: .command)) == Action.addItem
                expect(action(0, character: "w", modifiers: .command)) == Action.close
            }

            it("⌘Delete で選択中アイテムを削除する") {
                expect(action(KeyCode.delete, modifiers: .command)) == Action.deleteItem
            }

            // ⌘ 付きは入力中でも効く（入力欄から手を離さずに保存・検索できる）
            it("テキスト入力中でも効く") {
                expect(action(0, character: "s", modifiers: .command, editing: true)) == Action.save
                expect(action(0, character: "f", modifiers: .command, editing: true)) == Action.focusSearch
                expect(action(0, character: "n", modifiers: .command, editing: true)) == Action.addItem
                expect(action(0, character: "w", modifiers: .command, editing: true)) == Action.close
            }

            // ⌘Delete は入力中だと「行頭まで削除」の標準操作。
            // 横取りするとアイテムごと消えてしまう
            it("⌘Delete はテキスト入力中には割り当てない") {
                expect(action(KeyCode.delete, modifiers: .command, editing: true)) == nil
                expect(action(KeyCode.delete, modifiers: .command, editing: false)) == Action.deleteItem
            }

            // キーボード配列に依存しないよう文字で判定している
            it("キーコードではなく文字で判定する") {
                // 別配列で s の位置に別のキーコードが来ても動く
                expect(action(99, character: "s", modifiers: .command)) == Action.save
                // 文字が取れなければ割り当てない
                expect(action(1, character: nil, modifiers: .command)) == nil
            }

            it("修飾キーが増えると割り当てない") {
                expect(action(0, character: "s", modifiers: [.command, .shift])) == nil
                expect(action(0, character: "n", modifiers: [.command, .option])) == nil
            }

            it("未割り当ての ⌘ ショートカットは素通しする") {
                expect(action(0, character: "q", modifiers: .command)) == nil
                expect(action(0, character: "c", modifiers: .command)) == nil
            }
        }
    }

    // MARK: - vim keys

    private static func vimKeySpecs() {
        describe("vim 風のキー操作") {

            it("j / k で一覧の選択を上下に動かす") {
                expect(action(KeyCode.letterJ)) == Action.moveSelectionDown
                expect(action(KeyCode.letterK)) == Action.moveSelectionUp
            }

            it("Ctrl+j / Ctrl+k で並べ替える") {
                expect(action(KeyCode.letterJ, modifiers: .control)) == Action.reorderDown
                expect(action(KeyCode.letterK, modifiers: .control)) == Action.reorderUp
            }

            // 並べ替えは入力中でも効く（値を打ちながら行を動かせる）
            it("並べ替えはテキスト入力中でも効く") {
                expect(action(KeyCode.letterJ, modifiers: .control, editing: true)) == Action.reorderDown
                expect(action(KeyCode.letterK, modifiers: .control, editing: true)) == Action.reorderUp
            }

            it("l / → / Return で右ペインへ移る") {
                expect(action(KeyCode.letterL)) == Action.focusDetail
                expect(action(KeyCode.rightArrow)) == Action.focusDetail
                expect(action(KeyCode.returnKey)) == Action.focusDetail
            }

            it("h / ← で一覧へ戻る") {
                expect(action(KeyCode.letterH)) == Action.focusList
                expect(action(KeyCode.leftArrow)) == Action.focusList
            }

            it("/ で検索欄へ移る") {
                expect(action(KeyCode.slash)) == Action.focusSearch
            }

            it("Ctrl は j / k 以外に割り当てない") {
                expect(action(KeyCode.letterH, modifiers: .control)) == nil
                expect(action(KeyCode.letterL, modifiers: .control)) == nil
                expect(action(KeyCode.slash, modifiers: .control)) == nil
            }
        }
    }

    // MARK: - Escape

    /// Esc は 2 段階。1 回目で編集を確定し、2 回目でウィンドウを閉じる。
    /// 1 回目からいきなり閉じると、打ちかけの内容の扱いが分かりにくくなる
    private static func escapeSpecs() {
        describe("Esc の 2 段階") {

            it("入力中は編集の確定になる") {
                expect(action(KeyCode.escape, editing: true)) == Action.endEditing
            }

            it("入力中でなければウィンドウを閉じる") {
                expect(action(KeyCode.escape, editing: false)) == Action.close
            }

            it("修飾キー付きの Esc は割り当てない") {
                expect(action(KeyCode.escape, modifiers: .command)) == nil
                expect(action(KeyCode.escape, modifiers: .control)) == nil
                expect(action(KeyCode.escape, modifiers: .shift, editing: true)) == nil
            }
        }
    }

    // MARK: - Editing guard

    /// 入力中に h/j/k/l や / を横取りすると、その文字が打てなくなる
    private static func editingGuardSpecs() {
        describe("テキスト入力中の保護") {

            it("入力中は vim キーを横取りしない") {
                for keyCode in [KeyCode.letterH, KeyCode.letterJ, KeyCode.letterK, KeyCode.letterL, KeyCode.slash] {
                    expect(action(keyCode, editing: true)) == nil
                }
            }

            it("入力中は矢印キーと Return も横取りしない") {
                for keyCode in [KeyCode.leftArrow, KeyCode.rightArrow, KeyCode.returnKey] {
                    expect(action(keyCode, editing: true)) == nil
                }
            }

            it("入力中でなければ同じキーが操作になる") {
                for keyCode in [KeyCode.letterH, KeyCode.letterJ, KeyCode.letterK, KeyCode.letterL, KeyCode.slash] {
                    expect(action(keyCode, editing: false)) != nil
                }
            }
        }
    }

    // MARK: - Unmapped

    private static func unmappedSpecs() {
        describe("割り当てのないキー") {

            it("Shift や Option 単独の修飾は割り当てない") {
                expect(action(KeyCode.letterJ, modifiers: .shift)) == nil
                expect(action(KeyCode.letterJ, modifiers: .option)) == nil
                expect(action(KeyCode.letterJ, modifiers: [.control, .shift])) == nil
            }

            it("知らないキーコードは素通しする") {
                expect(action(200)) == nil
                expect(action(0)) == nil
            }

            // 一覧のキー操作が右ペインの Tab 巡回を壊さないこと
            it("Tab は割り当てない（AppKit のキービューループに任せる）") {
                expect(action(48)) == nil
                expect(action(48, modifiers: .shift)) == nil
            }
        }
    }
}
