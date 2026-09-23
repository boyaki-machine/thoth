import Quick
import Nimble
import AppKit
@testable import Thoth

/// Xib の部品の種類（必要な幅の測り方が違う）
enum XibControlKind { case checkbox, radio, push, label }

/// 環境設定の全タブの配置の不変条件。
/// v1.6.1 の開発中、ベータ機能タブに部品を足したときに Xib の部品が二重にずれてツールバーに重なり、
/// 個別のスペックでは見逃した。どのタブ・どの言語でも、次を機械的に確かめる。
/// - 部品がタブ（親）の外にはみ出さない
/// - 兄弟の部品同士が重ならない
/// - 文字が枠に収まる（表示中の言語で組み立てた画面と、Xib の翻訳 .strings の全言語）
///
/// 座標を直値で固定しないので、配置を変えても条件を満たしていれば落ちない
class PreferencesLayoutSpec: QuickSpec {

    /// 重なり・はみ出しの許容量（枠線やフォーカスリングの分）
    static let tolerance: CGFloat = 1

    static let repositoryRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    static let panelsDirectory = repositoryRoot.appendingPathComponent("Thoth/Sources/Preferences/Panels")

    override class func spec() {
        builtTabSpecs()
        xibTranslationSpecs()
    }

    // MARK: - 表示中の言語で組み立てた画面

    /// 検査の対象にする部品（表示されている、大きさのある部品）
    static func visibleSubviews(of view: NSView) -> [NSView] {
        return view.subviews.filter { !$0.isHidden && $0.frame.width > 0 && $0.frame.height > 0 }
    }

    /// 部品の説明（失敗したときにどれか分かるように）
    static func describe(_ view: NSView) -> String {
        let text: String
        if let button = view as? NSButton {
            text = button.title
        } else if let field = view as? NSTextField {
            text = field.stringValue
        } else {
            text = ""
        }
        return "\(type(of: view)) \"\(text.prefix(30))\" \(view.frame)"
    }

    /// 文字を持つ部品について、文字を出すのに必要な幅。対象外なら nil
    static func requiredWidth(of view: NSView) -> CGFloat? {
        if let popUp = view as? NSPopUpButton {
            // ポップアップは選択中の項目が収まれば見切れない
            return popUp.titleOfSelectedItem.map { _ in popUp.fittingSize.width }
        }
        if let button = view as? NSButton, !button.title.isEmpty, button.image == nil || button.imagePosition != .imageOnly {
            return button.fittingSize.width
        }
        if let field = view as? NSTextField, !field.isEditable, !field.stringValue.isEmpty,
           field.cell?.wraps == false, field.cell?.truncatesLastVisibleLine == false {
            return field.fittingSize.width
        }
        return nil
    }

    private static func builtTabSpecs() {
        describe("環境設定の全タブ（表示中の言語）") {
            let bundle = Bundle(for: AppDelegate.self)

            it("部品がタブの外にはみ出さない（入れ子の部品も親の中に収まる）") {
                for viewController in CPYPreferencesWindowController.makeTabViewControllers(bundle: bundle) {
                    let tab = String(describing: type(of: viewController)) + " " + (viewController.nibName ?? "")
                    func check(_ view: NSView) {
                        for subview in visibleSubviews(of: view) {
                            let inside = view.bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(subview.frame)
                            expect(inside).to(beTrue(), description: "\(tab): \(describe(subview)) が \(view.bounds) の外")
                            // スクロールビューの中身は大きくなるのが正しい。ボタン等の部品の内部（macOS が描画のために
                            // 持つ子）は部品の枠をはみ出すことがあるので、その先は見ない
                            if !(subview is NSScrollView) && !(subview is NSControl) { check(subview) }
                        }
                    }
                    check(viewController.view)
                }
            }

            it("兄弟の部品同士が重ならない") {
                for viewController in CPYPreferencesWindowController.makeTabViewControllers(bundle: bundle) {
                    let tab = viewController.nibName ?? String(describing: type(of: viewController))
                    let views = visibleSubviews(of: viewController.view)
                    for (index, first) in views.enumerated() {
                        for second in views[(index + 1)...] {
                            let overlap = first.frame.insetBy(dx: tolerance, dy: tolerance)
                                .intersects(second.frame.insetBy(dx: tolerance, dy: tolerance))
                            expect(overlap).to(beFalse(), description: "\(tab): \(describe(first)) と \(describe(second)) が重なる")
                        }
                    }
                }
            }

            it("文字が枠に収まる（見切れない）") {
                for viewController in CPYPreferencesWindowController.makeTabViewControllers(bundle: bundle) {
                    let tab = viewController.nibName ?? String(describing: type(of: viewController))
                    func check(_ view: NSView) {
                        for subview in visibleSubviews(of: view) {
                            if let required = requiredWidth(of: subview) {
                                expect(required).to(beLessThanOrEqualTo(subview.frame.width + tolerance),
                                                    description: "\(tab): \(describe(subview)) には幅 \(required) が要る")
                            }
                            // スクロールビューの中身は大きくなるのが正しい。ボタン等の部品の内部（macOS が描画のために
                            // 持つ子）は部品の枠をはみ出すことがあるので、その先は見ない
                            if !(subview is NSScrollView) && !(subview is NSControl) { check(subview) }
                        }
                    }
                    check(viewController.view)
                }
            }
        }
    }

    // MARK: - Xib の翻訳（全言語）

    /// Xib の中の、文字を持つ部品
    struct XibControl {
        let cellID: String
        let kind: XibControlKind
        let width: CGFloat
        let fontSize: CGFloat
        let baseTitle: String
    }

    /// Xib（ソース）から、1 行の文字を持つ部品と幅を読む
    static func xibControls(in xibURL: URL) -> [XibControl] {
        guard let document = try? XMLDocument(contentsOf: xibURL, options: []),
              let elements = try? document.nodes(forXPath: "//button | //textField") as? [XMLElement] else { return [] }
        return elements.compactMap { element in
            guard let rect = (try? element.nodes(forXPath: "rect[@key='frame']"))?.first as? XMLElement,
                  let width = rect.attribute(forName: "width")?.stringValue.flatMap(Double.init),
                  let cell = element.elements(forName: element.name == "button" ? "buttonCell" : "textFieldCell").first,
                  let cellID = cell.attribute(forName: "id")?.stringValue,
                  let title = cell.attribute(forName: "title")?.stringValue, !title.isEmpty else { return nil }
            let kind: XibControlKind
            if element.name == "textField" {
                // 折り返す・複数行の説明文は幅ではなく高さで収めるので対象外
                let lineBreak = cell.attribute(forName: "lineBreakMode")?.stringValue ?? "clipping"
                let height = rect.attribute(forName: "height")?.stringValue.flatMap(Double.init) ?? 0
                guard lineBreak != "wordWrapping", height < 24,
                      cell.attribute(forName: "editable")?.stringValue != "YES" else { return nil }
                kind = .label
            } else {
                switch cell.attribute(forName: "type")?.stringValue {
                case "check": kind = .checkbox
                case "radio": kind = .radio
                case "push": kind = .push
                default: return nil
                }
            }
            let font = cell.elements(forName: "font").first
            let size = font?.attribute(forName: "size")?.stringValue.flatMap(Double.init) ?? Double(NSFont.systemFontSize)
            return XibControl(cellID: cellID, kind: kind, width: CGFloat(width), fontSize: CGFloat(size), baseTitle: title)
        }
    }

    /// その部品の種類で、文字を出すのに必要な幅
    static func requiredWidth(for title: String, kind: XibControlKind, fontSize: CGFloat) -> CGFloat {
        let font = NSFont.systemFont(ofSize: fontSize)
        switch kind {
        case .checkbox:
            let button = NSButton(checkboxWithTitle: title, target: nil, action: nil)
            button.font = font
            return button.fittingSize.width
        case .radio:
            let button = NSButton(radioButtonWithTitle: title, target: nil, action: nil)
            button.font = font
            return button.fittingSize.width
        case .push:
            let button = NSButton(title: title, target: nil, action: nil)
            button.bezelStyle = .rounded
            button.font = font
            return button.fittingSize.width
        case .label:
            let field = NSTextField(labelWithString: title)
            field.font = font
            return field.fittingSize.width
        }
    }

    private static func xibTranslationSpecs() {
        describe("環境設定の Xib の翻訳（全言語）") {
            let xibs = ((try? FileManager.default.contentsOfDirectory(
                at: panelsDirectory.appendingPathComponent("Base.lproj"), includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.pathExtension == "xib" }

            it("Xib を読めている（検査が空回りしない）") {
                expect(xibs.count) >= 7
                expect(xibs.map { xibControls(in: $0).count }.reduce(0, +)) >= 20
            }

            it("どの言語の文言も、Xib の部品の幅に収まる") {
                var checked = 0
                for xib in xibs {
                    let name = xib.deletingPathExtension().lastPathComponent
                    let controls = xibControls(in: xib)
                    let localizations = ((try? FileManager.default.contentsOfDirectory(at: panelsDirectory, includingPropertiesForKeys: nil)) ?? [])
                        .filter { $0.pathExtension == "lproj" && $0.lastPathComponent != "Base.lproj" }
                    for control in controls {
                        var titles = ["Base": control.baseTitle]
                        for lproj in localizations {
                            let strings = lproj.appendingPathComponent("\(name).strings")
                            if let table = NSDictionary(contentsOf: strings) as? [String: String],
                               let title = table["\(control.cellID).title"] {
                                titles[lproj.deletingPathExtension().lastPathComponent] = title
                            }
                        }
                        for (language, title) in titles {
                            let required = requiredWidth(for: title, kind: control.kind, fontSize: control.fontSize)
                            expect(required).to(beLessThanOrEqualTo(control.width + tolerance),
                                                description: "\(name) [\(language)] \"\(title)\" には幅 \(required) が要る（枠は \(control.width)）")
                            checked += 1
                        }
                    }
                }
                expect(checked) >= 50
            }
        }
    }
}
