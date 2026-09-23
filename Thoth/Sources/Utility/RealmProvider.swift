//
//  RealmProvider.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Copyright © 2015-2018 Clipy Project.
//

import Foundation
import AppKit
import RealmSwift
import Security

/// Realm データベースの構成・スキーマ移行・保存時暗号化を一元管理するユーティリティ。
///
/// v1.5 からは保存先が SwiftData に移ったため、ここは (1) アプリ生成鍵（app-keys）の管理と
/// (2) 移行元の Realm を読むための構成（makeBaseConfiguration）にだけ使う。
/// 起動時に Realm を開く処理（旧 warmUp・「リセット」ダイアログ）は削除した。
/// Realm のライブラリと合わせて v1.6.x で整理する。
///
/// ## 暗号化の設計
/// - クリップボード履歴・スニペットは従来ディスクに平文で保存されていた。
///   Realm の保存時暗号化（AES-256）を有効化し、64 バイトの暗号鍵を
///   Keychain（`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`、ACL なし）に保存する。
///   起動時に無人で読み出す必要があるため、生体認証 ACL は付けない。
/// - 既存の平文データベースは初回起動時に `writeCopy(toFile:encryptionKey:)` で
///   暗号化コピーへ移行する（`.bak` 退避 → 差し替え → 検証オープン → `.bak` 削除）。
///
/// ## 署名との相互作用（重要）
/// Keychain 項目は作成したアプリの署名に紐づく。ad-hoc 署名のまま鍵を作成すると、
/// CodeSignService による再署名後に「別アプリ」と判定され鍵が読めなくなり、
/// データベースを二度と開けなくなる。そのため鍵の新規作成は
/// **安定署名（Thoth Local Signing）で実行中の場合のみ** 行い、
/// それ以外では平文のまま起動して次回以降に再試行する。
///
/// ## フェイルセーフ
/// - Keychain 読み出しが `errSecItemNotFound` 以外で失敗した場合、
///   鍵が「存在するのに読めない」可能性があるため **新しい鍵は絶対に作成しない**
///   （既存の暗号化済みデータベースを開けなくする事故の防止）。
/// - ユニットテスト実行時は暗号化を行わない
///   （テストは in-memory Realm を使い、encryptionKey と併用できないため）。
enum RealmProvider {

    // MARK: - Constants

    /// アプリ生成鍵専用の Keychain サービス名
    static let keychainServiceName = "io.github.boyaki-machine.Thoth.Database"
    /// Clipy 時代のサービス名（改名移行用）。移行後もバックアップとしてエントリを残す
    static let legacyKeychainServiceName = "com.clipy-app.Clipy.Database"
    /// アプリ生成鍵（AppGeneratedKeys の JSON）を集約する Keychain アカウント名
    static let appKeysAccount = "app-keys"
    /// 旧形式: Realm 暗号鍵の Keychain アカウント名。移行元として参照する
    static let legacyRealmKeyAccount = "realm-encryption-key"
    /// 旧形式: クリップ .data ファイル暗号鍵の Keychain アカウント名。移行元として参照する
    static let legacyClipDataKeyAccount = "clipdata-encryption-key"

    /// Realm が要求する暗号鍵の長さ（バイト）
    static let realmKeyLength = 64
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
        /// Realm データベースの暗号鍵（64 バイト）
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
        case realmDatabase
        case clipData

        var keyLength: Int {
            switch self {
            case .realmDatabase: return RealmProvider.realmKeyLength
            case .clipData:      return RealmProvider.clipDataKeyLength
            }
        }

        var legacyAccount: String {
            switch self {
            case .realmDatabase: return RealmProvider.legacyRealmKeyAccount
            case .clipData:      return RealmProvider.legacyClipDataKeyAccount
            }
        }
    }

    // MARK: - Configuration

    /// 既定構成の Realm を返す（Realm はスレッド毎にインスタンスをキャッシュする）。
    /// 構成（暗号鍵・スキーマ・テスト時の in-memory 差し替え）は defaultConfiguration で
    /// 一元管理されているため、アプリ内の Realm 取得はこのアクセサ経由に統一する
    static func defaultRealm() -> Realm {
        return try! Realm()
    }

    /// スキーマバージョンと移行ブロックのみを持つ基本構成を返す（暗号鍵なし）
    static func makeBaseConfiguration() -> Realm.Configuration {
        return Realm.Configuration(schemaVersion: 7, migrationBlock: { migration, oldSchemaVersion in
            if oldSchemaVersion <= 2 {
                // CPYSnippet に identifier を追加
                migration.enumerateObjects(ofType: CPYSnippet.className()) { _, newObject in
                    newObject!["identifier"] = NSUUID().uuidString
                }
            }
            if oldSchemaVersion <= 4 {
                // CPYFolder に identifier を追加
                migration.enumerateObjects(ofType: CPYFolder.className()) { _, newObject in
                    newObject!["identifier"] = NSUUID().uuidString
                }
            }
            if oldSchemaVersion <= 5 {
                // RealmObjc から RealmSwift への移行
                migration.enumerateObjects(ofType: CPYClip.className(), { oldObject, newObject in
                    newObject!["dataPath"] = oldObject!["dataPath"]
                    newObject!["title"] = oldObject!["title"]
                    newObject!["dataHash"] = oldObject!["dataHash"]
                    newObject!["primaryType"] = oldObject!["primaryType"]
                    newObject!["updateTime"] = oldObject!["updateTime"]
                    newObject!["thumbnailPath"] = oldObject!["thumbnailPath"]
                })
                migration.enumerateObjects(ofType: CPYSnippet.className(), { oldObject, newObject in
                    newObject!["index"] = oldObject!["index"]
                    newObject!["enable"] = oldObject!["enable"]
                    newObject!["title"] = oldObject!["title"]
                    newObject!["content"] = oldObject!["content"]
                    if oldSchemaVersion >= 3 {
                        newObject!["identifier"] = oldObject!["identifier"]
                    }
                })
                migration.enumerateObjects(ofType: CPYFolder.className(), { oldObject, newObject in
                    newObject!["index"] = oldObject!["index"]
                    newObject!["enable"] = oldObject!["enable"]
                    newObject!["title"] = oldObject!["title"]
                    if oldSchemaVersion >= 5 {
                        newObject!["identifier"] = oldObject!["identifier"]
                    }
                })
            }
        })
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
                NSLog("[RealmProvider] app-keys decode failed; encryption disabled this launch")
                return nil
            }
            appKeys = decoded
        case errSecItemNotFound:
            appKeys = AppGeneratedKeys()
        default:
            NSLog("[RealmProvider] keychain read failed with status \(status); encryption disabled this launch")
            return nil
        }
        if let key = existingKey(in: appKeys, for: role), key.count == role.keyLength {
            return key
        }

        // 2. 旧形式の個別エントリから移行する
        let (legacyStatus, legacyKey) = readKeychainData(account: role.legacyAccount)
        if legacyStatus != errSecSuccess && legacyStatus != errSecItemNotFound {
            NSLog("[RealmProvider] legacy key read failed with status \(legacyStatus); encryption disabled this launch")
            return nil
        }
        if let legacyKey = legacyKey, legacyKey.count == role.keyLength {
            setKey(legacyKey, in: &appKeys, for: role)
            // 集約エントリへの反映と検証に成功した場合のみ旧エントリを削除する。
            // 失敗しても鍵自体は旧エントリに残っているためそのまま使える（次回再試行）
            if storeAppKeysVerified(appKeys) {
                deleteKeychainEntry(account: role.legacyAccount)
                NSLog("[RealmProvider] migrated legacy key (\(role.legacyAccount)) into app-keys")
            }
            return legacyKey
        }

        // 3. Clipy 時代の旧サービス名から移行する（Thoth への改名対応）。
        //    旧サービスのエントリはロールバックに備えてバックアップとして残す
        let (oldStatus, oldRaw) = readKeychainData(account: Self.appKeysAccount, service: Self.legacyKeychainServiceName)
        if oldStatus != errSecSuccess && oldStatus != errSecItemNotFound {
            NSLog("[RealmProvider] legacy service read failed with status \(oldStatus); encryption disabled this launch")
            return nil
        }
        if oldStatus == errSecSuccess, let oldRaw = oldRaw,
           let oldKeys = try? JSONDecoder().decode(AppGeneratedKeys.self, from: oldRaw) {
            if appKeys.realmEncryptionKey == nil { appKeys.realmEncryptionKey = oldKeys.realmEncryptionKey }
            if appKeys.clipDataEncryptionKey == nil { appKeys.clipDataEncryptionKey = oldKeys.clipDataEncryptionKey }
            if let key = existingKey(in: appKeys, for: role), key.count == role.keyLength {
                if storeAppKeysVerified(appKeys) {
                    NSLog("[RealmProvider] migrated app-keys from legacy Clipy service")
                }
                return key
            }
        }
        // 旧サービスの個別エントリ（さらに古い形式）も確認する
        let (oldLegacyStatus, oldLegacyKey) = readKeychainData(account: role.legacyAccount, service: Self.legacyKeychainServiceName)
        if oldLegacyStatus != errSecSuccess && oldLegacyStatus != errSecItemNotFound {
            NSLog("[RealmProvider] legacy service key read failed with status \(oldLegacyStatus); encryption disabled this launch")
            return nil
        }
        if let oldLegacyKey = oldLegacyKey, oldLegacyKey.count == role.keyLength {
            setKey(oldLegacyKey, in: &appKeys, for: role)
            if storeAppKeysVerified(appKeys) {
                NSLog("[RealmProvider] migrated legacy key (\(role.legacyAccount)) from legacy Clipy service")
            }
            return oldLegacyKey
        }

        // 4. 新規作成（ad-hoc 署名のまま作ると再署名後に読めなくなるため、安定署名時のみ）
        guard CodeSignService().isStablySigned else {
            NSLog("[RealmProvider] not stably signed yet; postpone encryption key creation")
            return nil
        }
        var bytes = [UInt8](repeating: 0, count: role.keyLength)
        guard SecRandomCopyBytes(kSecRandomDefault, role.keyLength, &bytes) == errSecSuccess else { return nil }
        let key = Data(bytes)
        setKey(key, in: &appKeys, for: role)
        guard storeAppKeysVerified(appKeys) else {
            NSLog("[RealmProvider] failed to persist new key; encryption disabled this launch")
            return nil
        }
        return key
    }

    private static func existingKey(in appKeys: AppGeneratedKeys, for role: AppKeyRole) -> Data? {
        switch role {
        case .realmDatabase: return appKeys.realmEncryptionKey
        case .clipData:      return appKeys.clipDataEncryptionKey
        }
    }

    private static func setKey(_ key: Data, in appKeys: inout AppGeneratedKeys, for role: AppKeyRole) {
        switch role {
        case .realmDatabase: appKeys.realmEncryptionKey = key
        case .clipData:      appKeys.clipDataEncryptionKey = key
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

    // MARK: - Plaintext → Encrypted Migration

    /// 平文データベースを暗号化データベースへ移行する（冪等・失敗時は平文のまま継続）。
    ///
    /// 手順: 平文で開く → 暗号化コピー作成 → 元ファイルを `.bak` 退避 → 差し替え
    /// → 暗号化で検証オープン → 成功時のみ `.bak` 削除（失敗時は `.bak` を復元）。
    /// - Returns: 移行を実施して成功した場合と、既に移行済み・移行不要の場合に true。
    @discardableResult
    static func migrateToEncryptedIfNeeded(at fileURL: URL, key: Data) -> Bool {
        let fileManager = FileManager.default
        // データベースが存在しない（新規インストール）→ 暗号化構成でそのまま作られる
        guard fileManager.fileExists(atPath: fileURL.path) else { return true }

        // 既に暗号化済みなら開けるはず（フラグではなく実体で冪等性を判定する）。
        // Realm インスタンスはスレッド毎にキャッシュされるため、確認用のオープンは
        // autoreleasepool で確実に解放してから次のファイル操作に進む
        var encryptedConfig = makeBaseConfiguration()
        encryptedConfig.fileURL = fileURL
        encryptedConfig.encryptionKey = key
        let alreadyEncrypted = autoreleasepool { (try? Realm(configuration: encryptedConfig)) != nil }
        if alreadyEncrypted { return true }

        // 平文として開けなければ（破損等）ここでは何もしない
        var plainConfig = makeBaseConfiguration()
        plainConfig.fileURL = fileURL
        let tmpURL = fileURL.deletingLastPathComponent()
            .appendingPathComponent("migrating-\(UUID().uuidString).realm")
        do {
            // autoreleasepool で Realm 参照を確実に解放してからファイルを差し替える
            try autoreleasepool {
                let plainRealm = try Realm(configuration: plainConfig)
                try plainRealm.writeCopy(toFile: tmpURL, encryptionKey: key)
            }
        } catch {
            NSLog("[RealmProvider] failed to create encrypted copy: \(error); keep plaintext")
            try? fileManager.removeItem(at: tmpURL)
            return false
        }

        let backupURL = fileURL.appendingPathExtension("bak")
        do {
            try? fileManager.removeItem(at: backupURL)
            try fileManager.moveItem(at: fileURL, to: backupURL)
            // Realm の付随ファイルは新しいデータベースで再生成されるため削除する
            for suffix in ["lock", "management", "note"] {
                try? fileManager.removeItem(at: fileURL.appendingPathExtension(suffix))
            }
            try fileManager.moveItem(at: tmpURL, to: fileURL)
        } catch {
            NSLog("[RealmProvider] failed to swap database files: \(error); restoring backup")
            try? fileManager.removeItem(at: fileURL)
            try? fileManager.moveItem(at: backupURL, to: fileURL)
            try? fileManager.removeItem(at: tmpURL)
            return false
        }

        // 検証オープンに成功した場合のみバックアップを破棄する
        let verified = autoreleasepool { (try? Realm(configuration: encryptedConfig)) != nil }
        if verified {
            try? fileManager.removeItem(at: backupURL)
            NSLog("[RealmProvider] database migrated to encrypted format")
            return true
        } else {
            NSLog("[RealmProvider] verification open failed; restoring plaintext backup")
            try? fileManager.removeItem(at: fileURL)
            try? fileManager.moveItem(at: backupURL, to: fileURL)
            return false
        }
    }
}
