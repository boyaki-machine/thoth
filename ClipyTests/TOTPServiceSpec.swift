import Quick
import Nimble
import Foundation
@testable import Clipy

class TOTPServiceSpec: QuickSpec {

    private let service = TOTPService()

    override func spec() {

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
            let params = makeParams(base32: rfcSecretBase32, digits: 8)
            let cases: [(TimeInterval, String)] = [
                (59, "94287082"),
                (1111111109, "07081804"),
                (1111111111, "14050471"),
                (1234567890, "89005924"),
                (2000000000, "69279037")
            ]

            it("Generates the expected codes for each timestamp") {
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
                expect(data).toNot(beNil())
                expect(String(data: data!, encoding: .utf8)) == "12345678901234567890"
            }
            it("Ignores whitespace, padding and lowercase") {
                let a = TOTPService.base32Decode("JBSWY3DPEHPK3PXP")
                let b = TOTPService.base32Decode("jbsw y3dp ehpk 3pxp")
                expect(a).toNot(beNil())
                expect(a) == b
            }
            it("Returns nil for invalid characters") {
                expect(TOTPService.base32Decode("0189!")).to(beNil())
            }
        }

        // MARK: - Parsing

        describe("Parsing input") {
            it("Parses a raw Base32 secret with default parameters") {
                let params = TOTPService.parse("JBSWY3DPEHPK3PXP")
                expect(params).toNot(beNil())
                expect(params?.digits) == TOTPParameters.defaultDigits
                expect(params?.period) == TOTPParameters.defaultPeriod
                expect(params?.algorithm) == .sha1
            }

            it("Parses an otpauth:// URI with all parameters") {
                let uri = "otpauth://totp/GitHub:octocat?secret=\(rfcSecretBase32)&issuer=GitHub&algorithm=SHA256&digits=8&period=60"
                let params = TOTPService.parse(uri)
                expect(params).toNot(beNil())
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
                expect(TOTPService.parse("otpauth://totp/Example?issuer=X")).to(beNil())
            }

            it("Returns nil for empty or clearly invalid input") {
                expect(TOTPService.parse("")).to(beNil())
                expect(TOTPService.parse("   ")).to(beNil())
            }

            it("isValid reflects parseability") {
                expect(TOTPService.isValid(rfcSecretBase32)) == true
                expect(TOTPService.isValid("!!!")) == false
            }
        }

        // MARK: - Remaining seconds

        describe("Remaining seconds") {
            let params = makeParams(base32: rfcSecretBase32)
            it("Counts down within the period") {
                expect(self.service.remainingSeconds(for: params, at: Date(timeIntervalSince1970: 0))) == 30
                expect(self.service.remainingSeconds(for: params, at: Date(timeIntervalSince1970: 1))) == 29
                expect(self.service.remainingSeconds(for: params, at: Date(timeIntervalSince1970: 29))) == 1
                expect(self.service.remainingSeconds(for: params, at: Date(timeIntervalSince1970: 30))) == 30
            }
        }
    }
}

// MARK: - SecureMenuItem.Field (createdAt)

class SecureMenuItemFieldSpec: QuickSpec {
    override func spec() {
        describe("SecureMenuItem.Field with createdAt") {
            it("Creates a TOTP field with createdAt set to now") {
                let now = Date()
                let field = SecureMenuItem.Field(label: "GitHub TOTP", value: "otpauth://totp/GitHub:me?secret=GEZDGNBVGY3TQOJQ",
                                                 kind: .totp, createdAt: now)
                expect(field.isTOTP) == true
                expect(field.createdAt).to(beCloseTo(now, within: 0.1))
            }

            it("Creates a plain field with default createdAt (now)") {
                let field = SecureMenuItem.Field(label: "Username", value: "alice")
                expect(field.kind) == .plain
                expect(field.createdAt).to(beCloseTo(Date(), within: 0.1))
            }

            it("Encodes and decodes a TOTP field preserving createdAt") {
                let original = SecureMenuItem.Field(label: "TOTP", value: "secret",
                                                    kind: .totp, createdAt: Date(timeIntervalSince1970: 1234567890))
                let encoder = JSONEncoder()
                let data = try! encoder.encode(original)
                let decoder = JSONDecoder()
                let decoded = try! decoder.decode(SecureMenuItem.Field.self, from: data)
                expect(decoded.createdAt.timeIntervalSince1970) == 1234567890
            }

            it("Decodes a legacy field without createdAt, using current time as fallback") {
                let legacyJSON = """
                {
                    "fieldID": "test-id",
                    "label": "Old field",
                    "value": "test-value",
                    "isPassword": false,
                    "kind": "plain",
                    "history": []
                }
                """
                let decoder = JSONDecoder()
                let field = try! decoder.decode(SecureMenuItem.Field.self, from: legacyJSON.data(using: .utf8)!)
                expect(field.createdAt).to(beCloseTo(Date(), within: 1.0))
            }
        }
    }
}
