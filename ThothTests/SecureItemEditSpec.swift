import Quick
import Nimble
import AppKit
@testable import Thoth

/// セキュアアイテム編集シートの値収集と、編集フロー経由の履歴記録を担保するスペック。
/// 「履歴に Label が表示される」リグレッションを検出するためのテストを含む。
class SecureItemEditSpec: QuickSpec {
    override class func spec() {
        valueCollectionSpecs()
        extendedKindPreservationSpecs()
        multilinePreviewSpecs()
        editFlowHistorySpecs()
        columnBehaviorSpecs()
        passwordMaskToggleSpecs()
    }

    /// 単一行セルで編集できない種別（メモ）が、既存の編集シートを通しても壊れないことを担保する。
    /// TOTP と同じ経路で「セルの空文字がモデルを上書きして本文が消える」事故が起きうる。
    private static func extendedKindPreservationSpecs() {
        describe("Extended kind preservation in the legacy edit sheet") {

            let memo = "契約番号: 12345-678\nサポート: 03-0000-0000"

            /// メモ・URL・通常フィールドを持つアイテムの編集シートを組み立てる
            func makeViewController() -> SecureItemEditViewController {
                let fields = [SecureMenuItem.Field(fieldID: "n1", label: "Memo", value: memo, kind: .note),
                              SecureMenuItem.Field(fieldID: "u1", label: "URL", value: "https://example.com", kind: .url),
                              SecureMenuItem.Field(fieldID: "p1", label: "ID", value: "user")]
                let item = SecureMenuItem(itemID: "extended", title: "Accounting", fields: fields)
                let viewController = SecureItemEditViewController(item: item)
                _ = viewController.view
                viewController.fieldsTable.reloadData()
                return viewController
            }

            it("Does not show the raw note value in the single line cell") {
                let viewController = makeViewController()
                let noteCell = viewController.fieldsTable.view(atColumn: 2, row: 0, makeIfNecessary: true) as? FieldValueCell
                // 値をセルに入れると編集で改行が失われるため、プレビューはプレースホルダーに出す
                expect(noteCell?.currentValue) == ""
                expect(noteCell?.plainField.isEditable) == false
                expect(noteCell?.plainField.placeholderString).to(contain("契約番号"))
            }

            // 中核の回帰テスト: 保存でメモ本文と改行が失われないこと
            it("Preserves the multiline note value through the edit sheet save") {
                let viewController = makeViewController()
                _ = viewController.fieldsTable.view(atColumn: 2, row: 0, makeIfNecessary: true)

                var saved: SecureMenuItem?
                viewController.onSave = { saved = $0 }
                viewController.perform(NSSelectorFromString("saveSheet"))

                expect(saved?.fields.first?.value) == memo
                expect(saved?.fields.first?.value.contains("\n")) == true
                expect(saved?.fields.first?.kind) == .note
            }

            it("Keeps the url kind and lets its value be edited in the cell") {
                let viewController = makeViewController()
                let urlCell = viewController.fieldsTable.view(atColumn: 2, row: 1, makeIfNecessary: true) as? FieldValueCell
                expect(urlCell?.currentValue) == "https://example.com"
                expect(urlCell?.plainField.isEditable) == true
                urlCell?.plainField.stringValue = "https://example.org/login"

                var saved: SecureMenuItem?
                viewController.onSave = { saved = $0 }
                viewController.perform(NSSelectorFromString("saveSheet"))

                expect(saved?.fields[1].value) == "https://example.org/login"
                expect(saved?.fields[1].kind) == .url
            }

            // メモは伏せ字にすると覚書として用を成さないため 🔒 を持たない
            it("Hides the password checkbox for a note row but keeps it for a url row") {
                let viewController = makeViewController()
                let table = viewController.fieldsTable
                let passCol = table.column(withIdentifier: SecureItemEditViewController.ColID.pass)

                let noteCheckbox = table.view(atColumn: passCol, row: 0, makeIfNecessary: true)?
                    .subviews.first(where: { $0 is NSButton })
                let urlCheckbox = table.view(atColumn: passCol, row: 1, makeIfNecessary: true)?
                    .subviews.first(where: { $0 is NSButton })

                expect(noteCheckbox?.isHidden) == true
                expect(urlCheckbox?.isHidden) == false
            }

            it("Hides the history button for a note row but keeps it for a url row") {
                let viewController = makeViewController()
                let table = viewController.fieldsTable
                let historyCol = table.column(withIdentifier: SecureItemEditViewController.ColID.history)

                let noteHistory = table.view(atColumn: historyCol, row: 0, makeIfNecessary: true)?
                    .subviews.first(where: { $0 is NSButton })
                let urlHistory = table.view(atColumn: historyCol, row: 1, makeIfNecessary: true)?
                    .subviews.first(where: { $0 is NSButton })

                expect(noteHistory?.isHidden) == true
                expect(urlHistory?.isHidden) == false
            }
        }
    }

    /// 複数行の値を単一行セルに出すためのプレビュー生成（純粋関数）
    private static func multilinePreviewSpecs() {
        describe("FieldValueCell.multilinePreview") {

            it("Shows the first line and marks that more lines follow") {
                expect(FieldValueCell.multilinePreview(for: "first\nsecond", isPassword: false)) == "first …"
            }

            it("Returns a single line unchanged") {
                expect(FieldValueCell.multilinePreview(for: "only line", isPassword: false)) == "only line"
            }

            it("Truncates a long first line") {
                let preview = FieldValueCell.multilinePreview(for: String(repeating: "a", count: 40), isPassword: false)
                expect(preview) == String(repeating: "a", count: 26) + "…"
            }

            it("Masks the preview when the field is marked as a password") {
                expect(FieldValueCell.multilinePreview(for: "secret\nlines", isPassword: true)) == "••••••••"
            }

            it("Returns an empty string for an empty value") {
                expect(FieldValueCell.multilinePreview(for: "", isPassword: false)) == ""
            }
        }
    }

    /// 不可視（🔒）チェックボックスの ON/OFF が値セルのマスク表示に反映されることを担保する。
    /// （実クリックはユニットテスト不可だが、ハンドラ経由のセル再構成は検証できる。
    ///  列番号の取り違えでセルが取得できず反映されないリグレッションを検出する）
    private static func passwordMaskToggleSpecs() {
        describe("Password mask checkbox reflection") {
            it("switches the value cell between secure and plain when toggled") {
                let field = SecureMenuItem.Field(fieldID: "p", label: "PW", value: "secret", isPassword: true)
                let item = SecureMenuItem(itemID: "mask", title: "T", fields: [field])
                let viewController = SecureItemEditViewController(item: item)
                _ = viewController.view
                let table = viewController.fieldsTable
                table.reloadData()

                let valueCol = table.column(withIdentifier: SecureItemEditViewController.ColID.value)
                let passCol  = table.column(withIdentifier: SecureItemEditViewController.ColID.pass)
                let valueCell = table.view(atColumn: valueCol, row: 0, makeIfNecessary: true) as? FieldValueCell

                // 初期状態（isPassword=true）: secureField 表示
                expect(valueCell?.secureField.isHidden) == false
                expect(valueCell?.plainField.isHidden) == true

                // チェックを外す → 平文（plainField）表示に即時切り替わる
                guard let passCell = table.view(atColumn: passCol, row: 0, makeIfNecessary: true),
                      let button = passCell.subviews.first(where: { $0 is NSButton }) as? NSButton else {
                    fail("checkbox button not found")
                    return
                }
                button.state = .off
                viewController.passwordCheckboxChanged(button)
                expect(valueCell?.secureField.isHidden) == true
                expect(valueCell?.plainField.isHidden) == false
                expect(valueCell?.plainField.stringValue) == "secret"

                // 再びチェック → secureField 表示へ戻り、値は保持される
                button.state = .on
                viewController.passwordCheckboxChanged(button)
                expect(valueCell?.secureField.isHidden) == false
                expect(valueCell?.plainField.isHidden) == true
                expect(valueCell?.secureField.stringValue) == "secret"
            }
        }
    }

    /// クリック時のシングルクリック編集・行ドラッグ許可の列判定（純粋関数）。
    /// UI 操作そのものはユニットテストできないため、対象列を決めるロジックだけを担保する
    private static func columnBehaviorSpecs() {
        describe("Column behavior predicates") {
            typealias EditVC = SecureItemEditViewController

            let allKinds: [SecureMenuItem.Field.Kind] = [.plain, .totp, .url, .note]

            it("always makes the label column editable") {
                for kind in allKinds {
                    expect(EditVC.isEditableColumn(EditVC.ColID.label, kind: kind)) == true
                }
            }

            // TOTP は secret を表示しない、メモは改行が失われるため、
            // いずれも単一行セルでは編集させない
            it("makes the value column editable only for plain and url") {
                expect(EditVC.isEditableColumn(EditVC.ColID.value, kind: .plain)) == true
                expect(EditVC.isEditableColumn(EditVC.ColID.value, kind: .url)) == true
                expect(EditVC.isEditableColumn(EditVC.ColID.value, kind: .totp)) == false
                expect(EditVC.isEditableColumn(EditVC.ColID.value, kind: .note)) == false
            }

            it("does not make button / drag-handle columns editable") {
                for kind in allKinds {
                    expect(EditVC.isEditableColumn(EditVC.ColID.dragHandle, kind: kind)) == false
                    expect(EditVC.isEditableColumn(EditVC.ColID.pass, kind: kind)) == false
                    expect(EditVC.isEditableColumn(EditVC.ColID.history, kind: kind)) == false
                }
            }

            it("allows row drag only from the drag-handle column") {
                expect(EditVC.allowsRowDrag(from: EditVC.ColID.dragHandle)) == true
                expect(EditVC.allowsRowDrag(from: EditVC.ColID.label)) == false
                expect(EditVC.allowsRowDrag(from: EditVC.ColID.value)) == false
                expect(EditVC.allowsRowDrag(from: EditVC.ColID.pass)) == false
                expect(EditVC.allowsRowDrag(from: EditVC.ColID.history)) == false
            }
        }
    }

    private static func valueCollectionSpecs() {
        describe("Edit sheet value collection") {

            it("Collects label and value from the correct columns") {
                let field = SecureMenuItem.Field(fieldID: "f1", label: "MyLabel", value: "MyValue")
                let item = SecureMenuItem(itemID: "collect", title: "Title", fields: [field])
                let viewController = SecureItemEditViewController(item: item)
                _ = viewController.view
                let table = viewController.fieldsTable
                table.reloadData()

                let labelCell = table.view(atColumn: 1, row: 0, makeIfNecessary: true) as? NSTableCellView
                let valueCell = table.view(atColumn: 2, row: 0, makeIfNecessary: true) as? FieldValueCell
                expect(labelCell?.textField?.stringValue) == "MyLabel"
                expect(valueCell?.currentValue) == "MyValue"

                // Value を書き換えて保存 → value に入り label / fieldID は変わらない
                valueCell?.plainField.stringValue = "NewValue"
                var saved: SecureMenuItem?
                viewController.onSave = { saved = $0 }
                viewController.perform(NSSelectorFromString("saveSheet"))
                expect(saved?.fields.first?.label) == "MyLabel"
                expect(saved?.fields.first?.value) == "NewValue"
                expect(saved?.fields.first?.fieldID) == "f1"
            }

            // TOTP の Value はセルに表示されない（セルの入力値は常に空）ため、
            // 保存時にセルから読むと秘密鍵が空文字で消えるリグレッションがあった。
            // 編集シート経由の保存で TOTP の value が無傷であることを担保する
            it("Preserves the TOTP value through the edit sheet save") {
                let uri = "otpauth://totp/GitHub:user?secret=GEZDGNBVGY3TQOJQ&issuer=GitHub"
                let totpField = SecureMenuItem.Field(fieldID: "t1", label: "GitHub 2FA", value: uri,
                                                     isPassword: false, kind: .totp)
                let plainField = SecureMenuItem.Field(fieldID: "p1", label: "ID", value: "user")
                let item = SecureMenuItem(itemID: "totp-save", title: "GitHub", fields: [totpField, plainField])
                let viewController = SecureItemEditViewController(item: item)
                _ = viewController.view
                viewController.fieldsTable.reloadData()
                // TOTP セルを生成させる（表示上は空・編集不可であることも確認）
                let totpCell = viewController.fieldsTable.view(atColumn: 2, row: 0, makeIfNecessary: true) as? FieldValueCell
                expect(totpCell?.currentValue) == ""

                var saved: SecureMenuItem?
                viewController.onSave = { saved = $0 }
                viewController.perform(NSSelectorFromString("saveSheet"))

                // TOTP の value はセルではなくモデルの値が保存される
                expect(saved?.fields.first?.value) == uri
                expect(saved?.fields.first?.kind) == .totp
                // 通常フィールドは従来どおりセルの値が保存される
                expect(saved?.fields.last?.value) == "user"
            }
        }
    }

    private static func editFlowHistorySpecs() {
        describe("Edit flow history") {

            // 編集シート → サービス保存の実経路で、履歴に Label ではなく旧 Value が入ることを担保する
            it("Stores the old value (not the label) into history through the edit flow") {
                let service = SecureMenuService(keychainService: "com.clipy-app.ClipyTests.SecureMenu.EditFlow")
                service.deleteAllItems()
                defer { service.deleteAllItems() }

                let field = SecureMenuItem.Field(label: "MyLabel", value: "value-1")
                _ = service.save(SecureMenuItem(itemID: "flow", title: "Item", fields: [field]))

                // 編集シートで Value のみ変更して保存する
                guard let loaded = service.loadAllItems().first else {
                    fail("failed to load saved item")
                    return
                }
                let viewController = SecureItemEditViewController(item: loaded)
                _ = viewController.view
                viewController.fieldsTable.reloadData()
                let valueCell = viewController.fieldsTable.view(atColumn: 2, row: 0, makeIfNecessary: true) as? FieldValueCell
                valueCell?.plainField.stringValue = "value-2"
                var saved: SecureMenuItem?
                viewController.onSave = { saved = $0 }
                viewController.perform(NSSelectorFromString("saveSheet"))

                expect(saved) != nil
                if let savedItem = saved {
                    _ = service.save(savedItem)
                }

                let history = service.loadAllItems().first?.fields.first?.history
                // 履歴に入るのは旧 Value（"value-1"）であり、Label（"MyLabel"）ではない
                expect(history?.map { $0.value }) == ["value-1"]
            }
        }
    }
}
