//
//  FieldCipher.swift
//
//  Thoth
//  GitHub: https://github.com/boyaki-machine/Thoth
//

import Foundation
import CryptoKit

/// 保存層の項目暗号化（AES-256-GCM・付加データ付き）と、内容キー（HMAC）の計算。
///
/// SwiftData（中身は SQLite）には保存時暗号化の機能が無いため、表示用の中身は
/// この型で暗号化してから保存する。
///
/// ## 鍵
/// キーチェーンに新しい鍵は作らず、既存の `.data` 用の鍵（app-keys の
/// `clipDataEncryptionKey`、32 バイト）から HKDF-SHA256 で用途ごとに導出する。
/// **導出の定数（salt・info）を変えると保存済みのデータがすべて読めなくなる。**
/// 固定値のテスト（FieldCipherSpec）で押さえてあるので、変えるときは移行を用意すること。
///
/// ## 形式
/// `"TSF"(3B) + 形式版 0x01(1B) + AES-GCM combined（nonce 12B + 暗号文 + タグ 16B）`
///
/// ## 付加データ（AAD）
/// `"Thoth.store/v1|<モデル名>|<id>|<項目名>"`。暗号文を別の行・別の項目へ
/// 差し替えられても、復号に失敗して気づける。
struct FieldCipher {

    /// どの行のどの項目を暗号化したか（付加データになる）
    struct Context: Equatable {
        let entity: String
        let id: String
        let field: String

        var authenticatedData: Data {
            return Data("Thoth.store/v1|\(entity)|\(id)|\(field)".utf8)
        }
    }

    // MARK: - Constants

    static let magic = Data("TSF".utf8)
    static let formatVersion: UInt8 = 1
    static let headerLength = 4
    /// 導出元の鍵の長さ（`.data` 用の鍵と同じ）
    static let rootKeyLength = 32

    static let derivationSalt = Data("io.github.boyaki-machine.Thoth.store".utf8)
    static let sealKeyInfo = Data("io.github.boyaki-machine.Thoth.store.seal.v1".utf8)
    static let contentKeyInfo = Data("io.github.boyaki-machine.Thoth.store.content-key.v1".utf8)

    // MARK: - Properties

    private let sealKey: SymmetricKey
    private let contentKey: SymmetricKey

    // MARK: - Initialize

    /// - Parameter rootKey: `.data` 用の鍵（32 バイト）。長さが違えば nil
    init?(rootKey: Data) {
        guard rootKey.count == Self.rootKeyLength else { return nil }
        let root = SymmetricKey(data: rootKey)
        sealKey = Self.derive(from: root, info: Self.sealKeyInfo)
        contentKey = Self.derive(from: root, info: Self.contentKeyInfo)
    }

    static func derive(from root: SymmetricKey, info: Data) -> SymmetricKey {
        return HKDF<SHA256>.deriveKey(inputKeyMaterial: root, salt: derivationSalt, info: info, outputByteCount: 32)
    }

    // MARK: - Seal / Open

    /// 暗号化する。nonce は通常は毎回乱数（テストで形式を固定するときだけ指定する）
    func seal(_ plaintext: Data, context: Context, nonce: AES.GCM.Nonce? = nil) throws -> Data {
        let box = try AES.GCM.seal(plaintext, using: sealKey, nonce: nonce ?? AES.GCM.Nonce(),
                                   authenticating: context.authenticatedData)
        guard let combined = box.combined else { throw CryptoKitError.incorrectParameterSize }
        var sealed = Self.magic
        sealed.append(Self.formatVersion)
        sealed.append(combined)
        return sealed
    }

    /// 復号する。形式違い・鍵違い・改ざん・付加データ違い（別の行・項目の暗号文）なら nil
    func open(_ sealed: Data, context: Context) -> Data? {
        guard sealed.count > Self.headerLength,
              sealed.starts(with: Self.magic),
              sealed[sealed.startIndex + Self.magic.count] == Self.formatVersion else { return nil }
        let combined = sealed.subdata(in: (sealed.startIndex + Self.headerLength)..<sealed.endIndex)
        guard let box = try? AES.GCM.SealedBox(combined: combined) else { return nil }
        return try? AES.GCM.open(box, using: sealKey, authenticating: context.authenticatedData)
    }

    /// 値を JSON にして暗号化する
    func sealJSON<T: Encodable>(_ value: T, context: Context) throws -> Data {
        return try seal(JSONEncoder().encode(value), context: context)
    }

    /// 復号して JSON から値に戻す。復号・解釈のどちらかに失敗すれば nil
    func openJSON<T: Decodable>(_ type: T.Type, from sealed: Data, context: Context) -> T? {
        guard let plain = open(sealed, context: context) else { return nil }
        return try? JSONDecoder().decode(type, from: plain)
    }

    // MARK: - Content Key

    /// 内容から決まる識別子（`dataHash`）を、平文で置いても手掛かりにならない値に変える。
    /// 同じ内容なら同じ値になる（「同じ内容を上書き」の判定に使える）
    /// - Returns: HMAC-SHA256 の 16 進表記（64 文字）
    func contentID(for dataHash: String) -> String {
        let mac = HMAC<SHA256>.authenticationCode(for: Data(dataHash.utf8), using: contentKey)
        return mac.map { String(format: "%02x", $0) }.joined()
    }
}
