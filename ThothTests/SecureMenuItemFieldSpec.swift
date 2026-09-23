import Quick
import Nimble
import Foundation
@testable import Thoth

// MARK: - SecureMenuItem.Field (CRUD)

class SecureMenuItemFieldSpec: QuickSpec {
    // swiftlint:disable:next function_body_length
    override class func spec() {

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
                guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                    fail("Failed to serialize field to JSON object")
                    return
                }

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
                let field = SecureMenuItem.Field(label: "Old Label", value: "value")
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
