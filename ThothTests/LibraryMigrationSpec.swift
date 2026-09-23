import Foundation
import CryptoKit
import Quick
import Nimble
@testable import Thoth

// 保存層のストアの作成と照合（LibraryMigrator）と、起動時の判断（LibraryProvider.makePrepared）。
//
// v1.6.2 までは Realm からの移行も確かめていた。v1.6.3 で Realm を外したので、いまは
// - ストアの作成（照合に通ったら完了の印を書く・照合に失敗したら使わない）
// - 起動時の判断（新規インストール・2 回目の起動・鍵が無い / 合わない・途中で止まったストア・開けないストア）
// - 旧 Realm のファイル: 移行済みなら消し、未移行なら残してディスクに何も書かない
// を確かめる。テストごとに一時フォルダを作って後で消す。
class LibraryMigrationSpec: QuickSpec {

    private static var directory: URL!
    private static let cipher = FieldCipher(rootKey: Data((1...32).map { UInt8($0) }))!
    private static var rootKey: Data { Data((1...32).map { UInt8($0) }) }

    override class func spec() {
        beforeEach {
            directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("ThothMigration-\(UUID().uuidString)", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        afterEach {
            try? FileManager.default.removeItem(at: directory)
        }
        migrateSpecs()
        failureSpecs()
        providerSpecs()
        legacyRealmSpecs()
    }

    // MARK: - Helpers

    static var realmURL: URL { directory.appendingPathComponent(LibraryProvider.realmFileName) }
    static var storeURL: URL { directory.appendingPathComponent(LibraryProvider.storeFileName) }

    static func sha256(of url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// v1.5.x 以降で移行した Mac に残っている、旧 Realm のファイル一式を置く（中身は何でもよい）
    static let legacyRealmNames = ["default.realm", "default.realm.lock", "default.realm.note",
                                   "default.realm.backup-log", "default.v20.backup.realm"]

    static func placeLegacyRealmFiles() {
        for name in legacyRealmNames {
            FileManager.default.createFile(atPath: directory.appendingPathComponent(name).path, contents: Data("realm \(name)".utf8))
        }
        try? FileManager.default.createDirectory(at: directory.appendingPathComponent("default.realm.management"),
                                                 withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: directory.appendingPathComponent("default.realm.management/access").path, contents: Data())
    }

    static func existingNames() -> Set<String> {
        return Set((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
    }

    // MARK: - Migrate

    private static func migrateSpecs() {
        describe("移行") {
            it("移行すると、全データが同じ中身で読め、履歴の id は鍵付きハッシュになる") {
                guard let migrated = try? LibraryMigrator.migrate(MigrationFixture.snapshot, to: storeURL, cipher: cipher) else {
                    fail("移行できない")
                    return
                }
                expect(migrated.report.clipCount) == MigrationFixture.snapshot.clips.count
                expect(migrated.report.folderCount) == MigrationFixture.snapshot.folders.count
                expect(migrated.report.snippetCount) == MigrationFixture.snapshot.snippetCount

                let library = migrated.library
                let expectedClips = LibraryMigrator.expectedClips(MigrationFixture.snapshot, cipher: cipher)
                expect(SwiftDataHistoryStore(library: library).clips(ascending: true)) == expectedClips
                expect(SwiftDataSnippetStore(library: library).folders()) == MigrationFixture.snapshot.folders
                expect(Set(expectedClips.map(\.id)).intersection(MigrationFixture.snapshot.clips.map(\.id))).to(beEmpty())
                expect(LibraryMigrator.migrationRecord(in: library)?.sourceSnippetCount) == MigrationFixture.snapshot.snippetCount
            }

            it("旧版でサムネイルがあった履歴を、作り直す対象として移行後の id で返す") {
                let migrated = try? LibraryMigrator.migrate(MigrationFixture.snapshot, to: storeURL, cipher: cipher)
                let expected = MigrationFixture.snapshot.clips.filter(\.hasThumbnail).map { cipher.contentID(for: $0.id) }
                expect(expected.count) == 2
                expect(migrated?.report.clipIDsNeedingThumbnail) == expected
            }

            it("移行すると、照合に通ったあとで完了の印が書かれる") {
                expect(FileManager.default.fileExists(atPath: LibraryMigrator.completionMarkerURL(for: storeURL).path)) == false
                _ = try? LibraryMigrator.migrate(MigrationFixture.snapshot, to: storeURL, cipher: cipher)
                expect(FileManager.default.fileExists(atPath: LibraryMigrator.completionMarkerURL(for: storeURL).path)) == true
            }

            it("照合は、中身が 1 項目でも違えばその説明を返す") {
                guard let library = try? SwiftDataLibrary.inMemory(cipher: cipher) else {
                    fail("保存層を作れない（前提が崩れている）")
                    return
                }
                var altered = MigrationFixture.snapshot
                altered.folders[0].snippets[0].content += "!"
                SwiftDataHistoryStore(library: library).importClips(LibraryMigrator.expectedClips(altered, cipher: cipher))
                SwiftDataSnippetStore(library: library).importFolders(altered.folders)
                expect(LibraryMigrator.verify(MigrationFixture.snapshot, cipher: cipher, in: library)) != nil
            }
        }
    }

    // MARK: - Failure

    private static func failureSpecs() {
        describe("移行に失敗したとき") {
            it("照合に失敗すると投げ、完了の印を書かない（そのストアは使われない）") {
                expect {
                    try LibraryMigrator.migrate(MigrationFixture.snapshot, to: storeURL, cipher: cipher,
                                                verifier: { _, _, _ in "injected mismatch" })
                }.to(throwError(LibraryMigrator.Failure.verificationFailed("injected mismatch")))
                expect(FileManager.default.fileExists(atPath: LibraryMigrator.completionMarkerURL(for: storeURL).path)) == false
            }

            it("移す先にファイルが残っていれば、消さずに中止する") {
                FileManager.default.createFile(atPath: storeURL.path + "-wal", contents: Data("keep me".utf8))
                expect { try LibraryMigrator.migrate(MigrationFixture.snapshot, to: storeURL, cipher: cipher) }
                    .to(throwError(LibraryMigrator.Failure.destinationExists))
                expect(try? String(contentsOfFile: storeURL.path + "-wal", encoding: .utf8)) == "keep me"
            }
        }
    }

    // MARK: - Provider

    private static func providerSpecs() {
        describe("起動時の判断") {
            it("新規インストール（ストアも旧 Realm も無い）では、空のストアを作り、完了の印を書く") {
                let prepared = LibraryProvider.makePrepared(directory: directory, rootKey: rootKey)
                expect(prepared.availability) == .ready
                expect(prepared.historyStore.isEmpty) == true
                expect(FileManager.default.fileExists(atPath: storeURL.path)) == true
                expect(FileManager.default.fileExists(atPath: LibraryMigrator.completionMarkerURL(for: storeURL).path)) == true
            }

            it("2 回目の起動では作り直さず、前回の変更が残る") {
                let first = LibraryProvider.makePrepared(directory: directory, rootKey: rootKey)
                first.snippetStore.saveFolder(SnippetFolderRecord(id: "kept", index: 99, title: "前回追加"))
                let second = LibraryProvider.makePrepared(directory: directory, rootKey: rootKey)
                expect(second.migrationReport) == nil
                expect(second.snippetStore.folder(id: "kept")?.title) == "前回追加"
            }

            it("鍵が無ければ、メモリ上だけで動き、ディスクには何も作らない") {
                let prepared = LibraryProvider.makePrepared(directory: directory, rootKey: nil)
                expect(prepared.availability) == .keyUnavailable
                prepared.historyStore.upsert(LibraryStoreContract.clip("c1", time: 1))
                expect(prepared.historyStore.clip(id: "c1")?.id) == "c1"
                expect(existingNames()).to(beEmpty())
            }

            it("別の鍵で保存されたストアなら keyMismatch で、ストアは消さずに残す") {
                _ = LibraryProvider.makePrepared(directory: directory, rootKey: rootKey)
                    .snippetStore.saveFolder(SnippetFolderRecord(id: "f1", index: 0, title: "keep"))
                let prepared = LibraryProvider.makePrepared(directory: directory, rootKey: Data(repeating: 0x7F, count: 32))
                expect(prepared.availability) == .keyMismatch
                let reopened = LibraryProvider.makePrepared(directory: directory, rootKey: rootKey)
                expect(reopened.snippetStore.folder(id: "f1")?.title) == "keep"
            }

            it("完了の印が無いストア（作成の途中で止まったもの）は、消して作り直す") {
                // 前回の起動で、照合に失敗して印の無いストアが残った状態を作る
                autoreleasepool {
                    _ = try? LibraryMigrator.migrate(MigrationFixture.snapshot, to: storeURL, cipher: cipher,
                                                     verifier: { _, _, _ in "interrupted" })
                }
                expect(FileManager.default.fileExists(atPath: storeURL.path)) == true
                let prepared = autoreleasepool { LibraryProvider.makePrepared(directory: directory, rootKey: rootKey) }
                expect(prepared.availability) == .ready
                // 印の無いストアの中身（途中まで書いたもの）は使わない
                expect(prepared.snippetStore.folders()).to(beEmpty())
            }

            it("完了の印があるのに開けないストアは、削除せず別名へ退避して作り直す") {
                FileManager.default.createFile(atPath: storeURL.path, contents: Data("not a database".utf8))
                FileManager.default.createFile(atPath: LibraryMigrator.completionMarkerURL(for: storeURL).path, contents: Data())
                let prepared = LibraryProvider.makePrepared(directory: directory, rootKey: rootKey)
                expect(prepared.availability) == .ready
                expect(existingNames().contains { $0.hasPrefix("\(LibraryProvider.storeFileName).broken-") }) == true
            }
        }
    }

    // MARK: - Legacy Realm files

    private static func legacyRealmSpecs() {
        describe("旧 Realm のファイル（v1.4.x までの保存先）") {
            it("移行済み（完了の印があるストアを読めた）なら、旧 Realm のファイル一式を消す") {
                _ = LibraryProvider.makePrepared(directory: directory, rootKey: rootKey)
                    .snippetStore.saveFolder(SnippetFolderRecord(id: "f1", index: 0, title: "移行後のデータ"))
                placeLegacyRealmFiles()
                expect(LibraryProvider.legacyRealmFiles(in: directory).count) == legacyRealmNames.count + 1

                let prepared = LibraryProvider.makePrepared(directory: directory, rootKey: rootKey)
                expect(prepared.availability) == .ready
                expect(LibraryProvider.legacyRealmFiles(in: directory)).to(beEmpty())
                // ストアと、移行後のデータは消さない
                expect(prepared.snippetStore.folder(id: "f1")?.title) == "移行後のデータ"
                expect(existingNames()).to(contain(LibraryProvider.storeFileName))
            }

            it("旧 Realm と名前が似ていても、別のファイル（ストア・.data など）は消さない") {
                _ = LibraryProvider.makePrepared(directory: directory, rootKey: rootKey)
                placeLegacyRealmFiles()
                let others = ["ABCD-1234.data", "my.default.realm.txt", "realm-notes.txt"]
                for name in others {
                    FileManager.default.createFile(atPath: directory.appendingPathComponent(name).path, contents: Data("keep".utf8))
                }
                _ = LibraryProvider.makePrepared(directory: directory, rootKey: rootKey)
                expect(existingNames().isSuperset(of: others)) == true
            }

            it("未移行（旧 Realm だけがある）なら、メモリ上だけで動き、旧ファイルも残してストアを作らない") {
                placeLegacyRealmFiles()
                let before = sha256(of: realmURL)
                let prepared = LibraryProvider.makePrepared(directory: directory, rootKey: rootKey)
                expect(prepared.availability) == .legacyDataNotMigrated
                expect(FileManager.default.fileExists(atPath: storeURL.path)) == false
                expect(sha256(of: realmURL)) == before
                // 次の起動でも「移行済み」と誤って判断して旧ファイルを消さない
                _ = LibraryProvider.makePrepared(directory: directory, rootKey: rootKey)
                expect(LibraryProvider.legacyRealmFiles(in: directory).count) == legacyRealmNames.count + 1
            }

            it("鍵が合わず移行済みのストアを読めないときは、旧 Realm のファイルを消さない") {
                // 空のストアはどの鍵でも「読める」ので、データを入れておく
                _ = LibraryProvider.makePrepared(directory: directory, rootKey: rootKey)
                    .snippetStore.saveFolder(SnippetFolderRecord(id: "f1", index: 0, title: "keep"))
                placeLegacyRealmFiles()
                let prepared = LibraryProvider.makePrepared(directory: directory, rootKey: Data(repeating: 0x7F, count: 32))
                expect(prepared.availability) == .keyMismatch
                expect(LibraryProvider.legacyRealmFiles(in: directory).count) == legacyRealmNames.count + 1
            }
        }
    }
}

// MARK: - Fixture

/// ストアの作成・照合のテストで使うデータ（境界値を集めたもの。v1.6.2 までは Realm からの移行にも使っていた）
enum MigrationFixture {

    static let snapshot = LibraryMigrator.Snapshot(
        clips: [
            clip("0", time: 1_000, title: ""),
            clip("-4611686018427387904", time: 1_001, title: String(repeating: "あ", count: 10_000)),
            clip("987654321", time: 1_002, title: "👨‍👩‍👧‍👦 家族\r\nCRLF 全角　スペース"),
            clip("-123", time: 1_003, title: "#FF0000", hasThumbnail: true, isColorCode: true),
            clip("555", time: 1_004, title: "", type: "NSTIFFPboardType", hasThumbnail: true),
            clip("666", time: 1_005, title: "/Users/tester/a.txt", type: "NSFilenamesPboardType"),
            // 「同じ内容を上書き」がオフのときは同じ内容でも別の id（乱数）で 2 件入る
            clip("111111", time: 1_006, title: "dup"),
            clip("222222", time: 1_007, title: "dup")
        ],
        folders: [
            SnippetFolderRecord(id: "F0000000-0000-0000-0000-000000000001", index: 0, title: "フォルダ 1", snippets: [
                SnippetRecord(id: "S0000000-0000-0000-0000-000000000001", index: 0, title: "a", content: "本文\r\n😀"),
                SnippetRecord(id: "S0000000-0000-0000-0000-000000000002", index: 2, enable: false, title: "b（無効）", content: "x"),
                SnippetRecord(id: "S0000000-0000-0000-0000-000000000003", index: 5, title: "", content: "")
            ]),
            SnippetFolderRecord(id: "F0000000-0000-0000-0000-000000000003", index: 1, title: ""),
            SnippetFolderRecord(id: "F0000000-0000-0000-0000-000000000002", index: 3, enable: false, title: "無効フォルダ", snippets: [
                SnippetRecord(id: "S0000000-0000-0000-0000-000000000004", index: 0, title: "d", content: String(repeating: "長", count: 5_000))
            ])
        ])

    private static func clip(_ id: String, time: Int, title: String, type: String = "NSStringPboardType",
                             hasThumbnail: Bool = false, isColorCode: Bool = false) -> ClipRecord {
        return ClipRecord(id: id, dataPath: "/Users/tester/Library/Application Support/Thoth/\(id).data", title: title,
                          primaryType: type, updateTime: time, hasThumbnail: hasThumbnail, isColorCode: isColorCode)
    }
}
