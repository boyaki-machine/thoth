import Quick
import Nimble
import AppKit
@testable import Thoth

/// セキュアアイテム選択パネルの検索フィルタと行構成のスペック。
/// パネルはヘッドレスで生成し、表示（show）は行わない
class CPYSecurePickerPanelSpec: QuickSpec {

    override class func spec() {
        let items = [
            SecureMenuItem(title: "GitHub", fields: [
                SecureMenuItem.Field(label: "Password", value: "a", isPassword: true),
                SecureMenuItem.Field(label: "Token", value: "b", isPassword: true)
            ]),
            SecureMenuItem(title: "AWS Console", fields: [
                SecureMenuItem.Field(label: "Login ID", value: "c", isPassword: false)
            ])
        ]

        func makePanel(query: String = "") -> CPYSecurePickerPanel {
            let panel = CPYSecurePickerPanel(items: items, context: SecureSelectionContext())
            panel.searchField.stringValue = query
            panel.rebuildRows()
            return panel
        }

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

            it("複数語は AND 条件（タイトル内で全語一致）になる") {
                let panel = makePanel(query: "aws console")
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
        }

        describe("行構成") {
            it("通常時は親アイテム + 区切り線 + 管理行が並ぶ") {
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

            it("ヒットなしの検索では noResults 行と管理行が表示される") {
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
}
