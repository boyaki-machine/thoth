import Foundation
import CryptoKit
import Quick
import Nimble
import RealmSwift
@testable import Thoth

// Realm → SwiftData の移行（LibraryMigrator）と、起動時の判断（LibraryProvider.makePrepared）。
//
// 移行元は MigrationFixture の定義どおりの Realm ファイルで、次の 2 通りを使う:
// - テスト中に同じ定義から作ったファイル
// - リポジトリに置いた固定のファイル（ThothTests/Fixtures/LibraryMigrationFixture.realm）。
//   RealmSwift 10.54.6 で一度だけ作ったもので、実際にディスクにある形式から読めることを押さえる
// 移行では Realm のファイルに 1 バイトも書き込まないこと、照合に失敗したら本番のストアを
// 作らないことも確かめる。テストごとに一時フォルダを作って後で消す。
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
        readSpecs()
        migrateSpecs()
        failureSpecs()
        providerSpecs()
    }

    // MARK: - Helpers

    static var realmURL: URL { directory.appendingPathComponent(LibraryProvider.realmFileName) }
    static var storeURL: URL { directory.appendingPathComponent(LibraryProvider.storeFileName) }

    static func sha256(of url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// 固定の Realm ファイルを一時フォルダへ写す（Realm はファイルの隣に .lock などを作るため）
    static func copyFixture(to url: URL) -> Bool {
        guard let source = Bundle(for: LibraryMigrationSpec.self)
            .url(forResource: "LibraryMigrationFixture", withExtension: "realm") else { return false }
        return (try? FileManager.default.copyItem(at: source, to: url)) != nil
    }

    // MARK: - Read

    private static func readSpecs() {
        describe("Realm の読み出し") {
            it("テスト中に作った暗号化 Realm から、定義どおりの全データを読める") {
                expect { try MigrationFixture.writeRealm(to: realmURL) }.toNot(throwError())
                let snapshot = try? LibraryMigrator.readRealm(at: realmURL, encryptionKey: MigrationFixture.realmKey)
                expect(snapshot) == MigrationFixture.snapshot
            }

            it("リポジトリに置いた固定の Realm ファイルから、定義どおりの全データを読める") {
                guard copyFixture(to: realmURL) else {
                    fail("固定の Realm ファイルがテストバンドルに無い（前提が崩れている）")
                    return
                }
                let snapshot = try? LibraryMigrator.readRealm(at: realmURL, encryptionKey: MigrationFixture.realmKey)
                expect(snapshot) == MigrationFixture.snapshot
            }

            it("暗号化されていない古い Realm も、鍵を渡したまま読める（鍵なしで開き直す）") {
                expect { try MigrationFixture.writeRealm(to: realmURL, key: nil) }.toNot(throwError())
                let snapshot = try? LibraryMigrator.readRealm(at: realmURL, encryptionKey: MigrationFixture.realmKey)
                expect(snapshot) == MigrationFixture.snapshot
            }

            it("鍵が違えば読めず、sourceUnreadable を投げる") {
                expect { try MigrationFixture.writeRealm(to: realmURL) }.toNot(throwError())
                expect { try LibraryMigrator.readRealm(at: realmURL, encryptionKey: Data(repeating: 9, count: 64)) }
                    .to(throwError(LibraryMigrator.Failure.sourceUnreadable))
            }

            it("読み出しても Realm のファイルは 1 バイトも変わらない") {
                guard copyFixture(to: realmURL), let before = sha256(of: realmURL) else {
                    fail("固定の Realm ファイルを用意できない（前提が崩れている）")
                    return
                }
                _ = try? LibraryMigrator.readRealm(at: realmURL, encryptionKey: MigrationFixture.realmKey)
                expect(sha256(of: realmURL)) == before
            }
        }
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
            it("初回起動（ストアなし・Realm あり）では移行し、移行の結果を返す。Realm は変わらない") {
                guard copyFixture(to: realmURL), let before = sha256(of: realmURL) else {
                    fail("固定の Realm ファイルを用意できない（前提が崩れている）")
                    return
                }
                let prepared = LibraryProvider.makePrepared(directory: directory, rootKey: rootKey,
                                                            realmKey: { MigrationFixture.realmKey })
                expect(prepared.availability) == .ready
                expect(prepared.migrationReport?.clipCount) == MigrationFixture.snapshot.clips.count
                expect(prepared.snippetStore.folders()) == MigrationFixture.snapshot.folders
                expect(sha256(of: realmURL)) == before
            }

            it("2 回目の起動では移行せず、Realm を読まない（前回の移行後の変更が残る）") {
                guard copyFixture(to: realmURL) else {
                    fail("固定の Realm ファイルを用意できない（前提が崩れている）")
                    return
                }
                var realmKeyCalls = 0
                let first = LibraryProvider.makePrepared(directory: directory, rootKey: rootKey,
                                                         realmKey: { realmKeyCalls += 1; return MigrationFixture.realmKey })
                first.snippetStore.saveFolder(SnippetFolderRecord(id: "after-migration", index: 99, title: "移行後に追加"))
                let second = LibraryProvider.makePrepared(directory: directory, rootKey: rootKey,
                                                          realmKey: { realmKeyCalls += 1; return MigrationFixture.realmKey })
                expect(second.migrationReport) == nil
                expect(realmKeyCalls) == 1
                expect(second.snippetStore.folder(id: "after-migration")?.title) == "移行後に追加"
            }

            it("新規インストール（ストアも Realm も無い）では、空のストアを作る") {
                let prepared = LibraryProvider.makePrepared(directory: directory, rootKey: rootKey, realmKey: { nil })
                expect(prepared.availability) == .ready
                expect(prepared.historyStore.isEmpty) == true
                expect(FileManager.default.fileExists(atPath: storeURL.path)) == true
            }

            it("鍵が無ければ、メモリ上だけで動き、ディスクには何も作らない") {
                let prepared = LibraryProvider.makePrepared(directory: directory, rootKey: nil, realmKey: { nil })
                expect(prepared.availability) == .keyUnavailable
                prepared.historyStore.upsert(LibraryStoreContract.clip("c1", time: 1))
                expect(prepared.historyStore.clip(id: "c1")?.id) == "c1"
                expect((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).to(beEmpty())
            }

            it("別の鍵で保存されたストアなら keyMismatch で、ストアは消さずに残す") {
                _ = LibraryProvider.makePrepared(directory: directory, rootKey: rootKey, realmKey: { nil })
                    .snippetStore.saveFolder(SnippetFolderRecord(id: "f1", index: 0, title: "keep"))
                let prepared = LibraryProvider.makePrepared(directory: directory, rootKey: Data(repeating: 0x7F, count: 32),
                                                            realmKey: { nil })
                expect(prepared.availability) == .keyMismatch
                let reopened = LibraryProvider.makePrepared(directory: directory, rootKey: rootKey, realmKey: { nil })
                expect(reopened.snippetStore.folder(id: "f1")?.title) == "keep"
            }

            it("完了の印が無いストア（移行の途中で止まったもの）は、消して Realm から移行し直す") {
                guard copyFixture(to: realmURL) else {
                    fail("固定の Realm ファイルを用意できない（前提が崩れている）")
                    return
                }
                // 前回の起動で、照合に失敗して印の無いストアが残った状態を作る
                autoreleasepool {
                    _ = try? LibraryMigrator.migrate(LibraryMigrator.Snapshot.empty, to: storeURL, cipher: cipher,
                                                     verifier: { _, _, _ in "interrupted" })
                }
                expect(FileManager.default.fileExists(atPath: storeURL.path)) == true
                let prepared = autoreleasepool {
                    LibraryProvider.makePrepared(directory: directory, rootKey: rootKey, realmKey: { MigrationFixture.realmKey })
                }
                expect(prepared.availability) == .ready
                expect(prepared.snippetStore.folders()) == MigrationFixture.snapshot.folders
            }

            it("完了の印があるのに開けないストアは、削除せず別名へ退避し、Realm から移行し直す") {
                guard copyFixture(to: realmURL) else {
                    fail("固定の Realm ファイルを用意できない（前提が崩れている）")
                    return
                }
                FileManager.default.createFile(atPath: storeURL.path, contents: Data("not a database".utf8))
                FileManager.default.createFile(atPath: LibraryMigrator.completionMarkerURL(for: storeURL).path, contents: Data())
                let prepared = LibraryProvider.makePrepared(directory: directory, rootKey: rootKey,
                                                            realmKey: { MigrationFixture.realmKey })
                expect(prepared.availability) == .ready
                expect(prepared.snippetStore.folders()) == MigrationFixture.snapshot.folders
                let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
                expect(names.contains { $0.hasPrefix("\(LibraryProvider.storeFileName).broken-") }) == true
            }

            it("Realm の鍵が違って移行できなければ migrationFailed で、ストアを作らない") {
                guard copyFixture(to: realmURL) else {
                    fail("固定の Realm ファイルを用意できない（前提が崩れている）")
                    return
                }
                let prepared = LibraryProvider.makePrepared(directory: directory, rootKey: rootKey,
                                                            realmKey: { Data(repeating: 9, count: 64) })
                expect(prepared.availability) == .migrationFailed
                expect(FileManager.default.fileExists(atPath: storeURL.path)) == false
            }
        }
    }
}

// MARK: - Fixture

/// 移行のテストで使う Realm のデータ（境界値を集めたもの）
enum MigrationFixture {
    /// テスト用の Realm の鍵（64 バイト）
    static let realmKey = Data((0..<64).map { UInt8(($0 * 7 + 3) % 256) })

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

    /// snapshot を Realm のファイルとして書き出す（v1.4.x までのアプリと同じスキーマ）
    static func writeRealm(to url: URL, key: Data? = realmKey) throws {
        try autoreleasepool {
            var configuration = RealmProvider.makeBaseConfiguration()
            configuration.fileURL = url
            configuration.encryptionKey = key
            configuration.objectTypes = [CPYClip.self, CPYFolder.self, CPYSnippet.self]
            let realm = try Realm(configuration: configuration)
            try realm.write {
                for record in snapshot.clips {
                    let clip = CPYClip()
                    clip.dataHash = record.id
                    clip.dataPath = record.dataPath
                    clip.title = record.title
                    clip.primaryType = record.primaryType
                    clip.updateTime = record.updateTime
                    // v1.4.x までは PINCache のキー（コピーした時刻）を入れていた
                    clip.thumbnailPath = record.hasThumbnail ? "\(record.updateTime)" : ""
                    clip.isColorCode = record.isColorCode
                    realm.add(clip)
                }
                for record in snapshot.folders {
                    let folder = CPYFolder()
                    folder.identifier = record.id
                    folder.index = record.index
                    folder.enable = record.enable
                    folder.title = record.title
                    for snippetRecord in record.snippets {
                        let snippet = CPYSnippet()
                        snippet.identifier = snippetRecord.id
                        snippet.index = snippetRecord.index
                        snippet.enable = snippetRecord.enable
                        snippet.title = snippetRecord.title
                        snippet.content = snippetRecord.content
                        folder.snippets.append(snippet)
                    }
                    realm.add(folder)
                }
            }
        }
    }
}
