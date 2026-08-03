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

// BDD スペックは多数の it ブロックを含み型本体が長くなるため型長ルールを緩める
// swiftlint:disable:next type_body_length
class SecureInfoPasswordGeneratorSpec: QuickSpec {

    private static let testKeychainService = "io.github.boyaki-machine.ThothTests.SecureInfoPasswordGenerator"

    override class func spec() {
        acceptanceSpecs()
        fillTargetSpecs()
        preferredDestinationSpecs()
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

    /// **入力先は推測しない。** 候補を全部出して選ばせる。
    /// 以前はフォーカスや「マスク指定が 1 つだけか」から推測していたが、
    /// マスク中の値欄はクリックしても編集が始まらずフォーカスが記録されないうえ、
    /// マスク欄は空でも •••••••• と表示されて入ったか確かめられないため、
    /// 取り違えにも気づけなかった
    private static func fillTargetSpecs() {
        describe("入力先の候補") {

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

            // マスクの有無で候補を絞らない。テキスト欄へ入れたい場面もある
            it("受け取れるフィールドをすべて画面順で候補にする") {
                let detailViewController = makeDetailViewController()
                expect(detailViewController.fillCandidates.map { $0.field.fieldID }) == ["f1", "f2"]
            }

            // パスワード欄が 2 つあっても導線は消えない（以前はここで消えていた）
            it("マスク指定が複数あっても候補は残る") {
                let detailViewController = CPYSecureInfoDetailViewController()
                _ = detailViewController.view
                detailViewController.show(item: SecureMenuItem(itemID: "s1", title: "GitHub", fields: [
                    SecureMenuItem.Field(fieldID: "p1", label: "Password", value: "a", isPassword: true),
                    SecureMenuItem.Field(fieldID: "p2", label: "Recovery", value: "b", isPassword: true)
                ]))
                expect(detailViewController.fillCandidates.map { $0.field.fieldID }) == ["p1", "p2"]
            }

            // テキスト欄しか無くても使える（以前はここでも消えていた）
            it("マスク指定が 1 つも無くても候補は残る") {
                let detailViewController = CPYSecureInfoDetailViewController()
                _ = detailViewController.view
                detailViewController.show(item: SecureMenuItem(itemID: "s1", title: "GitHub", fields: [
                    SecureMenuItem.Field(fieldID: "f1", label: "ID", value: "alice")
                ]))
                expect(detailViewController.fillCandidates.map { $0.field.fieldID }) == ["f1"]
            }

            it("TOTP とメモは候補にしない") {
                let detailViewController = CPYSecureInfoDetailViewController()
                _ = detailViewController.view
                detailViewController.show(item: SecureMenuItem(itemID: "s1", title: "GitHub", fields: [
                    SecureMenuItem.Field(fieldID: "t1", label: "TOTP", value: "JBSWY3DPEHPK3PXP",
                                         isPassword: false, kind: .totp),
                    SecureMenuItem.Field(fieldID: "n1", label: "Memo", value: "hello",
                                         isPassword: false, kind: .note)
                ]))
                expect(detailViewController.fillCandidates.isEmpty) == true
            }

            it("読み取り専用では候補にしない") {
                let detailViewController = CPYSecureInfoDetailViewController()
                _ = detailViewController.view
                detailViewController.isReadOnly = true
                detailViewController.show(item: SecureMenuItem(itemID: "s1", title: "GitHub", fields: [
                    SecureMenuItem.Field(fieldID: "f2", label: "Password", value: "old", isPassword: true)
                ]))
                expect(detailViewController.fillCandidates.isEmpty) == true
            }

        }
    }

    /// 初期選択はあくまで手掛かり。外れていても画面上で選び直せる
    private static func preferredDestinationSpecs() {
        describe("入力先の初期選択") {

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

            // 直前に編集していた欄は初期選択の手掛かりにするだけ。
            // 記録が無くても候補が消えないことが、以前との一番の違い
            it("直前に編集していた欄を初期選択にする") {
                let detailViewController = makeDetailViewController()
                detailViewController.fillTargetFieldID = "f2"
                expect(detailViewController.preferredFillFieldID) == "f2"
            }

            // ID 欄が既定になっていると、生成値で誤って潰しやすい
            it("覚えが無ければマスク指定の先頭を初期選択にする") {
                let detailViewController = makeDetailViewController()
                expect(detailViewController.fillTargetFieldID) == nil
                expect(detailViewController.preferredFillFieldID) == "f2"
            }

            it("マスク指定が無ければ初期選択も無い（候補は残る）") {
                let detailViewController = CPYSecureInfoDetailViewController()
                _ = detailViewController.view
                detailViewController.show(item: SecureMenuItem(itemID: "s1", title: "GitHub", fields: [
                    SecureMenuItem.Field(fieldID: "f1", label: "ID", value: "alice")
                ]))
                expect(detailViewController.preferredFillFieldID) == nil
                expect(detailViewController.fillCandidates.isEmpty) == false
            }

            // TOTP の secret を生成値で潰さないための境界
            it("受け取れない種別を覚えていたら初期選択に使わない") {
                let detailViewController = makeDetailViewController()
                detailViewController.fillTargetFieldID = "f3"   // TOTP
                expect(detailViewController.preferredFillFieldID) != "f3"
            }

            it("消えたフィールドを覚えていたら初期選択に使わない") {
                let detailViewController = makeDetailViewController()
                detailViewController.fillTargetFieldID = "missing"
                expect(detailViewController.preferredFillFieldID) != "missing"
            }

            // 別のアイテムの値へ生成値を撃ち込まないための境界
            it("別のアイテムへ移ると忘れる") {
                let detailViewController = makeDetailViewController()
                detailViewController.fillTargetFieldID = "f2"
                detailViewController.show(item: SecureMenuItem(itemID: "s2", title: "AWS", fields: [
                    SecureMenuItem.Field(fieldID: "f9", label: "Password", value: "x", isPassword: true)
                ]))
                expect(detailViewController.fillTargetFieldID) == nil
                expect(detailViewController.fillCandidates.map { $0.field.fieldID }) == ["f9"]
            }

            // フィールドの追加・削除・並べ替え・マスク切替でも show(item:) を通る
            it("同じアイテムの中の作り直しでは忘れない") {
                let detailViewController = makeDetailViewController()
                detailViewController.fillTargetFieldID = "f2"
                detailViewController.show(item: SecureMenuItem(itemID: "s1", title: "GitHub", fields: [
                    SecureMenuItem.Field(fieldID: "f2", label: "Password", value: "old", isPassword: true),
                    SecureMenuItem.Field(fieldID: "f1", label: "ID", value: "alice")
                ]))
                expect(detailViewController.preferredFillFieldID) == "f2"
            }

            // ラベルが空でもポップアップから選べる必要がある
            it("ラベルが空なら種別の既定名で表示する") {
                let masked = SecureMenuItem.Field(label: "  ", value: "", isPassword: true)
                let plain  = SecureMenuItem.Field(label: "", value: "", isPassword: false)
                expect(CPYSecureInfoSplitViewController.destinationTitle(for: masked))
                    == L10n.secureFieldDefaultLabelPassword
                expect(CPYSecureInfoSplitViewController.destinationTitle(for: plain))
                    == L10n.secureFieldDefaultLabelText
                let named = SecureMenuItem.Field(label: "Password", value: "", isPassword: true)
                expect(CPYSecureInfoSplitViewController.destinationTitle(for: named)) == "Password"
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
                expect(detail.fillCandidates.map { $0.field.fieldID }).to(contain("f2"))
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

    /// 入力先の選択とボタンの出し入れ。
    /// 独立ウィンドウや指紋パスワード管理から開いたときに出てしまうと、
    /// 押しても何も起きないボタンになる
    private static func generatorSheetSpecs() {
        describe("生成シートの入力先") {

            let destinations = [
                CPYPasswordGeneratorViewController.FillDestination(fieldID: "f1", title: "ID"),
                CPYPasswordGeneratorViewController.FillDestination(fieldID: "f2", title: "Password")
            ]

            it("候補が無ければ入力の導線を出さない") {
                let generator = CPYPasswordGeneratorViewController()
                _ = generator.view
                expect(generator.useButton.isHidden) == true
                expect(generator.destinationPopUp.isHidden) == true
            }

            it("候補があれば入力の導線を出す") {
                let generator = CPYPasswordGeneratorViewController()
                generator.fillDestinations = destinations
                generator.onUse = { _, _ in }
                _ = generator.view
                expect(generator.useButton.isHidden) == false
                expect(generator.destinationPopUp.isHidden) == false
                expect(generator.destinationPopUp.itemTitles) == ["ID", "Password"]
            }

            // onUse を渡さない呼び出し（独立ウィンドウ）では出さない
            it("受け取り口が無ければ候補があっても出さない") {
                let generator = CPYPasswordGeneratorViewController()
                generator.fillDestinations = destinations
                _ = generator.view
                expect(generator.useButton.isHidden) == true
            }

            it("覚えている欄を初期選択にする") {
                let generator = CPYPasswordGeneratorViewController()
                generator.fillDestinations = destinations
                generator.preferredDestinationID = "f2"
                generator.onUse = { _, _ in }
                _ = generator.view
                expect(generator.selectedDestination?.fieldID) == "f2"
            }

            it("覚えが無ければ先頭を選ぶ") {
                let generator = CPYPasswordGeneratorViewController()
                generator.fillDestinations = destinations
                generator.onUse = { _, _ in }
                _ = generator.view
                expect(generator.selectedDestination?.fieldID) == "f1"
            }

            // ラベルが同名でも取り違えないよう、選択は添字で解決する
            it("同名のラベルでも添字で取り違えない") {
                let generator = CPYPasswordGeneratorViewController()
                generator.fillDestinations = [
                    CPYPasswordGeneratorViewController.FillDestination(fieldID: "a", title: "Password"),
                    CPYPasswordGeneratorViewController.FillDestination(fieldID: "b", title: "Password")
                ]
                generator.onUse = { _, _ in }
                _ = generator.view
                generator.destinationPopUp.selectItem(at: 1)
                expect(generator.selectedDestination?.fieldID) == "b"
            }

            // loadView() より後に候補を設定しても取りこぼさない
            it("表示直前の設定にも追従する") {
                let generator = CPYPasswordGeneratorViewController()
                _ = generator.view
                expect(generator.useButton.isHidden) == true
                generator.fillDestinations = destinations
                generator.onUse = { _, _ in }
                generator.reloadFillDestinations()
                expect(generator.useButton.isHidden) == false
            }
        }
    }
}
