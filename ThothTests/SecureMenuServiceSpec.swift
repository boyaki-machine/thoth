import Quick
import Nimble
@testable import Thoth

// BDD スペックは多数の it ブロックを含み型本体が長くなるため型長ルールを緩める
// swiftlint:disable:next type_body_length
class SecureMenuServiceSpec: QuickSpec {

    /// 本番エントリ (com.clipy-app.Clipy.SecureMenu) と分離したテスト専用の service 名
    private static let testKeychainService = "io.github.boyaki-machine.ThothTests.SecureMenu"

    private static var service: SecureMenuService!

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
        corruptedDataGuardSpecs()
        cryptoPasswordSpecs()
        totpFieldSpecs()
        legacyMigrationSpecs()
    }

    /// 旧形式（all-items / crypto-password の 2 エントリ）を直接 Keychain に書き込むヘルパー
    private static func addLegacyEntry(account: String, data: Data) {
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
    private static func removeEntryDirectly(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: SecureMenuServiceSpec.testKeychainService,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    private static func removeAllEntriesDirectly() {
        ["user-data", "all-items", "crypto-password"].forEach { removeEntryDirectly(account: $0) }
    }

    /// Keychain に実際に保存されている生バイト列を読み出す。
    /// 「保存が拒否され、既存データが書き換わっていない」ことの検証に使う
    private static func rawEntryData(account: String) -> Data? {
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

    private static func legacyEntryExists(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: SecureMenuServiceSpec.testKeychainService,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    private static func legacyMigrationSpecs() {
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

                expect(self.service.loadAllItems().isEmpty) == true
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

    private static func cryptoPasswordSpecs() {
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
    private static func changeFirstFieldValue(itemID: String, to newValue: String) {
        guard let current = self.service.loadAllItems().first(where: { $0.itemID == itemID }),
              let field = current.fields.first else { return }
        let updatedField = SecureMenuItem.Field(fieldID: field.fieldID, label: field.label,
                                                value: newValue, isPassword: field.isPassword,
                                                history: field.history)
        let updated = SecureMenuItem(itemID: current.itemID, title: current.title,
                                     fields: [updatedField], displayOrder: current.displayOrder)
        _ = self.service.save(updated)
    }

    private static func valueHistorySpecs() {
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

    private static func saveAndLoadSpecs() {
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

    private static func deleteSpecs() {
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

    private static func reorderSpecs() {
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

    private static func accessDeniedGuardSpecs() {
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

    // MARK: - Corrupted Data Guard

    /// 「Keychain の読み出しには成功したが、内容を解釈できない」場合のガード。
    ///
    /// 以前はこの状態で `errSecSuccess` + nil が返り、呼び出し側のガードを素通りして
    /// 「アイテム 0 件」と解釈されていた。その直後に保存を行うと、読めなかった
    /// データを空で上書きして全アイテム（TOTP secret を含む）と指紋パスワードが
    /// 失われた。破損は「読めなかった」と同義に扱い、書き込みを禁止する。
    private static func corruptedDataGuardSpecs() {
        describe("Corrupted data guard") {

            /// user-data エントリを解釈不能なバイト列で置き換える
            func corruptUserDataEntry() {
                self.addLegacyEntry(account: "user-data", data: Data("{ this is not valid json".utf8))
            }

            it("Reports unreadable state when the stored data cannot be decoded") {
                expect(self.service.save(SecureMenuItem(title: "Existing"))) == true
                corruptUserDataEntry()

                expect(self.service.loadAllItems().isEmpty) == true
                expect(self.service.isKeychainAccessDenied) == true
            }

            // 中核の回帰テスト: 破損状態での保存が既存データを破壊しないこと
            it("Rejects save and leaves the stored bytes untouched") {
                expect(self.service.save(SecureMenuItem(title: "Existing"))) == true
                corruptUserDataEntry()
                let before = self.rawEntryData(account: "user-data")

                expect(self.service.save(SecureMenuItem(title: "Should not be written"))) == false
                expect(self.rawEntryData(account: "user-data")) == before
            }

            it("Rejects every mutating operation while the data is unreadable") {
                corruptUserDataEntry()
                let before = self.rawEntryData(account: "user-data")

                expect(self.service.save(SecureMenuItem(title: "New"))) == false
                expect(self.service.delete(itemID: "anything")) == false
                expect(self.service.reorderItems([SecureMenuItem(title: "New")])) == false
                expect(self.service.deleteAllItems()) == false
                // 指紋パスワードの保存も user-data の read-modify-write なので同じく拒否される
                expect(self.service.saveCryptoPassword("new-password")) == false
                expect(self.service.deleteCryptoPassword()) == false

                expect(self.rawEntryData(account: "user-data")) == before
            }

            it("Recovers once the stored data becomes readable again") {
                corruptUserDataEntry()
                expect(self.service.loadAllItems().isEmpty) == true
                expect(self.service.isKeychainAccessDenied) == true

                self.removeEntryDirectly(account: "user-data")
                expect(self.service.loadAllItems().isEmpty) == true
                expect(self.service.isKeychainAccessDenied) == false
                expect(self.service.save(SecureMenuItem(title: "After recovery"))) == true
                expect(self.service.loadAllItems().first?.title) == "After recovery"
            }

            // バージョンアップ／ダウングレードで最も怖い経路。
            // 新しいバージョンが書いた未知の kind を古いバイナリが読んだ状況を再現する。
            // 読めるか読めないかは実装によって変わってよいが、
            // 「保存済みの TOTP secret が失われる」ことは決してあってはならない。
            it("Never destroys a stored TOTP secret when the field kind is unknown") {
                let json = """
                {"version":2,"items":[{"itemID":"future-1","title":"Future","displayOrder":0,
                 "fields":[{"fieldID":"f1","label":"TOTP","value":"JBSWY3DPEHPK3PXP","isPassword":false,
                 "kind":"kind-from-the-future","history":[],"createdAt":0}]}],
                 "cryptoPassword":"fingerprint-password"}
                """
                self.addLegacyEntry(account: "user-data", data: Data(json.utf8))

                _ = self.service.loadAllItems()
                _ = self.service.save(SecureMenuItem(title: "Added after reading unknown data"))
                _ = self.service.saveCryptoPassword("overwrite-attempt")

                let stored = String(data: self.rawEntryData(account: "user-data") ?? Data(), encoding: .utf8) ?? ""
                expect(stored).to(contain("JBSWY3DPEHPK3PXP"))
                expect(stored).to(contain("fingerprint-password"))
            }
        }
    }

    // MARK: - TOTP Field Tests (A-2)

    private static func totpFieldSpecs() {
        describe("TOTP field management") {

            it("Saves and loads a TOTP field correctly") {
                let otpauthURI = "otpauth://totp/GitHub:user@example.com?secret=GEZDGNBVGY3TQOJQ&issuer=GitHub"
                let totpField = SecureMenuItem.Field(label: "GitHub TOTP", value: otpauthURI, kind: .totp)
                let item = SecureMenuItem(itemID: "github-totp", title: "GitHub Account", fields: [totpField])

                expect(self.service.save(item)) == true

                let loaded = self.service.loadAllItems()
                expect(loaded.count) == 1
                expect(loaded[0].fields.count) == 1
                expect(loaded[0].fields[0].label) == "GitHub TOTP"
                expect(loaded[0].fields[0].value) == otpauthURI
                expect(loaded[0].fields[0].isTOTP) == true
                expect(loaded[0].fields[0].kind) == .totp
            }

            it("Preserves TOTP createdAt timestamp through save/load cycle") {
                let fixedDate = Date(timeIntervalSince1970: 1234567890)
                let totpField = SecureMenuItem.Field(label: "Test TOTP", value: "otpauth://...", kind: .totp, createdAt: fixedDate)
                let item = SecureMenuItem(itemID: "test-totp", title: "Test", fields: [totpField])

                expect(self.service.save(item)) == true

                let loaded = self.service.loadAllItems()
                expect(loaded[0].fields[0].createdAt.timeIntervalSince1970) == fixedDate.timeIntervalSince1970
            }

            it("Handles multiple TOTP fields in a single item") {
                let field1 = SecureMenuItem.Field(label: "GitHub", value: "otpauth://totp/GitHub?secret=ABC", kind: .totp)
                let field2 = SecureMenuItem.Field(label: "AWS", value: "otpauth://totp/AWS?secret=DEF", kind: .totp)
                let field3 = SecureMenuItem.Field(label: "Password", value: "secret123", isPassword: true)
                let item = SecureMenuItem(itemID: "multi-totp", title: "Multi Auth", fields: [field1, field2, field3])

                expect(self.service.save(item)) == true

                let loaded = self.service.loadAllItems()
                let fields = loaded[0].fields
                expect(fields.count) == 3
                expect(fields[0].isTOTP) == true
                expect(fields[1].isTOTP) == true
                expect(fields[2].isTOTP) == false
                expect(fields[2].isPassword) == true
            }

            it("Preserves TOTP URI parameters through encryption/decryption") {
                let uriWithAllParams = "otpauth://totp/Example:alice@example.com?secret=JBSWY3DPEHPK3PXP&issuer=Example&algorithm=SHA256&digits=8&period=60"
                let field = SecureMenuItem.Field(label: "Complex TOTP", value: uriWithAllParams, kind: .totp)
                let item = SecureMenuItem(itemID: "complex", title: "Complex", fields: [field])

                expect(self.service.save(item)) == true

                let loaded = self.service.loadAllItems()
                expect(loaded[0].fields[0].value) == uriWithAllParams
            }

            it("Updates TOTP field while preserving type") {
                let field1 = SecureMenuItem.Field(label: "Old TOTP", value: "otpauth://old", kind: .totp)
                var item = SecureMenuItem(itemID: "update-totp", title: "Test", fields: [field1])
                _ = self.service.save(item)

                // Update: change value but keep TOTP type
                let field2 = SecureMenuItem.Field(fieldID: field1.fieldID, label: "Updated TOTP",
                                                  value: "otpauth://new", isPassword: false, kind: .totp,
                                                  history: field1.history, createdAt: field1.createdAt)
                item = SecureMenuItem(itemID: "update-totp", title: "Test", fields: [field2])
                expect(self.service.save(item)) == true

                let loaded = self.service.loadAllItems()
                expect(loaded[0].fields[0].label) == "Updated TOTP"
                expect(loaded[0].fields[0].value) == "otpauth://new"
                expect(loaded[0].fields[0].kind) == .totp
            }

            it("Reorders items containing TOTP fields correctly") {
                let totpField = SecureMenuItem.Field(label: "TOTP", value: "otpauth://...", kind: .totp)
                let item1 = SecureMenuItem(itemID: "totp-1", title: "First", fields: [totpField])
                let item2 = SecureMenuItem(itemID: "other", title: "Second", fields: [])

                _ = self.service.save(item1)
                _ = self.service.save(item2)

                let items = self.service.loadAllItems()
                let reordered = [items[1], items[0]]
                expect(self.service.reorderItems(reordered)) == true

                let loaded = self.service.loadAllItems()
                expect(loaded[0].itemID) == "other"
                expect(loaded[1].itemID) == "totp-1"
                expect(loaded[1].fields[0].kind) == .totp
            }

            it("Deletes TOTP field correctly via item update") {
                let totpField = SecureMenuItem.Field(label: "TOTP", value: "otpauth://...", kind: .totp)
                let plainField = SecureMenuItem.Field(label: "Username", value: "alice")
                var item = SecureMenuItem(itemID: "delete-totp", title: "Test", fields: [totpField, plainField])
                _ = self.service.save(item)

                // Remove TOTP field, keep plain field
                item = SecureMenuItem(itemID: "delete-totp", title: "Test", fields: [plainField])
                expect(self.service.save(item)) == true

                let loaded = self.service.loadAllItems()
                expect(loaded[0].fields.count) == 1
                expect(loaded[0].fields[0].label) == "Username"
                expect(loaded[0].fields[0].isTOTP) == false
            }
        }

        // ※ 猶予期間「外」の経路は実際の Touch ID / パスワードプロンプトが
        //   表示されてしまうため、ここでは猶予期間「内」の省略動作のみを検証する
        describe("Authentication grace period") {

            it("Skips re-authentication within the grace period") {
                self.service.lastAuthenticatedDate = Date()
                var result: Bool?
                waitUntil { done in
                    self.service.authenticate(reason: "test") { success in
                        result = success
                        done()
                    }
                }
                expect(result) == true
            }

            it("Grace period is 30 seconds") {
                // 仕様値。変更時は README / ドックコメントも更新すること
                expect(SecureMenuService.authenticationGracePeriod) == 30
            }
        }
    }
}
