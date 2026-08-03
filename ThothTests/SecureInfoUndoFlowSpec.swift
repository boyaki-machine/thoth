import Quick
import Nimble
import AppKit
@testable import Thoth

// MARK: - Secure Info Window Undo Flow Tests
//
// 取り消し（⌘Z）／やり直し（⌘⇧Z）を実サービスで通す。
// テスト専用の service 名を注入するので本番データには触れない。
//
// 積む単位は「Keychain へ 1 回書き込むごと」。編集の確定・アイテムの追加削除・
// 並べ替えのどれもこの粒度で戻せることを固定する。

// BDD スペックは多数の it ブロックを含み型本体が長くなるため型長ルールを緩める
// swiftlint:disable:next type_body_length
class SecureInfoUndoFlowSpec: QuickSpec {

    private static let testKeychainService = "io.github.boyaki-machine.ThothTests.SecureInfoUndo"

    override class func spec() {
        editUndoSpecs()
        structuralUndoSpecs()
        importUndoSpecs()
        historyPreservationSpecs()
        lifecycleSpecs()
    }

    // MARK: - Harness

    private static func makeController(with items: [SecureMenuItem],
                                       service: SecureMenuService) -> CPYSecureInfoSplitViewController {
        expect(service.save(items)) == true
        let controller = CPYSecureInfoSplitViewController()
        _ = controller.view
        controller.reloadItems()
        return controller
    }

    /// 一覧から 1 件選び、右ペインに表示した状態にする（選択経路を実際に通す）
    private static func select(_ itemID: String, on controller: CPYSecureInfoSplitViewController) {
        controller.editor.selectItem(itemID: itemID)
        controller.editor.beginEditing(itemID: itemID)
        controller.detailViewControllerForTesting.show(item: controller.editor.draft)
    }

    private static func field(_ label: String,
                              of itemID: String,
                              in service: SecureMenuService) -> SecureMenuItem.Field? {
        return service.loadAllItems().first { $0.itemID == itemID }?.fields.first { $0.label == label }
    }

    private static func sampleItems() -> [SecureMenuItem] {
        return [
            SecureMenuItem(itemID: "s1", title: "GitHub", fields: [
                SecureMenuItem.Field(fieldID: "f1", label: "ID", value: "alice"),
                SecureMenuItem.Field(fieldID: "f2", label: "Password", value: "s3cr3t", isPassword: true)
            ]),
            SecureMenuItem(itemID: "s2", title: "AWS"),
            SecureMenuItem(itemID: "s3", title: "経理システム")
        ]
    }

    // MARK: - Editing

    private static func editUndoSpecs() {
        describe("編集の取り消し") {

            var service: SecureMenuService!
            var controller: CPYSecureInfoSplitViewController!

            beforeEach {
                service = SecureMenuService(keychainService: testKeychainService)
                service.deleteAllItems()
                AppEnvironment.push(environment: Environment(secureMenuService: service))
                controller = makeController(with: sampleItems(), service: service)
                select("s1", on: controller)
            }
            afterEach {
                service.deleteAllItems()
                AppEnvironment.popLast()
            }

            it("値の編集を取り消すと保存前の値に戻る") {
                _ = controller.editor.updateField(fieldID: "f1", value: "bob")
                expect(controller.commitIfNeeded()) == true
                expect(field("ID", of: "s1", in: service)?.value) == "bob"

                controller.performUndo()
                expect(field("ID", of: "s1", in: service)?.value) == "alice"
                expect(controller.editor.draft?.fields.first?.value) == "alice"
            }

            it("やり直すと編集後の値に戻る") {
                _ = controller.editor.updateField(fieldID: "f1", value: "bob")
                expect(controller.commitIfNeeded()) == true
                controller.performUndo()

                controller.performRedo()
                expect(field("ID", of: "s1", in: service)?.value) == "bob"
                expect(controller.editor.draft?.fields.first?.value) == "bob"
            }

            it("タイトルの編集も取り消せる") {
                _ = controller.editor.updateTitle("GitHub Enterprise")
                expect(controller.commitIfNeeded()) == true

                controller.performUndo()
                expect(service.loadAllItems().first { $0.itemID == "s1" }?.title) == "GitHub"
                expect(controller.editor.draft?.title) == "GitHub"
            }

            it("マスク指定の切り替えも取り消せる") {
                _ = controller.editor.updateField(fieldID: "f1", isPassword: true)
                expect(controller.commitIfNeeded()) == true
                expect(field("ID", of: "s1", in: service)?.isPassword) == true

                controller.performUndo()
                expect(field("ID", of: "s1", in: service)?.isPassword) == false
            }

            // 1 回の ⌘Z が 1 世代だけ戻ること。まとめて戻ると直前の編集も巻き込む
            it("2 回編集したら 2 回の取り消しで初期状態まで戻る") {
                _ = controller.editor.updateField(fieldID: "f1", value: "bob")
                expect(controller.commitIfNeeded()) == true
                _ = controller.editor.updateField(fieldID: "f1", value: "carol")
                expect(controller.commitIfNeeded()) == true

                controller.performUndo()
                expect(field("ID", of: "s1", in: service)?.value) == "bob"
                controller.performUndo()
                expect(field("ID", of: "s1", in: service)?.value) == "alice"
                expect(controller.undoStack.canUndo) == false
            }

            it("戻せるものが無ければ何も起きない") {
                let before = service.loadAllItems()
                controller.performUndo()
                expect(service.loadAllItems()) == before
            }

            // 内容の変わらない保存（20 秒のフォールバックなど）で空振りの世代を作らない
            it("内容が変わらない保存では世代が増えない") {
                _ = controller.editor.updateField(fieldID: "f1", value: "bob")
                expect(controller.commitIfNeeded()) == true
                expect(controller.undoStack.undoSnapshots.count) == 1

                expect(controller.commitIfNeeded()) == true
                expect(controller.undoStack.undoSnapshots.count) == 1
            }

            // 読み取り専用は保存が拒否される状態。取り消しで書き戻すのも同じく通らない
            it("読み取り専用では取り消さない") {
                _ = controller.editor.updateField(fieldID: "f1", value: "bob")
                expect(controller.commitIfNeeded()) == true

                controller.editor.isReadOnly = true
                controller.performUndo()
                expect(field("ID", of: "s1", in: service)?.value) == "bob"
                expect(controller.undoStack.canUndo) == true
            }
        }
    }

    // MARK: - Structural changes

    private static func structuralUndoSpecs() {
        describe("構成変更の取り消し") {

            var service: SecureMenuService!
            var controller: CPYSecureInfoSplitViewController!

            beforeEach {
                service = SecureMenuService(keychainService: testKeychainService)
                service.deleteAllItems()
                AppEnvironment.push(environment: Environment(secureMenuService: service))
                controller = makeController(with: sampleItems(), service: service)
                select("s1", on: controller)
            }
            afterEach {
                service.deleteAllItems()
                AppEnvironment.popLast()
            }

            // 確認ダイアログを廃止した削除。戻せることが唯一の防波堤になる
            it("フィールドの削除を取り消すと同じ位置に復活する") {
                guard let target = controller.editor.draft?.fields.first else { return fail("no field") }
                controller.detailViewControllerForTesting.onFieldDeleteRequested?(target)
                expect(service.loadAllItems().first { $0.itemID == "s1" }?.fields.count) == 1

                controller.performUndo()
                let fields = service.loadAllItems().first { $0.itemID == "s1" }?.fields
                expect(fields?.map { $0.fieldID }) == ["f1", "f2"]
                expect(fields?.first?.value) == "alice"
            }

            it("フィールドの並べ替えを取り消すと元の順序に戻る") {
                expect(controller.editor.moveField(fieldID: "f1", by: 1)) == true
                expect(controller.commitIfNeeded()) == true
                expect(service.loadAllItems().first { $0.itemID == "s1" }?.fields.map { $0.fieldID }) == ["f2", "f1"]

                controller.performUndo()
                expect(service.loadAllItems().first { $0.itemID == "s1" }?.fields.map { $0.fieldID }) == ["f1", "f2"]
            }

            // 削除は displayOrder を振り直さないため、単純な再保存だと末尾へ回ってしまう
            it("アイテムの削除を取り消すと同じ位置に復活する") {
                select("s2", on: controller)
                guard let item = controller.editor.selectedItem else { return fail("no selection") }
                controller.deleteItem(item)
                expect(service.loadAllItems().map { $0.itemID }) == ["s1", "s3"]

                controller.performUndo()
                expect(service.loadAllItems().map { $0.itemID }) == ["s1", "s2", "s3"]
                expect(service.loadAllItems().map { $0.displayOrder }) == [0, 1, 2]
                expect(controller.editor.selectedItemID) == "s2"
            }

            it("アイテムの追加を取り消すと追加前に戻る") {
                controller.addItem()
                expect(service.loadAllItems().count) == 4

                controller.performUndo()
                expect(service.loadAllItems().map { $0.itemID }) == ["s1", "s2", "s3"]
            }

            it("アイテムの並べ替えを取り消すと元の順序に戻る") {
                select("s1", on: controller)
                controller.moveSelectedItem(by: 1)
                expect(service.loadAllItems().map { $0.itemID }) == ["s2", "s1", "s3"]

                controller.performUndo()
                expect(service.loadAllItems().map { $0.itemID }) == ["s1", "s2", "s3"]
            }

            // 削除は displayOrder を振り直さないので、真ん中を消すと [0, 2] のように穴が開く。
            // 一方 reorderItems は書き戻しで 0 から振り直すため、控えをそのまま信じると
            // 手元の写しと保存内容が食い違い、次に積む控えが実データと違う値を持ってしまう
            it("穴の開いた displayOrder を挟んでも、取り消し後の写しが保存内容と一致する") {
                select("s2", on: controller)
                guard let middle = controller.editor.selectedItem else { return fail("no selection") }
                controller.deleteItem(middle)
                // ここで手元の写しは [s1(0), s3(2)]（削除は振り直さない）
                expect(controller.editor.items.map { $0.displayOrder }) == [0, 2]

                select("s1", on: controller)
                _ = controller.editor.updateTitle("編集")
                expect(controller.commitIfNeeded()) == true

                controller.performUndo()
                expect(controller.editor.items) == service.loadAllItems()
                expect(controller.editor.items.map { $0.title }) == ["GitHub", "経理システム"]
            }

            it("並べ替えを取り消したあとも写しが一致する") {
                select("s1", on: controller)
                controller.moveSelectedItem(by: 1)
                controller.performUndo()
                expect(controller.editor.items) == service.loadAllItems()
            }

            it("削除したアイテムをやり直すと再び消える") {
                select("s2", on: controller)
                guard let item = controller.editor.selectedItem else { return fail("no selection") }
                controller.deleteItem(item)
                controller.performUndo()

                controller.performRedo()
                expect(service.loadAllItems().map { $0.itemID }) == ["s1", "s3"]
            }
        }
    }

    // MARK: - Import

    /// 取り込みはこの機能のなかで最も取り返しがつかない（既存のアイテムを
    /// まとめて上書きしうる）。読み直しは取り消しの世代を捨てるため、
    /// ここだけは世代を残して読み直している
    private static func importUndoSpecs() {
        describe("取り込みの取り消し") {

            var service: SecureMenuService!
            var controller: CPYSecureInfoSplitViewController!

            beforeEach {
                service = SecureMenuService(keychainService: testKeychainService)
                service.deleteAllItems()
                AppEnvironment.push(environment: Environment(secureMenuService: service))
                controller = makeController(with: sampleItems(), service: service)
                select("s1", on: controller)
            }
            afterEach {
                service.deleteAllItems()
                AppEnvironment.popLast()
            }

            it("取り込みで上書きされた内容を取り消しで戻せる") {
                // 別の内容で s1 を上書きし、新しい s9 を足すファイルを取り込んだ想定
                controller.pushUndoSnapshot(action: .importItems)
                _ = controller.performLocalChange {
                    SecureItemsTransfer.apply(items: [
                        SecureMenuItem(itemID: "s1", title: "上書きされた"),
                        SecureMenuItem(itemID: "s9", title: "取り込んだ")
                    ], cryptoPassword: nil, using: service)
                }
                controller.reloadItems(clearsUndoHistory: false)
                expect(service.loadAllItems().map { $0.itemID }) == ["s1", "s2", "s3", "s9"]
                expect(service.loadAllItems().first?.title) == "上書きされた"

                controller.performUndo()
                expect(service.loadAllItems().map { $0.itemID }) == ["s1", "s2", "s3"]
                expect(service.loadAllItems().first?.title) == "GitHub"
            }

            // 読み直しで世代を捨ててしまうと、取り込み直後に ⌘Z が効かない
            it("取り込み後の読み直しで世代を捨てない") {
                controller.pushUndoSnapshot(action: .importItems)
                controller.reloadItems(clearsUndoHistory: false)
                expect(controller.undoStack.canUndo) == true
                expect(controller.undoStack.undoAction) == SecureInfoUndoAction.importItems
            }

            // 既定の読み直しは従来どおり捨てる（控えが現在のデータと食い違うため）
            it("通常の読み直しでは捨てる") {
                controller.pushUndoSnapshot(action: .importItems)
                controller.reloadItems()
                expect(controller.undoStack.canUndo) == false
            }
        }
    }

    // MARK: - Value history

    private static func historyPreservationSpecs() {
        describe("値の変更履歴との関係") {

            var service: SecureMenuService!
            var controller: CPYSecureInfoSplitViewController!

            beforeEach {
                service = SecureMenuService(keychainService: testKeychainService)
                service.deleteAllItems()
                AppEnvironment.push(environment: Environment(secureMenuService: service))
                controller = makeController(with: sampleItems(), service: service)
                select("s1", on: controller)
            }
            afterEach {
                service.deleteAllItems()
                AppEnvironment.popLast()
            }

            // 書き戻しに save(_:) を使うと、取り消しのたびに旧値が履歴へ 1 件積まれ、
            // 上限 10 件の本当の旧値が押し出される。reorderItems は履歴をそのまま書くので増えない
            it("取り消しても変更履歴が増えない") {
                _ = controller.editor.updateField(fieldID: "f1", value: "bob")
                expect(controller.commitIfNeeded()) == true
                expect(field("ID", of: "s1", in: service)?.history.map { $0.value }) == ["alice"]

                controller.performUndo()
                let restored = field("ID", of: "s1", in: service)
                expect(restored?.value) == "alice"
                expect(restored?.history).to(beEmpty())
            }

            it("やり直すと保存直後の履歴がそのまま戻る") {
                _ = controller.editor.updateField(fieldID: "f1", value: "bob")
                expect(controller.commitIfNeeded()) == true
                controller.performUndo()

                controller.performRedo()
                let redone = field("ID", of: "s1", in: service)
                expect(redone?.value) == "bob"
                expect(redone?.history.map { $0.value }) == ["alice"]
            }

            it("何度取り消しても履歴が積み上がらない") {
                for value in ["bob", "carol", "dave"] {
                    _ = controller.editor.updateField(fieldID: "f1", value: value)
                    expect(controller.commitIfNeeded()) == true
                }
                expect(field("ID", of: "s1", in: service)?.history.count) == 3

                controller.performUndo()
                expect(field("ID", of: "s1", in: service)?.history.count) == 2
                controller.performUndo()
                expect(field("ID", of: "s1", in: service)?.history.count) == 1
            }
        }
    }

    // MARK: - Lifecycle

    /// 取り消しの世代は削除・編集前の**平文**を抱えている。
    /// 破棄すべき場面で残っていると、メモリ上に機微情報が残り続ける
    private static func lifecycleSpecs() {
        describe("世代の破棄") {

            var service: SecureMenuService!
            var controller: CPYSecureInfoSplitViewController!

            beforeEach {
                service = SecureMenuService(keychainService: testKeychainService)
                service.deleteAllItems()
                AppEnvironment.push(environment: Environment(secureMenuService: service))
                controller = makeController(with: sampleItems(), service: service)
                select("s1", on: controller)
            }
            afterEach {
                service.deleteAllItems()
                AppEnvironment.popLast()
            }

            func makeUndoableChange() {
                _ = controller.editor.updateField(fieldID: "f2", value: "new-password")
                expect(controller.commitIfNeeded()) == true
                expect(controller.undoStack.canUndo) == true
            }

            it("ウィンドウを閉じると平文ごと捨てる") {
                makeUndoableChange()
                controller.viewWillDisappear()
                expect(controller.undoStack.canUndo) == false
                expect(controller.undoStack.canRedo) == false
            }

            it("読み直すと捨てる") {
                makeUndoableChange()
                controller.reloadItems()
                expect(controller.undoStack.canUndo) == false
            }

            // 未保存の編集があると読み直さず案内バーを出す経路。ここで捨てないと
            // 控えてある状態が相手の変更を含まず、取り消した瞬間に巻き戻してしまう
            it("他の画面の変更で案内バーを出すときも捨てる") {
                makeUndoableChange()
                _ = controller.editor.updateTitle("Editing")
                expect(controller.editor.isDirty) == true

                expect(service.save(SecureMenuItem(itemID: "s9", title: "別画面が追加"))) == true
                controller.applyExternalChangeIfNeeded()

                expect(controller.detailViewControllerForTesting.externalChangeBanner.isHidden) == false
                expect(controller.undoStack.canUndo) == false
            }

            it("やり直しの世代も一緒に捨てる") {
                makeUndoableChange()
                controller.performUndo()
                expect(controller.undoStack.canRedo) == true

                controller.viewWillDisappear()
                expect(controller.undoStack.canRedo) == false
            }
        }
    }
}
