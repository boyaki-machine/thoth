import Foundation
import Security
import Quick
import Nimble
@testable import Thoth

// BDD スペックは多数の it ブロックを含み型本体が長くなるため型長ルールを緩める
class SecureMenuServiceSpec: QuickSpec {

    /// 本番エントリ (com.clipy-app.Clipy.SecureMenu) と分離したテスト専用の service 名
    static let testKeychainService = "io.github.boyaki-machine.ThothTests.SecureMenu"

    static var service: SecureMenuService!

    override class func spec() {
        beforeEach {
            // 破損データを書き込むテストの後でも確実にクリーンな状態から始める。
            // deleteAllItems() / deleteCryptoPassword() は破損状態では
            // 意図的に失敗するため、後片付けには使えない
            self.removeAllEntriesDirectly()
            self.service = SecureMenuService(keychainService: SecureMenuServiceSpec.testKeychainService)
            self.service.deleteAllItems()
            self.service.deleteCryptoPassword()
        }
        afterEach {
            self.service.deleteAllItems()
            self.service.deleteCryptoPassword()
            self.removeAllEntriesDirectly()
        }

        saveAndLoadSpecs()
        valueHistorySpecs()
        deleteSpecs()
        reorderSpecs()
        accessDeniedGuardSpecs()
        authenticationLifetimeSpecs()
        corruptedDataGuardSpecs()
        cryptoPasswordSpecs()
        totpFieldSpecs()
        authenticationGraceSpecs()
        legacyMigrationSpecs()
    }

    /// 旧形式（all-items / crypto-password の 2 エントリ）を直接 Keychain に書き込むヘルパー
    static func addLegacyEntry(account: String, data: Data) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: SecureMenuServiceSpec.testKeychainService,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: data
        ]
        SecItemDelete(query as CFDictionary)
        expect(SecItemAdd(query as CFDictionary, nil)) == errSecSuccess
    }

    /// Keychain エントリを直接削除する。破損データを書き込んだテストの後始末用
    /// （サービス側の削除 API は破損状態では意図的に失敗するため使えない）
    static func removeEntryDirectly(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: SecureMenuServiceSpec.testKeychainService,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func removeAllEntriesDirectly() {
        ["user-data", "all-items", "crypto-password"].forEach { removeEntryDirectly(account: $0) }
    }

    /// Keychain に実際に保存されている生バイト列を読み出す。
    /// 「保存が拒否され、既存データが書き換わっていない」ことの検証に使う
    static func rawEntryData(account: String) -> Data? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: SecureMenuServiceSpec.testKeychainService,
            kSecAttrAccount as String: account
        ]
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    static func legacyEntryExists(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: SecureMenuServiceSpec.testKeychainService,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    static func legacyMigrationSpecs() {
        describe("Legacy entry migration") {

            // 旧形式（all-items + crypto-password の 2 エントリ）から
            // user-data（1 エントリ）への遅延移行を担保する
            it("Migrates legacy all-items and crypto-password entries into user-data") {
                let items = [SecureMenuItem(itemID: "legacy-1", title: "Legacy Item",
                                            fields: [SecureMenuItem.Field(label: "PW", value: "s3cr3t", isPassword: true)])]
                self.addLegacyEntry(account: "all-items", data: try! JSONEncoder().encode(items))
                self.addLegacyEntry(account: "crypto-password", data: Data("legacy-crypto-pass".utf8))

                // 初回アクセスで移行され、内容が無傷であること
                let loaded = self.service.loadAllItems()
                expect(loaded.count) == 1
                expect(loaded.first?.title) == "Legacy Item"
                expect(loaded.first?.fields.first?.value) == "s3cr3t"
                expect(self.service.loadCryptoPassword()) == "legacy-crypto-pass"

                // 検証済み移行が完了し、旧エントリは削除されている
                expect(self.legacyEntryExists(account: "all-items")) == false
                expect(self.legacyEntryExists(account: "crypto-password")) == false
            }

            it("Migrates items-only legacy entry (no crypto password)") {
                let items = [SecureMenuItem(itemID: "legacy-2", title: "Items Only")]
                self.addLegacyEntry(account: "all-items", data: try! JSONEncoder().encode(items))

                expect(self.service.loadAllItems().first?.title) == "Items Only"
                expect(self.service.hasCryptoPassword()) == false
                expect(self.legacyEntryExists(account: "all-items")) == false
            }

            it("Preserves crypto password when saving items and vice versa (single entry)") {
                _ = self.service.saveCryptoPassword("keep-me")
                _ = self.service.save(SecureMenuItem(title: "Item A"))
                expect(self.service.loadCryptoPassword()) == "keep-me"

                _ = self.service.saveCryptoPassword("updated")
                expect(self.service.loadAllItems().count) == 1
                expect(self.service.loadCryptoPassword()) == "updated"
            }

            // TOTP は再登録に各サービスの 2FA 設定をやり直す手間がかかるため、
            // 移行経路で secret がそのまま引き継がれることを明示的に担保する
            it("Carries TOTP secrets through the legacy migration untouched") {
                let secret = "otpauth://totp/GitHub:user?secret=JBSWY3DPEHPK3PXP&issuer=GitHub"
                let items = [SecureMenuItem(itemID: "legacy-totp", title: "GitHub",
                                            fields: [SecureMenuItem.Field(label: "TOTP", value: secret, kind: .totp)])]
                self.addLegacyEntry(account: "all-items", data: try! JSONEncoder().encode(items))

                let migrated = self.service.loadAllItems()
                expect(migrated.first?.fields.first?.value) == secret
                expect(migrated.first?.fields.first?.isTOTP) == true
                // 移行後に別アイテムを保存しても secret は書き換わらない
                _ = self.service.save(SecureMenuItem(title: "Another"))
                expect(self.service.loadAllItems().first { $0.itemID == "legacy-totp" }?
                        .fields.first?.value) == secret
            }

            // 旧エントリを解釈できない場合、空の items で移行を完了させてはならない。
            // 以前は空データを書き込んだうえで読み戻し検証（空でも成功する）を通過し、
            // 旧エントリを削除していたため、アップグレード時にデータが完全に失われた
            it("Aborts the migration and keeps the legacy entry when it cannot be decoded") {
                self.addLegacyEntry(account: "all-items", data: Data("not json at all".utf8))

                expect(self.service.loadAllItems()).to(beEmpty())
                expect(self.service.isKeychainAccessDenied) == true
                // 旧エントリは削除されずに残っている（あとから救出できる）
                expect(self.legacyEntryExists(account: "all-items")) == true
                // 新エントリは作られていない
                expect(self.rawEntryData(account: "user-data")) == nil
                // 読めない状態なので保存も拒否される
                expect(self.service.save(SecureMenuItem(title: "New"))) == false
                expect(self.legacyEntryExists(account: "all-items")) == true
            }
        }
    }

    static func cryptoPasswordSpecs() {
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
    static func changeFirstFieldValue(itemID: String, to newValue: String) {
        guard let current = self.service.loadAllItems().first(where: { $0.itemID == itemID }),
              let field = current.fields.first else {
            fail("更新対象のアイテム（\(itemID)）またはそのフィールドが読み出せない")
            return
        }
        let updatedField = SecureMenuItem.Field(fieldID: field.fieldID, label: field.label,
                                                value: newValue, isPassword: field.isPassword,
                                                history: field.history)
        let updated = SecureMenuItem(itemID: current.itemID, title: current.title,
                                     fields: [updatedField], displayOrder: current.displayOrder)
        _ = self.service.save(updated)
    }

    static func valueHistorySpecs() {
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

            /// 値を 1 度置き換えたあとの履歴を返す
            func historyAfterValueChange(kind: SecureMenuItem.Field.Kind) -> [SecureMenuItem.FieldHistoryEntry] {
                let original = SecureMenuItem.Field(label: "Field", value: "before", kind: kind)
                _ = self.service.save(SecureMenuItem(itemID: "kinded", title: "Item", fields: [original]))
                _ = self.service.save(SecureMenuItem(itemID: "kinded", title: "Item",
                                                     fields: [original.updating(value: "after")]))
                let saved = self.service.loadAllItems().first?.fields.first
                expect(saved?.value) == "after"
                expect(saved?.kind) == kind
                return saved?.history ?? []
            }

            // URL は通常のテキストと同じく、変更前の値をたどれると役に立つ
            it("Records history for url fields") {
                expect(historyAfterValueChange(kind: .url).map { $0.value }) == ["before"]
            }

            // メモは長文が履歴メニューの 1 行表示を壊し、
            // 上限 10 件を推敲だけで使い切ってしまうため履歴を残さない
            it("Does not record history for note fields") {
                expect(historyAfterValueChange(kind: .note)).to(beEmpty())
            }

            // secret が極めて機微なため、TOTP は従来どおり履歴を残さない
            it("Does not record history for totp fields") {
                expect(historyAfterValueChange(kind: .totp)).to(beEmpty())
            }

            it("Records history for plain fields") {
                expect(historyAfterValueChange(kind: .plain).map { $0.value }) == ["before"]
            }
        }
    }
}
