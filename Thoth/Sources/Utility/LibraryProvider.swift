//
//  LibraryProvider.swift
//
//  Thoth
//  GitHub: https://github.com/boyaki-machine/Thoth
//

import Foundation
import CryptoKit

/// 起動時に保存層（履歴・スニペット）を用意する。
///
/// - 完成したストア（完了の印あり）があれば開く
/// - 無ければ（新規インストール）空のストアを作る
///
/// ## Realm（v1.4.x までの保存先）について
/// v1.5.x〜v1.6.2 は初回起動で Realm から移行していた。v1.6.3 で Realm を外したので:
/// - 移行済み（ストアを開けて読めた）なら、残っている旧 Realm のファイルを消す（`removeLegacyRealmFiles`）。
///   移行した時点の履歴・スニペットの暗号化された写しが、消した後もディスクに残り続けないようにする
/// - 移行していない（旧 Realm のファイルだけがある）なら、読めないので、その起動中は
///   メモリ上だけで動き、旧ファイルもそのまま残す（`.legacyDataNotMigrated`）。空のストアを作ると、
///   次の起動で「移行済み」と判断して旧ファイルを消してしまうため作らない。v1.6.2 を一度起動すれば移行できる
///
/// ## 使えないとき
/// 暗号鍵が無い・合わない、旧 Realm のデータが移行されていない、のいずれかのときは、その起動中は
/// メモリ上だけの保存層で動き、**ディスクには何も書かない**。ストアの削除も、
/// 新しい鍵での上書きもしない（原因が解消すれば次の起動で元どおり読める）。
///
/// ## ストアの片付け（どちらも開く前に行う。開いたファイルを動かすと SQLite が壊れる）
/// - 完了の印（LibraryMigrator.completionMarkerURL）があるのに開けないストアは、削除せず別名へ退避する
/// - 完了の印が無いストアは作成の途中で止まったもので、利用者のデータは入っていないので消す
enum LibraryProvider {

    enum Availability: Equatable {
        case ready
        /// 暗号鍵をキーチェーンから読めない、またはまだ作れない
        case keyUnavailable
        /// 鍵は読めたが、保存済みのデータを復号できない
        case keyMismatch
        /// ストアを作れなかった（次回起動時にやり直す）
        case migrationFailed
        /// v1.4.x までの Realm のデータが移行されていない（v1.6.3 は Realm を読めない）
        case legacyDataNotMigrated
    }

    struct Prepared {
        let historyStore: HistoryStore
        let snippetStore: SnippetStore
        let availability: Availability
        /// この起動で移行したときの結果
        let migrationReport: LibraryMigrator.Report?
    }

    static let storeFileName = "Thoth.store"
    /// v1.4.x までの保存先（Realm）。移行済みなら消し、未移行なら残す
    static let realmFileName = "default.realm"
    /// v1.5.x が Realm 20 で開く前に取った、旧 Realm のバックアップ
    static let realmBackupFileName = "default.v20.backup.realm"

    /// 保存層の準備が済んだか（済むまでメニュー等は保存層に触れない）。メインスレッドからのみ使う
    private(set) static var isReady = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    private(set) static var availability = Availability.ready

    /// 準備が済むまでの間、および保存層を差し替えないテストで使う、メモリ上だけの保存層。
    /// 誤って触れても落ちず、ディスクにも書かない
    static let placeholder = makeEphemeral(availability: .ready)

    /// ストアと Realm のファイルを置く場所（Realm の既定と同じ ~/Library/Application Support/<バンドル ID>）
    static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent(Bundle.main.bundleIdentifier ?? "io.github.boyaki-machine.Thoth", isDirectory: true)
    }

    // MARK: - Prepare

    /// 保存層をバックグラウンドで用意し、メインスレッドで completion を呼ぶ
    static func prepare(completion: @escaping (Prepared) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let prepared = autoreleasepool {
                makePrepared(directory: defaultDirectory,
                             rootKey: AppKeyStore.appEncryptionKey(for: .clipData))
            }
            DispatchQueue.main.async {
                availability = prepared.availability
                isReady = true
                completion(prepared)
            }
        }
    }

    /// 起動時の判断の本体（場所と鍵を引数で受け取るので、テストから直接呼べる）
    /// - Parameter rootKey: `.data` 用の鍵（FieldCipher の導出元）。読めなければ nil
    static func makePrepared(directory: URL, rootKey: Data?) -> Prepared {
        guard let rootKey = rootKey, let cipher = FieldCipher(rootKey: rootKey) else {
            NSLog("[LibraryProvider] encryption key unavailable; running in memory for this launch")
            return makeEphemeral(availability: .keyUnavailable)
        }
        let storeURL = directory.appendingPathComponent(storeFileName)
        let realmURL = directory.appendingPathComponent(realmFileName)
        let markerURL = LibraryMigrator.completionMarkerURL(for: storeURL)
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: markerURL.path) && !fileManager.fileExists(atPath: storeURL.path) {
            // 印だけが残っている（ストアが消された）。作り直す
            try? fileManager.removeItem(at: markerURL)
        }
        if fileManager.fileExists(atPath: storeURL.path) {
            if fileManager.fileExists(atPath: markerURL.path) {
                if let library = try? SwiftDataLibrary.open(at: storeURL, cipher: cipher) {
                    guard library.isReadable else {
                        NSLog("[LibraryProvider] stored data cannot be decrypted with the current key; running in memory")
                        return makeEphemeral(availability: .keyMismatch)
                    }
                    // 移行済みで、いまのストアを読めることを確かめたので、旧 Realm のファイルを消す
                    removeLegacyRealmFiles(in: directory)
                    return Prepared(historyStore: SwiftDataHistoryStore(library: library),
                                    snippetStore: SwiftDataSnippetStore(library: library),
                                    availability: .ready, migrationReport: nil)
                }
                // 完了していたのに開けない（壊れている）。削除せず別名へ退避して作り直す
                quarantine(storeURL)
                try? fileManager.removeItem(at: markerURL)
            } else {
                // 完了の印が無い＝作成が途中で止まったストア。利用者のデータは入っていないので消してやり直す
                NSLog("[LibraryProvider] removing an incomplete store left by an interrupted creation")
                LibraryMigrator.removeStoreFiles(at: storeURL)
            }
        }

        if fileManager.fileExists(atPath: realmURL.path) {
            // 旧 Realm のデータが移行されていない。読めないので、空のストアも作らずメモリ上だけで動く
            NSLog("[LibraryProvider] legacy Realm data has not been migrated; run v1.6.2 once to migrate it")
            return makeEphemeral(availability: .legacyDataNotMigrated)
        }
        do {
            let migrated = try LibraryMigrator.migrate(.empty, to: storeURL, cipher: cipher)
            let report = migrated.report
            NSLog("[LibraryProvider] prepared store (clips: \(report.clipCount), folders: \(report.folderCount), snippets: \(report.snippetCount), missing .data: \(report.missingDataFiles))")
            return Prepared(historyStore: SwiftDataHistoryStore(library: migrated.library),
                            snippetStore: SwiftDataSnippetStore(library: migrated.library),
                            availability: .ready, migrationReport: report)
        } catch {
            NSLog("[LibraryProvider] could not create the store: \(error); running in memory for this launch")
            return makeEphemeral(availability: .migrationFailed)
        }
    }

    // MARK: - Private

    /// メモリ上だけの保存層（使い捨ての鍵）
    private static func makeEphemeral(availability: Availability) -> Prepared {
        let rootKey = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        // 32 バイトの鍵とメモリ上のコンテナなので失敗しない
        let library = try! SwiftDataLibrary.inMemory(cipher: FieldCipher(rootKey: rootKey)!)
        return Prepared(historyStore: SwiftDataHistoryStore(library: library),
                        snippetStore: SwiftDataSnippetStore(library: library),
                        availability: availability, migrationReport: nil)
    }

    /// 旧 Realm のファイル一式（本体・.lock・.note・.management・バックアップ）。
    /// 名前が `default.realm` で始まるものと、v1.5.x が取ったバックアップ
    static func legacyRealmFiles(in directory: URL) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names
            .filter { $0.hasPrefix(realmFileName) || $0.hasPrefix(realmBackupFileName) }
            .sorted()
            .map { directory.appendingPathComponent($0) }
    }

    /// 旧 Realm のファイルを消す。**移行済みのストアを読めた後にだけ呼ぶこと**
    static func removeLegacyRealmFiles(in directory: URL) {
        let files = legacyRealmFiles(in: directory)
        guard !files.isEmpty else { return }
        for file in files {
            try? FileManager.default.removeItem(at: file)
        }
        NSLog("[LibraryProvider] removed \(files.count) legacy Realm file(s) after confirming the migrated store")
    }

    /// 開けないストアを、削除せず別名へ退避する
    private static func quarantine(_ storeURL: URL) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let suffix = ".broken-\(formatter.string(from: Date()))"
        for file in LibraryMigrator.storeFiles(at: storeURL) where FileManager.default.fileExists(atPath: file.path) {
            let destination = file.deletingLastPathComponent().appendingPathComponent(file.lastPathComponent + suffix)
            try? FileManager.default.moveItem(at: file, to: destination)
        }
        NSLog("[LibraryProvider] moved an unreadable store aside (\(suffix))")
    }
}
