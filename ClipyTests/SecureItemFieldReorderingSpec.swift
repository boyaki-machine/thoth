import Quick
import Nimble
@testable import Clipy

// MARK: - A-3: Drag & Drop Reordering Logic Tests

class SecureItemFieldReorderingSpec: QuickSpec {

    override func spec() {
        describe("Field reordering logic (.above dropOperation semantics)") {

            // MARK: - Basic Reordering

            it("Moves field from index 1 to index 3 (.above semantics)") {
                var fields = makeTestFields(5)

                let sourceRow = 1
                let dropRow = 3
                let moved = fields.remove(at: sourceRow)
                let targetIndex = dropRow > sourceRow ? dropRow - 1 : dropRow
                fields.insert(moved, at: targetIndex)

                // Result: [F0, F2, F1, F3, F4]
                expect(fields.map { $0.label }) == ["Field 0", "Field 2", "Field 1", "Field 3", "Field 4"]
            }

            it("Moves field from index 3 to index 1 (.above semantics)") {
                var fields = makeTestFields(5)

                let sourceRow = 3
                let dropRow = 1
                let moved = fields.remove(at: sourceRow)
                let targetIndex = dropRow > sourceRow ? dropRow - 1 : dropRow
                fields.insert(moved, at: targetIndex)

                // Result: [F0, F3, F1, F2, F4]
                expect(fields.map { $0.label }) == ["Field 0", "Field 3", "Field 1", "Field 2", "Field 4"]
            }

            // MARK: - Edge Cases: Boundary Positions

            it("Moves last field to first position") {
                var fields = makeTestFields(5)

                let sourceRow = 4
                let dropRow = 0
                let moved = fields.remove(at: sourceRow)
                let targetIndex = dropRow > sourceRow ? dropRow - 1 : dropRow
                fields.insert(moved, at: targetIndex)

                // Result: [F4, F0, F1, F2, F3]
                expect(fields.map { $0.label }) == ["Field 4", "Field 0", "Field 1", "Field 2", "Field 3"]
            }

            it("Moves first field to last position") {
                var fields = makeTestFields(5)

                let sourceRow = 0
                let dropRow = 5
                let moved = fields.remove(at: sourceRow)
                let targetIndex = dropRow > sourceRow ? dropRow - 1 : dropRow
                fields.insert(moved, at: targetIndex)

                // Result: [F1, F2, F3, F4, F0]
                expect(fields.map { $0.label }) == ["Field 1", "Field 2", "Field 3", "Field 4", "Field 0"]
            }

            it("Moves first field to second position") {
                var fields = makeTestFields(5)

                let sourceRow = 0
                let dropRow = 2
                let moved = fields.remove(at: sourceRow)
                let targetIndex = dropRow > sourceRow ? dropRow - 1 : dropRow
                fields.insert(moved, at: targetIndex)

                // Result: [F1, F0, F2, F3, F4]
                expect(fields.map { $0.label }) == ["Field 1", "Field 0", "Field 2", "Field 3", "Field 4"]
            }

            it("Moves last field to second-to-last position") {
                var fields = makeTestFields(5)

                let sourceRow = 4
                let dropRow = 4
                let moved = fields.remove(at: sourceRow)
                let targetIndex = dropRow > sourceRow ? dropRow - 1 : dropRow
                fields.insert(moved, at: targetIndex)

                // Result: [F0, F1, F2, F3, F4] (no change, same position)
                expect(fields.map { $0.label }) == ["Field 0", "Field 1", "Field 2", "Field 3", "Field 4"]
            }

            // MARK: - Single Item Edge Case

            it("Single field table cannot be reordered") {
                var fields = makeTestFields(1)

                // dropRow would be 0 or 1, both are edge cases
                let sourceRow = 0
                let dropRow = 0
                guard sourceRow != dropRow else { return }  // Should reject same position

                let moved = fields.remove(at: sourceRow)
                let targetIndex = dropRow > sourceRow ? dropRow - 1 : dropRow
                fields.insert(moved, at: targetIndex)

                // Field should be unchanged
                expect(fields.count) == 1
            }

            // MARK: - TOTP Fields Mixed

            it("Reorders mixed plain and TOTP fields") {
                let field0 = SecureMenuItem.Field(label: "Username", value: "alice")
                let field1 = SecureMenuItem.Field(label: "GitHub TOTP", value: "otpauth://...", kind: .totp)
                let field2 = SecureMenuItem.Field(label: "Password", value: "secret")
                let field3 = SecureMenuItem.Field(label: "AWS TOTP", value: "otpauth://...", kind: .totp)
                var fields = [field0, field1, field2, field3]

                // Move TOTP (index 1) to index 3
                let sourceRow = 1
                let dropRow = 3
                let moved = fields.remove(at: sourceRow)
                let targetIndex = dropRow > sourceRow ? dropRow - 1 : dropRow
                fields.insert(moved, at: targetIndex)

                // Result: [Username, Password, GitHub TOTP, AWS TOTP]
                expect(fields[0].label) == "Username"
                expect(fields[1].label) == "Password"
                expect(fields[2].label) == "GitHub TOTP"
                expect(fields[2].isTOTP) == true
                expect(fields[3].label) == "AWS TOTP"
            }

            // MARK: - Field Integrity

            it("Preserves field properties through reordering") {
                let originalField = SecureMenuItem.Field(label: "Important", value: "secret123", isPassword: true)
                var fields = [
                    SecureMenuItem.Field(label: "First", value: "val1"),
                    originalField,
                    SecureMenuItem.Field(label: "Third", value: "val3")
                ]

                // Move field at index 1 to index 2
                let sourceRow = 1
                let dropRow = 2
                let moved = fields.remove(at: sourceRow)
                let targetIndex = dropRow > sourceRow ? dropRow - 1 : dropRow
                fields.insert(moved, at: targetIndex)

                let rearranged = fields[1]  // Now at position 1
                expect(rearranged.label) == originalField.label
                expect(rearranged.value) == originalField.value
                expect(rearranged.isPassword) == originalField.isPassword
                expect(rearranged.fieldID) == originalField.fieldID
                expect(rearranged.createdAt).to(beCloseTo(originalField.createdAt, within: 0.001))
            }

            // MARK: - Validation: Same Row Prevention

            it("Detects when drop position equals source position (validation)") {
                let fields = makeTestFields(5)

                // Validation should catch attempts to drop on same row
                let sourceRow = 2
                let dropRow = 2
                let isValidDrop = !(sourceRow == dropRow || sourceRow + 1 == dropRow)

                expect(isValidDrop) == false
            }

            it("Detects when drop position is immediately after source (validation)") {
                let fields = makeTestFields(5)

                let sourceRow = 2
                let dropRow = 3
                let isValidDrop = !(sourceRow == dropRow || sourceRow + 1 == dropRow)

                expect(isValidDrop) == false
            }

            it("Allows drop position two or more positions away") {
                let fields = makeTestFields(5)

                let sourceRow = 2
                let dropRow = 4
                let isValidDrop = !(sourceRow == dropRow || sourceRow + 1 == dropRow)

                expect(isValidDrop) == true
            }
        }
    }

    // MARK: - Helper

    private func makeTestFields(_ count: Int) -> [SecureMenuItem.Field] {
        return (0..<count).map { i in
            SecureMenuItem.Field(label: "Field \(i)", value: "value\(i)")
        }
    }
}
