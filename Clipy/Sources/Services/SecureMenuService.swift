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
            DispatchQueue.main.async { completion(success) }
        }
    }

    // MARK: - Keychain CRUD

    func loadAllItems() -> [SecureMenuItem] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: Self.itemsKey,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        #if DEBUG
        NSLog("[SecureMenuService] loadAllItems: status=\(status)")
        #endif
        // 「エントリが存在しない」以外の失敗はアクセス拒否として記録する
        // （バイナリ更新により Keychain ACL の照合に失敗した場合など）
        isKeychainAccessDenied = (status != errSecSuccess && status != errSecItemNotFound)

        guard status == errSecSuccess, let data = result as? Data else {
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
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: Self.itemsKey
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    // MARK: - Crypto Password (指紋パスワード)

    /// 暗号化・復号化の指紋パスワード（固定パスワード）を Keychain に保存する。
    /// セキュアアイテムと同じ Keychain サービス内の別エントリに保存する。
    @discardableResult
    func saveCryptoPassword(_ password: String) -> Bool {
        guard let data = password.data(using: .utf8) else { return false }
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: Self.cryptoPasswordKey
        ]
        if SecItemCopyMatching(baseQuery as CFDictionary, nil) == errSecSuccess {
            let attributes: [String: Any] = [kSecValueData as String: data]
            return SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary) == errSecSuccess
        } else {
            var addQuery = baseQuery
            addQuery[kSecAttrLabel as String] = "Clipy Crypto Password"
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            addQuery[kSecValueData as String] = data
            return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
        }
    }

    /// 保存済みの指紋パスワードを読み出す。未登録の場合は nil を返す。
    func loadCryptoPassword() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: Self.cryptoPasswordKey,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// 指紋パスワードが登録済みか
    func hasCryptoPassword() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: Self.cryptoPasswordKey,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    /// 指紋パスワードの Keychain エントリを削除する（テストのクリーンアップ用）
    @discardableResult
    func deleteCryptoPassword() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: Self.cryptoPasswordKey
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
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
            if old.value != field.value && !old.value.isEmpty {
                history.append(SecureMenuItem.FieldHistoryEntry(value: old.value, replacedAt: Date()))
            }
            // 上限を超えた分は古いものから削除する
            history = Array(history.suffix(Self.maxFieldHistoryCount))
            return SecureMenuItem.Field(fieldID: field.fieldID, label: field.label, value: field.value,
                                        isPassword: field.isPassword, history: history)
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

        // 既存エントリが存在するか確認
        let existsQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: Self.itemsKey,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        if SecItemCopyMatching(existsQuery as CFDictionary, nil) == errSecSuccess {
            let updateQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: keychainService,
                kSecAttrAccount as String: Self.itemsKey
            ]
            let attributes: [String: Any] = [
                kSecValueData as String: data,
                kSecAttrLabel as String: "Clipy Secure Items"
            ]
            let status = SecItemUpdate(updateQuery as CFDictionary, attributes as CFDictionary)
            #if DEBUG
            NSLog("[SecureMenuService] saveAllItems: update status=\(status)")
            #endif
            return status == errSecSuccess
        } else {
            let addQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: keychainService,
                kSecAttrAccount as String: Self.itemsKey,
                kSecAttrLabel as String: "Clipy Secure Items",
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                kSecValueData as String: data
            ]
            let status = SecItemAdd(addQuery as CFDictionary, nil)
            #if DEBUG
            NSLog("[SecureMenuService] saveAllItems: add status=\(status)")
            #endif
            return status == errSecSuccess
        }
    }
}
