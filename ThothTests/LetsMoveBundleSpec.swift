import Foundation
import Quick
import Nimble
@testable import Thoth

// LetsMove（Packages/LetsMove）が翻訳を読むバンドル。
// Swift Package では翻訳がモジュール用のバンドル（LetsMove_LetsMove.bundle）に入る。
// 本家の `bundleForClass:` のままだとアプリ本体のバンドルを見てしまい、
// 「アプリケーションフォルダに移動しますか？」が英語でしか出なくなる。
class LetsMoveBundleSpec: QuickSpec {

    // MARK: - Fixtures

    /// LetsMove が翻訳を読むバンドル（`+[LetsMove bundle]`。LetsMove の内部クラス）
    static func letsMoveBundle() -> Bundle? {
        guard let letsMoveClass = NSClassFromString("LetsMove") else { return nil }
        return (letsMoveClass as AnyObject).perform(NSSelectorFromString("bundle"))?.takeUnretainedValue() as? Bundle
    }

    override class func spec() {
        describe("LetsMove の翻訳") {
            it("モジュール用のバンドルから読む") {
                expect(letsMoveBundle()?.bundleURL.lastPathComponent) == "LetsMove_LetsMove.bundle"
            }

            it("日本語の文言を読める") {
                let japanese = letsMoveBundle()?.path(forResource: "ja", ofType: "lproj").flatMap(Bundle.init(path:))
                expect(japanese?.localizedString(forKey: "Do Not Move", value: nil, table: "MoveApplication")) == "移動しない"
            }
        }
    }
}
