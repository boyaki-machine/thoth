import Foundation
import Quick
import Nimble
import Security
@testable import Thoth

// 起動時の自己再署名の判定と codesign の引数。
// Hardened Runtime が無いと、同じユーザーの他のプロセスが DYLD_INSERT_LIBRARIES などで
// Thoth にコードを注入し、キーチェーンのセキュア情報を Thoth として読めてしまう。
class CodeSignServiceSpec: QuickSpec {
    override class func spec() {

        describe("再署名が要るかの判定") {
            let stableName = CodeSignService.certificateCommonName

            it("安定署名で Hardened Runtime 付きなら再署名しない") {
                expect(CodeSignService.needsResign(commonName: stableName, hasHardenedRuntime: true)) == false
            }

            // v1.6.5 以前に再署名したアプリ（安定署名だが Hardened Runtime なし）
            it("安定署名でも Hardened Runtime が無ければ再署名する") {
                expect(CodeSignService.needsResign(commonName: stableName, hasHardenedRuntime: false)) == true
            }

            it("ad-hoc 署名（証明書なし）なら再署名する") {
                expect(CodeSignService.needsResign(commonName: nil, hasHardenedRuntime: true)) == true
                expect(CodeSignService.needsResign(commonName: nil, hasHardenedRuntime: false)) == true
            }

            it("別の証明書（Clipy 時代など）なら再署名する") {
                expect(CodeSignService.needsResign(commonName: "Clipy Local Signing", hasHardenedRuntime: true)) == true
            }
        }

        describe("codesign の引数") {
            var arguments: [String] = []

            beforeEach {
                arguments = CodeSignService.resignArguments(bundlePath: "/Applications/Thoth.app")
            }

            it("Hardened Runtime を付ける") {
                guard let index = arguments.firstIndex(of: "--options") else { return fail("missing --options") }
                expect(arguments.indices.contains(index + 1) ? arguments[index + 1] : nil) == "runtime"
            }

            // 引き継がないと Hardened Runtime の下でカメラが使えなくなる
            it("ビルド時のエンタイトルメントを引き継ぐ") {
                expect(arguments).to(contain("--preserve-metadata=entitlements"))
            }

            it("安定署名の証明書で署名し、バンドルのパスは最後に 1 語で渡す") {
                guard let index = arguments.firstIndex(of: "--sign") else { return fail("missing --sign") }
                expect(arguments[index + 1]) == CodeSignService.certificateCommonName
                expect(arguments.last) == "/Applications/Thoth.app"
            }
        }

        describe("ビルド設定") {
            // Hardened Runtime の下でカメラを使うにはエンタイトルメントが要る（テストホストは Thoth.app）。
            // Hardened Runtime そのものは、Xcode がテスト用の Debug ビルドには付けないためここでは見ない
            // （Release ビルドと、起動時の再署名で付く）
            it("テストホストの Thoth.app はカメラのエンタイトルメントを持つ") {
                var staticCode: SecStaticCode?
                SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, [], &staticCode)
                var infoRef: CFDictionary?
                if let staticCode = staticCode {
                    SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &infoRef)
                }
                let info = infoRef as? [String: Any] ?? [:]
                let entitlements = info[kSecCodeInfoEntitlementsDict as String] as? [String: Any] ?? [:]
                expect(entitlements["com.apple.security.device.camera"] as? Bool) == true
            }
        }
    }
}
