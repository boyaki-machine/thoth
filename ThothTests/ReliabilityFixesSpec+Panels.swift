import AppKit
import Nimble
import Quick
@testable import Thoth

// 選択パネル・配置・そのほかの回帰テスト（ReliabilityFixesSpec の続き）
extension ReliabilityFixesSpec {

    // MARK: - Picker panel

    static func pickerPanelSpecs() {
        describe("セキュア選択パネル") {
            func makeItems(_ count: Int) -> [SecureMenuItem] {
                return (0..<count).map { index in
                    SecureMenuItem(title: "item-\(index)", fields: [SecureMenuItem.Field(label: "ID", value: "v\(index)")])
                }
            }

            it("ページ末尾から ↓ で進むと、次ページの先頭が選ばれる") {
                let panel = CPYSecurePickerPanel(items: makeItems(25), context: SecureSelectionContext())
                let lastParent = CPYSecurePickerPanel.Layout.pageSize - 1
                panel.tableView.selectRowIndexes(IndexSet(integer: lastParent), byExtendingSelection: false)

                panel.selectNext()

                expect(panel.currentPage) == 1
                expect(panel.tableView.selectedRow) == 0
            }

            it("フィールドの確定は閉じる前に知らせる（閉じると「選択なし」の扱いになる）") {
                let items = makeItems(1)
                let panel = CPYSecurePickerPanel(items: items, context: SecureSelectionContext())
                panel.tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
                panel.orderFrontRegardless()
                defer { panel.close() }
                panel.openSubPanel(for: items[0], fields: items[0].fields, atRow: 0)

                var wasVisibleAtSelect: Bool?
                panel.onSelect = { [weak panel] _ in wasVisibleAtSelect = panel?.isVisible }
                panel.confirmField(at: 0)

                expect(wasVisibleAtSelect) == true
                expect(panel.isVisible) == false
            }
        }

        describe("メニュー項目のタイトルの切り詰め") {
            it("絵文字の途中で切らない") {
                let defaults = UserDefaults(suiteName: "ThothTests.Reliability.\(UUID().uuidString)")!
                defaults.set(6, forKey: Constants.UserDefaults.maxMenuItemTitleLength)
                AppEnvironment.push(defaults: defaults)
                defer { AppEnvironment.popLast() }

                // 上限 6 - "..." 3 = 3 の位置が絵文字の途中（1 + 2 UTF-16 の中間ではなく境界の内側）
                let title = MenuManager().trimTitle("ab😀😀😀😀")
                expect(title) == "ab..."
            }
        }
    }

    // MARK: - Picker geometry

    static func pickerGeometrySpecs() {
        describe("パネルの配置") {
            let visible = NSRect(x: 0, y: 0, width: 1000, height: 800)
            let main = NSRect(x: 100, y: 100, width: 260, height: 300)
            let subSize = NSSize(width: 220, height: 100)

            it("右側に余裕があれば右に置く") {
                let placement = PickerPanelSupport.subPanelPlacement(mainFrame: main, subPanelSize: subSize, rowTopY: 300, visible: visible)
                expect(placement.isOnLeft) == false
                expect(placement.origin) == NSPoint(x: main.maxX + PickerPanelSupport.subPanelGap, y: 200)
            }

            it("右に収まらなければ左に置く") {
                let right = NSRect(x: 700, y: 100, width: 260, height: 300)
                let placement = PickerPanelSupport.subPanelPlacement(mainFrame: right, subPanelSize: subSize, rowTopY: 300, visible: visible)
                expect(placement.isOnLeft) == true
                expect(placement.origin.x) == right.minX - PickerPanelSupport.subPanelGap - subSize.width
            }

            it("どちらにも収まらなければ画面内に収める") {
                let narrow = NSRect(x: 0, y: 0, width: 300, height: 800)
                let frame = NSRect(x: 20, y: 100, width: 260, height: 300)
                let placement = PickerPanelSupport.subPanelPlacement(mainFrame: frame, subPanelSize: subSize, rowTopY: 300, visible: narrow)
                expect(placement.isOnLeft) == false
                expect(placement.origin.x + subSize.width) <= narrow.maxX
                expect(placement.origin.x) >= narrow.minX
            }

            it("下にはみ出す位置は画面内へ戻す") {
                let placement = PickerPanelSupport.subPanelPlacement(mainFrame: main, subPanelSize: subSize, rowTopY: 50, visible: visible)
                expect(placement.origin.y) == visible.minY + PickerPanelSupport.screenInset
            }

            it("メインパネルはカーソルの右下に出し、画面に収める") {
                let size = NSSize(width: 260, height: 300)
                expect(PickerPanelSupport.panelOrigin(near: NSPoint(x: 500, y: 500), panelSize: size, visible: visible))
                    == NSPoint(x: 515, y: 215)
                expect(PickerPanelSupport.panelOrigin(near: NSPoint(x: 990, y: 10), panelSize: size, visible: visible))
                    == NSPoint(x: 736, y: 4)
            }

            it("画面が 1 枚も無くても計算できる（落ちない）") {
                let origin = PickerPanelSupport.panelOrigin(near: .zero, panelSize: NSSize(width: 10, height: 10), visible: .zero)
                expect(origin.x.isFinite) == true
            }
        }
    }

    // MARK: - Misc

    static func miscSpecs() {
        describe("暗号化の出力ファイル名") {
            it("フォルダをまたぐ名前を受け付けない") {
                for name in ["", ".", "..", "../x.enc", "a/b.enc", "/etc/x", "a\0b"] {
                    expect(CryptoService.isValidOutputName(name)).to(equal(false), description: name)
                }
            }

            it("普通の名前は受け付ける") {
                for name in ["file.enc", "..hidden", "日本語 名前.enc", "-dash.enc"] {
                    expect(CryptoService.isValidOutputName(name)).to(equal(true), description: name)
                }
            }
        }

        describe("外部コマンドの実行") {
            it("パイプのバッファを超える出力でも固まらない") {
                let result = CPYUtilities.runCommand("/bin/sh", ["-c", "head -c 200000 /dev/zero | tr '\\0' a"])
                expect(result.status) == 0
                expect(result.output.utf8.count) == 200_000
            }

            it("起動できなければ -1 を返す") {
                expect(CPYUtilities.runCommand("/nonexistent/command", []).status) == -1
            }
        }

        describe("ファイルのサムネイル") {
            it("名前に ? を含むファイルでも拡張子を判定できる") {
                let directory = makeWorkDirectory()
                defer { try? FileManager.default.removeItem(at: directory) }
                let url = directory.appendingPathComponent("a?b.png")
                let image = solidImage(.red)
                let png = NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
                try! png.write(to: url)
                let data = CPYClipData(image: image)
                data.fileNames = [url.path]

                expect(data.thumbnailImage) != nil
            }
        }
    }
}
