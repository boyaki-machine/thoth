import Quick
import Nimble
import AppKit
@testable import Thoth

// セキュアアイテム選択パネルの検索フィルタ・行構成・サブパネル表示のスペック。
// パネルはヘッドレスで生成し、表示（show）は行わない。
// BDD スペックは多数の it ブロックを含み型本体が長くなるため型長ルールを緩める
// swiftlint:disable:next type_body_length
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

    private static func sampleItems() -> [SecureMenuItem] {
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

    private static func makePanel(items: [SecureMenuItem]? = nil, query: String = "") -> CPYSecurePickerPanel {
        let panel = CPYSecurePickerPanel(items: items ?? sampleItems(), context: SecureSelectionContext())
        panel.searchField.stringValue = query
        panel.rebuildRows()
        return panel
    }

    private static func parentTitles(_ panel: CPYSecurePickerPanel) -> [String] {
        return panel.rows.compactMap { row in
            if case .parent(let item) = row { return item.title }
            return nil
        }
    }

    // MARK: - Search

    /// 絞り込みの条件そのものは共通ロジック側（`SecureItemSearchSpec`）で固定している。
    /// ここで見るのは「パネルが検索窓の内容を共通ロジックへ渡せているか」と、
    /// パネル固有の入口（空クエリ・空白のみ）の扱い
    private static func searchFilterSpecs() {
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

    private static func dismissDecisionSpecs() {
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

    private static func monitorLifecycleSpecs() {
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

    private static func rowCompositionSpecs() {
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
    private static func manageShortcutSpecs() {
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

    // MARK: - Sub-panel field selection

    /// 確定時の fieldIndex は `subPanelFields` が返す配列に対する添字として記録・復元される。
    /// 除外と順序がずれると継続ペーストモードが別のフィールドを貼り付けてしまう
    private static func subPanelFieldSpecs() {
        describe("サブパネルに出すフィールド") {

            // subPanelFields はサブパネルの内容と開閉判定の唯一の入口。
            // ここが item.fields に戻ると添字がずれ、空のサブパネルも開くようになる
            it("subPanelFields はメモを除いた配列を返す") {
                let item = SecureMenuItem(title: "Mixed", fields: [
                    SecureMenuItem.Field(label: "ID", value: "user"),
                    SecureMenuItem.Field(label: "Memo", value: "m", kind: .note),
                    SecureMenuItem.Field(label: "URL", value: "https://example.com", kind: .url)
                ])
                expect(CPYSecurePickerPanel.subPanelFields(for: item)?.map { $0.label }) == ["ID", "URL"]
            }

            it("表示対象が無いアイテムでは subPanelFields が nil を返す（サブパネルを開かない）") {
                let noteOnly = SecureMenuItem(title: "Memo only", fields: [
                    SecureMenuItem.Field(label: "Memo", value: "m", kind: .note)
                ])
                expect(CPYSecurePickerPanel.subPanelFields(for: noteOnly)) == nil
                expect(CPYSecurePickerPanel.subPanelFields(for: SecureMenuItem(title: "Empty"))) == nil
            }

            it("メモは除外され、URL と TOTP は残る") {
                let item = SecureMenuItem(title: "Accounting", fields: [
                    SecureMenuItem.Field(label: "ID", value: "user"),
                    SecureMenuItem.Field(label: "Memo", value: "契約番号: 12345", kind: .note),
                    SecureMenuItem.Field(label: "URL", value: "https://example.com", kind: .url),
                    SecureMenuItem.Field(label: "TOTP", value: "otpauth://totp/X?secret=JBSWY3DPEHPK3PXP", kind: .totp)
                ])
                expect(item.pickerFields.map { $0.label }) == ["ID", "URL", "TOTP"]
            }

            it("メモを挟んでも残りのフィールドの相対順序は保たれる") {
                let item = SecureMenuItem(title: "T", fields: [
                    SecureMenuItem.Field(label: "Memo1", value: "m", kind: .note),
                    SecureMenuItem.Field(label: "A", value: "1"),
                    SecureMenuItem.Field(label: "Memo2", value: "m", kind: .note),
                    SecureMenuItem.Field(label: "B", value: "2"),
                    SecureMenuItem.Field(label: "Memo3", value: "m", kind: .note)
                ])
                expect(item.pickerFields.map { $0.label }) == ["A", "B"]
            }

            // メモのラベルで検索した場合も、アイテム自体は見つかる（探せなくなるより良い）。
            // ただしサブパネルに出るのは表示対象のフィールドだけ
            it("メモのラベルで検索してもアイテムは見つかる") {
                let noteItem = SecureMenuItem(title: "Contract", fields: [
                    SecureMenuItem.Field(label: "ID", value: "user"),
                    SecureMenuItem.Field(label: "契約番号", value: "12345", kind: .note)
                ])
                let panel = makePanel(items: [noteItem], query: "契約番号")
                expect(panel.filteredItems().map { $0.title }) == ["Contract"]
                expect(panel.filteredItems().first?.pickerFields.map { $0.label }) == ["ID"]
                panel.close()
            }
        }
    }

    // MARK: - Sub-panel row rendering

    private static func subPanelDisplaySpecs() {
        describe("サブパネルの行表示") {
            typealias SubPanel = CPYSecureSubPanel

            it("通常フィールドは「ラベル: 値」で表示する") {
                let field = SecureMenuItem.Field(label: "ID", value: "alice")
                expect(SubPanel.fieldDisplayString(for: field)) == "ID: alice"
            }

            it("URL は 🔗 を頭に付けて表示する") {
                let field = SecureMenuItem.Field(label: "URL", value: "https://a.example", kind: .url)
                expect(SubPanel.fieldDisplayString(for: field)) == "🔗 URL: https://a.example"
            }

            it("パスワードは値を出さずマスク表示にする") {
                let field = SecureMenuItem.Field(label: "PW", value: "s3cr3t", isPassword: true)
                expect(SubPanel.fieldDisplayString(for: field)) == "PW: ••••••••"
            }

            // URL でもマスク指定があれば値は出さない（種別より秘匿を優先する）
            it("マスク指定の URL は 🔗 付きでもマスク表示になる") {
                let field = SecureMenuItem.Field(label: "URL", value: "https://a.example",
                                                 isPassword: true, kind: .url)
                expect(SubPanel.fieldDisplayString(for: field)) == "🔗 URL: ••••••••"
            }

            // 境界値: 26 文字ちょうどは切り詰めず、27 文字から省略記号が付く
            it("プレビューは 26 文字までそのまま、27 文字から切り詰める") {
                let exact = SecureMenuItem.Field(label: "L", value: String(repeating: "a", count: 26))
                expect(SubPanel.fieldDisplayString(for: exact)) == "L: " + String(repeating: "a", count: 26)

                let over = SecureMenuItem.Field(label: "L", value: String(repeating: "a", count: 27))
                expect(SubPanel.fieldDisplayString(for: over)) == "L: " + String(repeating: "a", count: 26) + "…"
            }

            // 特殊値: 改行を含む値がそのまま入ると単一行セルの描画が崩れる。
            // CRLF は .newlines で 2 つに分割されるため、素朴に連結すると空白が二重になる
            it("改行を含む値は 1 行に潰して表示する") {
                let field = SecureMenuItem.Field(label: "L", value: "line1\nline2\r\nline3")
                expect(SubPanel.fieldDisplayString(for: field)).toNot(contain("\n"))
                expect(SubPanel.fieldDisplayString(for: field)) == "L: line1 line2 line3"
            }

            it("空行を含む値でも空白が連続しない") {
                let field = SecureMenuItem.Field(label: "L", value: "line1\n\n\nline2")
                expect(SubPanel.fieldDisplayString(for: field)) == "L: line1 line2"
            }

            it("空の値やラベルでも破綻しない") {
                expect(SubPanel.fieldDisplayString(for: SecureMenuItem.Field(label: "L", value: ""))) == "L: "
                expect(SubPanel.fieldDisplayString(for: SecureMenuItem.Field(label: "", value: "v"))) == ": v"
                expect(SubPanel.fieldDisplayString(for: SecureMenuItem.Field(label: "", value: ""))) == ": "
            }

            // 特殊値: 結合絵文字（ZWJ シーケンス）を切り詰めても分解されない。
            // Swift の prefix は Character（書記素クラスタ）単位で動くため境界で壊れない
            it("結合絵文字を切り詰めてもシーケンスが壊れない") {
                let family = "👨‍👩‍👧‍👦"
                let field = SecureMenuItem.Field(label: "L", value: String(repeating: family, count: 30))
                let displayed = SubPanel.fieldDisplayString(for: field)
                expect(displayed).to(endWith("…"))
                expect(displayed) == "L: " + String(repeating: family, count: 26) + "…"
            }

            // 特殊値: 全角文字も 1 文字として数える（バイト数ではない）
            it("全角文字は 1 文字として数える") {
                let field = SecureMenuItem.Field(label: "L", value: String(repeating: "あ", count: 26))
                expect(SubPanel.fieldDisplayString(for: field)).toNot(contain("…"))
            }
        }
    }

    // MARK: - Sub-panel selection

    private static func subPanelSelectionSpecs() {
        describe("サブパネルの選択操作") {

            func twoFields() -> [SecureMenuItem.Field] {
                return [SecureMenuItem.Field(label: "A", value: "1"),
                        SecureMenuItem.Field(label: "B", value: "2")]
            }

            func makeSubPanel(_ fields: [SecureMenuItem.Field]) -> CPYSecureSubPanel {
                let sub = CPYSecureSubPanel()
                sub.setFields(fields)
                return sub
            }

            it("setFields 直後は未選択で、selectedField は nil を返す") {
                let sub = makeSubPanel(twoFields())
                expect(sub.selectedFieldIndex) == -1
                expect(sub.selectedField()?.label) == nil
                sub.close()
            }

            // 境界値: 上端・下端を越える移動は false を返し、選択位置は動かない
            it("端を越える移動は false を返して選択位置を保つ") {
                let sub = makeSubPanel(twoFields())
                sub.selectFirst()
                expect(sub.selectPrev()) == false
                expect(sub.selectedFieldIndex) == 0
                expect(sub.selectNext()) == true
                expect(sub.selectNext()) == false
                expect(sub.selectedFieldIndex) == 1
                sub.close()
            }

            it("範囲外の添字を指定しても選択は変わらない") {
                let sub = makeSubPanel(twoFields())
                sub.selectFirst()
                sub.selectField(at: 99)
                expect(sub.selectedFieldIndex) == 0
                sub.selectField(at: -1)
                expect(sub.selectedFieldIndex) == 0
                sub.close()
            }

            it("フィールドが空なら選択操作はすべて無効になる") {
                let sub = makeSubPanel([])
                sub.selectFirst()
                expect(sub.selectedFieldIndex) == -1
                sub.selectLast()
                expect(sub.selectedFieldIndex) == -1
                expect(sub.selectNext()) == false
                expect(sub.selectPrev()) == false
                sub.close()
            }

            // 操作シーケンス: 別アイテムへ移ってフィールド数が減っても、
            // 前のアイテムの選択位置が残って範囲外を指さない
            it("フィールドを差し替えると選択がリセットされる") {
                let sub = makeSubPanel(twoFields())
                sub.selectLast()
                expect(sub.selectedFieldIndex) == 1
                sub.setFields([SecureMenuItem.Field(label: "Only", value: "1")])
                expect(sub.selectedFieldIndex) == -1
                expect(sub.selectedField()?.label) == nil
                sub.close()
            }

            it("selectLast は最終フィールドを指す") {
                let sub = makeSubPanel(twoFields())
                sub.selectLast()
                expect(sub.selectedField()?.label) == "B"
                sub.deselect()
                expect(sub.selectedFieldIndex) == -1
                sub.close()
            }
        }
    }

    // MARK: - Continuation paste mode

    /// 選択確定時に記録される fieldIndex はサブパネルの配列に対する添字。
    /// 表示側と復元側でどちらか一方でも item.fields を使うと、
    /// 30 秒以内に開き直したときに別のフィールドが貼り付けられる
    private static func continuationIndexSpecs() {
        describe("継続ペーストモードの添字") {

            /// メモを間に挟んだ構成。fields と pickerFields で添字がずれる
            func itemWithNoteInTheMiddle() -> SecureMenuItem {
                return SecureMenuItem(itemID: "mixed", title: "Mixed", fields: [
                    SecureMenuItem.Field(label: "ID", value: "user"),
                    SecureMenuItem.Field(label: "Memo", value: "契約番号: 12345", kind: .note),
                    SecureMenuItem.Field(label: "URL", value: "https://example.com", kind: .url)
                ])
            }

            it("表示対象の添字は元の配列の添字とずれる") {
                let item = itemWithNoteInTheMiddle()
                // 添字 1 は元配列ではメモ、表示対象では URL
                expect(item.fields[1].label) == "Memo"
                expect(item.pickerFields[1].label) == "URL"
            }

            it("記録した添字で復元すると同じフィールドに戻る") {
                let item = itemWithNoteInTheMiddle()
                guard let fields = CPYSecurePickerPanel.subPanelFields(for: item) else {
                    fail("sub panel fields should not be nil")
                    return
                }
                let sub = CPYSecureSubPanel()
                sub.setFields(fields)

                // ユーザーが URL を選ぶ
                sub.selectField(at: 1)
                let selected = sub.selectedField()
                let recordedIndex = sub.selectedFieldIndex
                expect(selected?.label) == "URL"

                // 開き直して同じ添字で復元する
                let reopened = CPYSecureSubPanel()
                reopened.setFields(fields)
                reopened.selectField(at: recordedIndex)
                expect(reopened.selectedField()?.label) == "URL"
                expect(reopened.selectedField()?.value) == selected?.value

                sub.close()
                reopened.close()
            }

            it("URL の選択は TOTP 扱いにならず通常のペースト経路に乗る") {
                let selection = SecureFieldSelection(parentItemID: "x", fieldValue: "https://example.com",
                                                     fieldIndex: 0, kind: .url)
                expect(selection.isTOTP) == false
                expect(selection.fieldValue) == "https://example.com"
            }

            it("TOTP の選択は TOTP 扱いになる") {
                let selection = SecureFieldSelection(parentItemID: "x", fieldValue: "secret",
                                                     fieldIndex: 0, kind: .totp)
                expect(selection.isTOTP) == true
            }
        }
    }

    // MARK: - Paging

    private static func pagingSpecs() {
        describe("ページングの境界") {

            func makePagedPanel(itemCount: Int) -> CPYSecurePickerPanel {
                let items = (0..<itemCount).map {
                    SecureMenuItem(itemID: "i\($0)", title: "Item \($0)",
                                   fields: [SecureMenuItem.Field(label: "ID", value: "v")])
                }
                return makePanel(items: items)
            }

            func hasPageControl(_ panel: CPYSecurePickerPanel) -> Bool {
                return panel.rows.contains { if case .pageControl = $0 { return true } else { return false } }
            }

            // 境界値: pageSize はちょうど 10。10 件までは 1 ページ、11 件から分割される
            it("10 件ちょうどではページ送りが出ない") {
                let panel = makePagedPanel(itemCount: 10)
                expect(parentTitles(panel).count) == 10
                expect(hasPageControl(panel)) == false
                panel.close()
            }

            it("11 件からページ送りが出て 1 ページ目は 10 件になる") {
                let panel = makePagedPanel(itemCount: 11)
                expect(parentTitles(panel).count) == 10
                expect(hasPageControl(panel)) == true
                panel.close()
            }

            it("最終ページには余りの件数だけ並ぶ") {
                let panel = makePagedPanel(itemCount: 11)
                panel.currentPage = 1
                panel.rebuildRows()
                expect(parentTitles(panel)) == ["Item 10"]
                panel.close()
            }

            // 境界値: 存在しないページ番号が残っていても最終ページに丸められる
            it("範囲外のページ番号は最終ページに丸められる") {
                let panel = makePagedPanel(itemCount: 11)
                panel.currentPage = 99
                panel.rebuildRows()
                expect(panel.currentPage) == 1
                expect(parentTitles(panel)) == ["Item 10"]
                panel.close()
            }

            it("負のページ番号は先頭ページに丸められる") {
                let panel = makePagedPanel(itemCount: 11)
                panel.currentPage = -5
                panel.rebuildRows()
                expect(panel.currentPage) == 0
                expect(parentTitles(panel).first) == "Item 0"
                panel.close()
            }

            // 操作シーケンス: 後ろのページを見ている状態で検索して件数が減っても、
            // 空ページに取り残されない
            it("後ろのページを見ている状態で絞り込んでも空ページにならない") {
                let panel = makePagedPanel(itemCount: 25)
                panel.currentPage = 2
                panel.rebuildRows()
                expect(parentTitles(panel).isEmpty) == false

                panel.searchField.stringValue = "Item 1"
                panel.rebuildRows()
                expect(parentTitles(panel).isEmpty) == false
                panel.close()
            }

            it("アイテムが 0 件でもセキュア情報確認の行だけは残る") {
                let panel = makePagedPanel(itemCount: 0)
                expect(parentTitles(panel).isEmpty) == true
                expect(panel.rows.contains { if case .manage = $0 { return true } else { return false } }) == true
                panel.close()
            }
        }
    }
}
