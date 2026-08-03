import Quick
import Nimble
import AppKit
@testable import Thoth

// MARK: - Secure Field Row Interaction Tests
//
// フィールド行の「触り方」に関する部分。
// 削除ボタンをコピーの隣から引き剥がした構造と、右クリックメニューの構成を固定する。

class SecureFieldRowInteractionSpec: QuickSpec {

    private typealias Row = SecureFieldRowView

    override class func spec() {
        deleteButtonVisibilitySpecs()
        deleteButtonLayoutSpecs()
        contextMenuSpecs()
    }

    // MARK: - Delete button visibility

    /// 誤爆対策の中身。既定では隠し、行に触れているときだけ出す
    private static func deleteButtonVisibilitySpecs() {
        describe("削除ボタンを出す条件") {

            it("触れていなければ出さない") {
                expect(Row.showsDeleteButton(isReadOnly: false, isHovered: false, hasFocus: false)) == false
            }

            it("マウスが乗っていれば出す") {
                expect(Row.showsDeleteButton(isReadOnly: false, isHovered: true, hasFocus: false)) == true
            }

            // マウスを使わない操作でも削除へ到達できるようにする
            it("その行を編集中なら出す") {
                expect(Row.showsDeleteButton(isReadOnly: false, isHovered: false, hasFocus: true)) == true
            }

            it("読み取り専用ではどの状態でも出さない") {
                for hovered in [true, false] {
                    for focused in [true, false] {
                        expect(Row.showsDeleteButton(isReadOnly: true, isHovered: hovered, hasFocus: focused)) == false
                    }
                }
            }

            it("生成直後は隠れている") {
                let row = Row(field: SecureMenuItem.Field(label: "ID", value: "a"))
                expect(row.deleteButton.isHidden) == true
                expect(row.isHovered) == false
            }

            it("マウスが乗ると現れ、離れると隠れる") {
                let row = Row(field: SecureMenuItem.Field(label: "ID", value: "a"))
                row.setHovered(true)
                expect(row.deleteButton.isHidden) == false
                row.setHovered(false)
                expect(row.deleteButton.isHidden) == true
            }

            it("読み取り専用ではマウスが乗っても現れない") {
                let row = Row(field: SecureMenuItem.Field(label: "ID", value: "a"), isReadOnly: true)
                row.setHovered(true)
                expect(row.deleteButton.isHidden) == true
            }
        }
    }

    // MARK: - Delete button layout

    private static func deleteButtonLayoutSpecs() {
        describe("削除ボタンの分離") {

            // スタックの一員のまま isHidden にすると幅が畳まれ、マウスを乗せるたびに
            // 他のボタンが横へ動く。狙って押せなくなるので構造として分けてある
            it("ボタンスタックには入れない") {
                let row = Row(field: SecureMenuItem.Field(label: "ID", value: "a"))
                expect(row.deleteButton.superview is NSStackView) == false
                expect(row.copyButton.superview is NSStackView) == true
                expect(row.deleteButton.superview) === row
            }

            it("読み取り専用では削除ボタンを組み立てない") {
                let row = Row(field: SecureMenuItem.Field(label: "ID", value: "a"), isReadOnly: true)
                expect(row.deleteButton.superview) == nil
            }

            // コピー ⧉ と隣り合わせにしない。押し間違いの直接の原因だった
            it("コピーとの間に区切りの余白がある") {
                let row = Row(field: SecureMenuItem.Field(label: "ID", value: "a"))
                row.frame = NSRect(x: 0, y: 0, width: 420, height: 24)
                row.setHovered(true)
                row.layoutSubtreeIfNeeded()

                let gap = row.deleteButton.frame.minX - row.copyButton.frame.maxX
                expect(gap) >= 8
            }

            // 隠れているあいだも位置は動かない（現れた瞬間に他が横滑りしない）
            it("表示・非表示で他のボタンの位置が変わらない") {
                let row = Row(field: SecureMenuItem.Field(label: "ID", value: "a"))
                row.frame = NSRect(x: 0, y: 0, width: 420, height: 24)
                row.layoutSubtreeIfNeeded()
                let hiddenCopyFrame = row.copyButton.frame

                row.setHovered(true)
                row.layoutSubtreeIfNeeded()
                expect(row.copyButton.frame) == hiddenCopyFrame
            }
        }
    }

    // MARK: - Context menu

    /// ホバーでしか出ない削除の導線を補うメニュー
    private static func contextMenuSpecs() {
        describe("右クリックメニュー") {

            func menu(for row: Row) -> NSMenu? {
                let event = NSEvent.mouseEvent(with: .rightMouseDown, location: .zero,
                                               modifierFlags: [], timestamp: 0, windowNumber: 0,
                                               context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
                guard let event = event else { return nil }
                return row.menu(for: event)
            }

            it("上へ移動・下へ移動・削除が並ぶ") {
                let row = Row(field: SecureMenuItem.Field(label: "ID", value: "a"))
                let titles = menu(for: row)?.items.map { $0.isSeparatorItem ? "-" : $0.title }
                expect(titles) == [L10n.secureInfoMoveUp, L10n.secureInfoMoveDown, "-", L10n.secureInfoRemoveField]
            }

            it("読み取り専用ではメニューを出さない") {
                let row = Row(field: SecureMenuItem.Field(label: "ID", value: "a"), isReadOnly: true)
                expect(menu(for: row)) == nil
            }

            it("上へ移動・下へ移動が移動量を通知する") {
                var reported: [Int] = []
                let row = Row(field: SecureMenuItem.Field(label: "ID", value: "a"))
                row.onMove = { _, offset in reported.append(offset) }
                guard let items = menu(for: row)?.items else { return fail("no menu") }
                _ = items[0].target?.perform(items[0].action, with: items[0])
                _ = items[1].target?.perform(items[1].action, with: items[1])
                expect(reported) == [-1, 1]
            }

            it("メニューの削除が対象の行を通知する") {
                var deleted: String?
                let row = Row(field: SecureMenuItem.Field(fieldID: "f1", label: "ID", value: "a"))
                row.onDelete = { deleted = $0.field.fieldID }
                guard let items = menu(for: row)?.items else { return fail("no menu") }
                _ = items[3].target?.perform(items[3].action, with: items[3])
                expect(deleted) == "f1"
            }
        }
    }
}
