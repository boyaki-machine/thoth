import Quick
import Nimble
import AppKit
@testable import Thoth

// 履歴パネルの UI 構成（行構造・設定連動・サブパネル表示行・キー操作）のスペック。
// パネルはヘッドレスで生成し、表示（show）は行わない

// BDD スペックは多数の it ブロックを含み型本体が長くなるため型長ルールを緩める
// swiftlint:disable:next type_body_length
class CPYHistoryPickerPanelSpec: QuickSpec {

    // MARK: - Helpers

    /// テスト用の表示設定（既定はメニュータブのデフォルト相当）
    private static func makeSettings(markWithNumber: Bool = true,
                              numericKeysEnabled: Bool = true,
                              numberOffset: Int = 0,
                              showIcon: Bool = true,
                              showToolTip: Bool = true,
                              maxToolTipLength: Int = 200,
                              placeInline: Int = 0,
                              groupSize: Int = 10,
                              showImage: Bool = true,
                              showColorCode: Bool = true,
                              maxTitleLength: Int = 0,
                              showsClearHistory: Bool = false) -> CPYHistoryPickerPanel.DisplaySettings {
        return CPYHistoryPickerPanel.DisplaySettings(markWithNumber: markWithNumber,
                                                     numericKeysEnabled: numericKeysEnabled,
                                                     numberOffset: numberOffset,
                                                     showIcon: showIcon,
                                                     showToolTip: showToolTip,
                                                     maxToolTipLength: maxToolTipLength,
                                                     placeInline: placeInline,
                                                     groupSize: groupSize,
                                                     showImage: showImage,
                                                     showColorCode: showColorCode,
                                                     maxTitleLength: maxTitleLength,
                                                     showsClearHistory: showsClearHistory)
    }

    private static func makeItem(_ hash: String, title: String, index: Int,
                          primaryType: NSPasteboard.PasteboardType = .deprecatedString,
                          thumbnailPath: String = "", isColorCode: Bool = false) -> CPYHistoryPickerPanel.ClipItem {
        let clip = CPYClip()
        clip.dataHash = hash
        clip.title = title
        clip.primaryType = primaryType.rawValue
        clip.dataPath = "/tmp/\(hash).data"
        clip.thumbnailPath = thumbnailPath
        clip.isColorCode = isColorCode
        return CPYHistoryPickerPanel.ClipItem(clip: clip, index: index)
    }

    /// 行の種別を検証用の文字列へ変換する
    private static func kinds(of rows: [CPYHistoryPickerPanel.Row]) -> [String] {
        return rows.map { row in
            switch row {
            case .sectionHeader: return "header"
            case .clip:          return "clip"
            case .group:         return "group"
            case .separator:     return "separator"
            case .action(let action): return "action:\(action)"
            case .noResults:     return "noResults"
            }
        }
    }

    override class func spec() {
        clipItemSpecs()
        rowStructureSpecs()
        subEntrySpecs()
        subPanelWidthSpecs()
        subPanelKeySpecs()
        dismissBehaviorSpecs()
    }

    // MARK: - Dismiss on Outside Click

    private static func dismissBehaviorSpecs() {
        describe("パネル外クリックの解除判定") {
            let clips = [self.makeItem("c0", title: "clip 0", index: 0)]

            it("本体ウィンドウとサブパネル（子ウィンドウ）は「属する＝閉じない」と判定する") {
                let panel = CPYHistoryPickerPanel(clips: clips, settings: self.makeSettings())
                let child = NSWindow(contentRect: .zero, styleMask: [.borderless],
                                     backing: .buffered, defer: false)
                panel.addChildWindow(child, ordered: .above)
                expect(panel.belongsToPanelGroup(panel)) == true
                expect(panel.belongsToPanelGroup(child)) == true
                panel.removeChildWindow(child)
                panel.close()
            }

            it("無関係なウィンドウと nil は「属さない＝閉じる」と判定する") {
                let panel = CPYHistoryPickerPanel(clips: clips, settings: self.makeSettings())
                let other = NSWindow(contentRect: .zero, styleMask: [.borderless],
                                     backing: .buffered, defer: false)
                expect(panel.belongsToPanelGroup(other)) == false
                expect(panel.belongsToPanelGroup(nil)) == false
                panel.close()
            }
        }

        describe("解除モニタのライフサイクル") {
            let clips = [self.makeItem("c0", title: "clip 0", index: 0)]

            it("install で登録され、多重呼び出しでも累積せず、close で全解除される") {
                let panel = CPYHistoryPickerPanel(clips: clips, settings: self.makeSettings())
                panel.installDismissMonitors()
                let installed = panel.dismissMonitorCount
                expect(installed) >= 1
                panel.installDismissMonitors()
                expect(panel.dismissMonitorCount) == installed
                panel.close()
                expect(panel.dismissMonitorCount) == 0
            }
        }
    }

    // MARK: - ClipItem

    private static func clipItemSpecs() {
        describe("ClipItem の表示タイトル") {
            it("画像・PDF・ファイル名クリップは特殊タイトルに置換される") {
                expect(self.makeItem("i", title: "raw", index: 0, primaryType: .deprecatedTIFF).title) == "(Image)"
                expect(self.makeItem("p", title: "raw", index: 0, primaryType: .deprecatedPDF).title) == "(PDF)"
                expect(self.makeItem("f", title: "", index: 0, primaryType: .deprecatedFilenames).title) == "(Filenames)"
            }

            it("複数行タイトルは 1 行目のみ表示し、ツールチップ用の全体を保持する") {
                let item = self.makeItem("m", title: "first line\nsecond line", index: 0)
                expect(item.title) == "first line"
                expect(item.fullTitle) == "first line\nsecond line"
            }
        }
    }

    // MARK: - Row Structure

    private static func rowStructureSpecs() {
        describe("パネルの行構成") {
            let clips = (0..<12).map { self.makeItem("c\($0)", title: "clip \($0)", index: $0) }

            it("フル構成では 4 セクション（履歴/スニペット/ツール/設定）に分かれ、終了は区切り線で分離される") {
                let panel = CPYHistoryPickerPanel(clips: clips, settings: self.makeSettings())
                expect(self.kinds(of: panel.rows)) == [
                    "header", "group", "group",
                    "separator", "header", "action:snippets",
                    "separator", "header", "action:generatePassword", "action:crypto", "action:secureInfo",
                    "separator", "header", "action:editSnippets", "action:preferences",
                    "separator", "action:quit"
                ]
                panel.close()
            }

            // 表示ラベルの "(&x)" とキー処理は同じ定義元から作る。
            // 別々に書いていたため、行を追加したときにラベルだけ付いて
            // ショートカットが効かない状態になっていた
            it("ショートカットを持つ行のラベルに (&キー) が付く") {
                typealias Action = CPYHistoryPickerPanel.PanelAction
                for action in Action.allCases {
                    guard let key = action.shortcutKey else {
                        expect(action.title) == action.name
                        continue
                    }
                    expect(action.title) == "\(action.name) (&\(key))"
                    expect(action.title).to(contain("(&\(key))"))
                }
            }

            it("ショートカットはすべて小文字 1 文字で重複しない") {
                typealias Action = CPYHistoryPickerPanel.PanelAction
                let keys = Action.allCases.compactMap { $0.shortcutKey }
                expect(keys.allSatisfy { $0.count == 1 && $0 == $0.lowercased() }) == true
                expect(Set(keys).count) == keys.count
            }

            it("ツール系の行にショートカットが割り当てられている") {
                typealias Action = CPYHistoryPickerPanel.PanelAction
                expect(Action.generatePassword.shortcutKey) == "p"
                expect(Action.crypto.shortcutKey) == "e"
                expect(Action.secureInfo.shortcutKey) == "s"
            }

            // セキュア情報確認ウィンドウはメインメニューのツールセクションから開く。
            // 導線が消えると認証付きの一覧・編集画面へ到達する手段が無くなる
            it("ツールセクションにセキュア情報の行がある") {
                let panel = CPYHistoryPickerPanel(clips: clips, settings: self.makeSettings())
                expect(self.kinds(of: panel.rows)).to(contain("action:secureInfo"))
                panel.close()
            }

            it("履歴専用モードではセキュア情報の行を出さない") {
                let panel = CPYHistoryPickerPanel(clips: clips, showsFixedSections: false,
                                                  settings: self.makeSettings())
                expect(self.kinds(of: panel.rows)).toNot(contain("action:secureInfo"))
                panel.close()
            }

            it("「履歴を消去」行は設定に応じて追加される") {
                let panel = CPYHistoryPickerPanel(clips: clips,
                                                  settings: self.makeSettings(showsClearHistory: true))
                expect(self.kinds(of: panel.rows)).to(contain("action:clearHistory"))
                panel.close()
            }

            it("履歴専用モード（⌘⌃V）では履歴セクションのみ表示される") {
                let panel = CPYHistoryPickerPanel(clips: clips, showsFixedSections: false,
                                                  settings: self.makeSettings())
                expect(self.kinds(of: panel.rows)) == ["header", "group", "group"]
                panel.close()
            }

            it("インライン表示数の設定で先頭が個別行になる") {
                let panel = CPYHistoryPickerPanel(clips: clips, showsFixedSections: false,
                                                  settings: self.makeSettings(placeInline: 3))
                expect(self.kinds(of: panel.rows)) == ["header", "clip", "clip", "clip", "group"]
                panel.close()
            }

            it("検索でヒットが無い場合は noResults 行を表示する") {
                let panel = CPYHistoryPickerPanel(clips: clips, showsFixedSections: false,
                                                  settings: self.makeSettings())
                panel.searchField.stringValue = "no-such-clip"
                panel.rebuildRows()
                expect(self.kinds(of: panel.rows)) == ["header", "noResults"]
                panel.close()
            }
        }
    }

    // MARK: - Sub Entries

    private static func subEntrySpecs() {
        describe("サブパネル表示行（設定連動）") {
            it("グループ内番号は元の位置と番号開始値から計算される") {
                // グループ "10 - 19" 内の元 15 番目 → 0 開始で 5、1 開始で 6
                let clip15 = self.makeItem("g15", title: "target", index: 15)
                let group = CPYHistoryPickerPanel.ClipGroup(startIndex: 10, title: "", clips: [clip15])

                let zeroPanel = CPYHistoryPickerPanel(clips: [clip15],
                                                      settings: self.makeSettings(numberOffset: 0))
                expect(zeroPanel.makeSubEntries(for: group).first?.number) == 5
                zeroPanel.close()

                let onePanel = CPYHistoryPickerPanel(clips: [clip15],
                                                     settings: self.makeSettings(numberOffset: 1))
                expect(onePanel.makeSubEntries(for: group).first?.number) == 6
                onePanel.close()
            }

            it("ツールチップは設定に応じて最大長で切り詰められる") {
                let longTitle = String(repeating: "x", count: 50)
                let clip = self.makeItem("t", title: longTitle, index: 0)
                let group = CPYHistoryPickerPanel.ClipGroup(startIndex: 0, title: "", clips: [clip])

                let panel = CPYHistoryPickerPanel(clips: [clip],
                                                  settings: self.makeSettings(showToolTip: true, maxToolTipLength: 10))
                expect(panel.makeSubEntries(for: group).first?.toolTip) == String(repeating: "x", count: 10)
                panel.close()

                let noTipPanel = CPYHistoryPickerPanel(clips: [clip],
                                                       settings: self.makeSettings(showToolTip: false))
                expect(noTipPanel.makeSubEntries(for: group).first?.toolTip).to(beNil())
                noTipPanel.close()
            }

            it("サムネイルは種別と設定の組み合わせで表示可否が決まる") {
                let image = self.makeItem("img", title: "(Image)", index: 0,
                                          primaryType: .deprecatedTIFF, thumbnailPath: "thumb-img")
                let color = self.makeItem("col", title: "#FF0000", index: 1,
                                          thumbnailPath: "thumb-col", isColorCode: true)
                let group = CPYHistoryPickerPanel.ClipGroup(startIndex: 0, title: "", clips: [image, color])

                // 両方 ON → 両方サムネイル表示
                let bothPanel = CPYHistoryPickerPanel(clips: [image, color],
                                                      settings: self.makeSettings(showImage: true, showColorCode: true))
                let bothEntries = bothPanel.makeSubEntries(for: group)
                expect(bothEntries[0].thumbnailPath) == "thumb-img"
                expect(bothEntries[1].thumbnailPath) == "thumb-col"
                bothPanel.close()

                // 画像 OFF・カラー ON → 画像のみ非表示
                let colorOnlyPanel = CPYHistoryPickerPanel(clips: [image, color],
                                                           settings: self.makeSettings(showImage: false, showColorCode: true))
                let colorOnlyEntries = colorOnlyPanel.makeSubEntries(for: group)
                expect(colorOnlyEntries[0].thumbnailPath).to(beNil())
                expect(colorOnlyEntries[1].thumbnailPath) == "thumb-col"
                colorOnlyPanel.close()
            }

            it("番号表示フラグは「メニュー項目に番号を付ける」設定に従う") {
                let clip = self.makeItem("n", title: "clip", index: 0)
                let group = CPYHistoryPickerPanel.ClipGroup(startIndex: 0, title: "", clips: [clip])

                let panel = CPYHistoryPickerPanel(clips: [clip],
                                                  settings: self.makeSettings(markWithNumber: false))
                expect(panel.makeSubEntries(for: group).first?.showsNumber) == false
                panel.close()
            }
        }
    }

    // MARK: - Sub Panel Keys

    /// サブパネルモードのキー操作。↓↑ は検索入力中もクリップ間を移動し、
    /// j / k は検索入力中は横取りせず文字入力に譲る（通常モードと同じ約束）。
    ///
    /// 以前は `case 125, 38 where !searching` と 1 つの case に書き、where が
    /// j にしか掛からないことに頼っていた（コンパイラが警告する書き方）。
    /// 警告を「両方に where を付ける」形で消すと、検索中に ↓ が効かなくなる
    private static func subPanelKeySpecs() {
        describe("サブパネルモードのキー操作") {
            func keyDown(_ character: String, keyCode: UInt16) -> NSEvent {
                return NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                        timestamp: 0, windowNumber: 0, context: nil,
                                        characters: character, charactersIgnoringModifiers: character,
                                        isARepeat: false, keyCode: keyCode)!
            }
            let downArrow = keyDown(String(UnicodeScalar(NSDownArrowFunctionKey)!), keyCode: 125)
            let upArrow = keyDown(String(UnicodeScalar(NSUpArrowFunctionKey)!), keyCode: 126)
            let jKey = keyDown("j", keyCode: 38)
            let kKey = keyDown("k", keyCode: 40)

            /// 3 件入りのサブパネルに入り、先頭を選んだ状態のパネルを作る。
            /// パネル・サブパネルとも画面には出さない
            func makePanelInSubPanelMode(searching: Bool) -> CPYHistoryPickerPanel {
                let clips = (0..<3).map { self.makeItem("c\($0)", title: "clip \($0)", index: $0) }
                let panel = CPYHistoryPickerPanel(clips: clips, showsFixedSections: false,
                                                  settings: self.makeSettings())
                let sub = CPYHistorySubPanel()
                sub.setEntries(clips.map {
                    CPYHistorySubPanel.Entry(clip: $0, number: $0.index, showsNumber: false,
                                             toolTip: nil, thumbnailPath: nil, showsTypeIcon: true)
                })
                panel.subPanel = sub
                panel.enterSubPanel()
                if searching { panel.makeFirstResponder(panel.searchField) }
                return panel
            }

            it("検索入力中でも ↓↑ でサブパネル内のクリップを移動する") {
                let panel = makePanelInSubPanelMode(searching: true)
                defer { panel.close() }
                guard panel.searchField.currentEditor() != nil else {
                    fail("検索欄が編集状態になっていない（前提が崩れている）")
                    return
                }
                expect(panel.handleKeyDown(downArrow)) == true
                expect(panel.subPanel?.selectedClipIndex) == 1
                expect(panel.handleKeyDown(upArrow)) == true
                expect(panel.subPanel?.selectedClipIndex) == 0
            }

            it("検索入力中の j / k は横取りせず、選択も動かさない") {
                let panel = makePanelInSubPanelMode(searching: true)
                defer { panel.close() }
                guard panel.searchField.currentEditor() != nil else {
                    fail("検索欄が編集状態になっていない（前提が崩れている）")
                    return
                }
                expect(panel.handleKeyDown(jKey)) == false
                expect(panel.handleKeyDown(kKey)) == false
                expect(panel.subPanel?.selectedClipIndex) == 0
            }

            it("検索入力していなければ j / k でサブパネル内のクリップを移動する") {
                let panel = makePanelInSubPanelMode(searching: false)
                defer { panel.close() }
                expect(panel.handleKeyDown(jKey)) == true
                expect(panel.subPanel?.selectedClipIndex) == 1
                expect(panel.handleKeyDown(kKey)) == true
                expect(panel.subPanel?.selectedClipIndex) == 0
            }
        }
    }

    // MARK: - Sub Panel Width

    private static func subPanelWidthSpecs() {
        describe("サブパネル幅の自動調整") {
            func entry(_ title: String) -> CPYHistorySubPanel.Entry {
                let clip = self.makeItem("w", title: title, index: 0)
                return CPYHistorySubPanel.Entry(clip: clip, number: 0, showsNumber: false,
                                                toolTip: nil, thumbnailPath: nil, showsTypeIcon: true)
            }

            it("タイトルが長いほど幅が広がる") {
                let short = CPYHistorySubPanel.preferredWidth(for: [entry("short")])
                let long = CPYHistorySubPanel.preferredWidth(for: [entry(String(repeating: "long title ", count: 5))])
                expect(long) > short
            }

            it("幅は上下限でクランプされる") {
                expect(CPYHistorySubPanel.preferredWidth(for: [entry("a")])) == 220
                expect(CPYHistorySubPanel.preferredWidth(for: [entry(String(repeating: "very long ", count: 50))])) == 620
            }
        }
    }
}
