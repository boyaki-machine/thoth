//
//  TOTPService.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Copyright © 2015-2018 Clipy Project.
//

import Foundation
import CommonCrypto

// MARK: - TOTPParameters

/// RFC 6238 の TOTP 生成に必要なパラメータ一式。
/// `otpauth://` URI または生の Base32 secret から生成する。
struct TOTPParameters: Equatable {

    enum Algorithm: String {
        case sha1   = "SHA1"
        case sha256 = "SHA256"
        case sha512 = "SHA512"

        var ccAlgorithm: CCHmacAlgorithm {
            switch self {
            case .sha1:   return CCHmacAlgorithm(kCCHmacAlgSHA1)
            case .sha256: return CCHmacAlgorithm(kCCHmacAlgSHA256)
            case .sha512: return CCHmacAlgorithm(kCCHmacAlgSHA512)
            }
        }

        var digestLength: Int {
            switch self {
            case .sha1:   return Int(CC_SHA1_DIGEST_LENGTH)
            case .sha256: return Int(CC_SHA256_DIGEST_LENGTH)
            case .sha512: return Int(CC_SHA512_DIGEST_LENGTH)
            }
        }
    }

    /// Base32 デコード済みの共有鍵
    let secret: Data
    /// 出力桁数（通常 6）
    let digits: Int
    /// タイムステップ秒数（通常 30）
    let period: Int
    let algorithm: Algorithm
    /// 表示用（サービス名 / アカウント名）。QR から取れた場合のみ入る
    let issuer: String?
    let account: String?

    static let defaultDigits = 6
    static let defaultPeriod = 30
}

// MARK: - TOTPService

/// TOTP（時間ベースのワンタイムパスワード）の生成と、`otpauth://` / Base32 secret のパースを行う。
/// HMAC は CommonCrypto の `CCHmac` を用いる（CryptoKit は macOS 10.15+ で本アプリの 10.13 対応では使えないため）。
final class TOTPService {

    // MARK: - Parse

    /// `otpauth://totp/...` URI または生の Base32 secret 文字列を解釈して `TOTPParameters` を返す。
    /// パースできない場合は nil。
    static func parse(_ rawInput: String) -> TOTPParameters? {
        let input = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return nil }

        if input.lowercased().hasPrefix("otpauth://") {
            return parseURI(input)
        }
        // 生の Base32 secret とみなす（デフォルトパラメータ）
        guard let secret = base32Decode(input), !secret.isEmpty else { return nil }
        return TOTPParameters(secret: secret,
                              digits: TOTPParameters.defaultDigits,
                              period: TOTPParameters.defaultPeriod,
                              algorithm: .sha1,
                              issuer: nil,
                              account: nil)
    }

    /// 入力が TOTP として解釈可能かどうか（登録フローのバリデーション用）
    static func isValid(_ rawInput: String) -> Bool {
        return parse(rawInput) != nil
    }

    private static func parseURI(_ uri: String) -> TOTPParameters? {
        guard let components = URLComponents(string: uri),
              components.host?.lowercased() == "totp" else { return nil }
        let queryItems = components.queryItems ?? []
        func value(_ name: String) -> String? {
            return queryItems.first { $0.name.lowercased() == name }?.value
        }
        guard let secretString = value("secret"),
              let secret = base32Decode(secretString), !secret.isEmpty else { return nil }

        let digits = value("digits").flatMap { Int($0) } ?? TOTPParameters.defaultDigits
        let period = value("period").flatMap { Int($0) } ?? TOTPParameters.defaultPeriod
        let algorithm = value("algorithm").flatMap { TOTPParameters.Algorithm(rawValue: $0.uppercased()) } ?? .sha1

        // ラベルは "Issuer:Account" 形式のことがある。issuer クエリを優先する
        let label = components.path.hasPrefix("/") ? String(components.path.dropFirst()) : components.path
        let decodedLabel = label.removingPercentEncoding ?? label
        var issuer = value("issuer")
        var account: String? = decodedLabel.isEmpty ? nil : decodedLabel
        if let colonIndex = decodedLabel.firstIndex(of: ":") {
            if issuer == nil { issuer = String(decodedLabel[decodedLabel.startIndex..<colonIndex]) }
            account = String(decodedLabel[decodedLabel.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
        }

        return TOTPParameters(secret: secret,
                              digits: max(1, min(digits, 10)),
                              period: max(1, period),
                              algorithm: algorithm,
                              issuer: issuer,
                              account: account)
    }

    // MARK: - Code Generation

    /// 指定時刻におけるワンタイムコードを生成する（ゼロ埋め済み文字列）。
    func code(for params: TOTPParameters, at date: Date = Date()) -> String? {
        let counter = UInt64(floor(date.timeIntervalSince1970 / Double(params.period)))
        return code(secret: params.secret, counter: counter, digits: params.digits, algorithm: params.algorithm)
    }

    /// 次のコード更新までの残り秒数（1...period）。
    func remainingSeconds(for params: TOTPParameters, at date: Date = Date()) -> Int {
        let elapsed = Int(floor(date.timeIntervalSince1970)) % params.period
        return params.period - elapsed
    }

    /// HOTP（RFC 4226）ベースのコード計算。TOTP はカウンタに時刻ステップを渡す。
    private func code(secret: Data, counter: UInt64, digits: Int, algorithm: TOTPParameters.Algorithm) -> String? {
        // カウンタを 8 バイトのビッグエンディアンに変換
        var bigEndianCounter = counter.bigEndian
        let counterData = Data(bytes: &bigEndianCounter, count: MemoryLayout<UInt64>.size)

        var hmac = [UInt8](repeating: 0, count: algorithm.digestLength)
        secret.withUnsafeBytes { keyBytes in
            counterData.withUnsafeBytes { msgBytes in
                CCHmac(algorithm.ccAlgorithm,
                       keyBytes.baseAddress, secret.count,
                       msgBytes.baseAddress, counterData.count,
                       &hmac)
            }
        }

        // 動的トランケーション（RFC 4226 §5.3）
        let offset = Int(hmac[hmac.count - 1] & 0x0f)
        guard offset + 3 < hmac.count else { return nil }
        let binary = (UInt32(hmac[offset] & 0x7f) << 24)
                   | (UInt32(hmac[offset + 1]) << 16)
                   | (UInt32(hmac[offset + 2]) << 8)
                   | (UInt32(hmac[offset + 3]))

        let modulo = UInt32(pow(10.0, Double(digits)))
        let otp = binary % modulo
        return String(format: "%0\(digits)u", otp)
    }

    // MARK: - Base32 (RFC 4648)

    /// RFC 4648 の Base32 文字列をデコードする。大文字小文字・空白・パディング（=）を許容する。
    /// 不正な文字が含まれる場合、および末尾の残余ビットが RFC 4648 §6 に
    /// 違反する場合（あり得ない残余長・非ゼロの残余ビット）は nil。
    static func base32Decode(_ input: String) -> Data? {
        let alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
        var lookup = [Character: UInt8]()
        for (index, char) in alphabet.enumerated() { lookup[char] = UInt8(index) }

        let normalized = input.uppercased()
            .replacingOccurrences(of: "=", with: "")
            .filter { !$0.isWhitespace }
        guard !normalized.isEmpty else { return nil }

        var bits = 0
        var value = 0
        var output = [UInt8]()
        for char in normalized {
            guard let charValue = lookup[char] else { return nil }
            value = (value << 5) | Int(charValue)
            bits += 5
            if bits >= 8 {
                bits -= 8
                output.append(UInt8((value >> bits) & 0xff))
            }
        }
        // RFC 4648 の正規エンコード長（文字数 mod 8 = 0/2/4/5/7）では
        // 残余は最大 4 ビット。5 ビット以上残る文字数（mod 8 = 1/3/6）は
        // エンコード長として成立しないため不正入力として拒否する
        guard bits < 5 else { return nil }
        // 残余ビットはパディング分であり、正規エンコードでは必ずゼロ。
        // 非ゼロは秘密鍵の取り違え（1文字違いなど）を示唆するため拒否する
        guard value & ((1 << bits) - 1) == 0 else { return nil }
        return Data(output)
    }
}
