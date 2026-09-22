//
//  LibraryMigrator.swift
//
//  Thoth
//  GitHub: https://github.com/boyaki-machine/Thoth
//

import Foundation
import RealmSwift
import SwiftData

/// 履歴・スニペットの Realm → SwiftData 移行（v1.5.x の初回起動で 1 回だけ）。
///
/// 1. Realm を**読み取り専用**で開き、全件を値型に読み出す（Realm のファイルには書き込まない）
/// 2. 本番の場所に新しいストアを作って書き込む
/// 3. 新しい ModelContext で読み直して、件数・全項目・並び順を照合する
/// 4. 照合に通ったときだけ、ストアの隣に**完了の印**（`<ストア名>.ready`）を書く
///
/// 完了の印が無いストアは「移行が途中で止まったもの」で、利用者のデータは入っていない
/// （アプリは印のあるストアしか使わない）。次回起動時に開く前に消してやり直す。
/// 一時ファイルに書いてから移す方式にしないのは、SwiftData にはストアを閉じる手段が無く、
/// 開いたことのあるファイルを動かすと SQLite が壊れる（SQLITE_IOERR_VNODE）ため。
/// Realm のファイルは v1.6.x まで残し、旧版へ戻せるようにする。
enum LibraryMigrator {

    /// 移行元から読み出した全データ（履歴の id は Realm の内容ハッシュのまま）
    struct Snapshot: Equatable {
        var clips: [ClipRecord]
        var folders: [SnippetFolderRecord]

        static let empty = Snapshot(clips: [], folders: [])

        var snippetCount: Int {
            return folders.reduce(0) { $0 + $1.snippets.count }
        }
    }

    struct Report: Equatable {
        var clipCount: Int
        var folderCount: Int
        var snippetCount: Int
        /// 参照先の .data ファイルが無かった履歴の数（移行前から同じ状態のため、記録だけ残す）
        var missingDataFiles: Int
        /// 旧版でサムネイルがあった履歴（移行後の id）。移行後に .data から作り直す
        var clipIDsNeedingThumbnail: [String]
    }

    enum Failure: Error, Equatable {
        case sourceUnreadable
        case verificationFailed(String)
        /// 移す先にストアのファイルが既にある（消さずに中止する。呼び出し側が先に退避すること）
        case destinationExists
    }

    /// StoreMeta に移行の記録を書くときのキー
    static let metaKey = "migration"

    // MARK: - Read Realm

    /// Realm のファイルを読み取り専用で開き、全件を値型に読み出す。
    /// 暗号化されていない古いファイルにも対応するため、鍵あり → 鍵なしの順で試す
    static func readRealm(at fileURL: URL, encryptionKey: Data?) throws -> Snapshot {
        let keys: [Data?] = encryptionKey.map { [$0, nil] } ?? [nil]
        for key in keys {
            let snapshot: Snapshot? = autoreleasepool {
                var configuration = RealmProvider.makeBaseConfiguration()
                configuration.fileURL = fileURL
                configuration.readOnly = true
                configuration.encryptionKey = key
                configuration.objectTypes = [CPYClip.self, CPYFolder.self, CPYSnippet.self]
                guard let realm = try? Realm(configuration: configuration) else { return nil }
                let clips = realm.objects(CPYClip.self)
                    .sorted(byKeyPath: #keyPath(CPYClip.updateTime), ascending: true)
                    .map(ClipRecord.init)
                let folders = realm.objects(CPYFolder.self)
                    .sorted(byKeyPath: #keyPath(CPYFolder.index), ascending: true)
                    .map(SnippetFolderRecord.init)
                return Snapshot(clips: Array(clips), folders: Array(folders))
            }
            if let snapshot = snapshot { return snapshot }
        }
        throw Failure.sourceUnreadable
    }

    // MARK: - Migrate

    /// 照合に使う関数（テストから差し替えて、照合に失敗したときの挙動を確かめる）
    typealias Verifier = (_ expected: Snapshot, _ cipher: FieldCipher, _ library: SwiftDataLibrary) -> String?

    struct Migrated {
        let report: Report
        /// 移行したストア。開き直さずにそのまま使う（同じファイルに 2 つ目のコンテナを作らない）
        let library: SwiftDataLibrary
    }

    /// snapshot を storeURL に新しいストアとして書き込み、照合に通ったら完了の印を書く。
    /// storeURL にストアのファイルが既にあれば、消さずに中止する（呼び出し側が先に片付けること）
    @discardableResult
    static func migrate(_ snapshot: Snapshot, to storeURL: URL, cipher: FieldCipher,
                        verifier: Verifier = verify) throws -> Migrated {
        let fileManager = FileManager.default
        guard !storeFiles(at: storeURL).contains(where: { fileManager.fileExists(atPath: $0.path) }),
              !fileManager.fileExists(atPath: completionMarkerURL(for: storeURL).path) else {
            throw Failure.destinationExists
        }
        try fileManager.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let library = try SwiftDataLibrary.open(at: storeURL, cipher: cipher)
        write(snapshot, into: library)
        // 書いたときの ModelContext とは別の、新しい ModelContext で読み直して照合する
        let reader = SwiftDataLibrary(container: library.container, cipher: cipher)
        if let problem = verifier(snapshot, cipher, reader) {
            throw Failure.verificationFailed(problem)
        }
        try writeCompletionMarker(for: storeURL)
        let missing = snapshot.clips.filter { !fileManager.fileExists(atPath: $0.dataPath) }.count
        let needingThumbnail = snapshot.clips.filter(\.hasThumbnail).map { cipher.contentID(for: $0.id) }
        let report = Report(clipCount: snapshot.clips.count, folderCount: snapshot.folders.count,
                            snippetCount: snapshot.snippetCount, missingDataFiles: missing,
                            clipIDsNeedingThumbnail: needingThumbnail)
        return Migrated(report: report, library: library)
    }

    // MARK: - Completion Marker

    /// 移行（または新規作成）が完了したことを示す印のファイル
    static func completionMarkerURL(for storeURL: URL) -> URL {
        return storeURL.appendingPathExtension("ready")
    }

    private static func writeCompletionMarker(for storeURL: URL) throws {
        let body = "Thoth library store ready. Created: \(ISO8601DateFormatter().string(from: Date()))\n"
        try Data(body.utf8).write(to: completionMarkerURL(for: storeURL), options: .atomic)
    }

    /// 移行後の履歴（id を鍵付きハッシュに置き換えたもの）。
    /// サムネイルは旧キャッシュから移さず、移行後に .data から作り直すので、この時点では無し
    static func expectedClips(_ snapshot: Snapshot, cipher: FieldCipher) -> [ClipRecord] {
        return snapshot.clips.map { clip in
            var migrated = clip
            migrated.id = cipher.contentID(for: clip.id)
            migrated.hasThumbnail = false
            return migrated
        }
    }

    /// 移行先が snapshot と一致するか照合する。
    /// - Returns: 食い違いがあればその説明。一致すれば nil
    static func verify(_ expected: Snapshot, cipher: FieldCipher, in library: SwiftDataLibrary) -> String? {
        let clips = SwiftDataHistoryStore(library: library).clips(ascending: true)
        let expectedClips = expectedClips(expected, cipher: cipher)
        guard clips.count == expectedClips.count else {
            return "履歴の件数が違う（期待 \(expectedClips.count) / 実際 \(clips.count)）"
        }
        let clipsByID = Dictionary(clips.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for clip in expectedClips where clipsByID[clip.id] != clip {
            return "履歴の中身が違う（updateTime \(clip.updateTime)）"
        }

        let folders = SwiftDataSnippetStore(library: library).folders()
        guard folders.count == expected.folders.count else {
            return "フォルダの件数が違う（期待 \(expected.folders.count) / 実際 \(folders.count)）"
        }
        let foldersByID = Dictionary(folders.map { ($0.id, normalized($0)) }, uniquingKeysWith: { first, _ in first })
        for folder in expected.folders where foldersByID[folder.id] != normalized(folder) {
            return "フォルダまたはスニペットの中身・並び順が違う（フォルダ番号 \(folder.index)）"
        }

        guard let meta = migrationRecord(in: library),
              meta.sourceClipCount == expected.clips.count,
              meta.sourceFolderCount == expected.folders.count,
              meta.sourceSnippetCount == expected.snippetCount else {
            return "移行の記録が無い、または件数が違う"
        }
        return nil
    }

    // MARK: - Migration Record

    struct MigrationRecord: Equatable {
        var migratedAt: Date?
        var sourceClipCount: Int
        var sourceFolderCount: Int
        var sourceSnippetCount: Int
    }

    static func migrationRecord(in library: SwiftDataLibrary) -> MigrationRecord? {
        return library.perform { context in
            let key = metaKey
            var descriptor = FetchDescriptor<StoreMeta>(predicate: #Predicate { $0.key == key })
            descriptor.fetchLimit = 1
            guard let meta = (try? context.fetch(descriptor))?.first else { return nil }
            return MigrationRecord(migratedAt: meta.migratedAt, sourceClipCount: meta.sourceClipCount,
                                   sourceFolderCount: meta.sourceFolderCount, sourceSnippetCount: meta.sourceSnippetCount)
        }
    }

    // MARK: - Private

    /// 書き込みの失敗は保存層の中で記録されるだけなので、書いたあとに照合で確かめる
    private static func write(_ snapshot: Snapshot, into library: SwiftDataLibrary) {
        SwiftDataHistoryStore(library: library).importClips(expectedClips(snapshot, cipher: library.cipher))
        SwiftDataSnippetStore(library: library).importFolders(snapshot.folders)
        library.write(notifying: library) { context in
            context.insert(StoreMeta(key: metaKey, migratedAt: Date(),
                                     sourceClipCount: snapshot.clips.count,
                                     sourceFolderCount: snapshot.folders.count,
                                     sourceSnippetCount: snapshot.snippetCount))
        }
    }

    /// 照合用に、スニペットを番号 → id の順に並べ直す（番号が重なっていても比較できるように）
    private static func normalized(_ folder: SnippetFolderRecord) -> SnippetFolderRecord {
        var copy = folder
        copy.snippets.sort { ($0.index, $0.id) < ($1.index, $1.id) }
        return copy
    }

    /// ストア一式（本体・-wal・-shm・外部保存のフォルダ）のファイル。
    /// 外部保存のフォルダ名は、拡張子を除いたストア名から作られる（`.Thoth_SUPPORT`）
    static func storeFiles(at url: URL) -> [URL] {
        let directory = url.deletingLastPathComponent()
        let name = url.lastPathComponent
        let baseName = url.deletingPathExtension().lastPathComponent
        return [url,
                directory.appendingPathComponent(name + "-wal"),
                directory.appendingPathComponent(name + "-shm"),
                directory.appendingPathComponent(".\(baseName)_SUPPORT", isDirectory: true)]
    }

    /// ストア一式を消す。**開いていないストアにだけ使うこと**（開いたまま消すと SQLite が壊れる）
    static func removeStoreFiles(at url: URL) {
        storeFiles(at: url).forEach { try? FileManager.default.removeItem(at: $0) }
    }
}
