import Quick
import Nimble
import AppKit
@testable import Thoth

// MARK: - Secure Info Window Commit Flow Tests
//
// 編集・構成変更から Keychain 保存までを実サービスで通す。
// テスト専用の service 名を注入するので本番データには触れない。

// BDD スペックは多数の it ブロックを含み型本体が長くなるため型長ルールを緩める
// swiftlint:disable:next type_body_length
class SecureInfoCommitFlowSpec: QuickSpec {

    override class func spec() {
        commitFlowSpecs()
        structuralFlowSpecs()
        changeNotificationSpecs()
        externalChangeSyncSpecs()
    }

    // MARK: - Change notification

    /// 変更通知は、同じサービスを共有する複数のウィンドウが表示を同期するための土台。
    /// 通知が飛ばない経路があると、片方の画面が古い内容を表示し続ける
    private static func changeNotificationSpecs() {
        describe("変更通知") {

            var service: SecureMenuService!
            var received: Int!
            var observer: NSObjectProtocol!

            beforeEach {
                service = SecureMenuService(keychainService: testKeychainService)
                service.deleteAllItems()
                received = 0
                observer = NotificationCenter.default.addObserver(forName: .secureItemsDidChange,
                                                                  object: nil, queue: nil) { _ in
                    received += 1
                }
            }
            afterEach {
                NotificationCenter.default.removeObserver(observer!)
                service.deleteAllItems()
            }

            it("保存で 1 回だけ通知され、通し番号が進む") {
                let before = service.itemsChangeToken
                expect(service.save(SecureMenuItem(itemID: "n1", title: "A"))) == true
                expect(received) == 1
                expect(service.itemsChangeToken) == before + 1
            }

            it("削除でも通知される") {
                _ = service.save(SecureMenuItem(itemID: "n1", title: "A"))
                received = 0
                expect(service.delete(itemID: "n1")) == true
                expect(received) == 1
            }

            it("並べ替えでも通知される") {
                _ = service.save(SecureMenuItem(itemID: "n1", title: "A"))
                _ = service.save(SecureMenuItem(itemID: "n2", title: "B"))
                received = 0
                let reordered = service.loadAllItems().reversed().map { $0 }
                expect(service.reorderItems(reordered)) == true
                expect(received) == 1
            }

            // saveAllItems を通らない経路。ここを取りこぼすと全削除が同期されない
            it("全削除でも通知される") {
                _ = service.save(SecureMenuItem(itemID: "n1", title: "A"))
                received = 0
                expect(service.deleteAllItems()) == true
                expect(received) == 1
            }

            it("消すものが無い全削除では通知しない") {
                received = 0
                _ = service.deleteAllItems()
                expect(received) == 0
            }

            // 読み出しは変更ではない（通知すると再読込が無限に続きかねない）
            it("読み出しでは通知しない") {
                _ = service.save(SecureMenuItem(itemID: "n1", title: "A"))
                received = 0
                _ = service.loadAllItems()
                _ = service.loadCryptoPassword()
                expect(received) == 0
            }

            // isKeychainAccessDenied を直接立てても save 内の loadAllItems が読み直して
            // 解除してしまうため、実際に解釈できないデータを置いて再現する
            it("保存に失敗したときは通知しない") {
                _ = service.save(SecureMenuItem(itemID: "n1", title: "A"))
                writeRawUserData(Data("{ broken".utf8))
                expect(service.loadAllItems().isEmpty) == true
                expect(service.isKeychainAccessDenied) == true

                received = 0
                let tokenBefore = service.itemsChangeToken
                expect(service.save(SecureMenuItem(itemID: "n2", title: "B"))) == false
                expect(received) == 0
                expect(service.itemsChangeToken) == tokenBefore

                removeRawUserData()
            }
        }
    }

    // MARK: - External change sync

    private static func externalChangeSyncSpecs() {
        describe("他の画面での変更への追従") {

            var service: SecureMenuService!

            beforeEach {
                service = SecureMenuService(keychainService: testKeychainService)
                service.deleteAllItems()
                AppEnvironment.push(environment: Environment(secureMenuService: service))
            }
            afterEach {
                service.deleteAllItems()
                AppEnvironment.popLast()
            }

            /// 行ビューの作り直しを検出できるよう、フィールドを持たせておく
            func makeSplitViewController() -> CPYSecureInfoSplitViewController {
                let item = SecureMenuItem(itemID: "s1", title: "GitHub", fields: [
                    SecureMenuItem.Field(fieldID: "f1", label: "ID", value: "alice")
                ])
                expect(service.save(item)) == true
                let splitViewController = CPYSecureInfoSplitViewController()
                _ = splitViewController.view
                splitViewController.reloadItems()
                splitViewController.editor.beginEditing(itemID: "s1")
                splitViewController.detailViewControllerForTesting.show(item: splitViewController.editor.draft)
                return splitViewController
            }

            it("他の画面での変更を取り込む") {
                let splitViewController = makeSplitViewController()
                expect(splitViewController.editor.items.count) == 1

                // 別の画面が追加した想定
                expect(service.save(SecureMenuItem(itemID: "s2", title: "AWS"))) == true
                splitViewController.applyExternalChangeIfNeeded()

                expect(splitViewController.editor.items.map { $0.itemID }) == ["s1", "s2"]
            }

            // 自分の保存で読み直すと、入力中のフォーカスとカーソル位置が飛ぶ
            it("自分が起こした変更では読み直さない") {
                let splitViewController = makeSplitViewController()
                splitViewController.editor.beginEditing(itemID: "s1")
                _ = splitViewController.editor.updateTitle("Renamed")
                expect(splitViewController.commitIfNeeded()) == true

                // 保存直後の通知では行ビューが作り直されない（同じインスタンスのまま）
                let before = splitViewController.detailViewControllerForTesting.fieldRows
                expect(before.isEmpty) == false
                splitViewController.applyExternalChangeIfNeeded()
                let after = splitViewController.detailViewControllerForTesting.fieldRows
                expect(after.count) == before.count
                expect(zip(before, after).allSatisfy { $0 === $1 }) == true
                expect(splitViewController.detailViewControllerForTesting.externalChangeBanner.isHidden) == true
            }

            // 打ちかけの内容を黙って捨てない
            it("未保存の編集がある場合は読み直さず案内を出す") {
                let splitViewController = makeSplitViewController()
                splitViewController.editor.beginEditing(itemID: "s1")
                _ = splitViewController.editor.updateTitle("Editing")

                expect(service.save(SecureMenuItem(itemID: "s2", title: "AWS"))) == true
                splitViewController.applyExternalChangeIfNeeded()

                expect(splitViewController.detailViewControllerForTesting.externalChangeBanner.isHidden) == false
                // 編集内容は残り、一覧もまだ読み直していない
                expect(splitViewController.editor.draft?.title) == "Editing"
                expect(splitViewController.editor.items.count) == 1
            }

            it("案内から読み直すと取り込まれ、案内は消える") {
                let splitViewController = makeSplitViewController()
                splitViewController.editor.beginEditing(itemID: "s1")
                _ = splitViewController.editor.updateTitle("Editing")
                expect(service.save(SecureMenuItem(itemID: "s2", title: "AWS"))) == true
                splitViewController.applyExternalChangeIfNeeded()

                let detail = splitViewController.detailViewControllerForTesting
                detail.externalChangeReloadButton.performClick(nil)

                expect(detail.externalChangeBanner.isHidden) == true
                expect(splitViewController.editor.items.count) == 2
            }

            // 変更通知は NotificationCenter の仕様上、メインスレッドからの post だと
            // 保存処理の**途中で同期的に**届く。その時点では通し番号の更新も
            // 保存完了の記録も済んでいないため、通し番号だけの判定では
            // 自分の保存を「他の画面での変更」と誤認して案内バーが出ていた
            it("自分の保存の途中で届いた通知では案内を出さない") {
                let splitViewController = makeSplitViewController()
                splitViewController.editor.beginEditing(itemID: "s1")
                _ = splitViewController.editor.updateTitle("Renamed")

                var shownDuringSave = false
                // queue: nil は post したスレッドで同期的に呼ばれる
                let observer = NotificationCenter.default.addObserver(forName: .secureItemsDidChange,
                                                                      object: nil, queue: nil) { _ in
                    splitViewController.applyExternalChangeIfNeeded()
                    let banner = splitViewController.detailViewControllerForTesting.externalChangeBanner
                    if !banner.isHidden { shownDuringSave = true }
                }
                defer { NotificationCenter.default.removeObserver(observer) }

                expect(splitViewController.commitIfNeeded()) == true
                expect(shownDuringSave) == false
                expect(splitViewController.detailViewControllerForTesting.externalChangeBanner.isHidden) == true
                expect(service.loadAllItems().first?.title) == "Renamed"
            }

            // 一度出た案内が残り続けると、以後の操作のたびに出ているように見える
            it("自分の保存が成功すると残っていた案内も消える") {
                let splitViewController = makeSplitViewController()
                splitViewController.detailViewControllerForTesting.showExternalChangeBanner {}
                splitViewController.editor.beginEditing(itemID: "s1")
                _ = splitViewController.editor.updateTitle("Renamed")

                expect(splitViewController.commitIfNeeded()) == true
                expect(splitViewController.detailViewControllerForTesting.externalChangeBanner.isHidden) == true
            }

            it("読み直すと案内は消える") {
                let splitViewController = makeSplitViewController()
                splitViewController.detailViewControllerForTesting.showExternalChangeBanner {}
                splitViewController.reloadItems()
                expect(splitViewController.detailViewControllerForTesting.externalChangeBanner.isHidden) == true
            }

            // 管理ウィンドウ側も同じ通知で追従する。
            // 通知経由では警告を出さない（同じ警告が繰り返し積み上がるため）
            it("管理ウィンドウが警告なしで再読込できる") {
                let itemsViewController = CPYSecureItemsViewController()
                _ = itemsViewController.view
                service.isKeychainAccessDenied = true
                // 警告を出さない経路なので、ウィンドウが無くてもモーダルで止まらない
                itemsViewController.reloadItems(showsAlert: false)
                service.isKeychainAccessDenied = false
            }
        }
    }

    // MARK: - Fixtures

    private static func sampleItems() -> [SecureMenuItem] {
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

    private static func makeEditor() -> SecureInfoEditor {
        let editor = SecureInfoEditor()
        editor.setItems(sampleItems())
        return editor
    }

    private static func titles(_ items: [SecureMenuItem]) -> [String] {
        return items.map { $0.title }
    }

    // MARK: - Commit flow (end to end)
    //
    // 編集 → コミット → Keychain 保存 → 読み直し までを実サービスで通す。
    // テスト専用の service 名を注入するので本番データには触れない

    private static let testKeychainService = "io.github.boyaki-machine.ThothTests.SecureInfo"

    /// テスト用サービスの user-data エントリを直接書き換える（破損状態の再現用）
    private static func writeRawUserData(_ data: Data) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: testKeychainService,
            kSecAttrAccount as String: "user-data",
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: data
        ]
        SecItemDelete(query as CFDictionary)
        expect(SecItemAdd(query as CFDictionary, nil)) == errSecSuccess
    }

    private static func rawUserDataString() -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: testKeychainService,
            kSecAttrAccount as String: "user-data"
        ]
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func removeRawUserData() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: testKeychainService,
            kSecAttrAccount as String: "user-data"
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Structural changes (end to end)

    /// フィールドとアイテムの増減・並べ替えを実サービス経由で確認する
    private static func structuralFlowSpecs() {
        describe("構成変更の保存フロー") {

            var service: SecureMenuService!

            beforeEach {
                service = SecureMenuService(keychainService: testKeychainService)
                service.deleteAllItems()
                AppEnvironment.push(environment: Environment(secureMenuService: service))
            }
            afterEach {
                service.deleteAllItems()
                AppEnvironment.popLast()
            }

            func makeSplitViewController(with items: [SecureMenuItem]) -> CPYSecureInfoSplitViewController {
                for item in items {
                    expect(service.save(item)) == true
                }
                let splitViewController = CPYSecureInfoSplitViewController()
                _ = splitViewController.view
                splitViewController.reloadItems()
                return splitViewController
            }

            it("追加したフィールドが保存され、種別とマスク指定が保たれる") {
                let splitViewController = makeSplitViewController(with: [
                    SecureMenuItem(itemID: "s1", title: "GitHub")
                ])
                splitViewController.editor.beginEditing(itemID: "s1")
                splitViewController.editor.addField(kind: .url, label: "URL", value: "https://example.com")
                splitViewController.editor.addField(kind: .plain, label: "PW", value: "s3cr3t", isPassword: true)
                expect(splitViewController.commitIfNeeded()) == true

                let saved = service.loadAllItems().first
                expect(saved?.fields.map { $0.label }) == ["URL", "PW"]
                expect(saved?.fields.first?.kind) == SecureMenuItem.Field.Kind.url
                expect(saved?.fields.last?.isPassword) == true
            }

            it("削除したフィールドが保存に反映される") {
                let splitViewController = makeSplitViewController(with: [
                    SecureMenuItem(itemID: "s1", title: "GitHub", fields: [
                        SecureMenuItem.Field(fieldID: "f1", label: "ID", value: "alice"),
                        SecureMenuItem.Field(fieldID: "f2", label: "PW", value: "s3cr3t", isPassword: true)
                    ])
                ])
                splitViewController.editor.beginEditing(itemID: "s1")
                expect(splitViewController.editor.removeField(fieldID: "f1")) == true
                expect(splitViewController.commitIfNeeded()) == true

                expect(service.loadAllItems().first?.fields.map { $0.fieldID }) == ["f2"]
            }

            it("並べ替えた順序が保存され、TOTP secret も保たれる") {
                let secret = "otpauth://totp/GitHub?secret=JBSWY3DPEHPK3PXP"
                let splitViewController = makeSplitViewController(with: [
                    SecureMenuItem(itemID: "s1", title: "GitHub", fields: [
                        SecureMenuItem.Field(fieldID: "f1", label: "ID", value: "alice"),
                        SecureMenuItem.Field(fieldID: "f2", label: "TOTP", value: secret, kind: .totp)
                    ])
                ])
                splitViewController.editor.beginEditing(itemID: "s1")
                expect(splitViewController.editor.moveField(fieldID: "f2", by: -1)) == true
                expect(splitViewController.commitIfNeeded()) == true

                let saved = service.loadAllItems().first
                expect(saved?.fields.map { $0.fieldID }) == ["f2", "f1"]
                expect(saved?.fields.first?.value) == secret
                expect(saved?.fields.first?.history.isEmpty) == true
            }

            // マスク切り替えは値を書き換えないこと（Step 8 の伏せ字保存事故の裏返し）
            it("マスク切り替えで値が壊れない") {
                let splitViewController = makeSplitViewController(with: [
                    SecureMenuItem(itemID: "s1", title: "GitHub", fields: [
                        SecureMenuItem.Field(fieldID: "f1", label: "ID", value: "alice")
                    ])
                ])
                splitViewController.editor.beginEditing(itemID: "s1")
                expect(splitViewController.editor.updateField(fieldID: "f1", isPassword: true)) == true
                expect(splitViewController.commitIfNeeded()) == true

                let saved = service.loadAllItems().first?.fields.first
                expect(saved?.isPassword) == true
                expect(saved?.value) == "alice"
                // 値は変わっていないので履歴も積まれない
                expect(saved?.history.isEmpty) == true
            }

            it("アイテムの並べ替えが保存される") {
                let splitViewController = makeSplitViewController(with: [
                    SecureMenuItem(itemID: "a", title: "A"),
                    SecureMenuItem(itemID: "b", title: "B"),
                    SecureMenuItem(itemID: "c", title: "C")
                ])
                guard let reordered = SecureInfoEditor.reordered(splitViewController.editor.items,
                                                                 movingItemID: "a", by: 2) else {
                    fail("expected reorder")
                    return
                }
                expect(service.reorderItems(reordered)) == true
                expect(service.loadAllItems().map { $0.itemID }) == ["b", "c", "a"]
            }

            // 未保存の編集を残したままアイテムを削除しても、保存で復活しない
            it("削除したアイテムは未保存の編集ごと消える") {
                let splitViewController = makeSplitViewController(with: [
                    SecureMenuItem(itemID: "s1", title: "GitHub"),
                    SecureMenuItem(itemID: "s2", title: "AWS")
                ])
                splitViewController.editor.beginEditing(itemID: "s1")
                _ = splitViewController.editor.updateTitle("Edited")

                // 削除時と同じ流れ: 作業コピーを捨ててから削除する
                splitViewController.editor.beginEditing(itemID: nil)
                expect(service.delete(itemID: "s1")) == true
                splitViewController.editor.setItems(service.loadAllItems())
                expect(splitViewController.commitIfNeeded()) == true

                expect(service.loadAllItems().map { $0.itemID }) == ["s2"]
            }

            // reorderItems は渡した配列の内容をそのまま書き戻すため、並べ替え前に
            // コミットしないと直前の編集が保存前の内容で上書きされる
            it("並べ替えの直前に編集していても、その編集が失われない") {
                let splitViewController = makeSplitViewController(with: [
                    SecureMenuItem(itemID: "a", title: "A"),
                    SecureMenuItem(itemID: "b", title: "B")
                ])
                splitViewController.editor.beginEditing(itemID: "a")
                _ = splitViewController.editor.updateTitle("A renamed")

                // 並べ替え操作と同じ流れ（コミット → 並びの組み立て → 保存）
                expect(splitViewController.commitIfNeeded()) == true
                guard let reordered = SecureInfoEditor.reordered(splitViewController.editor.items,
                                                                 movingItemID: "a", by: 1) else {
                    fail("expected reorder")
                    return
                }
                expect(service.reorderItems(reordered)) == true

                let saved = service.loadAllItems()
                expect(saved.map { $0.itemID }) == ["b", "a"]
                expect(saved.first { $0.itemID == "a" }?.title) == "A renamed"
            }

            // 閉じたあともメモリに平文が残らないようにする。
            // シングルトンのウィンドウなので、閉じても VC は生き続ける
            it("ウィンドウを閉じると保持データが破棄され、開き直すと復帰する") {
                let splitViewController = makeSplitViewController(with: [
                    SecureMenuItem(itemID: "s1", title: "GitHub", fields: [
                        SecureMenuItem.Field(label: "PW", value: "s3cr3t", isPassword: true)
                    ])
                ])
                splitViewController.editor.beginEditing(itemID: "s1")
                expect(splitViewController.editor.items.isEmpty) == false
                expect(splitViewController.editor.draft?.itemID) == "s1"

                splitViewController.viewWillDisappear()
                expect(splitViewController.editor.items.isEmpty) == true
                expect(splitViewController.editor.draft?.itemID) == nil
                expect(splitViewController.editor.selectedItemID) == nil
                expect(splitViewController.detailViewControllerForTesting.fieldRows.isEmpty) == true

                // 開き直せば Keychain から読み直される
                splitViewController.reloadItems()
                expect(splitViewController.editor.items.map { $0.itemID }) == ["s1"]
            }

            // 閉じる直前の未保存の編集は捨てずに保存する
            it("閉じる操作で未保存の編集が保存される") {
                let splitViewController = makeSplitViewController(with: [
                    SecureMenuItem(itemID: "s1", title: "GitHub")
                ])
                splitViewController.editor.beginEditing(itemID: "s1")
                _ = splitViewController.editor.updateTitle("Renamed")

                splitViewController.viewWillDisappear()
                expect(service.loadAllItems().first?.title) == "Renamed"
            }

            // 「編集内容は保持されています」と案内しておきながら、選択を切り替えた
            // 拍子に draft を捨てていた。保存できないときは切り替え自体を取り消す
            it("保存できない状態で選択を切り替えても編集内容が残る") {
                let splitViewController = makeSplitViewController(with: [
                    SecureMenuItem(itemID: "s1", title: "GitHub"),
                    SecureMenuItem(itemID: "s2", title: "AWS")
                ])
                splitViewController.editor.beginEditing(itemID: "s1")
                _ = splitViewController.editor.updateTitle("")
                _ = splitViewController.editor.updateField(fieldID: "no-such", value: "x")

                // 別アイテムを選んだときと同じ流れ
                expect(splitViewController.commitIfNeeded()) == false
                expect(splitViewController.editor.isDirty) == true
                expect(splitViewController.editor.draft?.itemID) == "s1"
                // 保存もされていない
                expect(service.loadAllItems().first { $0.itemID == "s1" }?.title) == "GitHub"
            }

            // 直前の編集を保存できない状態で + を押すと、その編集が失われていた
            it("保存できない状態ではアイテムを追加しない") {
                let splitViewController = makeSplitViewController(with: [
                    SecureMenuItem(itemID: "s1", title: "GitHub")
                ])
                splitViewController.editor.beginEditing(itemID: "s1")
                _ = splitViewController.editor.updateTitle("")

                splitViewController.addItem()

                expect(service.loadAllItems().count) == 1
                expect(splitViewController.editor.draft?.itemID) == "s1"
                expect(splitViewController.editor.isDirty) == true
            }

            it("新規アイテムは既定タイトルを持つのでそのまま保存できる") {
                let splitViewController = makeSplitViewController(with: [])
                let newItem = SecureMenuItem(title: L10n.newSecureItemTitle)
                expect(service.save(newItem)) == true
                splitViewController.editor.setItems(service.loadAllItems())
                splitViewController.editor.beginEditing(itemID: newItem.itemID)

                expect(splitViewController.editor.draft?.title.isEmpty) == false
                _ = splitViewController.editor.updateTitle("My Account")
                expect(splitViewController.commitIfNeeded()) == true
                expect(service.loadAllItems().first?.title) == "My Account"
            }
        }
    }

    private static func commitFlowSpecs() {
        describe("編集からの保存フロー") {

            var service: SecureMenuService!

            beforeEach {
                service = SecureMenuService(keychainService: testKeychainService)
                service.deleteAllItems()
                AppEnvironment.push(environment: Environment(secureMenuService: service))
            }
            afterEach {
                service.deleteAllItems()
                AppEnvironment.popLast()
            }

            /// 1 アイテムを保存した状態のウィンドウを組み立てる
            func makeSplitViewController() -> CPYSecureInfoSplitViewController {
                let item = SecureMenuItem(itemID: "e2e", title: "GitHub", fields: [
                    SecureMenuItem.Field(fieldID: "f-id", label: "ID", value: "alice"),
                    SecureMenuItem.Field(fieldID: "f-pw", label: "Password", value: "old-pass", isPassword: true),
                    SecureMenuItem.Field(fieldID: "f-memo", label: "Memo", value: "line1", kind: .note)
                ])
                expect(service.save(item)) == true
                let splitViewController = CPYSecureInfoSplitViewController()
                _ = splitViewController.view
                splitViewController.reloadItems()
                splitViewController.editor.beginEditing(itemID: "e2e")
                return splitViewController
            }

            it("タイトルの編集がキーチェーンへ保存される") {
                let splitViewController = makeSplitViewController()
                _ = splitViewController.editor.updateTitle("GitHub Enterprise")
                expect(splitViewController.commitIfNeeded()) == true

                expect(service.loadAllItems().first?.title) == "GitHub Enterprise"
                expect(splitViewController.editor.isDirty) == false
            }

            it("値の編集がキーチェーンへ保存され、旧値が変更履歴に残る") {
                let splitViewController = makeSplitViewController()
                _ = splitViewController.editor.updateField(fieldID: "f-pw", value: "new-pass")
                expect(splitViewController.commitIfNeeded()) == true

                let saved = service.loadAllItems().first?.fields.first { $0.fieldID == "f-pw" }
                expect(saved?.value) == "new-pass"
                expect(saved?.history.map { $0.value }) == ["old-pass"]
            }

            // 打鍵の途中経過を保存すると、上限 10 件の履歴が中途半端な文字列で
            // 埋まって本当の旧値が押し出される。確定は編集の区切りでのみ行う
            it("入力のたびに保存しないので履歴が打鍵で汚れない") {
                let splitViewController = makeSplitViewController()
                for value in ["n", "ne", "new", "new-", "new-p", "new-pa", "new-pass"] {
                    _ = splitViewController.editor.updateField(fieldID: "f-pw", value: value)
                }
                expect(splitViewController.commitIfNeeded()) == true

                let saved = service.loadAllItems().first?.fields.first { $0.fieldID == "f-pw" }
                expect(saved?.value) == "new-pass"
                // 履歴に残るのは編集前の値ひとつだけ
                expect(saved?.history.map { $0.value }) == ["old-pass"]
            }

            it("メモの改行が保存を通過する") {
                let splitViewController = makeSplitViewController()
                _ = splitViewController.editor.updateField(fieldID: "f-memo", value: "契約番号: 12345\nTEL: 03-0000-0000")
                expect(splitViewController.commitIfNeeded()) == true

                let saved = service.loadAllItems().first?.fields.first { $0.fieldID == "f-memo" }
                expect(saved?.value) == "契約番号: 12345\nTEL: 03-0000-0000"
                expect(saved?.kind) == SecureMenuItem.Field.Kind.note
            }

            it("変更が無ければ保存しない") {
                let splitViewController = makeSplitViewController()
                expect(splitViewController.commitIfNeeded()) == true
                expect(service.loadAllItems().first?.title) == "GitHub"
            }

            // タイトルを空にしたまま閉じても、編集内容は失われず保存もされない
            it("タイトルが空だと保存されず編集内容は保持される") {
                let splitViewController = makeSplitViewController()
                _ = splitViewController.editor.updateTitle("")
                _ = splitViewController.editor.updateField(fieldID: "f-id", value: "bob")
                expect(splitViewController.commitIfNeeded()) == false

                expect(service.loadAllItems().first?.title) == "GitHub"
                expect(service.loadAllItems().first?.fields.first?.value) == "alice"
                expect(splitViewController.editor.isDirty) == true
                expect(splitViewController.editor.draft?.fields.first?.value) == "bob"
            }

            // 操作シーケンス: 編集したまま別アイテムを選ぶと、離れる前に保存される
            it("別アイテムへ移る前に編集内容が保存される") {
                let other = SecureMenuItem(itemID: "other", title: "AWS")
                expect(service.save(other)) == true

                let splitViewController = makeSplitViewController()
                splitViewController.reloadItems()
                splitViewController.editor.beginEditing(itemID: "e2e")
                _ = splitViewController.editor.updateTitle("Renamed")

                // 一覧で別アイテムを選んだときと同じ流れ
                splitViewController.editor.selectItem(itemID: "other")
                splitViewController.commitIfNeeded()
                splitViewController.editor.beginEditing(itemID: "other")

                expect(service.loadAllItems().first { $0.itemID == "e2e" }?.title) == "Renamed"
                expect(splitViewController.editor.draft?.itemID) == "other"
                expect(splitViewController.editor.isDirty) == false
            }

            // 読み出せない状態では編集そのものを止める（保存が拒否されるだけの
            // 状態で入力させると、打った内容がそのまま失われる）
            it("キーチェーンを読み出せない場合は読み取り専用になる") {
                let splitViewController = makeSplitViewController()
                // 実際に解釈できないデータへ置き換えて再現する
                writeRawUserData(Data("{ broken".utf8))
                splitViewController.reloadItems()

                expect(splitViewController.editor.isReadOnly) == true
                expect(splitViewController.editor.items.isEmpty) == true
                splitViewController.editor.beginEditing(itemID: "e2e")
                expect(splitViewController.editor.updateTitle("Renamed")) == false
                expect(splitViewController.editor.isDirty) == false
                // 読めない状態のデータは上書きされない
                expect(splitViewController.commitIfNeeded()) == true
                expect(rawUserDataString()) == "{ broken"

                removeRawUserData()
            }

            it("読み取り専用モードでは行もタイトルも編集できない") {
                let splitViewController = makeSplitViewController()
                splitViewController.detailViewControllerForTesting.isReadOnly = true
                splitViewController.detailViewControllerForTesting.show(item: splitViewController.editor.draft)

                expect(splitViewController.detailViewControllerForTesting.titleField.isEditable) == false
                let rows = splitViewController.detailViewControllerForTesting.fieldRows
                expect(rows.allSatisfy { !$0.labelField.isEditable }) == true
                expect(rows.first { !$0.field.kind.isMultiline }?.valueField.isEditable) == false
            }

            it("TOTP の secret は編集経路を通っても書き換わらない") {
                let secret = "otpauth://totp/GitHub?secret=JBSWY3DPEHPK3PXP"
                let item = SecureMenuItem(itemID: "totp-e2e", title: "GitHub", fields: [
                    SecureMenuItem.Field(fieldID: "f-totp", label: "TOTP", value: secret, kind: .totp)
                ])
                expect(service.save(item)) == true

                let splitViewController = CPYSecureInfoSplitViewController()
                _ = splitViewController.view
                splitViewController.reloadItems()
                splitViewController.editor.beginEditing(itemID: "totp-e2e")
                _ = splitViewController.editor.updateTitle("GitHub 2FA")
                expect(splitViewController.commitIfNeeded()) == true

                let saved = service.loadAllItems().first { $0.itemID == "totp-e2e" }
                expect(saved?.fields.first?.value) == secret
                expect(saved?.fields.first?.kind) == SecureMenuItem.Field.Kind.totp
                expect(saved?.fields.first?.history.isEmpty) == true
            }
        }
    }
}
