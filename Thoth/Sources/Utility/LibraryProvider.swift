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
/// - 移行済みのストアがあれば開く
/// - 無ければ Realm から移行する（LibraryMigrator。Realm のファイルには書き込まない）
/// - Realm も無ければ（新規インストール）空のストアを作る
///
/// ## 使えないとき
/// 暗号鍵が無い・合わない、移行に失敗した、のいずれかのときは、その起動中は
/// メモリ上だけの保存層で動き、**ディスクには何も書かない**。ストアの削除も、
/// 新しい鍵での上書きもしない（原因が解消すれば次の起動で元どおり読める）。
///
/// ## ストアの片付け（どちらも開く前に行う。開いたファイルを動かすと SQLite が壊れる）
/// - 完了の印（LibraryMigrator.completionMarkerURL）があるのに開けないストアは、削除せず別名へ退避する
/// - 完了の印が無いストアは移行の途中で止まったもので、利用者のデータは入っていないので消す
enum LibraryProvider {

    enum Availability: Equatable {
        case ready
        /// 暗号鍵をキーチェーンから読めない、またはまだ作れない
        case keyUnavailable
        /// 鍵は読めたが、保存済みのデータを復号できない
        case keyMismatch
        /// Realm からの移行に失敗した（次回起動時にやり直す）
        case migrationFailed
    }

    struct Prepared {
        let historyStore: HistoryStore
        let snippetStore: SnippetStore
        let availability: Availability
        /// この起動で移行したときの結果
        let migrationReport: LibraryMigrator.Report?
    }

    static let storeFileName = "Thoth.store"
    static let realmFileName = "default.realm"

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
                             rootKey: RealmProvider.appEncryptionKey(for: .clipData),
                             realmKey: { RealmProvider.appEncryptionKey(for: .realmDatabase) })
            }
            DispatchQueue.main.async {
                availability = prepared.availability
                isReady = true
                completion(prepared)
            }
        }
    }

    /// 起動時の判断の本体（場所と鍵を引数で受け取るので、テストから直接呼べる）
    /// - Parameters:
    ///   - rootKey: `.data` 用の鍵（FieldCipher の導出元）。読めなければ nil
    ///   - realmKey: Realm の鍵。移行するときだけ呼ぶ
    static func makePrepared(directory: URL, rootKey: Data?, realmKey: () -> Data?) -> Prepared {
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
                    return Prepared(historyStore: SwiftDataHistoryStore(library: library),
                                    snippetStore: SwiftDataSnippetStore(library: library),
                                    availability: .ready, migrationReport: nil)
                }
                // 完了していたのに開けない（壊れている）。削除せず別名へ退避して作り直す
                quarantine(storeURL)
                try? fileManager.removeItem(at: markerURL)
            } else {
                // 完了の印が無い＝移行が途中で止まったストア。利用者のデータは入っていないので消してやり直す
                NSLog("[LibraryProvider] removing an incomplete store left by an interrupted migration")
                LibraryMigrator.removeStoreFiles(at: storeURL)
            }
        }

        do {
            let snapshot = fileManager.fileExists(atPath: realmURL.path)
                ? try LibraryMigrator.readRealm(at: realmURL, encryptionKey: realmKey())
                : LibraryMigrator.Snapshot.empty
            let migrated = try LibraryMigrator.migrate(snapshot, to: storeURL, cipher: cipher)
            let report = migrated.report
            NSLog("[LibraryProvider] prepared store (clips: \(report.clipCount), folders: \(report.folderCount), snippets: \(report.snippetCount), missing .data: \(report.missingDataFiles))")
            return Prepared(historyStore: SwiftDataHistoryStore(library: migrated.library),
                            snippetStore: SwiftDataSnippetStore(library: migrated.library),
                            availability: .ready, migrationReport: report)
        } catch {
            NSLog("[LibraryProvider] migration failed: \(error); running in memory for this launch")
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
