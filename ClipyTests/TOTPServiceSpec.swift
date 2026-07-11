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
            // RFC 4648 §6: 末尾の残余（パディング）ビットは必ずゼロでなければならない。
            // 非ゼロを許すと 1 文字違いの秘密鍵が別のバイト列に静かにデコードされてしまう
            it("Rejects non-zero trailing bits (RFC 4648)") {
                // "MZXW6===" (fooの正規形) の末尾文字を変えて残余ビットを非ゼロにしたもの
                expect(TOTPService.base32Decode("MZXW7")).to(beNil())
                // 正規形はデコードできる
                let canonical = TOTPService.base32Decode("MZXW6")
                expect(canonical).toNot(beNil())
                expect(String(data: canonical!, encoding: .utf8)) == "foo"
            }
            it("Rejects impossible remainder lengths (1/3/6 characters)") {
                // 1文字（5ビット）は1バイトに満たず、正規のエンコード長として存在しない
                expect(TOTPService.base32Decode("A")).to(beNil())
                // 9文字 = 8+1 → 残余5ビットのあり得ない長さ
                expect(TOTPService.base32Decode("GEZDGNBVG")).to(beNil())
            }
            it("Accepts canonical padded encodings") {
                // "fo" → "MZXQ====" 残余2ビット・ゼロ埋め（正規形）
                let decoded = TOTPService.base32Decode("MZXQ====")
                expect(decoded).toNot(beNil())
                expect(String(data: decoded!, encoding: .utf8)) == "fo"
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

// MARK: - SecureMenuItem.Field (CRUD)

class SecureMenuItemFieldSpec: QuickSpec {
    override func spec() {

        // MARK: - createdAt Basics

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

        // MARK: - Field Types (Plain, Password, TOTP)

        describe("Field type variants") {
            it("Creates a plain text field") {
                let field = SecureMenuItem.Field(label: "Username", value: "alice@example.com", isPassword: false)
                expect(field.label) == "Username"
                expect(field.value) == "alice@example.com"
                expect(field.isPassword) == false
                expect(field.kind) == .plain
            }

            it("Creates a password field") {
                let field = SecureMenuItem.Field(label: "Password", value: "secret123", isPassword: true)
                expect(field.label) == "Password"
                expect(field.value) == "secret123"
                expect(field.isPassword) == true
                expect(field.kind) == .plain
            }

            it("Creates a TOTP field from otpauth URI") {
                let uri = "otpauth://totp/GitHub:user@example.com?secret=GEZDGNBVGY3TQOJQ&issuer=GitHub"
                let field = SecureMenuItem.Field(label: "GitHub TOTP", value: uri, kind: .totp)
                expect(field.label) == "GitHub TOTP"
                expect(field.value) == uri
                expect(field.isTOTP) == true
                expect(field.isPassword) == false
            }
        }

        // MARK: - Field History

        describe("Field history management") {
            it("Creates a field with empty history") {
                let field = SecureMenuItem.Field(label: "Test", value: "value1")
                expect(field.history.count) == 0
            }

            it("Encodes and decodes field with history entries") {
                let now = Date()
                let entry1 = SecureMenuItem.FieldHistoryEntry(value: "old-value-1", replacedAt: Date(timeIntervalSince1970: 1000))
                let entry2 = SecureMenuItem.FieldHistoryEntry(value: "old-value-2", replacedAt: Date(timeIntervalSince1970: 2000))
                let field = SecureMenuItem.Field(label: "Test", value: "current-value",
                                                 isPassword: false, kind: .plain, history: [entry1, entry2])

                let encoder = JSONEncoder()
                let data = try! encoder.encode(field)
                let decoder = JSONDecoder()
                let decoded = try! decoder.decode(SecureMenuItem.Field.self, from: data)

                expect(decoded.history.count) == 2
                expect(decoded.history[0].value) == "old-value-1"
                expect(decoded.history[1].value) == "old-value-2"
            }
        }

        // MARK: - JSON Serialization

        describe("Field JSON serialization") {
            it("Includes all required properties in JSON") {
                let field = SecureMenuItem.Field(label: "Test Field", value: "test-value",
                                                 isPassword: true, kind: .plain)
                let encoder = JSONEncoder()
                let data = try! encoder.encode(field)
                let json = try! JSONSerialization.jsonObject(with: data) as! [String: Any]

                expect(json.keys.contains("fieldID")) == true
                expect(json.keys.contains("label")) == true
                expect(json.keys.contains("value")) == true
                expect(json.keys.contains("isPassword")) == true
                expect(json.keys.contains("kind")) == true
                expect(json.keys.contains("history")) == true
                expect(json.keys.contains("createdAt")) == true
            }

            it("Decodes JSON with all properties correctly") {
                let original = SecureMenuItem.Field(label: "Username", value: "alice", isPassword: false)
                let encoder = JSONEncoder()
                let data = try! encoder.encode(original)
                let decoder = JSONDecoder()
                let field = try! decoder.decode(SecureMenuItem.Field.self, from: data)

                expect(field.label) == "Username"
                expect(field.value) == "alice"
                expect(field.isPassword) == false
                expect(field.kind) == .plain
                expect(field.fieldID) == original.fieldID
                expect(field.createdAt).to(beCloseTo(original.createdAt, within: 0.001))
            }
        }

        // MARK: - Field Update (Create, Read, Update, Delete)

        describe("Field CRUD operations") {
            it("Updates field label") {
                var field = SecureMenuItem.Field(label: "Old Label", value: "value")
                let newField = SecureMenuItem.Field(fieldID: field.fieldID, label: "New Label",
                                                    value: field.value, isPassword: field.isPassword,
                                                    kind: field.kind, history: field.history, createdAt: field.createdAt)
                expect(newField.label) == "New Label"
                expect(newField.fieldID) == field.fieldID
                expect(newField.createdAt).to(beCloseTo(field.createdAt, within: 0.001))
            }

            it("Updates field value while preserving metadata") {
                let original = SecureMenuItem.Field(label: "Password", value: "old-secret", isPassword: true)
                let updated = SecureMenuItem.Field(fieldID: original.fieldID, label: original.label,
                                                   value: "new-secret", isPassword: original.isPassword,
                                                   kind: original.kind, history: original.history)
                expect(updated.value) == "new-secret"
                expect(updated.isPassword) == true
                expect(updated.fieldID) == original.fieldID
                expect(updated.label) == original.label
            }

            it("Toggles password flag") {
                let plainField = SecureMenuItem.Field(label: "Secret", value: "mysecret", isPassword: false)
                let passwordField = SecureMenuItem.Field(fieldID: plainField.fieldID, label: plainField.label,
                                                         value: plainField.value, isPassword: true,
                                                         kind: plainField.kind, history: plainField.history)
                expect(plainField.isPassword) == false
                expect(passwordField.isPassword) == true
            }
        }

        // MARK: - Multiple Fields Reordering

        describe("Multiple field reordering") {
            it("Reorders fields array correctly (move to later position)") {
                var fields = [
                    SecureMenuItem.Field(label: "Field 1", value: "value1"),
                    SecureMenuItem.Field(label: "Field 2", value: "value2"),
                    SecureMenuItem.Field(label: "Field 3", value: "value3"),
                    SecureMenuItem.Field(label: "Field 4", value: "value4"),
                    SecureMenuItem.Field(label: "Field 5", value: "value5")
                ]

                // Move field at index 1 (F2) to position 3 (before F4 in .above semantics)
                let moved = fields.remove(at: 1)
                let targetIndex = 3 > 1 ? 3 - 1 : 3
                fields.insert(moved, at: targetIndex)

                // After: [F1, F3, F2, F4, F5]
                expect(fields[0].label) == "Field 1"
                expect(fields[1].label) == "Field 3"
                expect(fields[2].label) == "Field 2"
                expect(fields[3].label) == "Field 4"
                expect(fields[4].label) == "Field 5"
            }

            it("Reorders fields array correctly (move to earlier position)") {
                var fields = [
                    SecureMenuItem.Field(label: "Field 1", value: "value1"),
                    SecureMenuItem.Field(label: "Field 2", value: "value2"),
                    SecureMenuItem.Field(label: "Field 3", value: "value3"),
                    SecureMenuItem.Field(label: "Field 4", value: "value4"),
                    SecureMenuItem.Field(label: "Field 5", value: "value5")
                ]

                // Move field at index 3 (F4) to position 1 (before F2 in .above semantics)
                let moved = fields.remove(at: 3)
                let targetIndex = 1 > 3 ? 1 - 1 : 1
                fields.insert(moved, at: targetIndex)

                // After: [F1, F4, F2, F3, F5]
                expect(fields[0].label) == "Field 1"
                expect(fields[1].label) == "Field 4"
                expect(fields[2].label) == "Field 2"
                expect(fields[3].label) == "Field 3"
                expect(fields[4].label) == "Field 5"
            }

            it("Handles edge case: move last field to first position") {
                var fields = [
                    SecureMenuItem.Field(label: "Field 1", value: "value1"),
                    SecureMenuItem.Field(label: "Field 2", value: "value2"),
                    SecureMenuItem.Field(label: "Field 3", value: "value3")
                ]

                let moved = fields.remove(at: 2)
                let targetIndex = 0 > 2 ? 0 - 1 : 0
                fields.insert(moved, at: targetIndex)

                expect(fields[0].label) == "Field 3"
                expect(fields[1].label) == "Field 1"
                expect(fields[2].label) == "Field 2"
            }

            it("Handles edge case: move first field to last position") {
                var fields = [
                    SecureMenuItem.Field(label: "Field 1", value: "value1"),
                    SecureMenuItem.Field(label: "Field 2", value: "value2"),
                    SecureMenuItem.Field(label: "Field 3", value: "value3")
                ]

                let moved = fields.remove(at: 0)
                let targetIndex = 3 > 0 ? 3 - 1 : 3
                fields.insert(moved, at: targetIndex)

                expect(fields[0].label) == "Field 2"
                expect(fields[1].label) == "Field 3"
                expect(fields[2].label) == "Field 1"
            }
        }
    }
}
