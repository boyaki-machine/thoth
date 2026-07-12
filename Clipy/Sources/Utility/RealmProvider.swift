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
/// **安定署名（Clipy Local Signing）で実行中の場合のみ** 行い、
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

    /// データベース暗号鍵専用の Keychain サービス名
    static let keychainServiceName = "com.clipy-app.Clipy.Database"
    /// Realm 暗号鍵の Keychain アカウント名
    static let realmKeyAccount = "realm-encryption-key"
    /// クリップ .data ファイル暗号鍵の Keychain アカウント名
    static let clipDataKeyAccount = "clipdata-encryption-key"

    /// Realm が要求する暗号鍵の長さ（バイト）
    static let realmKeyLength = 64

    // MARK: - Setup (起動時に一度だけ呼ぶ)

    /// デフォルト Realm 構成（スキーマバージョン・移行ブロック・暗号鍵）を設定し、
    /// 必要なら平文データベースの暗号化移行を行う。
    /// AppEnvironment 経由で Realm に触れる前（起動処理の最初）に呼ぶこと。
    static func setup() {
        var config = makeBaseConfiguration()

        // テスト実行時は暗号化しない（各 spec が in-memory Realm に差し替えるため）
        let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        if !isTesting, let key = loadOrCreateEncryptionKey(account: Self.realmKeyAccount,
                                                           length: Self.realmKeyLength) {
            if let fileURL = config.fileURL {
                migrateToEncryptedIfNeeded(at: fileURL, key: key)
            }
            config.encryptionKey = key
        }

        Realm.Configuration.defaultConfiguration = config

        // ここで一度開いてスキーマ移行を確定させる（従来 Realm.migration() が行っていた処理）
        do {
            _ = try Realm()
        } catch {
            handleUnopenableDatabase(config: config, error: error)
        }
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

    /// Keychain から暗号鍵を読み出す。無ければ（安定署名時のみ）新規作成する。
    /// `errSecItemNotFound` 以外の読み出し失敗時は nil を返し、鍵は作成しない。
    static func loadOrCreateEncryptionKey(account: String, length: Int) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainServiceName,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let key = result as? Data, key.count == length {
            return key
        }
        guard status == errSecItemNotFound else {
            // 鍵が存在するのに読めない可能性（ACL 拒否等）。
            // ここで新規作成すると既存の暗号化 DB を永久に開けなくするため何もしない
            NSLog("[RealmProvider] keychain read failed with status \(status); encryption disabled this launch")
            return nil
        }

        // ad-hoc 署名のまま鍵を作ると再署名後に読めなくなるため、安定署名時のみ作成する
        guard CodeSignService().isStablySigned else {
            NSLog("[RealmProvider] not stably signed yet; postpone encryption key creation")
            return nil
        }

        var bytes = [UInt8](repeating: 0, count: length)
        guard SecRandomCopyBytes(kSecRandomDefault, length, &bytes) == errSecSuccess else { return nil }
        let key = Data(bytes)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainServiceName,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: key
        ]
        guard SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess else {
            NSLog("[RealmProvider] failed to store encryption key; encryption disabled this launch")
            return nil
        }

        // 「書けたつもりで読めない」事故を防ぐため、必ず読み戻して一致を検証してから使う
        var verifyResult: AnyObject?
        let verifyStatus = SecItemCopyMatching(query as CFDictionary, &verifyResult)
        guard verifyStatus == errSecSuccess, let verified = verifyResult as? Data, verified == key else {
            NSLog("[RealmProvider] key readback verification failed; encryption disabled this launch")
            SecItemDelete([kSecClass as String: kSecClassGenericPassword,
                           kSecAttrService as String: keychainServiceName,
                           kSecAttrAccount as String: account] as CFDictionary)
            return nil
        }
        return key
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

    // MARK: - Failure Handling

    /// 暗号化データベースを開けない場合（鍵消失・破損等）の最終手段。
    /// ユーザーに「終了して再試行」か「履歴・スニペットをリセット」を選ばせる。
    private static func handleUnopenableDatabase(config: Realm.Configuration, error: Error) {
        NSLog("[RealmProvider] failed to open database: \(error)")
        let alert = NSAlert()
        alert.messageText = L10n.realmOpenFailedTitle
        alert.informativeText = L10n.realmOpenFailedMessage
        alert.addButton(withTitle: L10n.realmOpenFailedQuit)
        alert.addButton(withTitle: L10n.realmOpenFailedReset)
        let response = alert.runModal()
        if response == .alertSecondButtonReturn, let fileURL = config.fileURL {
            // 履歴・スニペットを削除して新しいデータベースを作り直す
            let fileManager = FileManager.default
            try? fileManager.removeItem(at: fileURL)
            for suffix in ["lock", "management", "note"] {
                try? fileManager.removeItem(at: fileURL.appendingPathExtension(suffix))
            }
            if (try? Realm()) != nil { return }
        }
        NSApp.terminate(nil)
    }
}
