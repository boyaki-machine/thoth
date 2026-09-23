//
//  HotKeyService.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Econa77 on 2016/11/19.
//
//  Copyright © 2015-2018 Clipy Project.
//

import Foundation
import Cocoa
import Carbon
import Magnet

/// グローバルホットキー（メニュー呼び出し・履歴クリア・スニペットフォルダ表示）を
/// Magnet フレームワーク経由で登録・管理するサービス。
/// キーコンボは NSKeyedArchiver 形式で UserDefaults に永続化される。
final class HotKeyService: NSObject {

    // MARK: - Properties
    /// 既定のホットキー割り当て
    static var defaultKeyCombos: [String: Any] = {
        // MainMenu:    ⌘ + Shift + V
        // HistoryMenu: ⌘ + Control + V
        // SnipeetMenu: ⌘ + Shift + B
        // SecureMenu:  ⌘ + Shift + . (keyCode 47 = Period key)
        return [Constants.Menu.clip: ["keyCode": 9, "modifiers": 768],
                Constants.Menu.history: ["keyCode": 9, "modifiers": 4352],
                Constants.Menu.snippet: ["keyCode": 11, "modifiers": 768],
                Constants.Menu.secure: ["keyCode": 47, "modifiers": 768]]
    }()

    fileprivate(set) var mainKeyCombo: KeyCombo?
    fileprivate(set) var historyKeyCombo: KeyCombo?
    fileprivate(set) var snippetKeyCombo: KeyCombo?
    fileprivate(set) var secureKeyCombo: KeyCombo?
    fileprivate(set) var clearHistoryKeyCombo: KeyCombo?

}

// MARK: - Actions
extension HotKeyService {
    @objc func popupMainMenu() {
        AppEnvironment.current.menuManager.popUpMenu(.main)
    }

    @objc func popupHistoryMenu() {
        AppEnvironment.current.menuManager.popUpMenu(.history)
    }

    @objc func popUpSnippetMenu() {
        AppEnvironment.current.menuManager.popUpMenu(.snippet)
    }

    @objc func popUpSecureMenu() {
        Diagnostics.secureMenu.info("hotkey received (secureInput=\(IsSecureEventInputEnabled(), privacy: .public))")
        AppEnvironment.current.menuManager.popUpSecureMenu()
    }

    @objc func popUpClearHistoryAlert() {
        guard let appDelegate = NSApp.delegate as? AppDelegate else { return }
        appDelegate.clearAllHistory()
    }
}

// MARK: - Setup
extension HotKeyService {
    func setupDefaultHotKeys() {
        // Migration new framework
        if !AppEnvironment.current.defaults.bool(forKey: Constants.HotKey.migrateNewKeyCombo) {
            migrationKeyCombos()
            AppEnvironment.current.defaults.set(true, forKey: Constants.HotKey.migrateNewKeyCombo)
        }
        // Snippet hotkey
        setupSnippetHotKeys()

        // Main menu
        change(with: .main, keyCombo: savedKeyCombo(forKey: Constants.HotKey.mainKeyCombo))
        // History menu
        change(with: .history, keyCombo: savedKeyCombo(forKey: Constants.HotKey.historyKeyCombo))
        // Snippet menu
        change(with: .snippet, keyCombo: savedKeyCombo(forKey: Constants.HotKey.snippetKeyCombo))
        // Secure menu:
        // 旧デフォルト (keyCode 27 / Minus) は JIS キーボードで動作しないため一度だけリセット
        let secureKeyResetDone = "kCPYHotKeySecureKeyCodeV47Migrated"
        if !AppEnvironment.current.defaults.bool(forKey: secureKeyResetDone) {
            AppEnvironment.current.defaults.removeObject(forKey: Constants.HotKey.secureKeyCombo)
            AppEnvironment.current.defaults.set(true, forKey: secureKeyResetDone)
        }
        let savedSecure = savedKeyCombo(forKey: Constants.HotKey.secureKeyCombo)
        let secureCombo = savedSecure ?? KeyCombo(QWERTYKeyCode: 47, carbonModifiers: 768)
        change(with: .secure, keyCombo: secureCombo)
        // Clear History
        changeClearHistoryKeyCombo(savedKeyCombo(forKey: Constants.HotKey.clearHistoryKeyCombo))
    }

    func change(with type: MenuType, keyCombo: KeyCombo?) {
        switch type {
        case .main:
            mainKeyCombo = keyCombo
        case .history:
            historyKeyCombo = keyCombo
        case .snippet:
            snippetKeyCombo = keyCombo
        case .secure:
            secureKeyCombo = keyCombo
        }
        register(with: type, keyCombo: keyCombo)
    }

    func changeClearHistoryKeyCombo(_ keyCombo: KeyCombo?) {
        clearHistoryKeyCombo = keyCombo
        AppEnvironment.current.defaults.set(keyCombo?.archive(), forKey: Constants.HotKey.clearHistoryKeyCombo)
        // Reset hotkey
        HotKeyCenter.shared.unregisterHotKey(with: "ClearHistory")
        // Register new hotkey
        guard let keyCombo = keyCombo else { return }
        let hotkey = HotKey(identifier: "ClearHistory", keyCombo: keyCombo, target: self, action: #selector(HotKeyService.popUpClearHistoryAlert))
        hotkey.register()
    }

    private func savedKeyCombo(forKey key: String) -> KeyCombo? {
        guard let data = AppEnvironment.current.defaults.object(forKey: key) as? Data else { return nil }
        guard let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        unarchiver.requiresSecureCoding = false
        return unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey) as? KeyCombo
    }
}

// MARK: - Register
private extension HotKeyService {
    func register(with type: MenuType, keyCombo: KeyCombo?) {
        save(with: type, keyCombo: keyCombo)
        // Reset hotkey
        HotKeyCenter.shared.unregisterHotKey(with: type.rawValue)
        // Register new hotkey
        guard let keyCombo = keyCombo else { return }
        let hotKey = HotKey(identifier: type.rawValue, keyCombo: keyCombo, target: self, action: type.hotKeySelector)
        hotKey.register()
    }

    func save(with type: MenuType, keyCombo: KeyCombo?) {
        AppEnvironment.current.defaults.set(keyCombo?.archive(), forKey: type.userDefaultsKey)
    }
}

// MARK: - Migration
private extension HotKeyService {
    /**
     *  Migration for changing the storage with v1.1.0
     *  Changed framework, PTHotKey to Magnet
     */
    func migrationKeyCombos() {
        guard let keyCombos = AppEnvironment.current.defaults.object(forKey: Constants.UserDefaults.hotKeys) as? [String: Any] else { return }

        // Main menu
        if let (keyCode, modifiers) = parse(with: keyCombos, forKey: Constants.Menu.clip) {
            if let keyCombo = KeyCombo(QWERTYKeyCode: keyCode, carbonModifiers: modifiers) {
                AppEnvironment.current.defaults.set(keyCombo.archive(), forKey: Constants.HotKey.mainKeyCombo)
            }
        }
        // History menu
        if let (keyCode, modifiers) = parse(with: keyCombos, forKey: Constants.Menu.history) {
            if let keyCombo = KeyCombo(QWERTYKeyCode: keyCode, carbonModifiers: modifiers) {
                AppEnvironment.current.defaults.set(keyCombo.archive(), forKey: Constants.HotKey.historyKeyCombo)
            }
        }
        // Snippet menu
        if let (keyCode, modifiers) = parse(with: keyCombos, forKey: Constants.Menu.snippet) {
            if let keyCombo = KeyCombo(QWERTYKeyCode: keyCode, carbonModifiers: modifiers) {
                AppEnvironment.current.defaults.set(keyCombo.archive(), forKey: Constants.HotKey.snippetKeyCombo)
            }
        }
    }

    func parse(with keyCombos: [String: Any], forKey key: String) -> (Int, Int)? {
        guard let combos = keyCombos[key] as? [String: Any] else { return nil }
        guard let keyCode = combos["keyCode"] as? Int, let modifiers = combos["modifiers"] as? Int else { return nil }
        return (keyCode, modifiers)
    }
}

// MARK: - Snippet HotKey
extension HotKeyService {
    private var folderKeyCombos: [String: KeyCombo]? {
        get {
            guard let data = AppEnvironment.current.defaults.object(forKey: Constants.HotKey.folderKeyCombos) as? Data else { return nil }
            guard let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
            unarchiver.requiresSecureCoding = false
            return unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey) as? [String: KeyCombo]
        }
        set {
            if let value = newValue,
               let data = try? NSKeyedArchiver.archivedData(withRootObject: value, requiringSecureCoding: false) {
                AppEnvironment.current.defaults.set(data, forKey: Constants.HotKey.folderKeyCombos)
            } else {
                AppEnvironment.current.defaults.removeObject(forKey: Constants.HotKey.folderKeyCombos)
            }
        }
    }

    func snippetKeyCombo(forIdentifier identifier: String) -> KeyCombo? {
        return folderKeyCombos?[identifier]
    }

    func registerSnippetHotKey(with identifier: String, keyCombo: KeyCombo) {
        // Reset hotkey
        unregisterSnippetHotKey(with: identifier)
        // Register new hotkey
        let hotKey = HotKey(identifier: identifier, keyCombo: keyCombo, target: self, action: #selector(HotKeyService.popupSnippetFolder(_:)))
        hotKey.register()
        // Save key combos
        var keyCombos = folderKeyCombos ?? [String: KeyCombo]()
        keyCombos[identifier] = keyCombo
        folderKeyCombos = keyCombos
    }

    func unregisterSnippetHotKey(with identifier: String) {
        // Unregister
        HotKeyCenter.shared.unregisterHotKey(with: identifier)
        // Save key combos
        var keyCombos = folderKeyCombos ?? [String: KeyCombo]()
        keyCombos.removeValue(forKey: identifier)
        folderKeyCombos = keyCombos
    }

    @objc func popupSnippetFolder(_ object: AnyObject) {
        guard let hotKey = object as? HotKey else { return }
        // 暗号鍵が使えないときはフォルダを読めない。ここで「削除された」と誤判定して
        // ホットキーの割り当てを消してしまわないよう、何もせずに戻る
        guard AppEnvironment.current.isLibraryUsable else { return }
        guard let folder = AppEnvironment.current.snippetStore.folder(id: hotKey.identifier) else {
            // When already deleted folder, remove keycombos
            unregisterSnippetHotKey(with: hotKey.identifier)
            return
        }
        if !folder.enable { return }

        AppEnvironment.current.menuManager.popUpSnippetFolder(folder)
    }

    fileprivate func setupSnippetHotKeys() {
        folderKeyCombos?.forEach {
            let hotKey = HotKey(identifier: $0, keyCombo: $1, target: self, action: #selector(HotKeyService.popupSnippetFolder(_:)))
            hotKey.register()
        }
    }
}
