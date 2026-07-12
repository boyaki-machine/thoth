//
//  SecureMenuService.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Copyright © 2015-2018 Clipy Project.
//

import Foundation
import LocalAuthentication
import Security

/// セキュアメニューのアイテム（パスワード等の機微情報）と指紋パスワードを
/// macOS Keychain で管理し、Touch ID / パスワード認証を提供するサービス。
///
/// ## 認証と Keychain 保護の設計（トレードオフ）
/// - 認証（LAContext.evaluatePolicy）に成功したコンテキストは保持され、
///   以降の Keychain 読み出しに `kSecUseAuthenticationContext` で紐付けられる。
/// - エントリの新規作成時は `.userPresence` ACL 付き（data protection keychain）での
///   保存をプローブする。成功した環境では **OS が読み出しごとに在席確認を強制** し、
///   アプリコードの改変では迂回できない保護になる。
/// - ただし data protection keychain は application-identifier エンタイトルメントを要求し、
///   本アプリの ad-hoc / 自己署名（CodeSignService による署名安定化）では
///   `errSecMissingEntitlement` で失敗するため、従来のファイルベース Keychain に
///   自動フォールバックする。この場合の実効的な保護は
///   「CodeSignService による署名の安定化 + アプリ内の LAContext 認証ゲート」となる。
///   Developer ID 署名へ移行すれば ACL 保護が自動的に有効になる。
final class SecureMenuService {

    // MARK: - Constants

    private static let defaultKeychainService = "com.clipy-app.Clipy.SecureMenu"
    /// 全アイテムをひとつの Keychain エントリにまとめるためのキー。
    /// 1エントリ = 1回の "Allow" ダイアログで済む。
    private static let itemsKey = "all-items"
    /// 暗号化・復号化の指紋パスワード（固定パスワード）を保存するためのキー。
    /// セキュアアイテムと同じ Keychain サービス内に別エントリとして保存する。
    private static let cryptoPasswordKey = "crypto-password"

    /// Keychain エントリの service 名。テストでは専用の名前を注入して本番データと分離する。
    private let keychainService: String

    /// 直近の `loadAllItems()` がアクセス拒否等で失敗した場合 true（「アイテム 0 件」との区別に使う）。
    /// ad-hoc 署名ビルドではバイナリが変わるたびに Keychain の ACL 上は「別アプリ」と
    /// 判定されるため、既存エントリの読み出しが拒否されることがある。
    /// この状態のまま保存すると既存データを上書き消去してしまうため、`saveAllItems` はガードする。
    /// （テストから拒否状態を再現できるよう setter は internal にしている）
    var isKeychainAccessDenied = false

    /// 直近に成功した認証のコンテキスト。Keychain クエリに `kSecUseAuthenticationContext` で
    /// 引き渡し、認証結果と Keychain 読み出しを OS レベルで紐付ける。
    /// ACL 付きエントリ（後述のプローブが成功した環境）では、このコンテキストが無いと
    /// 読み出し時に OS が再認証を要求する＝アプリのロジックを迂回しても値を取れない。
    private var authenticatedContext: LAContext?

    // MARK: - Initialize

    init(keychainService: String = SecureMenuService.defaultKeychainService) {
        self.keychainService = keychainService
    }

    // MARK: - Authentication

    func authenticate(reason: String, completion: @escaping (Bool) -> Void) {
        let context = LAContext()
        var error: NSError?
        let policy = LAPolicy.deviceOwnerAuthentication

        guard context.canEvaluatePolicy(policy, error: &error) else {
            #if DEBUG
            NSLog("[SecureMenuService] authenticate: canEvaluatePolicy failed: \(String(describing: error))")
            #endif
            DispatchQueue.main.async { completion(false) }
            return
        }
        #if DEBUG
        NSLog("[SecureMenuService] authenticate: starting evaluatePolicy")
        #endif

        context.evaluatePolicy(policy, localizedReason: reason) { success, authError in
            #if DEBUG
            if let authError = authError {
                NSLog("[SecureMenuService] authenticate: evaluatePolicy error: \(authError)")
            }
            #endif
            DispatchQueue.main.async {
                // 評価済みコンテキストを保持し、以降の Keychain 読み出しに紐付ける
                self.authenticatedContext = success ? context : nil
                completion(success)
            }
        }
    }

    // MARK: - Keychain Primitives

    /// Keychain クエリの共通部分を組み立てる。
    /// - Parameter dataProtection: true の場合 data protection keychain
    ///   （ACL 付きエントリの保存先）を対象にする
    private func keychainQuery(account: String, dataProtection: Bool = false) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account
        ]
        if dataProtection {
            query[kSecUseDataProtectionKeychain as String] = true
        }
        return query
    }

    /// エントリを読み出す。従来のファイルベース Keychain → data protection keychain
    /// （ACL 付き）の順に検索し、評価済み LAContext があれば認証コンテキストとして引き渡す
    private func readEntry(account: String) -> (status: OSStatus, data: Data?) {
        var fileBasedStatus: OSStatus = errSecItemNotFound
        for dataProtection in [false, true] {
            var query = keychainQuery(account: account, dataProtection: dataProtection)
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            query[kSecReturnData as String] = true
            if let context = authenticatedContext {
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
    private func writeEntry(account: String, label: String, data: Data) -> Bool {
        // 既存エントリの更新（保存先はエントリ作成時の場所を維持する）
        for dataProtection in [false, true] {
            var existsQuery = keychainQuery(account: account, dataProtection: dataProtection)
            existsQuery[kSecMatchLimit as String] = kSecMatchLimitOne
            guard SecItemCopyMatching(existsQuery as CFDictionary, nil) == errSecSuccess else { continue }

            var query = keychainQuery(account: account, dataProtection: dataProtection)
            if dataProtection, let context = authenticatedContext {
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
    private func addProtectedEntry(account: String, label: String, data: Data) -> Bool {
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
        if let context = authenticatedContext {
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
    private func removeEntry(account: String) -> Bool {
        var success = true
        for dataProtection in [false, true] {
            let status = SecItemDelete(keychainQuery(account: account, dataProtection: dataProtection) as CFDictionary)
            if !dataProtection {
                success = (status == errSecSuccess || status == errSecItemNotFound)
            }
        }
        return success
    }

    // MARK: - Keychain CRUD

    func loadAllItems() -> [SecureMenuItem] {
        let (status, resultData) = readEntry(account: Self.itemsKey)
        #if DEBUG
        NSLog("[SecureMenuService] loadAllItems: status=\(status)")
        #endif
        // 「エントリが存在しない」以外の失敗はアクセス拒否として記録する
        // （バイナリ更新により Keychain ACL の照合に失敗した場合など）
        isKeychainAccessDenied = (status != errSecSuccess && status != errSecItemNotFound)

        guard status == errSecSuccess, let data = resultData else {
            if isKeychainAccessDenied {
                NSLog("[SecureMenuService] loadAllItems: keychain access failed with status \(status)")
            }
            return []
        }

        do {
            var items = try JSONDecoder().decode([SecureMenuItem].self, from: data)
            items.sort { $0.displayOrder < $1.displayOrder }
            #if DEBUG
            NSLog("[SecureMenuService] loadAllItems: returning \(items.count) item(s)")
            #endif
            return items
        } catch {
            #if DEBUG
            NSLog("[SecureMenuService] loadAllItems: decode failed: \(error)")
            #endif
            return []
        }
    }

    func save(_ item: SecureMenuItem) -> Bool {
        var items = loadAllItems()
        if let index = items.firstIndex(where: { $0.itemID == item.itemID }) {
            // 上書き時は各フィールドの Val 変更履歴を引き継ぎ・追記する
            items[index] = mergeFieldHistories(oldItem: items[index], newItem: item)
        } else {
            // 新規追加: displayOrder を末尾に設定
            let maxOrder = items.map { $0.displayOrder }.max() ?? -1
            let newItem = SecureMenuItem(
                itemID: item.itemID,
                title: item.title,
                fields: item.fields,
                displayOrder: maxOrder + 1
            )
            items.append(newItem)
        }
        return saveAllItems(items)
    }

    func delete(itemID: String) -> Bool {
        return delete(itemIDs: [itemID])
    }

    /// 複数アイテムをまとめて削除する（Keychain への書き込みは 1 回で行う）
    func delete(itemIDs: [String]) -> Bool {
        var items = loadAllItems()
        items.removeAll { itemIDs.contains($0.itemID) }
        return saveAllItems(items)
    }

    func reorderItems(_ orderedItems: [SecureMenuItem]) -> Bool {
        let reordered = orderedItems.enumerated().map { index, item in
            SecureMenuItem(itemID: item.itemID, title: item.title, fields: item.fields, displayOrder: index)
        }
        return saveAllItems(reordered)
    }

    /// Keychain のエントリ自体を削除する（全アイテムの削除・テストのクリーンアップ用）
    @discardableResult
    func deleteAllItems() -> Bool {
        return removeEntry(account: Self.itemsKey)
    }

    // MARK: - Crypto Password (指紋パスワード)

    /// 暗号化・復号化の指紋パスワード（固定パスワード）を Keychain に保存する。
    /// セキュアアイテムと同じ Keychain サービス内の別エントリに保存する。
    @discardableResult
    func saveCryptoPassword(_ password: String) -> Bool {
        guard let data = password.data(using: .utf8) else { return false }
        return writeEntry(account: Self.cryptoPasswordKey, label: "Clipy Crypto Password", data: data)
    }

    /// 保存済みの指紋パスワードを読み出す。未登録の場合は nil を返す。
    /// ACL 付きエントリの場合、authenticate() 済みのコンテキストが紐付いていないと
    /// OS が追加の認証を要求する
    func loadCryptoPassword() -> String? {
        let (status, data) = readEntry(account: Self.cryptoPasswordKey)
        guard status == errSecSuccess, let data = data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// 指紋パスワードが登録済みか
    func hasCryptoPassword() -> Bool {
        for dataProtection in [false, true] {
            var query = keychainQuery(account: Self.cryptoPasswordKey, dataProtection: dataProtection)
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            if SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess { return true }
        }
        return false
    }

    /// 指紋パスワードの Keychain エントリを削除する（テストのクリーンアップ用）
    @discardableResult
    func deleteCryptoPassword() -> Bool {
        return removeEntry(account: Self.cryptoPasswordKey)
    }

    // MARK: - Private Helpers

    /// フィールドごとの Val 変更履歴の最大保持件数（超過分は古いものから自動削除する）
    static let maxFieldHistoryCount = 10

    /// 同じ itemID の既存アイテムを上書きする際、各フィールドの Val が変更されていた場合に、
    /// 旧値を「置き換えられた日時」つきで変更履歴に追記する。
    /// フィールドの対応付けは fieldID（安定 ID）で行うため、Label を変更しても履歴は追従する。
    /// fieldID を持たない旧形式データから移行する場合のみ label で対応付ける。
    /// 履歴は渡されたフィールドのものを正とする（ポップアップからの削除を反映するため）。
    private func mergeFieldHistories(oldItem: SecureMenuItem, newItem: SecureMenuItem) -> SecureMenuItem {
        var merged = newItem
        merged.fields = newItem.fields.map { field in
            let oldField = oldItem.fields.first { $0.fieldID == field.fieldID }
                ?? oldItem.fields.first { $0.label == field.label }
            guard let old = oldField else { return field }
            var history = field.history
            // TOTP は secret を履歴に残さない（極めて機微なため）。それ以外は旧値を追記する
            if !field.isTOTP, old.value != field.value && !old.value.isEmpty {
                history.append(SecureMenuItem.FieldHistoryEntry(value: old.value, replacedAt: Date()))
            }
            // 上限を超えた分は古いものから削除する
            history = Array(history.suffix(Self.maxFieldHistoryCount))
            return SecureMenuItem.Field(fieldID: field.fieldID, label: field.label, value: field.value,
                                        isPassword: field.isPassword, kind: field.kind, history: history)
        }
        return merged
    }

    private func saveAllItems(_ items: [SecureMenuItem]) -> Bool {
        // 既存エントリを読み出せていない状態で保存すると、読めなかったデータを
        // 上書きして消去してしまうため保存を拒否する
        guard !isKeychainAccessDenied else {
            NSLog("[SecureMenuService] saveAllItems: rejected to prevent overwriting unreadable keychain data")
            return false
        }
        guard let data = try? JSONEncoder().encode(items) else { return false }
        return writeEntry(account: Self.itemsKey, label: "Clipy Secure Items", data: data)
    }
}
