import Quick
import Nimble
@testable import Clipy

class SecureMenuServiceSpec: QuickSpec {

    /// 本番エントリ (com.clipy-app.Clipy.SecureMenu) と分離したテスト専用の service 名
    private static let testKeychainService = "com.clipy-app.ClipyTests.SecureMenu"

    private var service: SecureMenuService!

    override func spec() {
        beforeEach {
            self.service = SecureMenuService(keychainService: SecureMenuServiceSpec.testKeychainService)
            self.service.deleteAllItems()
            self.service.deleteCryptoPassword()
        }
        afterEach {
            self.service.deleteAllItems()
            self.service.deleteCryptoPassword()
        }

        saveAndLoadSpecs()
        valueHistorySpecs()
        deleteSpecs()
        reorderSpecs()
        accessDeniedGuardSpecs()
        cryptoPasswordSpecs()
    }

    private func cryptoPasswordSpecs() {
        describe("Crypto password") {

            it("Is not registered initially") {
                expect(self.service.hasCryptoPassword()) == false
                expect(self.service.loadCryptoPassword()) == nil
            }

            it("Saves and loads the crypto password") {
                expect(self.service.saveCryptoPassword("my-fixed-pass")) == true
                expect(self.service.hasCryptoPassword()) == true
                expect(self.service.loadCryptoPassword()) == "my-fixed-pass"
            }

            it("Overwrites an existing crypto password") {
                _ = self.service.saveCryptoPassword("first")
                _ = self.service.saveCryptoPassword("second")
                expect(self.service.loadCryptoPassword()) == "second"
            }

            it("Deletes the crypto password") {
                _ = self.service.saveCryptoPassword("pass")
                expect(self.service.deleteCryptoPassword()) == true
                expect(self.service.hasCryptoPassword()) == false
                expect(self.service.loadCryptoPassword()) == nil
            }

            it("Is independent from secure items") {
                _ = self.service.save(SecureMenuItem(title: "Item"))
                _ = self.service.saveCryptoPassword("pass")
                // 一方を消してももう一方は残る
                self.service.deleteCryptoPassword()
                expect(self.service.loadAllItems().count) == 1
                expect(self.service.hasCryptoPassword()) == false
            }
        }
    }

    /// 保存済みアイテムを編集画面と同じ手順（読み込み→値変更→保存）で更新するヘルパー
    private func changeFirstFieldValue(itemID: String, to newValue: String) {
        guard let current = self.service.loadAllItems().first(where: { $0.itemID == itemID }),
              let field = current.fields.first else { return }
        let updatedField = SecureMenuItem.Field(fieldID: field.fieldID, label: field.label,
                                                value: newValue, isPassword: field.isPassword,
                                                history: field.history)
        let updated = SecureMenuItem(itemID: current.itemID, title: current.title,
                                     fields: [updatedField], displayOrder: current.displayOrder)
        _ = self.service.save(updated)
    }

    private func valueHistorySpecs() {
        describe("Value history") {

            it("Records the old value when a field value changes") {
                let original = SecureMenuItem(itemID: "history", title: "Item",
                                              fields: [SecureMenuItem.Field(label: "Password", value: "old-pass")])
                _ = self.service.save(original)
                self.changeFirstFieldValue(itemID: "history", to: "new-pass")

                let history = self.service.loadAllItems().first?.fields.first?.history
                expect(history?.count) == 1
                expect(history?.first?.value) == "old-pass"
                // 置き換えられた日時は保存時刻（直近）になっている
                expect(abs(history?.first?.replacedAt.timeIntervalSinceNow ?? 100)) < 10
            }

            it("Accumulates history across multiple changes") {
                let original = SecureMenuItem(itemID: "multi", title: "Item",
                                              fields: [SecureMenuItem.Field(label: "Key", value: "first")])
                _ = self.service.save(original)
                self.changeFirstFieldValue(itemID: "multi", to: "second")
                self.changeFirstFieldValue(itemID: "multi", to: "third")

                let history = self.service.loadAllItems().first?.fields.first?.history
                expect(history?.map { $0.value }) == ["first", "second"]
            }

            it("Does not record history when the value is unchanged") {
                let original = SecureMenuItem(itemID: "same", title: "Item",
                                              fields: [SecureMenuItem.Field(label: "Key", value: "value")])
                _ = self.service.save(original)
                self.changeFirstFieldValue(itemID: "same", to: "value")

                let history = self.service.loadAllItems().first?.fields.first?.history
                expect(history?.isEmpty) == true
            }

            it("History follows the field when the label changes") {
                // 履歴は Label ではなく fieldID（フィールドそのもの）に紐づく
                let field = SecureMenuItem.Field(fieldID: "stable-field", label: "Old Label", value: "v1")
                _ = self.service.save(SecureMenuItem(itemID: "rename", title: "Item", fields: [field]))

                let renamed = SecureMenuItem.Field(fieldID: "stable-field", label: "New Label", value: "v2",
                                                   history: field.history)
                _ = self.service.save(SecureMenuItem(itemID: "rename", title: "Item", fields: [renamed]))

                let loaded = self.service.loadAllItems().first?.fields.first
                expect(loaded?.label) == "New Label"
                expect(loaded?.history.map { $0.value }) == ["v1"]
            }

            it("Caps history at the maximum count dropping the oldest") {
                let original = SecureMenuItem(itemID: "cap", title: "Item",
                                              fields: [SecureMenuItem.Field(label: "Key", value: "v0")])
                _ = self.service.save(original)
                for index in 1...12 {
                    self.changeFirstFieldValue(itemID: "cap", to: "v\(index)")
                }

                let history = self.service.loadAllItems().first?.fields.first?.history
                expect(history?.count) == SecureMenuService.maxFieldHistoryCount
                // 古いもの（v0, v1）から自動削除され、直近 10 件が残る
                expect(history?.map { $0.value }) == (2...11).map { "v\($0)" }
            }

            it("Respects the incoming history so deletions are persisted") {
                // ポップアップから履歴を削除した状態で保存すると、削除が反映される
                let entries = [SecureMenuItem.FieldHistoryEntry(value: "v1", replacedAt: Date(timeIntervalSince1970: 1)),
                               SecureMenuItem.FieldHistoryEntry(value: "v2", replacedAt: Date(timeIntervalSince1970: 2))]
                let field = SecureMenuItem.Field(fieldID: "del", label: "Key", value: "v3", history: entries)
                _ = self.service.save(SecureMenuItem(itemID: "delete", title: "Item", fields: [field]))

                // v1 を削除した状態で保存し直す（値は変更しない）
                let deleted = SecureMenuItem.Field(fieldID: "del", label: "Key", value: "v3",
                                                   history: [entries[1]])
                _ = self.service.save(SecureMenuItem(itemID: "delete", title: "Item", fields: [deleted]))

                let history = self.service.loadAllItems().first?.fields.first?.history
                expect(history?.map { $0.value }) == ["v2"]
            }

            it("New fields start with empty history") {
                let original = SecureMenuItem(itemID: "fresh", title: "Item",
                                              fields: [SecureMenuItem.Field(label: "Key", value: "value")])
                _ = self.service.save(original)

                // 別 fieldID・別 Label のフィールドに置き換わった場合は履歴なし
                let replaced = SecureMenuItem(itemID: "fresh", title: "Item",
                                              fields: [SecureMenuItem.Field(label: "Another Key", value: "other")])
                _ = self.service.save(replaced)

                let history = self.service.loadAllItems().first?.fields.first?.history
                expect(history?.isEmpty) == true
            }
        }
    }

    private func saveAndLoadSpecs() {
        describe("Save and load") {

            it("Load returns empty when nothing is saved") {
                expect(self.service.loadAllItems()).to(beEmpty())
                expect(self.service.isKeychainAccessDenied) == false
            }

            it("Save new items assigns displayOrder in order") {
                expect(self.service.save(SecureMenuItem(title: "First"))) == true
                expect(self.service.save(SecureMenuItem(title: "Second"))) == true

                let loaded = self.service.loadAllItems()
                expect(loaded.count) == 2
                expect(loaded[0].title) == "First"
                expect(loaded[0].displayOrder) == 0
                expect(loaded[1].title) == "Second"
                expect(loaded[1].displayOrder) == 1
            }

            it("Save existing itemID overwrites the item") {
                let original = SecureMenuItem(itemID: "fixed-id", title: "Before",
                                              fields: [SecureMenuItem.Field(label: "ID", value: "old")])
                expect(self.service.save(original)) == true

                let updated = SecureMenuItem(itemID: "fixed-id", title: "After",
                                             fields: [SecureMenuItem.Field(label: "ID", value: "new", isPassword: true)])
                expect(self.service.save(updated)) == true

                let loaded = self.service.loadAllItems()
                expect(loaded.count) == 1
                expect(loaded.first?.title) == "After"
                expect(loaded.first?.fields.count) == 1
                expect(loaded.first?.fields.first?.value) == "new"
                expect(loaded.first?.fields.first?.isPassword) == true
            }

            it("Load returns items sorted by displayOrder") {
                _ = self.service.save(SecureMenuItem(itemID: "a", title: "A"))
                _ = self.service.save(SecureMenuItem(itemID: "b", title: "B"))
                _ = self.service.save(SecureMenuItem(itemID: "c", title: "C"))
                // displayOrder を逆順に並べ替えてから読み直す
                let reversed = self.service.loadAllItems().reversed()
                expect(self.service.reorderItems(Array(reversed))) == true

                let loaded = self.service.loadAllItems()
                expect(loaded.map { $0.title }) == ["C", "B", "A"]
            }

            it("Fields survive the keychain round trip") {
                let fields = [SecureMenuItem.Field(label: "ID", value: "user", isPassword: false),
                              SecureMenuItem.Field(label: "Password", value: "s3cr3t", isPassword: true)]
                _ = self.service.save(SecureMenuItem(itemID: "round-trip", title: "GitHub", fields: fields))

                let loaded = self.service.loadAllItems().first
                expect(loaded?.fields.count) == 2
                expect(loaded?.fields[0].label) == "ID"
                expect(loaded?.fields[0].value) == "user"
                expect(loaded?.fields[1].label) == "Password"
                expect(loaded?.fields[1].value) == "s3cr3t"
                expect(loaded?.fields[1].isPassword) == true
            }
        }
    }

    private func deleteSpecs() {
        describe("Delete") {

            it("Delete single item by itemID") {
                _ = self.service.save(SecureMenuItem(itemID: "keep", title: "Keep"))
                _ = self.service.save(SecureMenuItem(itemID: "remove", title: "Remove"))

                expect(self.service.delete(itemID: "remove")) == true

                let loaded = self.service.loadAllItems()
                expect(loaded.count) == 1
                expect(loaded.first?.itemID) == "keep"
            }

            it("Delete multiple items at once") {
                _ = self.service.save(SecureMenuItem(itemID: "one", title: "One"))
                _ = self.service.save(SecureMenuItem(itemID: "two", title: "Two"))
                _ = self.service.save(SecureMenuItem(itemID: "three", title: "Three"))

                expect(self.service.delete(itemIDs: ["one", "three"])) == true

                let loaded = self.service.loadAllItems()
                expect(loaded.count) == 1
                expect(loaded.first?.itemID) == "two"
            }

            it("Delete unknown itemID keeps existing items") {
                _ = self.service.save(SecureMenuItem(itemID: "keep", title: "Keep"))

                expect(self.service.delete(itemID: "unknown")) == true
                expect(self.service.loadAllItems().count) == 1
            }

            it("Delete all items removes the entry") {
                _ = self.service.save(SecureMenuItem(title: "Item"))

                expect(self.service.deleteAllItems()) == true
                expect(self.service.loadAllItems()).to(beEmpty())
            }
        }
    }

    private func reorderSpecs() {
        describe("Reorder") {

            it("Rearranges displayOrder to match the given order") {
                _ = self.service.save(SecureMenuItem(itemID: "a", title: "A"))
                _ = self.service.save(SecureMenuItem(itemID: "b", title: "B"))
                _ = self.service.save(SecureMenuItem(itemID: "c", title: "C"))
                let items = self.service.loadAllItems()

                let newOrder = [items[2], items[0], items[1]]
                expect(self.service.reorderItems(newOrder)) == true

                let loaded = self.service.loadAllItems()
                expect(loaded.map { $0.itemID }) == ["c", "a", "b"]
                expect(loaded.map { $0.displayOrder }) == [0, 1, 2]
            }
        }
    }

    private func accessDeniedGuardSpecs() {
        describe("Keychain access denied guard") {

            // バイナリ更新等で Keychain の読み出しが拒否された状態で保存すると、
            // 読めなかった既存データを上書き消去してしまうため、保存が拒否されることを担保する
            it("Rejects write while access is denied") {
                _ = self.service.save(SecureMenuItem(itemID: "existing", title: "Existing"))

                self.service.isKeychainAccessDenied = true
                expect(self.service.reorderItems([SecureMenuItem(title: "New")])) == false

                // 読み出しに成功するとフラグは解除され、既存データは無傷で保存も可能になる
                let loaded = self.service.loadAllItems()
                expect(loaded.count) == 1
                expect(loaded.first?.itemID) == "existing"
                expect(self.service.isKeychainAccessDenied) == false
                expect(self.service.reorderItems(loaded)) == true
            }

            it("Successful load resets the denied flag") {
                self.service.isKeychainAccessDenied = true
                _ = self.service.loadAllItems()
                expect(self.service.isKeychainAccessDenied) == false
            }
        }
    }
}
