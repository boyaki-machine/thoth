import Foundation
import Security
import Quick
import Nimble
@testable import Thoth

/// 保存・読み込み・削除・並べ替えと、読めないデータ・TOTP・認証の猶予の扱い（テスト用キーチェーンを使う）
extension SecureMenuServiceSpec {

    // MARK: - Save / load / delete / reorder

    static func saveAndLoadSpecs() {
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

            // 1 件ずつ save(_:) を呼ぶと件数分の読み書きと変更通知が走るため、
            // インポートのような一括処理では 1 回の書き込みにまとめる
            it("複数アイテムをまとめて保存し、通知は 1 回だけ飛ぶ") {
                var received = 0
                let observer = NotificationCenter.default.addObserver(forName: .secureItemsDidChange,
                                                                      object: nil, queue: nil) { _ in
                    received += 1
                }
                defer { NotificationCenter.default.removeObserver(observer) }

                let items = (0..<5).map { SecureMenuItem(itemID: "b\($0)", title: "Item \($0)") }
                expect(self.service.save(items)) == true
                expect(received) == 1

                let loaded = self.service.loadAllItems()
                expect(loaded.map { $0.itemID }) == ["b0", "b1", "b2", "b3", "b4"]
                // 新規追加は末尾に向かって displayOrder が振られる
                expect(loaded.map { $0.displayOrder }) == [0, 1, 2, 3, 4]
            }

            it("まとめ保存でも既存アイテムは上書きされ、変更履歴が引き継がれる") {
                let original = SecureMenuItem.Field(fieldID: "f1", label: "PW", value: "old", isPassword: true)
                expect(self.service.save(SecureMenuItem(itemID: "batch", title: "A", fields: [original]))) == true

                let updated = original.updating(value: "new")
                expect(self.service.save([SecureMenuItem(itemID: "batch", title: "A", fields: [updated]),
                                          SecureMenuItem(itemID: "added", title: "B")])) == true

                let loaded = self.service.loadAllItems()
                expect(loaded.count) == 2
                let saved = loaded.first { $0.itemID == "batch" }?.fields.first
                expect(saved?.value) == "new"
                expect(saved?.history.map { $0.value }) == ["old"]
            }

            it("空配列のまとめ保存は何もせず成功を返す") {
                expect(self.service.save([SecureMenuItem]())) == true
                expect(self.service.loadAllItems()).to(beEmpty())
            }

            // 拡張種別が Keychain の保存形式（JSON）を往復しても失われないこと。
            // メモは改行を含むため、単一行に丸められていないかも併せて確認する
            it("Url and note fields survive the keychain round trip") {
                let memo = "契約番号: 12345-678\nサポート: 03-0000-0000\n用途: 経理システムのログイン"
                let fields = [SecureMenuItem.Field(label: "URL", value: "https://example.com/login", kind: .url),
                              SecureMenuItem.Field(label: "Memo", value: memo, kind: .note)]
                _ = self.service.save(SecureMenuItem(itemID: "extended", title: "Accounting", fields: fields))

                let loaded = self.service.loadAllItems().first
                expect(loaded?.fields.count) == 2
                expect(loaded?.fields[0].kind) == SecureMenuItem.Field.Kind.url
                expect(loaded?.fields[0].value) == "https://example.com/login"
                expect(loaded?.fields[1].kind) == SecureMenuItem.Field.Kind.note
                expect(loaded?.fields[1].value) == memo
                expect(loaded?.fields[1].value.contains("\n")) == true
            }
        }
    }

    static func deleteSpecs() {
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

    static func reorderSpecs() {
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

    static func accessDeniedGuardSpecs() {
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

    // MARK: - Authentication Lifetime

    /// 常駐運用で「認証状態が残り続けない」ことを担保する。
    /// 評価済みの LAContext を保持したままだと、アプリ内の再認証ゲートを
    /// 過ぎても OS レベルの認証が有効に残る
    static func authenticationLifetimeSpecs() {
        describe("認証状態の寿命") {

            it("明示的な破棄で猶予期間もリセットされる") {
                self.service.lastAuthenticatedDate = Date()
                self.service.invalidateAuthentication()
                expect(self.service.lastAuthenticatedDate) == nil
            }

            // 猶予期間内なら再認証を省略する（既存の UX を壊さない）
            it("猶予期間内は再認証を省略する") {
                self.service.lastAuthenticatedDate = Date()
                var authenticated: Bool?
                self.service.authenticate(reason: "test") { authenticated = $0 }
                expect(authenticated).toEventually(equal(true), timeout: .seconds(1))
            }

            // 破棄したあとは猶予が効かない（＝再認証が要求される）
            it("破棄後は猶予期間が効かない") {
                self.service.lastAuthenticatedDate = Date()
                self.service.invalidateAuthentication()
                expect(self.service.lastAuthenticatedDate) == nil
            }

            it("読み書きは認証していなくても猶予判定で失敗しない") {
                // 認証を通していない状態でも通常の保存・読み出しは行える
                expect(self.service.save(SecureMenuItem(itemID: "auth", title: "A"))) == true
                expect(self.service.loadAllItems().count) == 1
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
    static func corruptedDataGuardSpecs() {
        describe("Corrupted data guard") {

            /// user-data エントリを解釈不能なバイト列で置き換える
            func corruptUserDataEntry() {
                self.addLegacyEntry(account: "user-data", data: Data("{ this is not valid json".utf8))
            }

            it("Reports unreadable state when the stored data cannot be decoded") {
                expect(self.service.save(SecureMenuItem(title: "Existing"))) == true
                corruptUserDataEntry()

                expect(self.service.loadAllItems()).to(beEmpty())
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
                expect(self.service.loadAllItems()).to(beEmpty())
                expect(self.service.isKeychainAccessDenied) == true

                self.removeEntryDirectly(account: "user-data")
                expect(self.service.loadAllItems()).to(beEmpty())
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
                // 読めるなら read-modify-write で、読めないなら保存拒否で、
                // いずれにせよ既存の値は保持されなければならない
                _ = self.service.save(SecureMenuItem(title: "Added after reading unknown data"))

                let stored = String(data: self.rawEntryData(account: "user-data") ?? Data(), encoding: .utf8) ?? ""
                expect(stored).to(contain("JBSWY3DPEHPK3PXP"))
                expect(stored).to(contain("fingerprint-password"))
            }

            // v1.2.0 以降は未知の種別を plain として読めるため、
            // 将来の版が書いたデータを開いてもアプリは編集可能なまま動く
            // （v1.1.x はここでデコードに失敗し、保存不能に陥っていた）
            it("Degrades an unknown field kind to plain instead of locking the app") {
                let json = """
                {"version":2,"items":[{"itemID":"future-2","title":"Future","displayOrder":0,
                 "fields":[{"fieldID":"f1","label":"Something","value":"kept","isPassword":false,
                 "kind":"kind-from-the-future","history":[],"createdAt":0}]}]}
                """
                self.addLegacyEntry(account: "user-data", data: Data(json.utf8))

                let loaded = self.service.loadAllItems()
                expect(self.service.isKeychainAccessDenied) == false
                expect(loaded.first?.fields.first?.kind) == SecureMenuItem.Field.Kind.plain
                expect(loaded.first?.fields.first?.value) == "kept"
                expect(self.service.save(SecureMenuItem(title: "Still editable"))) == true
            }
        }
    }

    // MARK: - TOTP Field Tests (A-2)

    static func totpFieldSpecs() {
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
    }

    static func authenticationGraceSpecs() {
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
