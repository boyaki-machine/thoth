//
//  PasswordGenerateService.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Copyright © 2015-2018 Clipy Project.
//

import Foundation

/// 指定条件に基づいてランダムなパスワードを生成するサービス。
/// 乱数は openssl コマンド（`openssl rand`）をバックグラウンド実行して取得する。
final class PasswordGenerateService {

    // MARK: - Conditions

    /// パスワード生成条件
    struct Conditions {
        /// 文字数
        var length: Int
        /// 半角英字 (a-z) を含める
        var useLetters: Bool
        /// 数字 (0-9) を含める
        var useDigits: Bool
        /// 記号を含める
        var useSymbols: Bool
        /// 大文字小文字を区別する（英字有効時に A-Z も含める）
        var distinguishCase: Bool
        /// 入力しやすいパスワード。
        /// 文字種ごとに 3〜4 文字のブロックを生成し、ランダムな順序で結合する。
        /// スマートフォン等での入力時に文字種の切り替え回数を最小化するための仕様。
        var easyToType: Bool = false

        /// 少なくとも 1 種類の文字種が有効か
        var hasAnyCharacterType: Bool {
            return useLetters || useDigits || useSymbols
        }
    }

    // MARK: - Constants

    static let minimumLength = 4
    static let maximumLength = 128

    private static let lowercaseLetters = "abcdefghijklmnopqrstuvwxyz"
    private static let uppercaseLetters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    private static let digits = "0123456789"
    /// 引用符・バックスラッシュ・空白を除いた記号
    static let symbols = "!#$%&()*+,-./:;<=>?@[]^_{|}~"

    // MARK: - Random Byte Stream

    /// openssl から取得した乱数バイト列を先頭から消費するストリーム
    private struct RandomByteStream {
        private let data: Data
        private var offset = 0

        init(data: Data) {
            self.data = data
        }

        mutating func next() -> UInt8? {
            guard offset < data.count else { return nil }
            defer { offset += 1 }
            return data[data.startIndex + offset]
        }

        /// 0..<upperBound の一様乱数を返す（256 % upperBound の剰余バイアスは棄却サンプリングで排除）
        mutating func next(below upperBound: Int) -> Int? {
            guard upperBound > 0, upperBound <= 256 else { return nil }
            let rejectionLimit = 256 - (256 % upperBound)
            while let byte = next() {
                let value = Int(byte)
                if value < rejectionLimit { return value % upperBound }
            }
            return nil
        }
    }

    // MARK: - Public Interface

    /// バックグラウンドでパスワードを生成し、メインスレッドで結果を返す。
    /// 生成に失敗した場合（openssl の実行失敗・条件不正など）は nil を返す。
    func generate(conditions: Conditions, completion: @escaping (String?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let password = self?.generatePassword(conditions: conditions)
            DispatchQueue.main.async { completion(password) }
        }
    }

    /// 同期的にパスワードを生成する（テスト用途および `generate(conditions:completion:)` の実体）
    func generatePassword(conditions: Conditions) -> String? {
        guard conditions.hasAnyCharacterType,
              conditions.length >= Self.minimumLength, conditions.length <= Self.maximumLength else { return nil }
        // 棄却サンプリング・シャッフルで消費する分を含めて余裕を持って乱数を取得する
        guard let randomBytes = generateRandomBytes(count: 256 + conditions.length * 8) else { return nil }
        var stream = RandomByteStream(data: randomBytes)

        if conditions.easyToType {
            return generateEasyToTypePassword(conditions: conditions, stream: &stream)
        }
        return generateStandardPassword(conditions: conditions, stream: &stream)
    }

    // MARK: - Generation Strategies

    /// 全文字種を混在させた通常のパスワードを生成する
    private func generateStandardPassword(conditions: Conditions, stream: inout RandomByteStream) -> String? {
        let characters = Array(characterGroups(for: conditions).joined())
        var passwordCharacters = [Character]()
        for _ in 0..<conditions.length {
            guard let index = stream.next(below: characters.count) else { return nil }
            passwordCharacters.append(characters[index])
        }
        return String(passwordCharacters)
    }

    /// 入力しやすいパスワードを生成する。
    /// 有効な文字種ごとに 3〜4 文字のブロックを生成し、文字種のランダムな順序で
    /// 指定の長さになるまで結合する（末尾に 1〜2 文字の端数が出る場合は直前のブロックに吸収する）。
    /// 例: 数字 4 文字 → 小文字英字 3 文字 → 記号 4 文字 → 大文字英字 3 文字 → ...
    private func generateEasyToTypePassword(conditions: Conditions, stream: inout RandomByteStream) -> String? {
        let groups = characterGroups(for: conditions)
        var passwordCharacters = [Character]()

        while passwordCharacters.count < conditions.length {
            // 各ラウンドで文字種の順序をランダムに並べ替える
            guard let shuffledGroups = shuffle(groups, stream: &stream) else { return nil }
            for group in shuffledGroups where passwordCharacters.count < conditions.length {
                let remaining = conditions.length - passwordCharacters.count
                guard let lengthChoice = stream.next(below: 2) else { return nil }
                var blockLength = 3 + lengthChoice
                // 残りが 1〜2 文字になる場合は同じ文字種に吸収する（ブロックは常に 3 文字以上）
                if remaining - blockLength < 3 {
                    blockLength = remaining
                }
                for _ in 0..<min(blockLength, remaining) {
                    guard let index = stream.next(below: group.count) else { return nil }
                    passwordCharacters.append(group[index])
                }
            }
        }
        return String(passwordCharacters)
    }

    // MARK: - Private Helpers

    /// 有効な文字種ごとの文字集合を返す（入力しやすいモードでは大文字と小文字も別ブロックとして扱う）
    private func characterGroups(for conditions: Conditions) -> [[Character]] {
        var groups = [[Character]]()
        if conditions.useLetters {
            groups.append(Array(Self.lowercaseLetters))
            if conditions.distinguishCase {
                groups.append(Array(Self.uppercaseLetters))
            }
        }
        if conditions.useDigits {
            groups.append(Array(Self.digits))
        }
        if conditions.useSymbols {
            groups.append(Array(Self.symbols))
        }
        return groups
    }

    /// Fisher-Yates で配列をシャッフルする（乱数はストリームから消費）
    private func shuffle(_ groups: [[Character]], stream: inout RandomByteStream) -> [[Character]]? {
        var result = groups
        guard result.count > 1 else { return result }
        for index in stride(from: result.count - 1, through: 1, by: -1) {
            guard let randomIndex = stream.next(below: index + 1) else { return nil }
            result.swapAt(index, randomIndex)
        }
        return result
    }

    /// openssl コマンドで乱数バイト列を取得する
    private func generateRandomBytes(count: Int) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
        process.arguments = ["rand", String(count)]
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            NSLog("[PasswordGenerateService] failed to run openssl: \(error)")
            return nil
        }
        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, data.count >= count else {
            NSLog("[PasswordGenerateService] openssl rand failed (status \(process.terminationStatus))")
            return nil
        }
        return data
    }
}
