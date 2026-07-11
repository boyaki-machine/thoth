import Quick
import Nimble
import AppKit
@testable import Clipy

/// セキュアアイテム編集シートの値収集と、編集フロー経由の履歴記録を担保するスペック。
/// 「履歴に Label が表示される」リグレッションを検出するためのテストを含む。
class SecureItemEditSpec: QuickSpec {
    override func spec() {
        valueCollectionSpecs()
        editFlowHistorySpecs()
    }

    private func valueCollectionSpecs() {
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
        }
    }

    private func editFlowHistorySpecs() {
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
