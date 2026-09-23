import Quick
import Nimble
import AppKit
@testable import Thoth

/// 「オリジナル」タブ（CPYUpdatesPreferenceViewController）のスペック。
/// サードパーティライセンスのボタンが、どの言語でも文字を見切れさせない幅を持つことを固定する
class CPYUpdatesPreferenceViewControllerSpec: QuickSpec {

    override class func spec() {
        typealias UpdatesVC = CPYUpdatesPreferenceViewController

        /// 各言語の Localizable.strings からボタンの文言を集める
        func localizedButtonTitles() -> [String: String] {
            let bundle = Bundle(for: AppDelegate.self)
            var titles = [String: String]()
            for localization in bundle.localizations {
                guard let path = bundle.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: localization),
                      let table = NSDictionary(contentsOfFile: path) as? [String: String],
                      let title = table["Updates Third Party Licenses Button"] else { continue }
                titles[localization] = title
            }
            return titles
        }

        func fittingWidth(of title: String) -> CGFloat {
            let button = NSButton(title: title, target: nil, action: nil)
            button.bezelStyle = .rounded
            return button.fittingSize.width
        }

        describe("サードパーティライセンスのボタン") {
            it("表示中の言語で、文字が収まる幅を持ち、タブの水平中央に置かれる") {
                let viewController = UpdatesVC(nibName: "CPYUpdatesPreferenceViewController", bundle: Bundle(for: AppDelegate.self))
                let view = viewController.view
                guard let button = view.subviews.first(where: { $0.identifier == UpdatesVC.ViewID.licensesButton }) as? NSButton else {
                    fail("licenses button not found")
                    return
                }
                expect(button.frame.width) >= button.fittingSize.width
                expect(abs(button.frame.midX - view.bounds.midX)) <= 1
            }

            it("すべての言語の文言が見切れない（固定幅 150 ではドイツ語が収まらない）") {
                let titles = localizedButtonTitles()
                // 言語の取りこぼし（文言が読めず空のまま通る）を防ぐ
                expect(titles.count) >= 6
                for (localization, title) in titles {
                    let needed = fittingWidth(of: title)
                    let frame = UpdatesVC.licensesButtonFrame(fittingWidth: needed, containerWidth: 480, originY: 10, height: 24)
                    expect(frame.width).to(beGreaterThanOrEqualTo(needed), description: "\(localization): \(title)")
                    expect(frame.minX) >= 20
                    expect(frame.maxX) <= 460
                }
                expect(titles.values.map(fittingWidth(of:)).max() ?? 0) > UpdatesVC.licensesButtonMinWidth
            }

            it("どの言語でも末尾に「…」を付けない（見切れて続きがあるように見える）") {
                for (localization, title) in localizedButtonTitles() {
                    expect(title.hasSuffix("…") || title.hasSuffix("...")).to(beFalse(), description: "\(localization): \(title)")
                }
            }

            it("短い文言でも最小幅を下回らず、タブより広い文言は左右の余白を残して収める") {
                let short = UpdatesVC.licensesButtonFrame(fittingWidth: 40, containerWidth: 480, originY: 10, height: 24)
                expect(short.width) == UpdatesVC.licensesButtonMinWidth
                expect(short.midX) == 240

                let huge = UpdatesVC.licensesButtonFrame(fittingWidth: 900, containerWidth: 480, originY: 10, height: 24)
                expect(huge.minX) == 20
                expect(huge.width) == 440
            }
        }
    }
}
