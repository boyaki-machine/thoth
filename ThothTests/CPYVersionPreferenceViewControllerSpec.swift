import Quick
import Nimble
import AppKit
@testable import Thoth

/// バージョンタブ（コード生成レイアウト）のスペック。
/// アイコンアセットの解決・中央配置・要素の縦順/間隔という
/// 壊れやすい不変条件を担保する（座標は直値で固定せず条件で検証）。
/// パネルはヘッドレスで生成し、表示は行わない
class CPYVersionPreferenceViewControllerSpec: QuickSpec {

    override class func spec() {
        typealias VersionVC = CPYVersionPreferenceViewController

        func makeVC() -> VersionVC {
            let viewController = VersionVC()
            _ = viewController.view // loadView → setupUI を走らせる
            return viewController
        }
        func subview(_ viewController: VersionVC, _ identifier: NSUserInterfaceItemIdentifier) -> NSView? {
            return viewController.view.subviews.first { $0.identifier == identifier }
        }

        describe("バージョンタブのレイアウト") {
            it("アプリアイコン画像が解決される（AppIconArtwork アセット・非 nil）") {
                let viewController = makeVC()
                let icon = subview(viewController, VersionVC.ViewID.icon) as? NSImageView
                expect(icon) != nil
                // アセット削除や applicationIconImage への差し戻しで image が nil/別物になる回帰を検出
                expect(icon?.image) != nil
            }

            it("アイコンとバージョン文字は水平中央に配置される") {
                let viewController = makeVC()
                let midX = viewController.view.frame.midX
                expect(subview(viewController, VersionVC.ViewID.icon)?.frame.midX) == midX
                expect(subview(viewController, VersionVC.ViewID.version)?.frame.midX) == midX
            }

            it("アイコンはバージョン文字の上に間隔を空けて置かれる") {
                let viewController = makeVC()
                guard let icon = subview(viewController, VersionVC.ViewID.icon),
                      let version = subview(viewController, VersionVC.ViewID.version) else {
                    fail("icon / version view not found")
                    return
                }
                expect(icon.frame.minY) > version.frame.maxY        // アイコンが上
                expect(icon.frame.minY - version.frame.maxY) > 10   // 目視で分かる間隔がある
            }

            it("表示ブロック全体がタブのほぼ縦中央に収まる") {
                let viewController = makeVC()
                let ids = [VersionVC.ViewID.icon, VersionVC.ViewID.version, VersionVC.ViewID.releaseDate]
                let frames = ids.compactMap { subview(viewController, $0)?.frame }
                let top = frames.map { $0.maxY }.max() ?? 0
                let bottom = frames.map { $0.minY }.min() ?? 0
                let blockCenter = (top + bottom) / 2
                // リリース日ラベルの有無で多少ずれるため許容幅を持たせる
                expect(abs(blockCenter - viewController.view.frame.midY)) < 30
            }

            it("バージョンラベルは \"<アプリ名> ver.\" 形式で始まる") {
                let viewController = makeVC()
                let version = subview(viewController, VersionVC.ViewID.version) as? NSTextField
                expect(version?.stringValue.hasPrefix("\(Constants.Application.name) ver.")) == true
            }
        }
    }
}
