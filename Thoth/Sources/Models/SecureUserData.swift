//
//  SecureUserData.swift
//
//  Thoth
//
//  セキュアアイテムの保存形式（キーチェーンの user-data エントリの中身）
//

import Foundation

/// 「ユーザー自身が設定する機微情報」の集合。Keychain の 1 エントリ（account: user-data）に
/// JSON で集約して保存する。エクスポート／インポートの対象はこの単位。
///
/// 対になる概念として「アプリが動作のために自動生成する情報」（DB 暗号鍵等）があり、
/// そちらは環境固有のため RealmProvider の app-keys エントリで別管理される
/// （エクスポート対象外・インストールごとに生成）。
struct SecureUserData: Codable {
    /// スキーマバージョン（将来の形式変更用）
    var version: Int
    /// セキュアアイテム全件
    var items: [SecureMenuItem]
    /// ファイル暗号化の指紋パスワード（未登録なら nil）
    var cryptoPassword: String?

    init(version: Int = SecureUserData.currentVersion, items: [SecureMenuItem] = [], cryptoPassword: String? = nil) {
        self.version = version
        self.items = items
        self.cryptoPassword = cryptoPassword
    }

    /// 現在のスキーマバージョン
    static let currentVersion = 2

    // キーが欠けていても読めるように寛容にデコードする（前方互換）
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? SecureUserData.currentVersion
        items = try container.decodeIfPresent([SecureMenuItem].self, forKey: .items) ?? []
        cryptoPassword = try container.decodeIfPresent(String.self, forKey: .cryptoPassword)
    }
}
