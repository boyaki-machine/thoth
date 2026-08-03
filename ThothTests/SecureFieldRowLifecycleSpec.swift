import Quick
import Nimble
import AppKit
@testable import Thoth

// MARK: - Secure Field Row Teardown Tests
//
// 右ペインの行ビューは使い捨てで、`rebuildRows` がアイテムの切り替え・
// フィールドの追加削除並べ替え・マスク切替のたびに作り直す。
//
// **画面から外すだけでは足りない。** フィールドエディタはウィンドウで 1 つを
// 使い回すため、外したあとの行にも編集の変更・終了が届く。届いた行は
// 「画面に見えていた文字列」を作業コピーへ書き戻すので、マスク中なら
// `••••••••` が、未入力なら空文字が、そのまま値として保存されてしまう。
// 実際に「入力した値が伏せ字や空に化ける」「フィールドごと消える」形で表面化した。

class SecureFieldRowLifecycleSpec: QuickSpec {

    private static let testKeychainService = "io.github.boyaki-machine.ThothTests.SecureFieldRowLifecycle"

    override class func spec() {
        describe("捨てた行の後始末") {

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

            func makeSplitViewController() -> CPYSecureInfoSplitViewController {
                let item = SecureMenuItem(itemID: "s1", title: "GitHub", fields: [
                    SecureMenuItem.Field(fieldID: "f1", label: "ID", value: "alice"),
                    SecureMenuItem.Field(fieldID: "f2", label: "Password", value: "old", isPassword: true)
                ])
                expect(service.save(item)) == true
                let splitViewController = CPYSecureInfoSplitViewController()
                _ = splitViewController.view
                splitViewController.reloadItems()
                splitViewController.editor.beginEditing(itemID: "s1")
                splitViewController.detailViewControllerForTesting.show(item: splitViewController.editor.draft)
                return splitViewController
            }

            /// 行を作り直したうえで、捨てた行から編集通知を送る
            func rebuildAndNotify(_ splitViewController: CPYSecureInfoSplitViewController,
                                  from staleRow: SecureFieldRowView) {
                splitViewController.detailViewControllerForTesting.show(item: splitViewController.editor.draft)
                staleRow.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification,
                                                           object: staleRow.valueField))
                staleRow.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification,
                                                           object: staleRow.labelField))
            }

            it("捨てた行の書き戻しで値が伏せ字に化けない") {
                let splitViewController = makeSplitViewController()
                let detail = splitViewController.detailViewControllerForTesting
                guard let staleRow = detail.fieldRows.first(where: { $0.field.fieldID == "f2" }) else {
                    fail("行が見つからない"); return
                }
                // マスク中の行が画面に出している文字列
                expect(staleRow.valueField.stringValue) == SecureFieldRowView.maskedPlaceholder

                _ = splitViewController.editor.updateField(fieldID: "f2", value: "NewSecret")
                rebuildAndNotify(splitViewController, from: staleRow)
                splitViewController.commitIfNeeded()

                let saved = service.loadAllItems().first { $0.itemID == "s1" }
                let field = saved?.fields.first { $0.fieldID == "f2" }
                expect(field?.value) == "NewSecret"
                expect(field?.label) == "Password"
                // 新しい値が変更履歴へ押し出されていないこと
                expect(field?.history.map { $0.value }) == ["old"]
            }

            // ラベルまで空にされると commitOutcome() の「ラベルも値も空なら除去」に
            // 掛かってフィールドごと消える
            it("捨てた行の書き戻しでフィールドが消えない") {
                let splitViewController = makeSplitViewController()
                let detail = splitViewController.detailViewControllerForTesting
                guard let staleRow = detail.fieldRows.first(where: { $0.field.fieldID == "f2" }) else {
                    fail("行が見つからない"); return
                }
                staleRow.labelField.stringValue = ""
                staleRow.valueField.stringValue = ""

                _ = splitViewController.editor.updateField(fieldID: "f2", value: "NewSecret")
                rebuildAndNotify(splitViewController, from: staleRow)
                splitViewController.commitIfNeeded()

                let saved = service.loadAllItems().first { $0.itemID == "s1" }
                expect(saved?.fields.contains { $0.fieldID == "f2" }) == true
                expect(saved?.fields.first { $0.fieldID == "f2" }?.label) == "Password"
            }

            // 捨てる行に平文を残さない（prepareForRemoval は伏せ字へ戻す）
            it("捨てた行の平文表示は伏せ字へ戻る") {
                let splitViewController = makeSplitViewController()
                let detail = splitViewController.detailViewControllerForTesting
                guard let staleRow = detail.fieldRows.first(where: { $0.field.fieldID == "f2" }) else {
                    fail("行が見つからない"); return
                }
                staleRow.toggleReveal()
                expect(staleRow.isRevealed) == true

                detail.show(item: splitViewController.editor.draft)

                expect(staleRow.isRevealed) == false
                expect(staleRow.valueField.stringValue) == SecureFieldRowView.maskedPlaceholder
            }
        }
    }
}
