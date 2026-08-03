import Quick
import Nimble
@testable import Thoth

// MARK: - Tab Navigation Logic Tests
//
// `SecureItemEditViewController.focusOrder(for:)` は Tab キーの巡回順を組み立てる純粋関数。
// handleTabKey はこの配列上を前後に 1 つ動くだけなので、順序さえ検証すれば
// Tab / Shift+Tab の挙動を UI 無しで担保できる。

class SecureItemEditTabNavigationSpec: QuickSpec {

    private typealias Stop = SecureItemEditViewController.FocusStop

    override class func spec() {
        focusOrderSpecs()
        traversalSpecs()
    }

    private static func focusOrderSpecs() {
        describe("SecureItemEditViewController.focusOrder") {

            /// ボトムバーのボタン列（全ケース共通の末尾）
            let trailingButtons: [Stop] = [.addField, .removeField, .passwordGenerator, .totpImport, .cancel, .save]

            it("Contains only the title and the buttons when there are no fields") {
                expect(SecureItemEditViewController.focusOrder(for: [])) == [.title] + trailingButtons
            }

            it("Visits label, value and checkbox for a plain field") {
                let fields = [SecureMenuItem.Field(label: "Username", value: "alice")]
                expect(SecureItemEditViewController.focusOrder(for: fields))
                    == [.title, .label(row: 0), .value(row: 0), .checkbox(row: 0)] + trailingButtons
            }

            it("Treats a password field the same as a plain field") {
                let fields = [SecureMenuItem.Field(label: "Password", value: "s3cr3t", isPassword: true)]
                expect(SecureItemEditViewController.focusOrder(for: fields))
                    == [.title, .label(row: 0), .value(row: 0), .checkbox(row: 0)] + trailingButtons
            }

            // TOTP は secret を表示しないため Value を編集できず、マスク切り替えも持たない
            it("Visits only the label for a totp field") {
                let fields = [SecureMenuItem.Field(label: "TOTP", value: "otpauth://x", kind: .totp)]
                expect(SecureItemEditViewController.focusOrder(for: fields))
                    == [.title, .label(row: 0)] + trailingButtons
            }

            // URL は通常のテキストと同じ扱い
            it("Visits label, value and checkbox for a url field") {
                let fields = [SecureMenuItem.Field(label: "URL", value: "https://example.com", kind: .url)]
                expect(SecureItemEditViewController.focusOrder(for: fields))
                    == [.title, .label(row: 0), .value(row: 0), .checkbox(row: 0)] + trailingButtons
            }

            // メモは単一行セルで編集できず（改行が失われる）、マスクも持たないため、
            // TOTP と同じくラベルだけが巡回対象になる
            it("Visits only the label for a note field") {
                let fields = [SecureMenuItem.Field(label: "Memo", value: "line1\nline2", kind: .note)]
                expect(SecureItemEditViewController.focusOrder(for: fields))
                    == [.title, .label(row: 0)] + trailingButtons
            }

            it("Builds the order for a mix of every kind") {
                let fields = [SecureMenuItem.Field(label: "ID", value: "alice"),
                              SecureMenuItem.Field(label: "Password", value: "s3cr3t", isPassword: true),
                              SecureMenuItem.Field(label: "TOTP", value: "otpauth://x", kind: .totp),
                              SecureMenuItem.Field(label: "URL", value: "https://example.com", kind: .url),
                              SecureMenuItem.Field(label: "Memo", value: "a\nb", kind: .note)]

                expect(SecureItemEditViewController.focusOrder(for: fields)) == [
                    .title,
                    .label(row: 0), .value(row: 0), .checkbox(row: 0),
                    .label(row: 1), .value(row: 1), .checkbox(row: 1),
                    .label(row: 2),
                    .label(row: 3), .value(row: 3), .checkbox(row: 3),
                    .label(row: 4)
                ] + trailingButtons
            }

            it("Keeps the row indices aligned with the field array") {
                let fields = [SecureMenuItem.Field(label: "TOTP", value: "otpauth://x", kind: .totp),
                              SecureMenuItem.Field(label: "ID", value: "alice")]
                // 先頭の TOTP が Value/Checkbox を持たなくても、2 番目の行は row: 1 のまま
                expect(SecureItemEditViewController.focusOrder(for: fields))
                    == [.title, .label(row: 0), .label(row: 1), .value(row: 1), .checkbox(row: 1)] + trailingButtons
            }

            it("Never contains duplicate stops") {
                let fields = [SecureMenuItem.Field(label: "A", value: "1"),
                              SecureMenuItem.Field(label: "B", value: "2", kind: .note),
                              SecureMenuItem.Field(label: "C", value: "3", kind: .totp)]
                let order = SecureItemEditViewController.focusOrder(for: fields)
                // handleTabKey は firstIndex(of:) で現在位置を求めるため、重複があると巡回が壊れる
                for stop in order {
                    expect(order.filter { $0 == stop }.count) == 1
                }
            }
        }

    }

    // 巡回はこの配列上を前後に 1 つ動くだけなので、代表的な遷移を配列操作として検証する
    private static func traversalSpecs() {
        describe("Tab traversal over the focus order") {

            /// ID（plain）→ TOTP → メモ の 3 行構成
            func mixedFields() -> [SecureMenuItem.Field] {
                return [SecureMenuItem.Field(label: "ID", value: "alice"),
                        SecureMenuItem.Field(label: "TOTP", value: "otpauth://x", kind: .totp),
                        SecureMenuItem.Field(label: "Memo", value: "a\nb", kind: .note)]
            }

            func next(from stop: Stop, in fields: [SecureMenuItem.Field], shift: Bool) -> Stop {
                let order = SecureItemEditViewController.focusOrder(for: fields)
                let index = order.firstIndex(of: stop)!
                let offset = shift ? order.count - 1 : 1
                return order[(index + offset) % order.count]
            }

            it("Moves from the last control of a row to the next row label") {
                expect(next(from: .checkbox(row: 0), in: mixedFields(), shift: false)) == Stop.label(row: 1)
            }

            it("Jumps over the skipped controls of a totp row") {
                expect(next(from: .label(row: 1), in: mixedFields(), shift: false)) == Stop.label(row: 2)
                expect(next(from: .label(row: 2), in: mixedFields(), shift: true)) == Stop.label(row: 1)
            }

            // メモ行は Value もチェックボックスも持たないため、ラベルの次はボタン列へ抜ける
            it("Leaves a note row after its label") {
                expect(next(from: .label(row: 2), in: mixedFields(), shift: false)) == Stop.addField
            }

            it("Wraps from save back to the title and vice versa") {
                expect(next(from: .save, in: mixedFields(), shift: false)) == Stop.title
                expect(next(from: .title, in: mixedFields(), shift: true)) == Stop.save
            }

            it("Enters the first row from the title") {
                expect(next(from: .title, in: mixedFields(), shift: false)) == Stop.label(row: 0)
            }

            it("Falls back to the add button when there are no fields") {
                expect(next(from: .title, in: [], shift: false)) == Stop.addField
            }

            // ボトムバーのボタン列を画面上の並びどおりに巡回する
            it("Walks the bottom bar buttons in their on-screen order") {
                expect(next(from: .addField, in: [], shift: false)) == Stop.removeField
                expect(next(from: .removeField, in: [], shift: false)) == Stop.passwordGenerator
                expect(next(from: .passwordGenerator, in: [], shift: false)) == Stop.totpImport
                expect(next(from: .totpImport, in: [], shift: false)) == Stop.cancel
                expect(next(from: .cancel, in: [], shift: false)) == Stop.save
            }

            it("Walks the bottom bar buttons backwards with shift") {
                expect(next(from: .save, in: [], shift: true)) == Stop.cancel
                expect(next(from: .cancel, in: [], shift: true)) == Stop.totpImport
                expect(next(from: .totpImport, in: [], shift: true)) == Stop.passwordGenerator
                expect(next(from: .passwordGenerator, in: [], shift: true)) == Stop.removeField
                expect(next(from: .removeField, in: [], shift: true)) == Stop.addField
            }

            // 一周してちょうど元に戻る（循環の抜けや重複を検出する）
            it("Returns to the starting stop after a full cycle in both directions") {
                let fields = mixedFields()
                let order = SecureItemEditViewController.focusOrder(for: fields)
                var forward = Stop.title
                var backward = Stop.title
                for _ in 0..<order.count {
                    forward = next(from: forward, in: fields, shift: false)
                    backward = next(from: backward, in: fields, shift: true)
                }
                expect(forward) == Stop.title
                expect(backward) == Stop.title
            }
        }
    }
}
