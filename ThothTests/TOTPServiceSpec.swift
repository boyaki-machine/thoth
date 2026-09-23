import Quick
import Nimble
import Foundation
@testable import Thoth

class TOTPServiceSpec: QuickSpec {

    private static let service = TOTPService()

    override class func spec() {

        // RFC 6238 Appendix B のテストベクタ（SHA1, ASCII secret "12345678901234567890", 8 桁）
        // ASCII "12345678901234567890" の Base32 表現
        let rfcSecretBase32 = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"

        func makeParams(base32: String, digits: Int = 6, period: Int = 30,
                        algorithm: TOTPParameters.Algorithm = .sha1) -> TOTPParameters {
            return TOTPParameters(secret: TOTPService.base32Decode(base32)!,
                                  digits: digits, period: period,
                                  algorithm: algorithm, issuer: nil, account: nil)
        }

        // MARK: - RFC 6238 Vectors

        describe("RFC 6238 test vectors (SHA1, 8 digits)") {
            let cases: [(TimeInterval, String)] = [
                (59, "94287082"),
                (1111111109, "07081804"),
                (1111111111, "14050471"),
                (1234567890, "89005924"),
                (2000000000, "69279037")
            ]

            it("Generates the expected codes for each timestamp") {
                let params = makeParams(base32: rfcSecretBase32, digits: 8)
                for (time, expected) in cases {
                    let code = self.service.code(for: params, at: Date(timeIntervalSince1970: time))
                    expect(code).to(equal(expected), description: "T=\(time)")
                }
            }
        }

        // MARK: - Base32

        describe("Base32 decoding") {
            it("Decodes a known ASCII secret") {
                let data = TOTPService.base32Decode(rfcSecretBase32)
                expect(data) != nil
                expect(String(data: data!, encoding: .utf8)) == "12345678901234567890"
            }
            it("Ignores whitespace, padding and lowercase") {
                let decoded = TOTPService.base32Decode("JBSWY3DPEHPK3PXP")
                let spacedLowercased = TOTPService.base32Decode("jbsw y3dp ehpk 3pxp")
                expect(decoded) != nil
                expect(decoded) == spacedLowercased
            }
            it("Returns nil for invalid characters") {
                expect(TOTPService.base32Decode("0189!")) == nil
            }
            // 実在のサービスは「ランダムな base32 文字列」を秘密鍵として発行するため、
            // 末尾ビットが非ゼロの鍵が普通に存在する（26文字の鍵では約75%）。
            // RFC 4648 の厳格検証を行うと実在の 2FA 秘密鍵を拒否してしまうため、
            // 主要な認証アプリと同様に末尾ビットは黙って捨てる（過去に厳格化して
            // 登録済み TOTP が全滅するリグレッションを起こした経緯があるので変更禁止）
            it("Accepts real-world secrets with non-zero trailing bits") {
                // "MZXW7": 末尾ビット非ゼロ → 上位ビットのみ採用して "foo" と同じ 3 バイトに
                let lenient = TOTPService.base32Decode("MZXW7")
                expect(lenient) != nil
                expect(lenient!.count) == 3
                // 正規形も当然デコードできる
                let canonical = TOTPService.base32Decode("MZXW6")
                expect(String(data: canonical!, encoding: .utf8)) == "foo"
                // 26文字のランダム風秘密鍵（末尾ビット非ゼロ）
                expect(TOTPService.base32Decode("JBSWY3DPEHPK3PXPJBSWY3DPEH")) != nil
            }
            it("Accepts canonical padded encodings") {
                // "fo" → "MZXQ====" 残余2ビット・ゼロ埋め（正規形）
                let decoded = TOTPService.base32Decode("MZXQ====")
                expect(decoded) != nil
                expect(String(data: decoded!, encoding: .utf8)) == "fo"
            }
        }

        // MARK: - Parsing

        describe("Parsing input") {
            it("Parses a raw Base32 secret with default parameters") {
                let params = TOTPService.parse("JBSWY3DPEHPK3PXP")
                expect(params) != nil
                expect(params?.digits) == TOTPParameters.defaultDigits
                expect(params?.period) == TOTPParameters.defaultPeriod
                expect(params?.algorithm) == .sha1
            }

            it("Parses an otpauth:// URI with all parameters") {
                let uri = "otpauth://totp/GitHub:octocat?secret=\(rfcSecretBase32)&issuer=GitHub&algorithm=SHA256&digits=8&period=60"
                let params = TOTPService.parse(uri)
                expect(params) != nil
                expect(params?.digits) == 8
                expect(params?.period) == 60
                expect(params?.algorithm) == .sha256
                expect(params?.issuer) == "GitHub"
                expect(params?.account) == "octocat"
            }

            it("Falls back to defaults when the URI omits optional parameters") {
                let uri = "otpauth://totp/Example?secret=\(rfcSecretBase32)"
                let params = TOTPService.parse(uri)
                expect(params?.digits) == 6
                expect(params?.period) == 30
                expect(params?.algorithm) == .sha1
            }

            it("Returns nil for a URI without a secret") {
                expect(TOTPService.parse("otpauth://totp/Example?issuer=X")) == nil
            }

            it("Returns nil for empty or clearly invalid input") {
                expect(TOTPService.parse("")) == nil
                expect(TOTPService.parse("   ")) == nil
            }

            it("isValid reflects parseability") {
                expect(TOTPService.isValid(rfcSecretBase32)) == true
                expect(TOTPService.isValid("!!!")) == false
            }
        }

        // MARK: - Remaining seconds

        describe("Remaining seconds") {
            it("Counts down within the period") {
                let params = makeParams(base32: rfcSecretBase32)
                expect(self.service.remainingSeconds(for: params, at: Date(timeIntervalSince1970: 0))) == 30
                expect(self.service.remainingSeconds(for: params, at: Date(timeIntervalSince1970: 1))) == 29
                expect(self.service.remainingSeconds(for: params, at: Date(timeIntervalSince1970: 29))) == 1
                expect(self.service.remainingSeconds(for: params, at: Date(timeIntervalSince1970: 30))) == 30
            }
        }
    }
}
