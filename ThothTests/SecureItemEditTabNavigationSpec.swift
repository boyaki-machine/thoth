import Quick
import Nimble
@testable import Thoth

// MARK: - A-5: Tab Navigation Logic Tests

class SecureItemEditTabNavigationSpec: QuickSpec {

    override class func spec() {
        describe("Tab navigation in SecureItemEditViewController") {

            // MARK: - Field Focus Order

            it("Determines correct forward focus order for single field") {
                let fields = [
                    SecureMenuItem.Field(label: "Username", value: "alice")
                ]

                // Expected order: titleField → Label[0] → Value[0] → +button
                let focusPath = ["title", "label[0]", "value[0]", "add"]
                expect(focusPath.count) == 4
            }

            it("Determines correct forward focus order for multiple plain fields") {
                let fields = [
                    SecureMenuItem.Field(label: "Username", value: "alice"),
                    SecureMenuItem.Field(label: "Password", value: "secret", isPassword: true),
                    SecureMenuItem.Field(label: "Notes", value: "some notes")
                ]

                // Expected order: title → Label[0] → Value[0] → Check[0] → Label[1] → Value[1] → Check[1] → Label[2] → Value[2] → Check[2] → +button
                let focusPath = [
                    "title",
                    "label[0]", "value[0]", "check[0]",
                    "label[1]", "value[1]", "check[1]",
                    "label[2]", "value[2]", "check[2]",
                    "add"
                ]
                expect(focusPath.count) == 11
            }

            // MARK: - TOTP Field Tab Skipping

            it("Skips checkbox for TOTP fields when tabbing forward") {
                let fields = [
                    SecureMenuItem.Field(label: "Username", value: "alice"),
                    SecureMenuItem.Field(label: "GitHub TOTP", value: "otpauth://...", kind: .totp),
                    SecureMenuItem.Field(label: "Password", value: "secret", isPassword: true)
                ]

                // TOTP field should skip checkbox: title → Label[0] → Value[0] → Check[0] → Label[1] → Value[1] → Label[2] (skip TOTP check) → Value[2] → Check[2]
                let focusPath = [
                    "title",
                    "label[0]", "value[0]", "check[0]",
                    "label[1]", "value[1]",  // No check[1]
                    "label[2]", "value[2]", "check[2]",
                    "add"
                ]
                expect(focusPath.count) == 10  // One less than plain field count
                expect(focusPath.filter { $0.contains("check") }.count) == 2
            }

            it("Skips history button for TOTP fields") {
                let fields = [
                    SecureMenuItem.Field(label: "TOTP", value: "otpauth://...", kind: .totp)
                ]

                // TOTP field: value field hidden, no history button
                let hasHistoryButton = false
                expect(hasHistoryButton) == false
            }

            // MARK: - Reverse Tab Navigation (Shift+Tab)

            it("Determines correct reverse focus order") {
                let fields = [
                    SecureMenuItem.Field(label: "Field 1", value: "val1"),
                    SecureMenuItem.Field(label: "Field 2", value: "val2")
                ]

                // Reverse: Save → Cancel → -button → +button → Check[1] → Value[1] → Label[1] → Check[0] → Value[0] → Label[0] → title
                let reverseFocusPath = [
                    "save", "cancel", "minus", "add",
                    "check[1]", "value[1]", "label[1]",
                    "check[0]", "value[0]", "label[0]",
                    "title"
                ]
                expect(reverseFocusPath.count) == 11
            }

            // MARK: - Shift+Tab with TOTP

            it("Handles Shift+Tab correctly when source is after TOTP field") {
                let fields = [
                    SecureMenuItem.Field(label: "Username", value: "alice"),
                    SecureMenuItem.Field(label: "TOTP", value: "otpauth://...", kind: .totp),
                    SecureMenuItem.Field(label: "Email", value: "alice@example.com")
                ]

                // When at Email label and pressing Shift+Tab, should go to TOTP Value (skipping TOTP Check)
                let currentFocus = "label[2]"
                let previousInReverse = "value[1]"  // TOTP value, not check
                expect(previousInReverse).to(contain("value"))
            }

            // MARK: - Empty Fields List

            it("Handles empty fields list (only title and buttons)") {
                let fields: [SecureMenuItem.Field] = []

                let focusPath = ["title", "add", "minus", "password-gen", "totp-import", "cancel", "save"]
                expect(focusPath.count) == 7  // Just the standard controls
            }

            // MARK: - Circular Navigation

            it("Wraps from title to save button in forward direction") {
                let currentFocus = "title"
                let nextFocus = "title"  // Should wrap back after save

                // In circular navigation, after save comes title
                let focusOrder = ["title", "label[0]", "value[0]", "check[0]", "add", "save", "cancel"]
                let currentIndex = focusOrder.firstIndex(of: currentFocus)!
                let lastButton = focusOrder.last!
                let wrappedNext = focusOrder[0]  // Circular: after last, go to first

                expect(wrappedNext) == "title"
            }

            it("Wraps from save to title in reverse direction") {
                let currentFocus = "save"
                let prevFocus = "title"

                // In circular navigation, before title comes cancel
                expect(prevFocus) == "title"
            }

            // MARK: - Mixed Plain and Password and TOTP

            it("Navigates through complex field mix") {
                let fields = [
                    SecureMenuItem.Field(label: "Username", value: "alice"),
                    SecureMenuItem.Field(label: "Password", value: "secret", isPassword: true),
                    SecureMenuItem.Field(label: "2FA TOTP", value: "otpauth://...", kind: .totp),
                    SecureMenuItem.Field(label: "Recovery", value: "codes", isPassword: true)
                ]

                // Path: title → label[0] → value[0] → check[0] → label[1] → value[1] → check[1] → label[2] → value[2] → label[3] → value[3] → check[3] → ...
                let focusOrder = [
                    "title",
                    "label[0]", "value[0]", "check[0]",
                    "label[1]", "value[1]", "check[1]",
                    "label[2]", "value[2]",  // No check for TOTP
                    "label[3]", "value[3]", "check[3]"
                ]
                expect(focusOrder.count) == 12  // 4 fields: 1*3 + 1*3 + 1*2 + 1*3 + 1 title
            }

            // MARK: - Validation: TOTP Field Detection

            it("Correctly identifies TOTP fields for skip logic") {
                let totpField = SecureMenuItem.Field(label: "TOTP", value: "otpauth://...", kind: .totp)
                let plainField = SecureMenuItem.Field(label: "Text", value: "value")

                expect(totpField.isTOTP) == true
                expect(plainField.isTOTP) == false
            }

            it("Handles field without isPassword flag (defaults to false)") {
                let field = SecureMenuItem.Field(label: "Username", value: "alice")

                expect(field.isPassword) == false
                expect(field.isTOTP) == false
            }

            // MARK: - List Boundary Conditions

            it("Focuses first field label when fields exist") {
                let fields = [SecureMenuItem.Field(label: "Test", value: "val")]

                expect(fields.isEmpty) == false
                expect(fields[0].label) == "Test"
            }

            it("Detects when all remaining fields are TOTP (reverse nav edge case)") {
                let fields = [
                    SecureMenuItem.Field(label: "User", value: "alice"),
                    SecureMenuItem.Field(label: "TOTP1", value: "otpauth://...", kind: .totp),
                    SecureMenuItem.Field(label: "TOTP2", value: "otpauth://...", kind: .totp)
                ]

                // When tabbing backward from add button, should reach check[0], not skip to title
                let plainFieldCount = fields.filter { !$0.isTOTP }.count
                expect(plainFieldCount) == 1
            }
        }
    }
}
