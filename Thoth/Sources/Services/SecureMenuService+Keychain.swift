//
//  SecureMenuService+Keychain.swift
//
//  Thoth
//
//  SecureMenuService のキーチェーンの基本操作（エントリの読み書きと削除）
//

import Foundation
import LocalAuthentication
import Security

/// キーチェーンの基本操作。user-data エントリの読み書き（SecureMenuService.swift）から使う。
///
/// ファイルを分けたため、別ファイルから呼べるよう private を外している（モジュール内からは見える）。
/// **SecureMenuService の外から直接呼ばないこと。** 読み書きは必ず loadAllItems / save などの
/// 公開の操作を通す（認証コンテキストの付与・旧形式からの移行・読めないときの保護がそこにある）。
extension SecureMenuService {

    // MARK: - Keychain Primitives

    /// Keychain クエリの共通部分を組み立てる。
    /// - Parameter dataProtection: true の場合 data protection keychain
    ///   （ACL 付きエントリの保存先）を対象にする
    func keychainQuery(account: String, dataProtection: Bool = false, service: String? = nil) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service ?? keychainService,
            kSecAttrAccount as String: account
        ]
        if dataProtection {
            query[kSecUseDataProtectionKeychain as String] = true
        }
        return query
    }

    /// エントリを読み出す。従来のファイルベース Keychain → data protection keychain
    /// （ACL 付き）の順に検索し、評価済み LAContext があれば認証コンテキストとして引き渡す
    func readEntry(account: String, service: String? = nil) -> (status: OSStatus, data: Data?) {
        var fileBasedStatus: OSStatus = errSecItemNotFound
        for dataProtection in [false, true] {
            var query = keychainQuery(account: account, dataProtection: dataProtection, service: service)
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            query[kSecReturnData as String] = true
            if let context = currentAuthenticationContext() {
                query[kSecUseAuthenticationContext as String] = context
            }
            var result: AnyObject?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            if status == errSecSuccess {
                return (status, result as? Data)
            }
            if !dataProtection {
                fileBasedStatus = status
                // ファイルベース側でアクセス拒否等が起きた場合はそのまま返す
                // （data protection 側の探索で notFound に化けさせない）
                if status != errSecItemNotFound { return (status, nil) }
            }
        }
        // data protection 側の失敗（errSecMissingEntitlement 等）は「存在しない」と同義に扱う
        return (fileBasedStatus, nil)
    }

    /// エントリを保存する（既存があれば更新、無ければ新規作成）。
    ///
    /// 新規作成時はまず `.userPresence` ACL 付きで data protection keychain への保存を試みる
    /// （プローブ）。成功すれば以降の読み出しに OS レベルの認証が要求される。
    /// ad-hoc / 自己署名ビルドは application-identifier エンタイトルメントを持たないため
    /// `errSecMissingEntitlement` で失敗する——その場合は従来のファイルベース Keychain に
    /// 自動フォールバックする（Developer ID 署名へ移行すれば ACL が自動的に有効になる）
    func writeEntry(account: String, label: String, data: Data) -> Bool {
        // 既存エントリの更新（保存先はエントリ作成時の場所を維持する）
        for dataProtection in [false, true] {
            var existsQuery = keychainQuery(account: account, dataProtection: dataProtection)
            existsQuery[kSecMatchLimit as String] = kSecMatchLimitOne
            guard SecItemCopyMatching(existsQuery as CFDictionary, nil) == errSecSuccess else { continue }

            var query = keychainQuery(account: account, dataProtection: dataProtection)
            if dataProtection, let context = currentAuthenticationContext() {
                query[kSecUseAuthenticationContext as String] = context
            }
            let attributes: [String: Any] = [
                kSecValueData as String: data,
                kSecAttrLabel as String: label
            ]
            return SecItemUpdate(query as CFDictionary, attributes as CFDictionary) == errSecSuccess
        }
        // 新規作成: ACL 付き保存をプローブし、失敗したら従来方式にフォールバック
        if addProtectedEntry(account: account, label: label, data: data) { return true }
        var addQuery = keychainQuery(account: account)
        addQuery[kSecAttrLabel as String] = label
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        addQuery[kSecValueData as String] = data
        return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
    }

    /// `.userPresence` ACL 付きエントリの作成を試みる。
    /// 成功すると、読み出し時に OS が Touch ID / パスワードによる在席確認を強制する
    /// （アプリのコードが改変されても Keychain 側で認証が要求される）
    func addProtectedEntry(account: String, label: String, data: Data) -> Bool {
        // テスト実行時はプローブしない（成功する環境だと読み出しで認証プロンプトが出て
        // テストが停止してしまうため、常にファイルベース側を使う）
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return false }
        guard let accessControl = SecAccessControlCreateWithFlags(nil,
                                                                  kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                                                                  .userPresence, nil) else { return false }
        var addQuery = keychainQuery(account: account, dataProtection: true)
        addQuery[kSecAttrLabel as String] = label
        addQuery[kSecAttrAccessControl as String] = accessControl
        addQuery[kSecValueData as String] = data
        if let context = currentAuthenticationContext() {
            addQuery[kSecUseAuthenticationContext as String] = context
        }
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        #if DEBUG
        if status != errSecSuccess {
            NSLog("[SecureMenuService] protected add failed (status \(status)); falling back to file-based keychain")
        }
        #endif
        return status == errSecSuccess
    }

    /// エントリを削除する（ファイルベース・data protection の両方から）
    func removeEntry(account: String) -> Bool {
        var success = true
        for dataProtection in [false, true] {
            let status = SecItemDelete(keychainQuery(account: account, dataProtection: dataProtection) as CFDictionary)
            if !dataProtection {
                success = (status == errSecSuccess || status == errSecItemNotFound)
            }
        }
        return success
    }
}
