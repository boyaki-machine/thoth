import Quick
import Nimble
import AppKit
@testable import Thoth

// セキュアアイテム選択パネルの検索フィルタ・行構成・サブパネル表示のスペック。
// パネルはヘッドレスで生成し、表示（show）は行わない。
// BDD スペックは多数の it ブロックを含み型本体が長くなるため型長ルールを緩める
class CPYSecurePickerPanelSpec: QuickSpec {

    override class func spec() {
        searchFilterSpecs()
        dismissDecisionSpecs()
        monitorLifecycleSpecs()
        rowCompositionSpecs()
        manageShortcutSpecs()
        subPanelFieldSpecs()
        subPanelDisplaySpecs()
        subPanelSelectionSpecs()
        continuationIndexSpecs()
        pagingSpecs()
    }

    // MARK: - Fixtures

    static func sampleItems() -> [SecureMenuItem] {
        return [
            SecureMenuItem(title: "GitHub", fields: [
                SecureMenuItem.Field(label: "Password", value: "a", isPassword: true),
                SecureMenuItem.Field(label: "Token", value: "github-token", isPassword: true)
            ]),
            SecureMenuItem(title: "AWS Console", fields: [
                SecureMenuItem.Field(label: "Login ID", value: "console-user", isPassword: false)
            ])
        ]
    }

    static func makePanel(items: [SecureMenuItem]? = nil, query: String = "") -> CPYSecurePickerPanel {
        let panel = CPYSecurePickerPanel(items: items ?? sampleItems(), context: SecureSelectionContext())
        panel.searchField.stringValue = query
        panel.rebuildRows()
        return panel
    }

    static func parentTitles(_ panel: CPYSecurePickerPanel) -> [String] {
        return panel.rows.compactMap { row in
            if case .parent(let item) = row { return item.title }
            return nil
        }
    }

    // MARK: - Search

    /// 絞り込みの条件そのものは共通ロジック側（`SecureItemSearchSpec`）で固定している。
    /// ここで見るのは「パネルが検索窓の内容を共通ロジックへ渡せているか」と、
    /// パネル固有の入口（空クエリ・空白のみ）の扱い
    static func searchFilterSpecs() {
        describe("インクリメンタルサーチのフィルタ") {
            it("タイトルの部分一致でヒットする（大文字小文字無視）") {
                let panel = makePanel(query: "github")
                expect(panel.filteredItems().map { $0.title }) == ["GitHub"]
                panel.close()
            }

            it("フィールドラベルの一致でもヒットする") {
                let panel = makePanel(query: "token")
                expect(panel.filteredItems().map { $0.title }) == ["GitHub"]
                panel.close()
            }

            // v1.3.1 で確認ウィンドウと条件を揃えた。
            // それまではラベルしか見ておらず、値では探せなかった
            it("マスクを掛けていない値でもヒットする") {
                let panel = makePanel(query: "console-user")
                expect(panel.filteredItems().map { $0.title }) == ["AWS Console"]
                panel.close()
            }

            it("マスクを掛けた値・TOTP secret では探せない") {
                let masked = makePanel(query: "github-token")
                expect(masked.filteredItems()).to(beEmpty())

                let totpItem = SecureMenuItem(title: "TOTP Item", fields: [
                    SecureMenuItem.Field(label: "TOTP", value: "otpauth://totp/X?secret=JBSWY3DPEHPK3PXP",
                                         kind: .totp)
                ])
                let totp = makePanel(items: [totpItem], query: "JBSWY3DPEHPK3PXP")
                expect(totp.filteredItems()).to(beEmpty())
                masked.close()
                totp.close()
            }

            // 以前は「1 つのラベル内で全語一致」しか通らず、
            // タイトルと値をまたいだ複数語では探せなかった
            it("複数語はタイトル・ラベル・値をまたいで AND 一致する") {
                let panel = makePanel(query: "aws console-user")
                expect(panel.filteredItems().map { $0.title }) == ["AWS Console"]
                let none = makePanel(query: "aws github")
                expect(none.filteredItems()).to(beEmpty())
                panel.close()
                none.close()
            }

            it("空クエリは全件を返す") {
                let panel = makePanel()
                expect(panel.filteredItems().count) == 2
                panel.close()
            }

            // 特殊値: 空白だけのクエリは「絞り込みなし」として扱う
            it("空白だけのクエリは全件を返す") {
                let panel = makePanel(query: "   ")
                expect(panel.filteredItems().count) == 2
                panel.close()
            }
        }
    }

    // MARK: - Dismiss

    static func dismissDecisionSpecs() {
        describe("パネル外クリックの解除判定") {
            it("本体ウィンドウとサブパネル（子ウィンドウ）は「属する＝閉じない」と判定する") {
                let panel = makePanel()
                let child = NSWindow(contentRect: .zero, styleMask: [.borderless],
                                     backing: .buffered, defer: false)
                panel.addChildWindow(child, ordered: .above)
                expect(panel.belongsToPanelGroup(panel)) == true
                expect(panel.belongsToPanelGroup(child)) == true
                panel.removeChildWindow(child)
                panel.close()
            }

            it("無関係なウィンドウと nil は「属さない＝閉じる」と判定する") {
                let panel = makePanel()
                let other = NSWindow(contentRect: .zero, styleMask: [.borderless],
                                     backing: .buffered, defer: false)
                expect(panel.belongsToPanelGroup(other)) == false
                expect(panel.belongsToPanelGroup(nil)) == false
                panel.close()
            }
        }
    }

    static func monitorLifecycleSpecs() {
        describe("解除モニタのライフサイクル") {
            it("install で登録され、多重呼び出しでも累積せず、close で全解除される") {
                let panel = makePanel()
                panel.installDismissMonitors()
                let installed = panel.dismissMonitorCount
                expect(installed) >= 1
                // 多重呼び出しでモニタが二重登録（リーク）しない
                panel.installDismissMonitors()
                expect(panel.dismissMonitorCount) == installed
                // close で確実に解除される
                panel.close()
                expect(panel.dismissMonitorCount) == 0
            }
        }
    }

    // MARK: - Rows

    static func rowCompositionSpecs() {
        describe("行構成") {
            it("通常時は親アイテム + 区切り線 + セキュア情報確認の行が並ぶ") {
                let panel = makePanel()
                var parentCount = 0
                var hasManage = false
                for row in panel.rows {
                    if case .parent = row { parentCount += 1 }
                    if case .manage = row { hasManage = true }
                }
                expect(parentCount) == 2
                expect(hasManage) == true
                panel.close()
            }

            it("ヒットなしの検索では noResults 行とセキュア情報確認の行が表示される") {
                let panel = makePanel(query: "no-such-item")
                var hasNoResults = false
                var hasManage = false
                for row in panel.rows {
                    if case .noResults = row { hasNoResults = true }
                    if case .manage = row { hasManage = true }
                }
                expect(hasNoResults) == true
                expect(hasManage) == true
                panel.close()
            }
        }
    }

    // MARK: - Secure info shortcut

    /// v1.3.0 でセキュアアイテム管理ウィンドウを廃止し、この行の宛先を
    /// セキュア情報確認ウィンドウへ移した。キーもメインメニューと揃えて p → s。
    ///
    /// **押す位置ではなく "s" という文字で判定する。** 表示は "(&s)" と約束しており、
    /// キーコードで見ると Dvorak 等の配列で「s と書いてあるのに s では開かない」
    /// 状態になる（hjkl は押す位置に意味があるのでキーコードのままでよい）
    static func manageShortcutSpecs() {
        describe("セキュア情報確認へのショートカット") {

            /// 検索欄にフォーカスが無い状態の keyDown を作る。
            /// keyCode と文字を別々に渡せるようにして、配列依存を検出できるようにする
            func keyDown(_ character: String, keyCode: UInt16,
                         modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
                return NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
                                        timestamp: 0, windowNumber: 0, context: nil,
                                        characters: character, charactersIgnoringModifiers: character,
                                        isARepeat: false, keyCode: keyCode)!
            }

            func firesManage(_ event: NSEvent) -> (handled: Bool, fired: Bool) {
                let panel = makePanel()
                var fired = false
                panel.onManage = { fired = true }
                let handled = panel.handleKeyDown(event)
                panel.close()
                return (handled, fired)
            }

            it("s キーで開く") {
                let result = firesManage(keyDown("s", keyCode: 1))
                expect(result.handled) == true
                expect(result.fired) == true
            }

            // QWERTY の s の位置（keyCode 1）に別の文字が来る配列でも、
            // 打った文字が s であれば開く
            it("キーボード配列に依存しない") {
                // Dvorak では keyCode 1 は "o"、"s" は keyCode 41 に来る
                let byCharacter = firesManage(keyDown("s", keyCode: 41))
                expect(byCharacter.fired) == true

                // 逆に、位置が同じでも文字が違えば開かない
                let byPosition = firesManage(keyDown("o", keyCode: 1))
                expect(byPosition.handled) == false
                expect(byPosition.fired) == false
            }

            it("大文字の S でも開く") {
                expect(firesManage(keyDown("S", keyCode: 1, modifiers: .shift)).fired) == true
            }

            // ⌘S など修飾キー付きは別の意味を持つので横取りしない
            it("修飾キー付きでは開かない") {
                expect(firesManage(keyDown("s", keyCode: 1, modifiers: .command)).fired) == false
                expect(firesManage(keyDown("s", keyCode: 1, modifiers: .control)).fired) == false
                expect(firesManage(keyDown("s", keyCode: 1, modifiers: .option)).fired) == false
            }

            it("旧ショートカットの p は解放されている") {
                let result = firesManage(keyDown("p", keyCode: 35))
                expect(result.handled) == false
                expect(result.fired) == false
            }

            // ラベルとキー処理が同じ定義元から作られていること
            it("表示ラベルがメインメニューと同じ文言・同じキーになる") {
                let panel = makePanel()
                guard let row = panel.rows.firstIndex(where: {
                    if case .manage = $0 { return true } else { return false }
                }) else { fail("管理行が無い"); return }
                let cell = panel.tableView(panel.tableView, viewFor: nil, row: row) as? NSTableCellView
                expect(cell?.textField?.stringValue)
                    == "\(L10n.secureInfo) (&\(CPYSecurePickerPanel.secureInfoShortcutKey))"
                // メインメニュー側の (&s) と同じキーであること
                expect(CPYSecurePickerPanel.secureInfoShortcutKey)
                    == CPYHistoryPickerPanel.PanelAction.secureInfo.shortcutKey
                panel.close()
            }
        }
    }
}
