import Quick
import Nimble
import AppKit
@testable import Thoth

// MARK: - Secure Info Window Action Menu / Close Button Tests
//
// アイテム全域にわたる操作（取り消し・やり直し・入出力）の置き場と、
// ウィンドウを閉じる導線。
//
// 削除ボタンがホバーでしか出ないぶん、「戻せる」ことは目に見えている必要がある。
// ⚙ メニューに取り消しを置くのはそのため。

class SecureInfoActionMenuSpec: QuickSpec {

    private typealias ListVC = CPYSecureInfoListViewController

    override class func spec() {
        menuTitleSpecs()
        menuStructureSpecs()
        menuActionSpecs()
        readOnlySpecs()
        closeButtonSpecs()
    }

    // MARK: - Titles

    private static func menuTitleSpecs() {
        describe("取り消し項目の表示名") {

            it("何が戻るのかを名前に出す") {
                expect(ListVC.undoTitle(for: .deleteItem)) == L10n.secureInfoUndoFormat(L10n.secureInfoActionDelete)
                expect(ListVC.redoTitle(for: .importItems)) == L10n.secureInfoRedoFormat(L10n.secureInfoActionImport)
            }

            it("戻せるものが無ければ操作名を空にする") {
                expect(ListVC.undoTitle(for: nil)) == L10n.secureInfoUndoFormat("")
                expect(ListVC.redoTitle(for: nil)) == L10n.secureInfoRedoFormat("")
            }

            it("すべての操作に名前がある") {
                let actions: [SecureInfoUndoAction] = [.edit, .addItem, .deleteItem, .reorderItems, .importItems]
                for action in actions {
                    expect(action.localizedName).toNot(beEmpty())
                }
                // 取り違えが起きないよう、名前は互いに異なること
                expect(Set(actions.map { $0.localizedName }).count) == actions.count
            }
        }
    }

    // MARK: - Structure

    private static func menuStructureSpecs() {
        describe("⚙ メニューの構成") {

            func makeListViewController(canUndo: Bool = false, canRedo: Bool = false,
                                        isReadOnly: Bool = false) -> ListVC {
                let editor = SecureInfoEditor()
                editor.setItems([SecureMenuItem(itemID: "s1", title: "GitHub")])
                editor.isReadOnly = isReadOnly
                let listViewController = ListVC(editor: editor)
                _ = listViewController.view
                listViewController.undoState = {
                    (undo: canUndo ? .deleteItem : nil, redo: canRedo ? .edit : nil)
                }
                return listViewController
            }

            it("取り消し・やり直し・インポート・エクスポートが並ぶ") {
                let menu = makeListViewController().makeActionMenu()
                let titles = menu.items.map { $0.isSeparatorItem ? "-" : $0.title }
                expect(titles) == [ListVC.undoTitle(for: nil), ListVC.redoTitle(for: nil), "-",
                                   L10n.importSecureItems, L10n.exportSecureItems]
            }

            it("⌘Z / ⌘⇧Z を項目に表示する") {
                let menu = makeListViewController().makeActionMenu()
                expect(menu.items[0].keyEquivalent) == "z"
                expect(menu.items[1].keyEquivalent.lowercased()) == "z"
                expect(menu.items[1].keyEquivalentModifierMask.contains(.shift)) == true
            }

            // 押しても何も起きない項目を有効に見せない。
            // autoenablesItems に任せると、validateMenuItem 未実装で全部有効になる
            it("戻せるものが無ければ取り消しを無効にする") {
                let menu = makeListViewController(canUndo: false, canRedo: false).makeActionMenu()
                expect(menu.autoenablesItems) == false
                expect(menu.items[0].isEnabled) == false
                expect(menu.items[1].isEnabled) == false
            }

            it("戻せるものがあれば有効にし、名前も出す") {
                let menu = makeListViewController(canUndo: true, canRedo: true).makeActionMenu()
                expect(menu.items[0].isEnabled) == true
                expect(menu.items[0].title) == ListVC.undoTitle(for: .deleteItem)
                expect(menu.items[1].isEnabled) == true
                expect(menu.items[1].title) == ListVC.redoTitle(for: .edit)
            }
        }
    }

    // MARK: - Actions

    private static func menuActionSpecs() {
        describe("⚙ メニューの通知") {

            it("各項目がそれぞれの要求を通知する") {
                let editor = SecureInfoEditor()
                editor.setItems([SecureMenuItem(itemID: "s1", title: "GitHub")])
                let listViewController = ListVC(editor: editor)
                _ = listViewController.view
                listViewController.undoState = { (undo: .edit, redo: .edit) }

                var fired: [String] = []
                listViewController.onUndoRequested = { fired.append("undo") }
                listViewController.onRedoRequested = { fired.append("redo") }
                listViewController.onImportRequested = { fired.append("import") }
                listViewController.onExportRequested = { fired.append("export") }

                for item in listViewController.makeActionMenu().items where !item.isSeparatorItem {
                    _ = item.target?.perform(item.action, with: item)
                }
                expect(fired) == ["undo", "redo", "import", "export"]
            }
        }
    }

    // MARK: - Read only

    /// キーチェーンを読み出せない状態。取り込みは保存が拒否されるだけだが、
    /// **書き出しは 0 件の JSON を作ってしまい、既存のバックアップを空で上書きしうる**
    private static func readOnlySpecs() {
        describe("読み取り専用のとき") {

            it("インポートとエクスポートを無効にする") {
                let editor = SecureInfoEditor()
                editor.isReadOnly = true
                let listViewController = ListVC(editor: editor)
                _ = listViewController.view
                let menu = listViewController.makeActionMenu()
                expect(menu.items[3].isEnabled) == false
                expect(menu.items[4].isEnabled) == false
            }

            it("Split VC 側でも入出力を受け付けない") {
                let splitViewController = CPYSecureInfoSplitViewController()
                _ = splitViewController.view
                splitViewController.editor.isReadOnly = false
                expect(splitViewController.allowsTransfer) == true
                splitViewController.editor.isReadOnly = true
                expect(splitViewController.allowsTransfer) == false
            }
        }
    }

    // MARK: - Close button

    private static func closeButtonSpecs() {
        describe("「閉じる」ボタン") {

            it("右ペインの下端に置かれる") {
                let detailViewController = CPYSecureInfoDetailViewController()
                _ = detailViewController.view
                expect(detailViewController.closeButton.superview) === detailViewController.view
                expect(detailViewController.closeButton.title) == L10n.close
            }

            // アイテムを選んでいなくても閉じられる必要がある
            it("選択が無くても隠さない") {
                let detailViewController = CPYSecureInfoDetailViewController()
                _ = detailViewController.view
                detailViewController.show(item: nil)
                expect(detailViewController.closeButton.isHidden) == false
                // フィールド追加のほうは選択が無ければ隠れる（従来どおり）
                expect(detailViewController.addFieldButton.isHidden) == true
            }

            // Return は右ペインへフォーカスを移す操作に割り当て済み。
            // 既定ボタンにすると横取りされる
            it("既定ボタンにしない") {
                let detailViewController = CPYSecureInfoDetailViewController()
                _ = detailViewController.view
                expect(detailViewController.closeButton.keyEquivalent) == ""
            }
        }
    }
}
