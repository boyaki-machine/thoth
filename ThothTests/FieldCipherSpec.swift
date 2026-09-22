import Foundation
import CryptoKit
import Quick
import Nimble
@testable import Thoth

// 保存層の項目暗号化（FieldCipher）。
//
// 導出した鍵・内容キー・暗号文の形式は、保存済みのデータを読めるかどうかに直結する。
// 固定値は Swift の実装とは独立に計算したもの（HKDF / HMAC は Python の hmac で
// RFC 5869 どおりに、AES-GCM は Ruby の OpenSSL で）を使い、
// 「実装が自分自身と一致する」だけのテストにしない。
class FieldCipherSpec: QuickSpec {

    // MARK: - Fixtures

    /// テスト用の導出元の鍵（0x01…0x20）
    static let rootKey = Data((1...32).map { UInt8($0) })
    static let context = FieldCipher.Context(entity: "StoredSnippet", id: "s1", field: "payload")

    static func hex(_ string: String) -> Data {
        var data = Data()
        var index = string.startIndex
        while index < string.endIndex {
            let next = string.index(index, offsetBy: 2)
            data.append(UInt8(string[index..<next], radix: 16)!)
            index = next
        }
        return data
    }

    static func bytes(of key: SymmetricKey) -> Data {
        return key.withUnsafeBytes { Data($0) }
    }

    static func makeCipher() -> FieldCipher {
        guard let cipher = FieldCipher(rootKey: rootKey) else {
            fatalError("32 バイトの鍵で FieldCipher が作れない（前提が崩れている）")
        }
        return cipher
    }

    override class func spec() {
        derivationSpecs()
        formatSpecs()
        roundTripSpecs()
        tamperSpecs()
        jsonSpecs()
    }

    // MARK: - Derivation

    private static func derivationSpecs() {
        describe("鍵の導出（変えると保存済みのデータが読めなくなる）") {
            it("暗号化用の鍵は、HKDF-SHA256 の独立計算と一致する") {
                let key = FieldCipher.derive(from: SymmetricKey(data: rootKey), info: FieldCipher.sealKeyInfo)
                expect(bytes(of: key)) == hex("161e1f19675f39f1f66329547fe347b302cfefc1c599d79b9c5be0b5df7acbca")
            }

            it("内容キー用の鍵は、HKDF-SHA256 の独立計算と一致する") {
                let key = FieldCipher.derive(from: SymmetricKey(data: rootKey), info: FieldCipher.contentKeyInfo)
                expect(bytes(of: key)) == hex("32c27bf51695678d43653d432067a07e8260a1da259ebac67d6042ebbd6215c4")
            }

            it("内容キーは HMAC-SHA256 の独立計算と一致し、同じ内容なら同じ値になる") {
                let cipher = makeCipher()
                expect(cipher.contentID(for: "12345")) == "3b34df076351a0e3b4ff7d7b8954e771e1bd2037adca7a6ba001ff851f3c36b4"
                expect(cipher.contentID(for: "-98765")) == "4a794086c769087b6b8bced460e2c8b361b95bdfefa28c5436b655ef6a9be6aa"
                expect(cipher.contentID(for: "12345")) == cipher.contentID(for: "12345")
            }

            it("導出元の鍵が 32 バイトでなければ作れない") {
                expect(FieldCipher(rootKey: Data(count: 31))) == nil
                expect(FieldCipher(rootKey: Data(count: 64))) == nil
            }
        }
    }

    // MARK: - Format

    private static func formatSpecs() {
        describe("暗号文の形式") {
            // "TSF" + 0x01 + nonce(a0…ab) + 暗号文 + タグ。Ruby の OpenSSL で作った値
            let pinned = hex("54534601a0a1a2a3a4a5a6a7a8a9aaab8e86f469808d40dbf01ee51bd49a3e872eb6bfc1497b842de6ea88d2330df5e2e0f8563ba940544649c4bb0a")
            let plain = Data("スニペット本文 😀\r\n".utf8)

            it("nonce を固定すると、OpenSSL で作った暗号文とバイト単位で一致する") {
                let nonce = try? AES.GCM.Nonce(data: Data((0..<12).map { UInt8(0xA0 + $0) }))
                let sealed = try? makeCipher().seal(plain, context: context, nonce: nonce)
                expect(sealed) == pinned
            }

            it("OpenSSL で作った暗号文を復号できる") {
                expect(makeCipher().open(pinned, context: context)) == plain
            }
        }
    }

    // MARK: - Round Trip

    private static func roundTripSpecs() {
        describe("暗号化と復号") {
            it("暗号化して復号すると元に戻る（空・絵文字・改行・1 万文字・大きなデータ）") {
                let cipher = makeCipher()
                let samples: [(String, Data)] = [
                    ("空", Data()),
                    ("絵文字と CRLF", Data("👨‍👩‍👧‍👦 家族\r\n全角　スペース".utf8)),
                    ("1 万文字", Data(String(repeating: "あ", count: 10_000).utf8)),
                    ("1MB", Data((0..<1_000_000).map { UInt8($0 % 251) }))
                ]
                for (name, sample) in samples {
                    let sealed = try? cipher.seal(sample, context: context)
                    expect(sealed.flatMap { cipher.open($0, context: context) }).to(equal(sample), description: name)
                }
            }

            it("同じ平文でも、暗号化のたびに暗号文が変わる（nonce が毎回違う）") {
                let cipher = makeCipher()
                let plain = Data("same".utf8)
                let first = try? cipher.seal(plain, context: context)
                let second = try? cipher.seal(plain, context: context)
                expect(first) != nil
                expect(first) != second
            }

            it("暗号文に平文がそのまま現れない") {
                let marker = "PLAINTEXT-MARKER-0123456789"
                let sealed = (try? makeCipher().seal(Data(marker.utf8), context: context)) ?? Data()
                expect(sealed.range(of: Data(marker.utf8))) == nil
            }
        }
    }

    // MARK: - Tamper

    private static func tamperSpecs() {
        describe("改ざん・取り違えの検出") {
            let plain = Data("secret snippet".utf8)

            it("暗号文のどこを 1 ビット変えても復号できない（nonce・暗号文・タグ）") {
                let cipher = makeCipher()
                guard let sealed = try? cipher.seal(plain, context: context) else {
                    fail("暗号化できない（前提が崩れている）")
                    return
                }
                let positions = [FieldCipher.headerLength,                  // nonce の先頭
                                 FieldCipher.headerLength + 12,             // 暗号文の先頭
                                 sealed.count - 1]                          // タグの末尾
                for position in positions {
                    var broken = sealed
                    broken[position] ^= 0x01
                    expect(cipher.open(broken, context: context)).to(beNil(), description: "位置 \(position)")
                }
            }

            it("別の行・別の項目・別のモデルの暗号文として開くと復号できない") {
                let cipher = makeCipher()
                guard let sealed = try? cipher.seal(plain, context: context) else {
                    fail("暗号化できない（前提が崩れている）")
                    return
                }
                let others = [
                    FieldCipher.Context(entity: "StoredSnippet", id: "s2", field: "payload"),
                    FieldCipher.Context(entity: "StoredSnippet", id: "s1", field: "thumbnail"),
                    FieldCipher.Context(entity: "StoredFolder", id: "s1", field: "payload")
                ]
                for other in others {
                    expect(cipher.open(sealed, context: other)).to(beNil(), description: "\(other)")
                }
                expect(cipher.open(sealed, context: context)) == plain
            }

            it("別の鍵では復号できない") {
                guard let sealed = try? makeCipher().seal(plain, context: context),
                      let otherCipher = FieldCipher(rootKey: Data(repeating: 0x7F, count: 32)) else {
                    fail("暗号化できない（前提が崩れている）")
                    return
                }
                expect(otherCipher.open(sealed, context: context)) == nil
            }

            it("目印・形式版が違うもの、短すぎるものは復号しない") {
                let cipher = makeCipher()
                guard let sealed = try? cipher.seal(plain, context: context) else {
                    fail("暗号化できない（前提が崩れている）")
                    return
                }
                var wrongMagic = sealed
                wrongMagic[0] = UInt8(ascii: "X")
                var wrongVersion = sealed
                wrongVersion[3] = 0x02
                let cases: [(String, Data)] = [("目印違い", wrongMagic), ("形式版違い", wrongVersion),
                                               ("ヘッダーだけ", sealed.prefix(FieldCipher.headerLength)),
                                               ("空", Data()), ("平文", plain)]
                for (name, data) in cases {
                    expect(cipher.open(data, context: context)).to(beNil(), description: name)
                }
            }
        }
    }

    // MARK: - JSON

    private static func jsonSpecs() {
        describe("値の暗号化（JSON）") {
            struct Payload: Codable, Equatable {
                var version: Int
                var title: String
            }

            it("値を暗号化して復号すると元に戻る") {
                let cipher = makeCipher()
                let payload = Payload(version: 1, title: "タイトル 😀")
                let sealed = try? cipher.sealJSON(payload, context: context)
                expect(sealed.flatMap { cipher.openJSON(Payload.self, from: $0, context: context) }) == payload
            }

            it("中身が期待した型として解釈できなければ nil を返す") {
                let cipher = makeCipher()
                let sealed = try? cipher.sealJSON(["unexpected": true], context: context)
                expect(sealed.flatMap { cipher.openJSON(Payload.self, from: $0, context: context) }) == nil
            }
        }
    }
}
