import Quick
import Nimble
@testable import Thoth

class SecureMenuItemSpec: QuickSpec {
    override class func spec() {
        secureMenuItemSpecs()
        codableCompatibilitySpecs()
        fieldSelectionSpecs()
        selectionContextSpecs()
    }

    private static func secureMenuItemSpecs() {
        describe("SecureMenuItem") {

            it("Create item with default values") {
                let item = SecureMenuItem(title: "GitHub")
                expect(UUID(uuidString: item.itemID)) != nil
                expect(item.title) == "GitHub"
                expect(item.fields.isEmpty) == true
                expect(item.displayOrder) == 0
            }

            it("Create item with explicit values") {
                let field = SecureMenuItem.Field(label: "Password", value: "s3cr3t", isPassword: true)
                let item = SecureMenuItem(itemID: "fixed-id", title: "AWS", fields: [field], displayOrder: 5)
                expect(item.itemID) == "fixed-id"
                expect(item.title) == "AWS"
                expect(item.fields.count) == 1
                expect(item.displayOrder) == 5
            }

            it("Create field with default values") {
                let field = SecureMenuItem.Field(label: "ID", value: "user")
                expect(field.label) == "ID"
                expect(field.value) == "user"
                expect(field.isPassword) == false
            }
        }
    }

    private static func codableCompatibilitySpecs() {
        describe("Codable compatibility") {

            it("Encode and decode round trip") {
                let fields = [SecureMenuItem.Field(label: "ID", value: "user", isPassword: false),
                              SecureMenuItem.Field(label: "Password", value: "s3cr3t", isPassword: true)]
                let item = SecureMenuItem(itemID: "round-trip-id", title: "GitHub", fields: fields, displayOrder: 3)

                let data = try! JSONEncoder().encode([item])
                let decoded = try! JSONDecoder().decode([SecureMenuItem].self, from: data)

                expect(decoded.count) == 1
                expect(decoded.first?.itemID) == "round-trip-id"
                expect(decoded.first?.title) == "GitHub"
                expect(decoded.first?.displayOrder) == 3
                expect(decoded.first?.fields.count) == 2
                expect(decoded.first?.fields[0].label) == "ID"
                expect(decoded.first?.fields[0].value) == "user"
                expect(decoded.first?.fields[0].isPassword) == false
                expect(decoded.first?.fields[1].label) == "Password"
                expect(decoded.first?.fields[1].value) == "s3cr3t"
                expect(decoded.first?.fields[1].isPassword) == true
            }

            // fieldID / history キーを持たない旧形式のデータも読み込めることを担保する（後方互換）
            it("Decode legacy format without fieldID and history keys") {
                let json = """
                [{"itemID":"legacy-id","title":"Legacy","displayOrder":0,
                  "fields":[{"label":"ID","value":"user","isPassword":false}]}]
                """
                let decoded = try! JSONDecoder().decode([SecureMenuItem].self, from: json.data(using: .utf8)!)
                expect(decoded.first?.fields.first?.history.isEmpty) == true
                // fieldID は自動採番される
                expect(UUID(uuidString: decoded.first?.fields.first?.fieldID ?? "")) != nil
            }

            it("History entries survive the round trip") {
                let history = [SecureMenuItem.FieldHistoryEntry(value: "old-1", replacedAt: Date(timeIntervalSince1970: 1_000)),
                               SecureMenuItem.FieldHistoryEntry(value: "old-2", replacedAt: Date(timeIntervalSince1970: 2_000))]
                let field = SecureMenuItem.Field(label: "Password", value: "current", isPassword: true, history: history)
                let item = SecureMenuItem(itemID: "history-id", title: "Item", fields: [field])

                let data = try! JSONEncoder().encode([item])
                let decoded = try! JSONDecoder().decode([SecureMenuItem].self, from: data)

                let decodedHistory = decoded.first?.fields.first?.history
                expect(decodedHistory?.count) == 2
                expect(decodedHistory?[0].value) == "old-1"
                expect(decodedHistory?[0].replacedAt) == Date(timeIntervalSince1970: 1_000)
                expect(decodedHistory?[1].value) == "old-2"
            }

            // Keychain 保存形式および Export/Import ファイル形式との互換性を担保する。
            // このテストが落ちる変更（プロパティ名の変更など）は既存の保存データや
            // エクスポート済みファイルが読めなくなるため、マイグレーションの検討が必要。
            it("Decode fixed persistence format") {
                let json = """
                [{"itemID":"11111111-2222-3333-4444-555555555555","title":"GitHub","displayOrder":2,
                  "fields":[{"label":"ID","value":"user","isPassword":false},
                            {"label":"Password","value":"s3cr3t","isPassword":true}]}]
                """
                let decoded = try! JSONDecoder().decode([SecureMenuItem].self, from: json.data(using: .utf8)!)

                expect(decoded.count) == 1
                expect(decoded.first?.itemID) == "11111111-2222-3333-4444-555555555555"
                expect(decoded.first?.title) == "GitHub"
                expect(decoded.first?.displayOrder) == 2
                expect(decoded.first?.fields.count) == 2
                expect(decoded.first?.fields[1].isPassword) == true
            }

            it("Encode emits stable JSON keys") {
                let item = SecureMenuItem(itemID: "key-check", title: "Title",
                                          fields: [SecureMenuItem.Field(label: "L", value: "V")], displayOrder: 0)
                let data = try! JSONEncoder().encode(item)
                let object = (try! JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]

                expect(Set(object.keys)) == Set(["itemID", "title", "fields", "displayOrder"])
                let fieldObject = (object["fields"] as? [[String: Any]])?.first ?? [:]
                expect(Set(fieldObject.keys)) == Set(["fieldID", "label", "value", "isPassword", "kind", "history", "createdAt"])
            }
        }
    }

    private static func fieldSelectionSpecs() {
        describe("SecureFieldSelection") {
            it("Store selection values") {
                let selection = SecureFieldSelection(parentItemID: "parent-id", fieldValue: "s3cr3t", fieldIndex: 1)
                expect(selection.parentItemID) == "parent-id"
                expect(selection.fieldValue) == "s3cr3t"
                expect(selection.fieldIndex) == 1
            }
        }
    }

    private static func selectionContextSpecs() {
        describe("SecureSelectionContext") {

            it("Initial state is outside the window") {
                let context = SecureSelectionContext()
                expect(context.isWithinWindow) == false
                expect(context.lastParentItemID) == nil
                expect(context.lastFieldIndex) == nil
                expect(context.lastSelectedDate) == nil
            }

            it("Record selection enters the window") {
                let context = SecureSelectionContext()
                context.record(parentItemID: "parent-id", fieldIndex: 2)
                expect(context.isWithinWindow) == true
                expect(context.lastParentItemID) == "parent-id"
                expect(context.lastFieldIndex) == 2
                expect(context.lastSelectedDate) != nil
            }

            it("Clear selection leaves the window") {
                let context = SecureSelectionContext()
                context.record(parentItemID: "parent-id", fieldIndex: 0)
                context.clear()
                expect(context.isWithinWindow) == false
                expect(context.lastParentItemID) == nil
                expect(context.lastFieldIndex) == nil
                expect(context.lastSelectedDate) == nil
            }

            it("Recency window is 30 seconds") {
                // 「継続ペーストモード」の仕様値。変更時はドキュメントも更新すること
                expect(SecureSelectionContext.recencyWindow) == 30
            }
        }
    }
}
