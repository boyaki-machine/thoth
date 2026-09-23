import CryptoKit
import Foundation
import Quick
import Nimble
@testable import Thoth

// サードパーティライセンス一覧（アプリに同梱する Acknowledgements.md と NOTICE）が、
// いまの Swift Package の解決結果（Package.resolved）から作られていること。
// パッケージを足したり版を変えたりしたのに scripts/update-acknowledgements.swift を
// 実行し忘れると、同梱する一覧が古いままになる（CocoaPods では pod install が自動で作っていた）。
class AcknowledgementsSpec: QuickSpec {

    // MARK: - Fixtures

    /// リポジトリの最上位（このファイルは ThothTests/ にある）
    static let repositoryRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    /// scripts/update-acknowledgements.swift と同じ計算で、Package.resolved の固定版から指紋を作る
    static func pinsFingerprint() -> String? {
        let url = repositoryRoot.appendingPathComponent("Thoth.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pins = json["pins"] as? [[String: Any]] else { return nil }
        let lines = pins.compactMap { pin -> String? in
            guard let identity = pin["identity"] as? String,
                  let state = pin["state"] as? [String: Any],
                  let version = (state["version"] as? String) ?? (state["revision"] as? String) else { return nil }
            return "\(identity) \(version)"
        }
        guard !lines.isEmpty, lines.count == pins.count else { return nil }
        let canonical = lines.sorted().joined(separator: "\n")
        return SHA256.hash(data: Data(canonical.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func bundledAcknowledgements() -> String? {
        guard let url = Bundle.main.url(forResource: "Acknowledgements", withExtension: "md") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    override class func spec() {
        describe("サードパーティライセンス一覧") {
            it("同梱する一覧は、いまの Package.resolved から作ったものである") {
                guard let fingerprint = pinsFingerprint() else {
                    fail("Package.resolved を読めない")
                    return
                }
                expect(bundledAcknowledgements()).to(contain("(pins SHA-256: \(fingerprint))"))
            }

            it("NOTICE は同梱する一覧と同じ内容である") {
                let notice = try? String(contentsOf: repositoryRoot.appendingPathComponent("NOTICE"), encoding: .utf8)
                expect(notice) != nil
                expect(notice) == bundledAcknowledgements()
            }

            it("元になったアプリ（Clipy・ClipMenu）の MIT の著作権表示を載せる") {
                let text = bundledAcknowledgements() ?? ""
                expect(text).to(contain("Copyright (c) 2015-2018 Clipy Project"))
                expect(text).to(contain("Copyright (c) 2008-2014 Naotaka Morimoto"))
            }
        }
    }
}
