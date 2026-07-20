import Quick
import Nimble
@testable import Thoth

// MARK: - A-4: PasteService TOTP Tests

class PasteServiceTOTPSpec: QuickSpec {

    private static var pasteService: PasteService!
    private static let testPasteboard = NSPasteboard(name: .general)

    override class func spec() {
        beforeEach {
            self.pasteService = PasteService()
        }

        describe("PasteService TOTP operations") {

            // MARK: - TOTP Direct Type (Non-pasteboard)

            it("Directly types TOTP code for a given secret") {
                let rfcSecretBase32 = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"
                let params = TOTPParameters(
                    secret: TOTPService.base32Decode(rfcSecretBase32)!,
                    digits: 6,
                    period: 30,
                    algorithm: .sha1,
                    issuer: nil,
                    account: nil
                )

                // Test at a known timestamp
                let testTime = Date(timeIntervalSince1970: 1111111109)
                let service = TOTPService()
                let expectedCode = service.code(for: params, at: testTime)

                expect(expectedCode) == "07081804"  // RFC 6238 vector
            }

            it("Generates TOTP code from otpauth URI") {
                let uri = "otpauth://totp/GitHub:user@example.com?secret=GEZDGNBVGY3TQOJQ&issuer=GitHub"
                let params = TOTPService.parse(uri)

                expect(params).toNot(beNil())
                expect(params?.issuer) == "GitHub"
                expect(params?.account) == "user@example.com"

                let service = TOTPService()
                let code = service.code(for: params!, at: Date())
                expect(code.count) == 6  // Default 6 digits
            }

            // MARK: - TOTP with Different Algorithms

            it("Generates code with SHA256 algorithm") {
                let uri = "otpauth://totp/Test?secret=GEZDGNBVGY3TQOJQ&algorithm=SHA256&digits=8"
                let params = TOTPService.parse(uri)

                expect(params?.algorithm) == .sha256
                expect(params?.digits) == 8

                let service = TOTPService()
                let code = service.code(for: params!, at: Date())
                expect(code.count) == 8
            }

            it("Generates code with SHA512 algorithm") {
                let uri = "otpauth://totp/Test?secret=GEZDGNBVGY3TQOJQ&algorithm=SHA512&digits=8&period=60"
                let params = TOTPService.parse(uri)

                expect(params?.algorithm) == .sha512
                expect(params?.period) == 60

                let service = TOTPService()
                let code = service.code(for: params!, at: Date())
                expect(code).toNot(beEmpty())
            }

            // MARK: - TOTP Field Integration

            it("Extracts TOTP parameters from Field and generates code") {
                let uri = "otpauth://totp/AWS:alice@company.com?secret=JBSWY3DPEHPK3PXP&issuer=AWS"
                let field = SecureMenuItem.Field(label: "AWS TOTP", value: uri, kind: .totp)

                let params = TOTPService.parse(field.value)
                expect(params).toNot(beNil())

                let service = TOTPService()
                let code = service.code(for: params!, at: Date())

                expect(code.count) == 6
                expect(field.isTOTP) == true
            }

            // MARK: - Remaining Seconds Calculation

            it("Calculates remaining seconds for code refresh") {
                let params = TOTPParameters(
                    secret: Data(),
                    digits: 6,
                    period: 30,
                    algorithm: .sha1,
                    issuer: nil,
                    account: nil
                )

                let service = TOTPService()

                // At T=0 seconds of a 30-second window
                let time0 = Date(timeIntervalSince1970: 0)
                expect(service.remainingSeconds(for: params, at: time0)) == 30

                // At T=15 seconds
                let time15 = Date(timeIntervalSince1970: 15)
                expect(service.remainingSeconds(for: params, at: time15)) == 15

                // At T=29 seconds (almost reset)
                let time29 = Date(timeIntervalSince1970: 29)
                expect(service.remainingSeconds(for: params, at: time29)) == 1

                // At T=30 seconds (new window)
                let time30 = Date(timeIntervalSince1970: 30)
                expect(service.remainingSeconds(for: params, at: time30)) == 30
            }

            it("Handles custom period (60 seconds)") {
                let params = TOTPParameters(
                    secret: Data(),
                    digits: 6,
                    period: 60,
                    algorithm: .sha1,
                    issuer: nil,
                    account: nil
                )

                let service = TOTPService()
                let time30 = Date(timeIntervalSince1970: 30)
                expect(service.remainingSeconds(for: params, at: time30)) == 30

                let time59 = Date(timeIntervalSince1970: 59)
                expect(service.remainingSeconds(for: params, at: time59)) == 1

                let time60 = Date(timeIntervalSince1970: 60)
                expect(service.remainingSeconds(for: params, at: time60)) == 60
            }

            // MARK: - Base32 Secret Handling

            it("Handles Base32-encoded secret from URI") {
                let base32Secret = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"
                let data = TOTPService.base32Decode(base32Secret)

                expect(data).toNot(beNil())
                expect(data?.count).to(beGreaterThan(0))
                expect(String(data: data!, encoding: .utf8)) == "12345678901234567890"
            }

            it("Rejects invalid Base32 characters") {
                let invalidBase32 = "INVALID!!!CHARS"
                let data = TOTPService.base32Decode(invalidBase32)

                expect(data).to(beNil())
            }

            // MARK: - URI Validation for TOTP

            it("Validates TOTP URI before code generation") {
                let validURI = "otpauth://totp/Test?secret=GEZDGNBVGY3TQOJQ"
                expect(TOTPService.isValid(validURI)) == true

                let invalidURI = "otpauth://totp/Test?secret=INVALID!!!"
                expect(TOTPService.isValid(invalidURI)) == false

                let missingSecret = "otpauth://totp/Test?issuer=Example"
                expect(TOTPService.isValid(missingSecret)) == false
            }

            it("Handles whitespace and case variations in Base32") {
                let variations = [
                    "GEZDGNBVGY3TQOJQ",
                    "gezdgnbvgy3tqojq",
                    "GEZD GNBV GY3T QOJQ",
                    "gezd gnbv gy3t qojq"
                ]

                let first = TOTPService.base32Decode(variations[0])
                expect(first).toNot(beNil())

                for variant in variations.dropFirst() {
                    let data = TOTPService.base32Decode(variant)
                    expect(data) == first
                }
            }

            // MARK: - Code Consistency

            it("Generates same code for same time window") {
                let uri = "otpauth://totp/Test?secret=GEZDGNBVGY3TQOJQ"
                let params = TOTPService.parse(uri)!
                let service = TOTPService()

                let testTime = Date(timeIntervalSince1970: 1111111110)
                let code1 = service.code(for: params, at: testTime)
                let code2 = service.code(for: params, at: testTime)

                expect(code1) == code2
            }

            it("Generates different codes for different time windows") {
                let uri = "otpauth://totp/Test?secret=GEZDGNBVGY3TQOJQ"
                let params = TOTPService.parse(uri)!
                let service = TOTPService()

                let time1 = Date(timeIntervalSince1970: 1111111110)
                let time2 = Date(timeIntervalSince1970: 1111111140)  // +30 seconds (next window)
                let code1 = service.code(for: params, at: time1)
                let code2 = service.code(for: params, at: time2)

                expect(code1) != code2
            }
        }
    }
}
