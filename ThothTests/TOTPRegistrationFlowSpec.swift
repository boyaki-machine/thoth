import Foundation
import Quick
import Nimble
@testable import Thoth

// MARK: - TOTP GUI Test: Phase 1-2 (URI Parse & Registration Flow)

class TOTPRegistrationFlowSpec: QuickSpec {

    private static let testKeychainService = "com.clipy-app.ClipyTests.SecureMenu"
    private static var service: SecureMenuService!

    override class func spec() {
        beforeEach {
            self.service = SecureMenuService(keychainService: TOTPRegistrationFlowSpec.testKeychainService)
            self.service.deleteAllItems()
        }
        afterEach {
            self.service.deleteAllItems()
        }
        parseAndRegistrationSpecs()
        codeAndLifecycleSpecs()
    }

    private static func parseAndRegistrationSpecs() {
        describe("TOTP registration workflow") {

            // MARK: - Phase 1: URI Parse and Field Creation

            it("Parses GitHub TOTP URI into Field") {
                let uri = "otpauth://totp/GitHub:user@example.com?secret=GEZDGNBVGY3TQOJQ&issuer=GitHub"
                let params = TOTPService.parse(uri)

                expect(params?.digits) != nil
                expect(params?.secret.isEmpty) == false
                expect(params?.issuer) == "GitHub"
                expect(params?.account) == "user@example.com"
                expect(params?.digits) == 6
                expect(params?.period) == 30
                expect(params?.algorithm) == .sha1

                let field = SecureMenuItem.Field(label: "GitHub 2FA", value: uri, kind: .totp)
                expect(field.isTOTP) == true
                expect(field.value) == uri
            }

            it("Parses AWS TOTP URI with custom parameters") {
                let uri = "otpauth://totp/AWS:alice@company.com?secret=JBSWY3DPEHPK3PXP&issuer=AWS&algorithm=SHA256&digits=8"
                let params = TOTPService.parse(uri)

                expect(params?.issuer) == "AWS"
                expect(params?.account) == "alice@company.com"
                expect(params?.digits) == 8
                expect(params?.algorithm) == .sha256

                let field = SecureMenuItem.Field(label: "AWS Console", value: uri, kind: .totp)
                expect(field.isTOTP) == true
            }

            it("Parses minimal TOTP URI") {
                let uri = "otpauth://totp/?secret=GEZDGNBVGY3TQOJQ"
                let params = TOTPService.parse(uri)

                expect(params?.digits) != nil
                expect(params?.issuer) == nil
                expect(params?.account) == nil
                expect(params?.digits) == 6  // default
                expect(params?.period) == 30  // default
            }

            // MARK: - Phase 2: Keychain Registration & Retrieval

            it("Saves TOTP field to keychain and retrieves it") {
                let uri = "otpauth://totp/GitHub:user@github.com?secret=GEZDGNBVGY3TQOJQ&issuer=GitHub"
                let field = SecureMenuItem.Field(label: "GitHub 2FA", value: uri, kind: .totp)
                let item = SecureMenuItem(itemID: "github-account", title: "GitHub", fields: [field])

                expect(self.service.save(item)) == true

                let loaded = self.service.loadAllItems()
                expect(loaded.count) == 1
                expect(loaded[0].itemID) == "github-account"
                expect(loaded[0].fields.count) == 1
                expect(loaded[0].fields[0].label) == "GitHub 2FA"
                expect(loaded[0].fields[0].isTOTP) == true
                expect(loaded[0].fields[0].value) == uri
            }

            it("Preserves TOTP createdAt timestamp through keychain cycle") {
                let fixedDate = Date(timeIntervalSince1970: 1234567890)
                let uri = "otpauth://totp/Test?secret=GEZDGNBVGY3TQOJQ"
                let field = SecureMenuItem.Field(label: "Test TOTP", value: uri, kind: .totp, createdAt: fixedDate)
                let item = SecureMenuItem(itemID: "test-totp", title: "Test", fields: [field])

                expect(self.service.save(item)) == true

                let loaded = self.service.loadAllItems()
                expect(loaded[0].fields[0].createdAt.timeIntervalSince1970) == fixedDate.timeIntervalSince1970
            }

            it("Supports multiple TOTP fields in single account") {
                let uri1 = "otpauth://totp/GitHub?secret=GEZDGNBVGY3TQOJQ"
                let uri2 = "otpauth://totp/AWS?secret=JBSWY3DPEHPK3PXP"
                let field1 = SecureMenuItem.Field(label: "GitHub 2FA", value: uri1, kind: .totp)
                let field2 = SecureMenuItem.Field(label: "AWS 2FA", value: uri2, kind: .totp)
                let item = SecureMenuItem(itemID: "multi-2fa", title: "Multiple Accounts", fields: [field1, field2])

                expect(self.service.save(item)) == true

                let loaded = self.service.loadAllItems()
                expect(loaded[0].fields.count) == 2
                expect(loaded[0].fields[0].isTOTP) == true
                expect(loaded[0].fields[1].isTOTP) == true
            }

            // MARK: - Phase 2: TOTP + Other Fields

            it("Stores TOTP field alongside regular password field") {
                let passwordField = SecureMenuItem.Field(label: "Password", value: "secret123", isPassword: true)
                let totpField = SecureMenuItem.Field(label: "2FA", value: "otpauth://totp/Test?secret=GEZDGNBVGY3TQOJQ", kind: .totp)
                let item = SecureMenuItem(itemID: "account", title: "Account", fields: [passwordField, totpField])

                expect(self.service.save(item)) == true

                let loaded = self.service.loadAllItems()
                expect(loaded[0].fields.count) == 2
                expect(loaded[0].fields[0].isPassword) == true
                expect(loaded[0].fields[1].isTOTP) == true
            }

        }
    }

    private static func codeAndLifecycleSpecs() {
        describe("TOTP code generation and lifecycle") {

            // MARK: - Code Generation After Registration

            it("Generates valid TOTP code from loaded field") {
                let uri = "otpauth://totp/Test?secret=GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"
                let field = SecureMenuItem.Field(label: "Test TOTP", value: uri, kind: .totp)
                let item = SecureMenuItem(itemID: "test", title: "Test", fields: [field])

                _ = self.service.save(item)

                let loaded = self.service.loadAllItems()
                let loadedField = loaded[0].fields[0]

                let params = TOTPService.parse(loadedField.value)
                expect(params?.digits) != nil

                let totpService = TOTPService()
                let code = totpService.code(for: params!, at: Date())
                expect(code?.count) == 6
            }

            it("Calculates remaining seconds for loaded TOTP field") {
                let uri = "otpauth://totp/Test?secret=GEZDGNBVGY3TQOJQ&period=30"
                let field = SecureMenuItem.Field(label: "TOTP", value: uri, kind: .totp)
                let item = SecureMenuItem(itemID: "test", title: "Test", fields: [field])

                _ = self.service.save(item)

                let loaded = self.service.loadAllItems()
                let loadedField = loaded[0].fields[0]

                let params = TOTPService.parse(loadedField.value)
                let totpService = TOTPService()
                let remaining = totpService.remainingSeconds(for: params!, at: Date())

                expect(remaining) > 0
                expect(remaining) <= 30
            }

            // MARK: - Update TOTP Field

            it("Updates TOTP URI while keeping field identity") {
                let oldURI = "otpauth://totp/OldService?secret=GEZDGNBVGY3TQOJQ"
                let oldField = SecureMenuItem.Field(label: "Auth", value: oldURI, kind: .totp)
                var item = SecureMenuItem(itemID: "service", title: "Service", fields: [oldField])

                _ = self.service.save(item)

                // Update URI
                let newURI = "otpauth://totp/NewService?secret=JBSWY3DPEHPK3PXP"
                let newField = SecureMenuItem.Field(
                    fieldID: oldField.fieldID,
                    label: "Auth",
                    value: newURI,
                    isPassword: false,
                    kind: .totp,
                    history: oldField.history,
                    createdAt: oldField.createdAt
                )
                item = SecureMenuItem(itemID: "service", title: "Service", fields: [newField])

                expect(self.service.save(item)) == true

                let loaded = self.service.loadAllItems()
                expect(loaded[0].fields[0].value) == newURI
                expect(loaded[0].fields[0].fieldID) == oldField.fieldID
            }

            // MARK: - Delete TOTP Field

            it("Removes TOTP field from account") {
                let totpField = SecureMenuItem.Field(label: "2FA", value: "otpauth://...", kind: .totp)
                let passwordField = SecureMenuItem.Field(label: "Password", value: "secret")
                var item = SecureMenuItem(itemID: "account", title: "Account", fields: [totpField, passwordField])

                _ = self.service.save(item)

                // Delete TOTP field
                item = SecureMenuItem(itemID: "account", title: "Account", fields: [passwordField])
                expect(self.service.save(item)) == true

                let loaded = self.service.loadAllItems()
                expect(loaded[0].fields.count) == 1
                expect(loaded[0].fields[0].isTOTP) == false
            }

            // MARK: - Sample URIs (Test Data)

            it("Successfully registers common provider URIs") {
                let sampleURIs = [
                    "otpauth://totp/GitHub:octocat@github.com?secret=GEZDGNBVGY3TQOJQ&issuer=GitHub",
                    "otpauth://totp/AWS:admin@example.com?secret=JBSWY3DPEHPK3PXP&issuer=AWS",
                    "otpauth://totp/Google:user@gmail.com?secret=HXDMVJECJJWSRB3H&issuer=Google",
                    "otpauth://totp/Microsoft:user@outlook.com?secret=NRXWK3DENFSWC4TBNRXWK3DENFSWC4TB&issuer=Microsoft"
                ]

                for (index, uri) in sampleURIs.enumerated() {
                    let field = SecureMenuItem.Field(label: "Provider \(index)", value: uri, kind: .totp)
                    let item = SecureMenuItem(itemID: "provider-\(index)", title: "Provider \(index)", fields: [field])

                    expect(self.service.save(item)) == true
                }

                let loaded = self.service.loadAllItems()
                expect(loaded.count) == sampleURIs.count
            }
        }
    }
}
