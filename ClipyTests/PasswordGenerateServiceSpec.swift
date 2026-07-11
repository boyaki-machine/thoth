import Quick
import Nimble
@testable import Clipy

class PasswordGenerateServiceSpec: QuickSpec {

    private let service = PasswordGenerateService()

    override func spec() {
        generationSpecs()
        characterTypeSpecs()
        easyToTypeSpecs()
        invalidConditionSpecs()
    }

    private func makeConditions(length: Int = 16,
                                useLetters: Bool = true,
                                useDigits: Bool = true,
                                useSymbols: Bool = false,
                                distinguishCase: Bool = true,
                                easyToType: Bool = false) -> PasswordGenerateService.Conditions {
        return PasswordGenerateService.Conditions(length: length,
                                                  useLetters: useLetters,
                                                  useDigits: useDigits,
                                                  useSymbols: useSymbols,
                                                  distinguishCase: distinguishCase,
                                                  easyToType: easyToType)
    }

    /// 文字を文字種（小文字/大文字/数字/記号）に分類する
    private func characterType(of character: Character) -> String {
        if character.isLowercase { return "lower" }
        if character.isUppercase { return "upper" }
        if character.isNumber { return "digit" }
        return "symbol"
    }

    /// 同じ文字種が連続する「ブロック」の長さの一覧を返す
    private func blockLengths(of password: String) -> [Int] {
        var lengths = [Int]()
        var currentType = ""
        for character in password {
            let type = self.characterType(of: character)
            if type == currentType, !lengths.isEmpty {
                lengths[lengths.count - 1] += 1
            } else {
                lengths.append(1)
                currentType = type
            }
        }
        return lengths
    }

    private func generationSpecs() {
        describe("Generate password") {

            it("Generates the requested length") {
                for length in [PasswordGenerateService.minimumLength, 16, 64, PasswordGenerateService.maximumLength] {
                    let password = self.service.generatePassword(conditions: self.makeConditions(length: length))
                    expect(password?.count) == length
                }
            }

            it("Generates a different password every time") {
                let conditions = self.makeConditions(length: 32)
                let first = self.service.generatePassword(conditions: conditions)
                let second = self.service.generatePassword(conditions: conditions)
                expect(first) != nil
                expect(second) != nil
                expect(first) != second
            }
        }
    }

    private func characterTypeSpecs() {
        describe("Character types") {

            it("Digits only") {
                let conditions = self.makeConditions(length: 64, useLetters: false, useDigits: true, useSymbols: false)
                let password = self.service.generatePassword(conditions: conditions) ?? ""
                let digits = CharacterSet(charactersIn: "0123456789")
                expect(password.unicodeScalars.allSatisfy { digits.contains($0) }) == true
            }

            it("Lowercase letters only when case is not distinguished") {
                let conditions = self.makeConditions(length: 64, useLetters: true, useDigits: false,
                                                     useSymbols: false, distinguishCase: false)
                let password = self.service.generatePassword(conditions: conditions) ?? ""
                let lowercase = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz")
                expect(password.unicodeScalars.allSatisfy { lowercase.contains($0) }) == true
            }

            it("Contains uppercase letters when case is distinguished") {
                // 64 文字全てが小文字になる確率は (1/2)^64 で無視できる
                let conditions = self.makeConditions(length: 64, useLetters: true, useDigits: false,
                                                     useSymbols: false, distinguishCase: true)
                let password = self.service.generatePassword(conditions: conditions) ?? ""
                let letters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
                expect(password.unicodeScalars.allSatisfy { letters.contains($0) }) == true
                expect(password.contains { $0.isUppercase }) == true
                expect(password.contains { $0.isLowercase }) == true
            }

            it("Symbols only") {
                let conditions = self.makeConditions(length: 64, useLetters: false, useDigits: false, useSymbols: true)
                let password = self.service.generatePassword(conditions: conditions) ?? ""
                let symbols = CharacterSet(charactersIn: PasswordGenerateService.symbols)
                expect(password.count) == 64
                expect(password.unicodeScalars.allSatisfy { symbols.contains($0) }) == true
            }

            it("All types produce characters only from the allowed set") {
                let conditions = self.makeConditions(length: 128, useLetters: true, useDigits: true,
                                                     useSymbols: true, distinguishCase: true)
                let password = self.service.generatePassword(conditions: conditions) ?? ""
                let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789" + PasswordGenerateService.symbols)
                expect(password.count) == 128
                expect(password.unicodeScalars.allSatisfy { allowed.contains($0) }) == true
            }
        }
    }

    private func easyToTypeSpecs() {
        describe("Easy to type password") {

            it("Generates the requested length") {
                for length in [PasswordGenerateService.minimumLength, 15, 16, 17, 64, PasswordGenerateService.maximumLength] {
                    let conditions = self.makeConditions(length: length, useSymbols: true, easyToType: true)
                    let password = self.service.generatePassword(conditions: conditions)
                    expect(password?.count) == length
                }
            }

            it("Groups characters into blocks of at least 3 per character type") {
                // 全文字種有効・大文字小文字区別あり → 小文字/大文字/数字/記号の 4 ブロック種
                for length in [12, 16, 23, 64] {
                    let conditions = self.makeConditions(length: length, useSymbols: true, easyToType: true)
                    let password = self.service.generatePassword(conditions: conditions) ?? ""
                    // 同じ文字種のまとまり（ブロック）は常に 3 文字以上
                    // （文字種切り替えコストを最小化する仕様）
                    expect(self.blockLengths(of: password).allSatisfy { $0 >= 3 }) == true
                }
            }

            it("Uses only characters from the allowed set") {
                let conditions = self.makeConditions(length: 64, useSymbols: true, easyToType: true)
                let password = self.service.generatePassword(conditions: conditions) ?? ""
                let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789" + PasswordGenerateService.symbols)
                expect(password.unicodeScalars.allSatisfy { allowed.contains($0) }) == true
            }

            it("Works with a single character type") {
                let conditions = self.makeConditions(length: 16, useLetters: false, useDigits: true,
                                                     useSymbols: false, easyToType: true)
                let password = self.service.generatePassword(conditions: conditions) ?? ""
                let digits = CharacterSet(charactersIn: "0123456789")
                expect(password.count) == 16
                expect(password.unicodeScalars.allSatisfy { digits.contains($0) }) == true
            }
        }
    }

    private func invalidConditionSpecs() {
        describe("Invalid conditions") {

            it("Returns nil when no character type is enabled") {
                let conditions = self.makeConditions(useLetters: false, useDigits: false, useSymbols: false)
                expect(conditions.hasAnyCharacterType) == false
                expect(self.service.generatePassword(conditions: conditions)) == nil
            }

            it("Returns nil when length is out of range") {
                expect(self.service.generatePassword(conditions: self.makeConditions(length: PasswordGenerateService.minimumLength - 1))) == nil
                expect(self.service.generatePassword(conditions: self.makeConditions(length: PasswordGenerateService.maximumLength + 1))) == nil
                expect(self.service.generatePassword(conditions: self.makeConditions(length: 0))) == nil
            }
        }
    }
}
