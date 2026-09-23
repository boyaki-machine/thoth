import Quick
import Nimble
import AppKit
@testable import Thoth

// MARK: - Secure Info Window Commit Flow Tests
//
// 編集・構成変更から Keychain 保存までを実サービスで通す。
// テスト専用の service 名を注入するので本番データには触れない。

// BDD スペックは多数の it ブロックを含み型本体が長くなるため型長ルールを緩める
class SecureInfoCommitFlowSpec: QuickSpec {

    override class func spec() {
        commitFlowSaveSpecs()
        commitFlowGuardSpecs()
        structuralFieldFlowSpecs()
        structuralItemFlowSpecs()
        structuralWindowFlowSpecs()
        changeNotificationSpecs()
        externalChangeSyncSpecs()
    }

    // MARK: - Change notification

    /// 変更通知は、同じサービスを共有する複数のウィンドウが表示を同期するための土台。
    /// 通知が飛ばない経路があると、片方の画面が古い内容を表示し続ける
    static func changeNotificationSpecs() {
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
                expect(service.loadAllItems()).to(beEmpty())
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

    static func externalChangeSyncSpecs() {
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
                expect(before).toNot(beEmpty())
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

        }
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

    // MARK: - Commit flow (end to end)
    //
    // 編集 → コミット → Keychain 保存 → 読み直し までを実サービスで通す。
    // テスト専用の service 名を注入するので本番データには触れない

    static let testKeychainService = "io.github.boyaki-machine.ThothTests.SecureInfo"

    /// テスト用サービスの user-data エントリを直接書き換える（破損状態の再現用）
    static func writeRawUserData(_ data: Data) {
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

    static func rawUserDataString() -> String? {
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

    static func removeRawUserData() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: testKeychainService,
            kSecAttrAccount as String: "user-data"
        ]
        SecItemDelete(query as CFDictionary)
    }
}
