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

    private static let keychainService = "com.clipy-app.Clipy.SecureMenu"
    /// 全アイテムをひとつの Keychain エントリにまとめるためのキー。
    /// 1エントリ = 1回の "Allow" ダイアログで済む。
    private static let itemsKey = "all-items"

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
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.itemsKey,
            kSecMatchLimit as String:  kSecMatchLimitOne,
            kSecReturnData as String:  true
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        #if DEBUG
        NSLog("[SecureMenuService] loadAllItems: status=\(status)")
        #endif

        guard status == errSecSuccess, let data = result as? Data else {
            #if DEBUG
            if status != errSecItemNotFound {
                NSLog("[SecureMenuService] loadAllItems: failed with status \(status)")
            }
            #endif
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
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        } else {
            // 新規追加: displayOrder を末尾に設定
            let maxOrder = items.map { $0.displayOrder }.max() ?? -1
            let newItem = SecureMenuItem(
                id: item.id,
                title: item.title,
                fields: item.fields,
                displayOrder: maxOrder + 1
            )
            items.append(newItem)
        }
        return saveAllItems(items)
    }

    func delete(id: String) -> Bool {
        var items = loadAllItems()
        items.removeAll { $0.id == id }
        return saveAllItems(items)
    }

    func reorderItems(_ orderedItems: [SecureMenuItem]) -> Bool {
        let reordered = orderedItems.enumerated().map { i, item in
            SecureMenuItem(id: item.id, title: item.title, fields: item.fields, displayOrder: i)
        }
        return saveAllItems(reordered)
    }

    // MARK: - Private Helpers

    private func saveAllItems(_ items: [SecureMenuItem]) -> Bool {
        guard let data = try? JSONEncoder().encode(items) else { return false }

        // 既存エントリが存在するか確認
        let existsQuery: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.itemsKey,
            kSecMatchLimit as String:  kSecMatchLimitOne
        ]

        if SecItemCopyMatching(existsQuery as CFDictionary, nil) == errSecSuccess {
            let updateQuery: [String: Any] = [
                kSecClass as String:       kSecClassGenericPassword,
                kSecAttrService as String: Self.keychainService,
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
                kSecClass as String:            kSecClassGenericPassword,
                kSecAttrService as String:      Self.keychainService,
                kSecAttrAccount as String:      Self.itemsKey,
                kSecAttrLabel as String:        "Clipy Secure Items",
                kSecAttrAccessible as String:   kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                kSecValueData as String:        data
            ]
            let status = SecItemAdd(addQuery as CFDictionary, nil)
            #if DEBUG
            NSLog("[SecureMenuService] saveAllItems: add status=\(status)")
            #endif
            return status == errSecSuccess
        }
    }
}
