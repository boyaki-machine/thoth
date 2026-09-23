import Quick
import Nimble
import AppKit
@testable import Thoth

// MARK: - Secure Info Window View Tests
//
// セキュア情報確認ウィンドウのビュー側（行の表示・編集可否・ボタン構成・
// URL 判定・詳細ペインの組み立て・平文表示の自動解除）。

// BDD スペックは多数の it ブロックを含み型本体が長くなるため型長ルールを緩める
class SecureInfoViewSpec: QuickSpec {

    override class func spec() {
        viewIntegrationSpecs()
        fieldRowSpecs()
        editabilitySpecs()
        openableURLSpecs()
        detailRowBuildingSpecs()
        rowButtonSpecs()
        revealExpirySpecs()
        windowProtectionSpecs()
    }

    // MARK: - Fixtures

    static func sampleItems() -> [SecureMenuItem] {
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

    static func makeEditor() -> SecureInfoEditor {
        let editor = SecureInfoEditor()
        editor.setItems(sampleItems())
        return editor
    }

    static func titles(_ items: [SecureMenuItem]) -> [String] {
        return items.map { $0.title }
    }

    // MARK: - Reveal expiry

    /// 平文表示は時間で必ず伏せ字へ戻す。
    /// 表示したまま離席されると、画面に平文が残り続けてしまうため
    static func revealExpirySpecs() {
        describe("平文表示の自動解除") {

            func maskedRow() -> SecureFieldRowView {
                return SecureFieldRowView(field: SecureMenuItem.Field(label: "PW", value: "s3cr3t", isPassword: true))
            }

            it("表示を始めた時刻を覚える") {
                let row = maskedRow()
                let now = Date(timeIntervalSince1970: 1_700_000_000)
                row.toggleReveal(at: now)
                expect(row.isRevealed) == true
                expect(row.revealedAt) == now
            }

            it("伏せ字へ戻すと時刻も忘れる") {
                let row = maskedRow()
                row.toggleReveal()
                row.hideRevealedValue()
                expect(row.revealedAt) == nil
            }

            // 境界値: ちょうど 30 秒で解除し、29 秒では解除しない
            it("期限ちょうどで解除し、それ未満では解除しない") {
                let start = Date(timeIntervalSince1970: 1_700_000_000)
                let timeout = SecureFieldRowView.revealTimeout

                let notYet = maskedRow()
                notYet.toggleReveal(at: start)
                expect(notYet.hideRevealedValueIfExpired(now: start.addingTimeInterval(timeout - 1))) == false
                expect(notYet.isRevealed) == true
                expect(notYet.valueField.stringValue) == "s3cr3t"

                let expired = maskedRow()
                expired.toggleReveal(at: start)
                expect(expired.hideRevealedValueIfExpired(now: start.addingTimeInterval(timeout))) == true
                expect(expired.isRevealed) == false
                expect(expired.valueField.stringValue) == SecureFieldRowView.maskedPlaceholder
            }

            it("表示していない行は解除の対象にならない") {
                let row = maskedRow()
                expect(row.hideRevealedValueIfExpired(now: Date().addingTimeInterval(9_999))) == false
            }

            // 操作シーケンス: 一度隠して再表示すると期限も引き直される
            it("表示し直すと期限が引き直される") {
                let start = Date(timeIntervalSince1970: 1_700_000_000)
                let row = maskedRow()
                row.toggleReveal(at: start)
                row.toggleReveal(at: start.addingTimeInterval(10))          // 隠す
                row.toggleReveal(at: start.addingTimeInterval(20))          // 再表示
                expect(row.hideRevealedValueIfExpired(now: start.addingTimeInterval(45))) == false
                expect(row.hideRevealedValueIfExpired(now: start.addingTimeInterval(50))) == true
            }

            it("詳細ペインが期限切れの行をまとめて伏せ字へ戻す") {
                let detail = CPYSecureInfoDetailViewController()
                _ = detail.view
                detail.show(item: SecureMenuItem(title: "T", fields: [
                    SecureMenuItem.Field(label: "PW1", value: "a", isPassword: true),
                    SecureMenuItem.Field(label: "PW2", value: "b", isPassword: true),
                    SecureMenuItem.Field(label: "ID", value: "c")
                ]))
                let start = Date(timeIntervalSince1970: 1_700_000_000)
                detail.fieldRows[0].toggleReveal(at: start)
                detail.fieldRows[1].toggleReveal(at: start.addingTimeInterval(20))

                // 先に表示した行だけが期限切れになる
                expect(detail.expireRevealedValues(now: start.addingTimeInterval(35))) == 1
                expect(detail.fieldRows[0].isRevealed) == false
                expect(detail.fieldRows[1].isRevealed) == true

                expect(detail.expireRevealedValues(now: start.addingTimeInterval(55))) == 1
                expect(detail.fieldRows[1].isRevealed) == false
            }
        }
    }

    // MARK: - Window protection

    static func windowProtectionSpecs() {
        describe("ウィンドウの保護") {

            // 値を平文で表示するため、画面共有・画面収録から除外する
            it("画面共有・画面収録から除外される") {
                expect(CPYSecureInfoWindowController.shared.window?.sharingType) == NSWindow.SharingType.none
            }

            it("画面ロックの通知名を持つ") {
                expect(CPYSecureInfoSplitViewController.screenIsLockedNotification.rawValue) == "com.apple.screenIsLocked"
            }

            // 閉じたあともメモリに平文が残らないようにする
            it("保持データの破棄で機微情報が残らない") {
                let editor = SecureInfoEditor()
                editor.setItems([
                    SecureMenuItem(itemID: "s1", title: "GitHub", fields: [
                        SecureMenuItem.Field(label: "PW", value: "s3cr3t", isPassword: true)
                    ])
                ])
                editor.setQuery("git")
                editor.selectItem(itemID: "s1")
                editor.beginEditing(itemID: "s1")
                _ = editor.updateTitle("Edited")

                editor.clearSensitiveData()
                expect(editor.items).to(beEmpty())
                expect(editor.draft?.itemID) == nil
                expect(editor.isDirty) == false
                expect(editor.selectedItemID) == nil
                expect(editor.query) == ""
                expect(editor.visibleItems).to(beEmpty())
            }
        }
    }

    // MARK: - Row buttons

    static func rowButtonSpecs() {
        describe("行のボタン構成") {

            /// スタックに並ぶボタン。削除ボタンは**あえてスタックの外**に置いてあるので
            /// ここには現れない（下の「削除ボタンの分離」を参照）
            func shownButtons(_ row: SecureFieldRowView) -> [NSButton] {
                return [row.maskButton, row.revealButton, row.openButton, row.copyButton, row.deleteButton]
                    .filter { $0.superview is NSStackView }
            }

            it("通常フィールドはマスク切替とコピーが並ぶ") {
                let row = SecureFieldRowView(field: SecureMenuItem.Field(label: "ID", value: "a"))
                expect(shownButtons(row)) == [row.maskButton, row.copyButton]
            }

            it("マスク中は表示切替も並ぶ") {
                let row = SecureFieldRowView(field: SecureMenuItem.Field(label: "PW", value: "a", isPassword: true))
                expect(shownButtons(row)) == [row.maskButton, row.revealButton, row.copyButton]
            }

            it("URL は「開く」も並ぶ") {
                let row = SecureFieldRowView(field: SecureMenuItem.Field(label: "U", value: "a", kind: .url))
                expect(shownButtons(row)) == [row.maskButton, row.openButton, row.copyButton]
            }

            // TOTP はマスク切替を持たない（secret を表示しない設計のため）
            it("TOTP はコピーだけが並ぶ") {
                let row = SecureFieldRowView(field: SecureMenuItem.Field(label: "T", value: "a", kind: .totp))
                expect(shownButtons(row)) == [row.copyButton]
            }

            // 読み取り専用では編集系のボタンを出さない（押しても何も起きないボタンを見せない）
            it("読み取り専用ではマスク切替を出さない") {
                let row = SecureFieldRowView(field: SecureMenuItem.Field(label: "PW", value: "a", isPassword: true),
                                             isReadOnly: true)
                expect(shownButtons(row)) == [row.revealButton, row.copyButton]
            }

            it("マスク切替はいまと逆の状態を通知する") {
                var reported: [Bool] = []
                let plain = SecureFieldRowView(field: SecureMenuItem.Field(label: "ID", value: "a"))
                plain.onMaskToggled = { _, isPassword in reported.append(isPassword) }
                plain.maskButton.performClick(nil)

                let masked = SecureFieldRowView(field: SecureMenuItem.Field(label: "PW", value: "a", isPassword: true))
                masked.onMaskToggled = { _, isPassword in reported.append(isPassword) }
                masked.maskButton.performClick(nil)

                expect(reported) == [true, false]
            }

            it("削除ボタンが対象の行を通知する") {
                var deleted: String?
                let row = SecureFieldRowView(field: SecureMenuItem.Field(fieldID: "f1", label: "ID", value: "a"))
                row.onDelete = { deleted = $0.field.fieldID }
                row.deleteButton.performClick(nil)
                expect(deleted) == "f1"
            }
        }
    }

    // MARK: - Editability

    /// どの状態でどこを編集できるか。**マスク中の編集を許すと、画面に見えている
    /// 伏せ字がそのまま値として保存されてしまう**ため、ここが最重要
    static func editabilitySpecs() {
        describe("編集できる場所の判定") {
            typealias Row = SecureFieldRowView

            func editable(_ field: SecureMenuItem.Field, revealed: Bool = false, readOnly: Bool = false) -> Bool {
                return Row.isValueEditable(field: field, isRevealed: revealed, isReadOnly: readOnly)
            }

            it("通常フィールドと URL とメモは編集できる") {
                expect(editable(SecureMenuItem.Field(label: "ID", value: "a"))) == true
                expect(editable(SecureMenuItem.Field(label: "U", value: "a", kind: .url))) == true
                expect(editable(SecureMenuItem.Field(label: "M", value: "a", kind: .note))) == true
            }

            // 伏せ字を編集させると「••••••••」が値として保存される
            it("マスク中は編集できず、表示切替で編集できるようになる") {
                let masked = SecureMenuItem.Field(label: "PW", value: "s3cr3t", isPassword: true)
                expect(editable(masked, revealed: false)) == false
                expect(editable(masked, revealed: true)) == true
            }

            // メモはマスクを持たないので、旧データの isPassword で編集不能にならない
            it("旧データでマスク指定が残っているメモも編集できる") {
                let legacy = SecureMenuItem.Field(label: "M", value: "a\nb", isPassword: true, kind: .note)
                expect(editable(legacy, revealed: false)) == true
                expect(editable(legacy, revealed: true)) == true
            }

            // TOTP は secret を表示しないので、編集させると空文字で潰れる
            it("TOTP は表示切替に関係なく編集できない") {
                let totp = SecureMenuItem.Field(label: "T", value: "secret", kind: .totp)
                expect(editable(totp, revealed: false)) == false
                expect(editable(totp, revealed: true)) == false
            }

            it("読み取り専用モードでは何も編集できない") {
                expect(editable(SecureMenuItem.Field(label: "ID", value: "a"), readOnly: true)) == false
                let masked = SecureMenuItem.Field(label: "PW", value: "a", isPassword: true)
                expect(editable(masked, revealed: true, readOnly: true)) == false
                expect(Row.isLabelEditable(isReadOnly: true)) == false
                expect(Row.isLabelEditable(isReadOnly: false)) == true
            }

            it("行ビューの編集可否が判定と一致する") {
                let masked = SecureFieldRowView(field: SecureMenuItem.Field(label: "PW", value: "s3cr3t", isPassword: true))
                expect(masked.valueField.isEditable) == false
                masked.toggleReveal()
                expect(masked.valueField.isEditable) == true
                masked.hideRevealedValue()
                expect(masked.valueField.isEditable) == false

                let note = SecureFieldRowView(field: SecureMenuItem.Field(label: "M", value: "a", kind: .note))
                expect(note.noteTextView.isEditable) == true

                let readOnlyRow = SecureFieldRowView(field: SecureMenuItem.Field(label: "ID", value: "a"), isReadOnly: true)
                expect(readOnlyRow.valueField.isEditable) == false
                expect(readOnlyRow.labelField.isEditable) == false
            }
        }
    }
}
