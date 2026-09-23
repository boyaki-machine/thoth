//
//  LegacyMigration.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Copyright © 2015-2018 Clipy Project.
//

import Foundation

/// Clipy から Thoth への改名に伴う、旧識別子で保存されたデータの一括移行。
///
/// 対象:
/// - UserDefaults（旧バンドル ID ドメイン → 現ドメインへコピー）
/// - Application Support フォルダ（~/Library/Application Support/Clipy → Thoth へ移動）
/// - ログイン項目（旧アプリ登録の引き継ぎ）
///
/// Keychain（セキュアアイテム・DB 暗号鍵）の移行は、それぞれ
/// `SecureMenuService` / `RealmProvider` が読み出し時に旧サービス名へ
/// フォールバックする形で行う（このファイルでは扱わない）。
///
/// アプリ起動の最初期（他のサービスが UserDefaults やデータフォルダに
/// 触れる前）に一度だけ実行すること。旧ドメイン・旧 Keychain エントリは
/// ロールバックに備えて削除せず残す。
enum LegacyMigration {

    #if DEBUG
    private static let legacyBundleIdentifier = "com.clipy-app.Clipy.debug"
    #else
    private static let legacyBundleIdentifier = "com.clipy-app.Clipy"
    #endif

    /// 移行完了マーカー（現ドメイン側に記録し、二重実行を防ぐ）
    private static let migratedMarkerKey = "kCPYMigratedFromClipy"

    static func migrateIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: migratedMarkerKey) else { return }
        let migratedDefaults = migrateUserDefaults(into: defaults)
        migrateApplicationSupportFolder()
        if migratedDefaults {
            refreshLoginItemIfNeeded(defaults: defaults)
        }
        defaults.set(true, forKey: migratedMarkerKey)
        NSLog("[LegacyMigration] migration from Clipy identifiers completed")
    }

    /// 旧バンドル ID ドメインの UserDefaults を現ドメインへコピーする。
    /// 現ドメインに既に値があるキーは上書きしない（新環境での設定を優先）。
    /// 旧ドメインはバックアップとして残す
    @discardableResult
    private static func migrateUserDefaults(into defaults: UserDefaults) -> Bool {
        guard let legacyDomain = defaults.persistentDomain(forName: legacyBundleIdentifier),
              !legacyDomain.isEmpty else { return false }
        for (key, value) in legacyDomain where defaults.object(forKey: key) == nil {
            defaults.set(value, forKey: key)
        }
        NSLog("[LegacyMigration] migrated \(legacyDomain.count) user defaults keys from \(legacyBundleIdentifier)")
        return true
    }

    /// ~/Library/Application Support/Clipy(DEBUG) を Thoth(DEBUG) へ移動する。
    /// Realm データベース・クリップ .data ファイルが含まれる。
    /// 新フォルダが既に存在する場合は何もしない（新環境のデータを優先）
    private static func migrateApplicationSupportFolder() {
        let fileManager = FileManager.default
        guard let basePath = NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory, .userDomainMask, true).first else { return }
        let newPath = (basePath as NSString).appendingPathComponent(Constants.Application.name)
        let legacyPath = (basePath as NSString).appendingPathComponent(Constants.Application.legacyName)
        guard !fileManager.fileExists(atPath: newPath), fileManager.fileExists(atPath: legacyPath) else { return }
        do {
            try fileManager.moveItem(atPath: legacyPath, toPath: newPath)
            NSLog("[LegacyMigration] moved Application Support folder: \(legacyPath) -> \(newPath)")
        } catch {
            NSLog("[LegacyMigration] failed to move Application Support folder: \(error)")
        }
    }

    /// ログイン項目が有効だった場合、新しいアプリ（Thoth.app）で登録し直す。
    /// 旧 Clipy.app の登録は macOS 側でバンドル消失時に無効化されるため放置してよい
    private static func refreshLoginItemIfNeeded(defaults: UserDefaults) {
        guard defaults.bool(forKey: Constants.UserDefaults.loginItem) else { return }
        LoginItemService.register()
        NSLog("[LegacyMigration] re-registered login item for renamed app")
    }
}
