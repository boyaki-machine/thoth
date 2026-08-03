import Quick
import Nimble
import AppKit
@testable import Thoth

// MARK: - Secure Info Window Password Generator Tests
//
// 廃止したセキュアアイテム管理ウィンドウから引き継いだ機能。
// あちらは生成画面を開くだけで、値はユーザーが手でコピペしていた。
// こちらは選択中のフィールドへ直接入れるので、そのぶん
// 「どの行が入力先か」「マスク中でも入るか」を落とさず担保する必要がある。

class SecureInfoPasswordGeneratorSpec: QuickSpec {

    private static let testKeychainService = "io.github.boyaki-machine.ThothTests.SecureInfoPasswordGenerator"

    override class func spec() {
        acceptanceSpecs()
        fillTargetSpecs()
        applySpecs()
        generatorSheetSpecs()
    }

    // MARK: - どの種別が生成値を受け取れるか

    /// 種別ごとの判断は `SecureMenuItem.Field.Kind` に集約してある。
    /// ここを固定しておかないと、種別が増えたときに TOTP の secret へ
    /// 生成値を上書きしてしまう事故が静かに通る
    private static func acceptanceSpecs() {
        describe("生成値を受け取れる種別") {

            it("テキスト（plain）だけが受け取る") {
                expect(SecureMenuItem.Field.Kind.plain.acceptsGeneratedPassword) == true
                expect(SecureMenuItem.Field.Kind.totp.acceptsGeneratedPassword) == false
                expect(SecureMenuItem.Field.Kind.url.acceptsGeneratedPassword) == false
                expect(SecureMenuItem.Field.Kind.note.acceptsGeneratedPassword) == false
            }

            it("マスクの有無は問わない") {
                let masked = SecureMenuItem.Field(label: "Password", value: "old", isPassword: true)
                let plain  = SecureMenuItem.Field(label: "ID", value: "alice", isPassword: false)
                expect(SecureFieldRowView.acceptsGeneratedPassword(field: masked, isReadOnly: false)) == true
                expect(SecureFieldRowView.acceptsGeneratedPassword(field: plain, isReadOnly: false)) == true
            }

            it("読み取り専用モードでは受け取らない") {
                let field = SecureMenuItem.Field(label: "Password", value: "old", isPassword: true)
                expect(SecureFieldRowView.acceptsGeneratedPassword(field: field, isReadOnly: true)) == false
            }

            it("TOTP は secret なので受け取らない") {
                let totp = SecureMenuItem.Field(label: "TOTP", value: "JBSWY3DPEHPK3PXP",
                                                isPassword: false, kind: .totp)
                expect(SecureFieldRowView.acceptsGeneratedPassword(field: totp, isReadOnly: false)) == false
            }
        }
    }

    // MARK: - 入力先の記憶

    /// ボタンを押した時点では編集が終わっていて first responder が行から離れている。
    /// 「直前にフォーカスが入っていた行」を覚えておかないと入力先が分からなくなる
    private static func fillTargetSpecs() {
        describe("入力先の記憶") {

            /// 行を組み立てた右ペインを作る
            func makeDetailViewController() -> CPYSecureInfoDetailViewController {
                let detailViewController = CPYSecureInfoDetailViewController()
                _ = detailViewController.view
                detailViewController.show(item: SecureMenuItem(itemID: "s1", title: "GitHub", fields: [
                    SecureMenuItem.Field(fieldID: "f1", label: "ID", value: "alice"),
                    SecureMenuItem.Field(fieldID: "f2", label: "Password", value: "old", isPassword: true),
                    SecureMenuItem.Field(fieldID: "f3", label: "TOTP", value: "JBSWY3DPEHPK3PXP",
                                         isPassword: false, kind: .totp)
                ]))
                return detailViewController
            }

            it("覚えた ID から行を解決する") {
                let detailViewController = makeDetailViewController()
                detailViewController.fillTargetFieldID = "f2"
                expect(detailViewController.fillTargetRow?.field.fieldID) == "f2"
            }

            // マスク中の値欄はクリックしても編集が始まらないため、素直に
            // パスワード欄を触ったユーザーには入力先が記録されない。
            // ラベルを選ばないと使えない機能にしないための逃げ道
            it("覚えが無くても、マスク指定が 1 つならそこへ入れる") {
                let detailViewController = makeDetailViewController()
                expect(detailViewController.fillTargetFieldID) == nil
                expect(detailViewController.fillTargetRow?.field.fieldID) == "f2"
            }

            // どちらのパスワードを潰すかを間違えると取り返しがつきにくい
            it("マスク指定が複数あるときは推測しない") {
                let detailViewController = CPYSecureInfoDetailViewController()
                _ = detailViewController.view
                detailViewController.show(item: SecureMenuItem(itemID: "s1", title: "GitHub", fields: [
                    SecureMenuItem.Field(fieldID: "p1", label: "Password", value: "a", isPassword: true),
                    SecureMenuItem.Field(fieldID: "p2", label: "Recovery", value: "b", isPassword: true)
                ]))
                expect(detailViewController.fillTargetRow) == nil
            }

            it("マスク指定が 1 つも無ければ推測しない") {
                let detailViewController = CPYSecureInfoDetailViewController()
                _ = detailViewController.view
                detailViewController.show(item: SecureMenuItem(itemID: "s1", title: "GitHub", fields: [
                    SecureMenuItem.Field(fieldID: "f1", label: "ID", value: "alice")
                ]))
                expect(detailViewController.fillTargetRow) == nil
            }

            // 行ビューは並べ替え・マスク切替のたびに作り直される。
            // ビュー参照ではなく ID で覚えているので、作り直しても解決できる
            it("行を作り直しても解決し直せる") {
                let detailViewController = makeDetailViewController()
                detailViewController.fillTargetFieldID = "f2"
                let before = detailViewController.fillTargetRow
                detailViewController.show(item: detailViewController.displayedItem)
                let after = detailViewController.fillTargetRow
                expect(after?.field.fieldID) == "f2"
                // 作り直されているので別インスタンスになっている
                expect(after !== before) == true
            }

            // 覚えていた行が使えない場合は、覚えを捨てて通常の判断に落ちる。
            // TOTP の secret を生成値で潰さないことがここの要点
            it("受け取れない種別を覚えていたら、それは入力先にしない") {
                let detailViewController = makeDetailViewController()
                detailViewController.fillTargetFieldID = "f3"   // TOTP
                expect(detailViewController.fillTargetRow?.field.fieldID) != "f3"
            }

            it("消えたフィールドを覚えていたら、それは入力先にしない") {
                let detailViewController = makeDetailViewController()
                detailViewController.fillTargetFieldID = "missing"
                expect(detailViewController.fillTargetRow?.field.fieldID) != "missing"
            }

            // 別のアイテムの値へ生成値を撃ち込まないための境界
            it("別のアイテムへ移ると忘れる") {
                let detailViewController = makeDetailViewController()
                detailViewController.fillTargetFieldID = "f2"
                detailViewController.show(item: SecureMenuItem(itemID: "s2", title: "AWS", fields: [
                    SecureMenuItem.Field(fieldID: "f9", label: "Password", value: "x", isPassword: true)
                ]))
                expect(detailViewController.fillTargetFieldID) == nil
                // 移った先のフィールドだけが候補になる（前のアイテムの f2 は残らない）
                expect(detailViewController.fillTargetRow?.field.fieldID) == "f9"
            }

            // フィールドの追加・削除・並べ替え・マスク切替でも show(item:) を通る。
            // ここで忘れてしまうと、行を動かした直後に入力先を選び直す羽目になる
            it("同じアイテムの中の作り直しでは忘れない") {
                let detailViewController = makeDetailViewController()
                detailViewController.fillTargetFieldID = "f2"
                detailViewController.show(item: SecureMenuItem(itemID: "s1", title: "GitHub", fields: [
                    SecureMenuItem.Field(fieldID: "f2", label: "Password", value: "old", isPassword: true),
                    SecureMenuItem.Field(fieldID: "f1", label: "ID", value: "alice")
                ]))
                expect(detailViewController.fillTargetFieldID) == "f2"
                expect(detailViewController.fillTargetRow?.field.fieldID) == "f2"
            }
        }
    }

    // MARK: - 生成値の反映

    private static func applySpecs() {
        describe("生成値の反映") {

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

            it("作業コピーに入り、Keychain まで保存される") {
                let splitViewController = makeSplitViewController()
                splitViewController.applyGeneratedPassword("Generated-1", toFieldID: "f2")

                expect(splitViewController.editor.draft?.fields.first { $0.fieldID == "f2" }?.value) == "Generated-1"
                let saved = service.loadAllItems().first { $0.itemID == "s1" }
                expect(saved?.fields.first { $0.fieldID == "f2" }?.value) == "Generated-1"
            }

            // マスク中は「伏せ字を見ながらの手入力」を禁じているだけで、
            // モデル経由の書き換えは別経路。ここを禁じると使い道が無くなる
            it("マスク中のフィールドにも入る") {
                let splitViewController = makeSplitViewController()
                let masked = splitViewController.editor.draft?.fields.first { $0.fieldID == "f2" }
                expect(masked?.isPassword) == true

                splitViewController.applyGeneratedPassword("Generated-2", toFieldID: "f2")

                let after = splitViewController.editor.draft?.fields.first { $0.fieldID == "f2" }
                expect(after?.value) == "Generated-2"
                // マスク指定は変わらない
                expect(after?.isPassword) == true
            }

            // 旧値は退避経路になるので、上書きで消してはいけない
            it("旧値が変更履歴に残る") {
                let splitViewController = makeSplitViewController()
                splitViewController.applyGeneratedPassword("Generated-3", toFieldID: "f2")

                let saved = service.loadAllItems().first { $0.itemID == "s1" }
                let history = saved?.fields.first { $0.fieldID == "f2" }?.history ?? []
                expect(history.map { $0.value }).to(contain("old"))
            }

            // 削除した直後にシートから戻ってくる、といった競合を素通ししない
            it("存在しないフィールドには何もしない") {
                let splitViewController = makeSplitViewController()
                splitViewController.applyGeneratedPassword("Generated-4", toFieldID: "missing")

                let saved = service.loadAllItems().first { $0.itemID == "s1" }
                expect(saved?.fields.first { $0.fieldID == "f2" }?.value) == "old"
                expect(saved?.fields.contains { $0.value == "Generated-4" }) == false
            }

            // 実際に起きた事故の再現。生成値を入れると行が作り直されるが、
            // フィールドエディタはウィンドウで 1 つを使い回すため、画面から外した
            // 古い行にも編集通知が届く。届いた行が「画面に見えていた文字列」
            // （マスク中なら ••••••••、未入力なら空文字）を書き戻していた。
            // 結果、生成したパスワードが変更履歴へ押し出されて値が化けた
            it("画面から外した行は作業コピーを書き換えない") {
                let splitViewController = makeSplitViewController()
                let detail = splitViewController.detailViewControllerForTesting
                guard let staleRow = detail.fieldRows.first(where: { $0.field.fieldID == "f2" }) else {
                    fail("行が見つからない"); return
                }

                splitViewController.applyGeneratedPassword("Generated-6", toFieldID: "f2")

                // 作り直しで捨てられた行が、あとから編集通知を送ってくる
                staleRow.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification,
                                                           object: staleRow.valueField))
                staleRow.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification,
                                                           object: staleRow.labelField))
                splitViewController.commitIfNeeded()

                let saved = service.loadAllItems().first { $0.itemID == "s1" }
                let field = saved?.fields.first { $0.fieldID == "f2" }
                expect(field?.value) == "Generated-6"
                expect(field?.label) == "Password"
                // 生成値が履歴へ押し出されていないこと
                expect(field?.history.map { $0.value }) == ["old"]
            }

            // ラベルまで空にされると commitOutcome() の「ラベルも値も空なら除去」に
            // 掛かってフィールドごと消え、次から入力先を解決できなくなる
            it("捨てた行の書き戻しでフィールドが消えない") {
                let splitViewController = makeSplitViewController()
                let detail = splitViewController.detailViewControllerForTesting
                guard let staleRow = detail.fieldRows.first(where: { $0.field.fieldID == "f2" }) else {
                    fail("行が見つからない"); return
                }
                staleRow.labelField.stringValue = ""
                staleRow.valueField.stringValue = ""

                splitViewController.applyGeneratedPassword("Generated-7", toFieldID: "f2")
                staleRow.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification,
                                                           object: staleRow.labelField))
                staleRow.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification,
                                                           object: staleRow.valueField))
                splitViewController.commitIfNeeded()

                let saved = service.loadAllItems().first { $0.itemID == "s1" }
                expect(saved?.fields.contains { $0.fieldID == "f2" }) == true
                expect(detail.fillTargetRow?.field.fieldID) == "f2"
            }

            it("⌘Z で生成前の値へ戻せる") {
                let splitViewController = makeSplitViewController()
                splitViewController.applyGeneratedPassword("Generated-5", toFieldID: "f2")
                expect(splitViewController.undoStack.undoAction) != nil

                splitViewController.performUndo()

                let saved = service.loadAllItems().first { $0.itemID == "s1" }
                expect(saved?.fields.first { $0.fieldID == "f2" }?.value) == "old"
            }
        }
    }

    // MARK: - 生成シート側

    /// 「この項目に入力」は入力先を持つ呼び出しでだけ出す。
    /// 独立ウィンドウや指紋パスワード管理から開いたときに出てしまうと、
    /// 押しても何も起きないボタンになる
    private static func generatorSheetSpecs() {
        describe("生成シートの「この項目に入力」") {

            it("onUse が無ければ出さない") {
                let generator = CPYPasswordGeneratorViewController()
                _ = generator.view
                expect(generator.useButton.isHidden) == true
            }

            it("onUse があれば出す") {
                let generator = CPYPasswordGeneratorViewController()
                generator.onUse = { _ in }
                _ = generator.view
                expect(generator.useButton.isHidden) == false
            }

            // loadView() より後に onUse を設定しても取りこぼさない
            it("表示直前の設定にも追従する") {
                let generator = CPYPasswordGeneratorViewController()
                _ = generator.view
                expect(generator.useButton.isHidden) == true
                generator.onUse = { _ in }
                generator.updateUseButtonVisibility()
                expect(generator.useButton.isHidden) == false
            }
        }
    }
}
