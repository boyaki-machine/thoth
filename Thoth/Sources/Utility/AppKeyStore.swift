//
//  AppKeyStore.swift
//
//  Thoth（Clipy の RealmProvider から、鍵の管理だけを残したもの）
//
//  Copyright © 2015-2018 Clipy Project.
//

import Foundation
import Security

/// アプリが動作のために自動生成する鍵（app-keys）を、キーチェーンで管理する。
///
/// いま使っているのは、履歴の `.data` ファイルの暗号鍵（`.clipData`）だけで、保存層（SwiftData）の
/// 項目暗号化の鍵もここから導出する（FieldCipher）。**この鍵が読めないと、保存済みの履歴・スニペットは
/// 一切読めない**ので、キーチェーンのサービス名・アカウント名・JSON の形式は変えないこと。
///
/// v1.6.2 までは Realm の構成と暗号化もここ（RealmProvider）で扱っていた。v1.6.3 で Realm を外したので、
/// 鍵の管理だけを残した。app-keys の JSON には Realm の暗号鍵（`realmEncryptionKey`）も入っているが、
/// 読み書きのたびにそのまま保持する（旧版へ戻したときに app-keys を壊さないため）。
///
/// ## 署名との相互作用（重要）
/// Keychain 項目は作成したアプリの署名に紐づく。ad-hoc 署名のまま鍵を作成すると、
/// CodeSignService による再署名後に「別アプリ」と判定され鍵が読めなくなり、
/// 保存済みのデータを二度と読めなくなる。そのため鍵の新規作成は
/// **安定署名（Thoth Local Signing）で実行中の場合のみ** 行う。
///
/// ## フェイルセーフ
/// Keychain 読み出しが `errSecItemNotFound` 以外で失敗した場合、
/// 鍵が「存在するのに読めない」可能性があるため **新しい鍵は絶対に作成しない**
/// （既存の暗号化データを読めなくする事故の防止）。
enum AppKeyStore {

    // MARK: - Constants

    /// アプリ生成鍵専用の Keychain サービス名
    static let keychainServiceName = "io.github.boyaki-machine.Thoth.Database"
    /// Clipy 時代のサービス名（改名移行用）。移行後もバックアップとしてエントリを残す
    static let legacyKeychainServiceName = "com.clipy-app.Clipy.Database"
    /// アプリ生成鍵（AppGeneratedKeys の JSON）を集約する Keychain アカウント名
    static let appKeysAccount = "app-keys"
    /// 旧形式: クリップ .data ファイル暗号鍵の Keychain アカウント名。移行元として参照する
    static let legacyClipDataKeyAccount = "clipdata-encryption-key"

    /// クリップ .data ファイル暗号鍵（AES-256）の長さ（バイト）
    static let clipDataKeyLength = 32

    /// アプリの動作用に自動生成する鍵（アプリ生成情報）の集合。
    /// Keychain の 1 エントリ（account: app-keys）に JSON で集約して保存する。
    ///
    /// ユーザー由来の機微情報（SecureUserData / user-data エントリ）と対になる概念で、
    /// こちらは**環境固有**（インストールごとに生成・エクスポート対象外）。
    /// エクスポートに含めても他環境では意味を持たない（暗号化された DB ファイルごと
    /// 移さない限り復号対象が存在しない）ため、明確に分離している。
    struct AppGeneratedKeys: Codable {
        var version: Int
        /// v1.6.2 までの Realm データベースの暗号鍵（64 バイト）。いまは使わないが、
        /// app-keys を書き直すときに落とさないよう保持する
        var realmEncryptionKey: Data?
        /// クリップ .data ファイルの暗号鍵（32 バイト）
        var clipDataEncryptionKey: Data?

        init(version: Int = 1, realmEncryptionKey: Data? = nil, clipDataEncryptionKey: Data? = nil) {
            self.version = version
            self.realmEncryptionKey = realmEncryptionKey
            self.clipDataEncryptionKey = clipDataEncryptionKey
        }

        // キーが欠けていても読めるように寛容にデコードする（前方互換）
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
            realmEncryptionKey = try container.decodeIfPresent(Data.self, forKey: .realmEncryptionKey)
            clipDataEncryptionKey = try container.decodeIfPresent(Data.self, forKey: .clipDataEncryptionKey)
        }
    }

    /// アプリ生成鍵の用途
    enum AppKeyRole {
        case clipData

        var keyLength: Int {
            switch self {
            case .clipData: return AppKeyStore.clipDataKeyLength
            }
        }

        var legacyAccount: String {
            switch self {
            case .clipData: return AppKeyStore.legacyClipDataKeyAccount
            }
        }
    }

    // MARK: - Encryption Key Management

    /// app-keys の解決を直列化するロック（LibraryProvider.prepare はバックグラウンド、
    /// ClipDataStore.shared の初期化は保存キューから呼ばれ得るため）
    private static let appKeysLock = NSLock()

    /// 指定用途のアプリ生成鍵を返す。
    ///
    /// 解決順序:
    /// 1. app-keys エントリ（集約 JSON）に鍵があればそれを返す
    /// 2. 無ければ旧形式の個別エントリから移行する
    ///    （app-keys への書き込み + 読み戻し検証に成功した場合のみ旧エントリを削除）
    /// 3. どこにも無ければ（安定署名時のみ）新規作成して app-keys に保存する
    ///
    /// フェイルセーフ: `errSecItemNotFound` 以外の読み出し失敗時は nil を返し、
    /// 鍵は絶対に作成しない（既存の暗号化データを永久に開けなくする事故の防止）。
    /// 新規作成時は読み戻し検証に成功するまで鍵を使用しない。
    static func appEncryptionKey(for role: AppKeyRole) -> Data? {
        appKeysLock.lock(); defer { appKeysLock.unlock() }

        // 1. 集約エントリから読む
        let (status, raw) = readKeychainData(account: Self.appKeysAccount)
        var appKeys: AppGeneratedKeys
        switch status {
        case errSecSuccess:
            guard let raw = raw, let decoded = try? JSONDecoder().decode(AppGeneratedKeys.self, from: raw) else {
                NSLog("[AppKeyStore] app-keys decode failed; encryption disabled this launch")
                return nil
            }
            appKeys = decoded
        case errSecItemNotFound:
            appKeys = AppGeneratedKeys()
        default:
            NSLog("[AppKeyStore] keychain read failed with status \(status); encryption disabled this launch")
            return nil
        }
        if let key = existingKey(in: appKeys, for: role), key.count == role.keyLength {
            return key
        }

        // 2. 旧形式の個別エントリから移行する
        let (legacyStatus, legacyKey) = readKeychainData(account: role.legacyAccount)
        if legacyStatus != errSecSuccess && legacyStatus != errSecItemNotFound {
            NSLog("[AppKeyStore] legacy key read failed with status \(legacyStatus); encryption disabled this launch")
            return nil
        }
        if let legacyKey = legacyKey, legacyKey.count == role.keyLength {
            setKey(legacyKey, in: &appKeys, for: role)
            // 集約エントリへの反映と検証に成功した場合のみ旧エントリを削除する。
            // 失敗しても鍵自体は旧エントリに残っているためそのまま使える（次回再試行）
            if storeAppKeysVerified(appKeys) {
                deleteKeychainEntry(account: role.legacyAccount)
                NSLog("[AppKeyStore] migrated legacy key (\(role.legacyAccount)) into app-keys")
            }
            return legacyKey
        }

        // 3. Clipy 時代の旧サービス名から移行する（Thoth への改名対応）。
        //    旧サービスのエントリはロールバックに備えてバックアップとして残す
        let (oldStatus, oldRaw) = readKeychainData(account: Self.appKeysAccount, service: Self.legacyKeychainServiceName)
        if oldStatus != errSecSuccess && oldStatus != errSecItemNotFound {
            NSLog("[AppKeyStore] legacy service read failed with status \(oldStatus); encryption disabled this launch")
            return nil
        }
        if oldStatus == errSecSuccess, let oldRaw = oldRaw,
           let oldKeys = try? JSONDecoder().decode(AppGeneratedKeys.self, from: oldRaw) {
            if appKeys.realmEncryptionKey == nil { appKeys.realmEncryptionKey = oldKeys.realmEncryptionKey }
            if appKeys.clipDataEncryptionKey == nil { appKeys.clipDataEncryptionKey = oldKeys.clipDataEncryptionKey }
            if let key = existingKey(in: appKeys, for: role), key.count == role.keyLength {
                if storeAppKeysVerified(appKeys) {
                    NSLog("[AppKeyStore] migrated app-keys from legacy Clipy service")
                }
                return key
            }
        }
        // 旧サービスの個別エントリ（さらに古い形式）も確認する
        let (oldLegacyStatus, oldLegacyKey) = readKeychainData(account: role.legacyAccount, service: Self.legacyKeychainServiceName)
        if oldLegacyStatus != errSecSuccess && oldLegacyStatus != errSecItemNotFound {
            NSLog("[AppKeyStore] legacy service key read failed with status \(oldLegacyStatus); encryption disabled this launch")
            return nil
        }
        if let oldLegacyKey = oldLegacyKey, oldLegacyKey.count == role.keyLength {
            setKey(oldLegacyKey, in: &appKeys, for: role)
            if storeAppKeysVerified(appKeys) {
                NSLog("[AppKeyStore] migrated legacy key (\(role.legacyAccount)) from legacy Clipy service")
            }
            return oldLegacyKey
        }

        // 4. 新規作成（ad-hoc 署名のまま作ると再署名後に読めなくなるため、安定署名時のみ）
        guard CodeSignService().isStablySigned else {
            NSLog("[AppKeyStore] not stably signed yet; postpone encryption key creation")
            return nil
        }
        var bytes = [UInt8](repeating: 0, count: role.keyLength)
        guard SecRandomCopyBytes(kSecRandomDefault, role.keyLength, &bytes) == errSecSuccess else { return nil }
        let key = Data(bytes)
        setKey(key, in: &appKeys, for: role)
        guard storeAppKeysVerified(appKeys) else {
            NSLog("[AppKeyStore] failed to persist new key; encryption disabled this launch")
            return nil
        }
        return key
    }

    private static func existingKey(in appKeys: AppGeneratedKeys, for role: AppKeyRole) -> Data? {
        switch role {
        case .clipData: return appKeys.clipDataEncryptionKey
        }
    }

    private static func setKey(_ key: Data, in appKeys: inout AppGeneratedKeys, for role: AppKeyRole) {
        switch role {
        case .clipData: appKeys.clipDataEncryptionKey = key
        }
    }

    /// app-keys エントリを書き込み、読み戻して内容一致を検証する。
    /// 「書けたつもりで読めない」まま鍵を使い始める事故を防ぐ
    private static func storeAppKeysVerified(_ appKeys: AppGeneratedKeys) -> Bool {
        guard let data = try? JSONEncoder().encode(appKeys) else { return false }
        guard writeKeychainData(account: Self.appKeysAccount, data: data) else { return false }
        let (status, raw) = readKeychainData(account: Self.appKeysAccount)
        return status == errSecSuccess && raw == data
    }

    // MARK: - Keychain Primitives

    private static func readKeychainData(account: String, service: String = keychainServiceName) -> (status: OSStatus, data: Data?) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return (status, result as? Data)
    }

    private static func writeKeychainData(account: String, data: Data) -> Bool {
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainServiceName,
            kSecAttrAccount as String: account
        ]
        if SecItemCopyMatching(baseQuery as CFDictionary, nil) == errSecSuccess {
            let attributes: [String: Any] = [kSecValueData as String: data]
            return SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary) == errSecSuccess
        }
        var addQuery = baseQuery
        addQuery[kSecAttrLabel as String] = "Thoth App Generated Keys"
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        addQuery[kSecValueData as String] = data
        return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
    }

    private static func deleteKeychainEntry(account: String) {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword,
                       kSecAttrService as String: keychainServiceName,
                       kSecAttrAccount as String: account] as CFDictionary)
    }

}
