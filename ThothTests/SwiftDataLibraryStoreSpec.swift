import Foundation
import Quick
import Nimble
@testable import Thoth

// SwiftData 版の保存層（SwiftDataHistoryStore / SwiftDataSnippetStore）。
//
// 保存層の契約（LibraryStoreContract）を Realm 版と同じ内容で通したうえで、
// SwiftData 版に固有の約束を確かめる:
// - ディスクに置いたファイル一式に、タイトル・本文・フォルダ名が平文で現れないこと
// - 閉じて開き直しても、同じ鍵なら元どおり読めること
// - 別の鍵で開いたときは読めない行を読み飛ばし、データを壊さないこと
// ファイルを使うテストは、テストごとに一時フォルダを作って後で消す。
class SwiftDataLibraryStoreSpec: QuickSpec {

    static let cipher = FieldCipher(rootKey: Data((1...32).map { UInt8($0) }))!
    static let otherCipher = FieldCipher(rootKey: Data(repeating: 0x7F, count: 32))!

    private static var directory: URL?

    /// テスト用の一時フォルダ内のストアの場所
    static func storeURL() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ThothTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        directory = dir
        return dir.appendingPathComponent("Thoth.store")
    }

    static func stores(_ library: SwiftDataLibrary) -> LibraryStoreContract.Stores {
        return (history: SwiftDataHistoryStore(library: library), snippets: SwiftDataSnippetStore(library: library))
    }

    override class func spec() {
        afterEach {
            if let dir = directory { try? FileManager.default.removeItem(at: dir) }
            directory = nil
        }
        LibraryStoreContract.specs {
            guard let library = try? SwiftDataLibrary.inMemory(cipher: cipher) else {
                fatalError("インメモリの保存層を作れない（前提が崩れている）")
            }
            return stores(library)
        }
        encryptionAtRestSpecs()
        persistenceSpecs()
        contentIDSpecs()
        concurrencySpecs()
    }

    // MARK: - Encryption at Rest

    private static func encryptionAtRestSpecs() {
        describe("保存時の暗号化") {
            it("ファイル一式にタイトル・本文・フォルダ名が平文で現れない（平文の列は現れる）") {
                let url = storeURL()
                guard let library = try? SwiftDataLibrary.open(at: url, cipher: cipher) else {
                    fail("ファイルの保存層を開けない（前提が崩れている）")
                    return
                }
                let (history, snippets) = stores(library)
                history.upsert(ClipRecord(id: "c1", dataPath: "/tmp/PLAIN-PATH-MARKER.data", title: "CLIP-TITLE-MARKER",
                                          primaryType: "PRIMARY-TYPE-MARKER", updateTime: 1,
                                          thumbnailPath: "", isColorCode: false))
                snippets.importFolders([SnippetFolderRecord(id: "f1", index: 0, title: "FOLDER-TITLE-MARKER", snippets: [
                    SnippetRecord(id: "s1", index: 0, title: "SNIPPET-TITLE-MARKER", content: "SNIPPET-CONTENT-MARKER")
                ])])

                let folder = url.deletingLastPathComponent()
                let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
                let bytes = files.compactMap { try? Data(contentsOf: $0) }.reduce(Data(), +)
                func contains(_ marker: String) -> Bool { bytes.range(of: Data(marker.utf8)) != nil }

                // 読んでいるファイルが正しいことの確認（平文の列はそのまま入っている）
                expect(contains("PLAIN-PATH-MARKER")) == true
                for marker in ["CLIP-TITLE-MARKER", "PRIMARY-TYPE-MARKER", "FOLDER-TITLE-MARKER",
                               "SNIPPET-TITLE-MARKER", "SNIPPET-CONTENT-MARKER"] {
                    expect(contains(marker)).to(beFalse(), description: "\(marker) が平文で見つかった")
                }
            }
        }
    }

    // MARK: - Persistence

    private static func persistenceSpecs() {
        describe("開き直し") {
            it("閉じて開き直しても、同じ鍵なら元どおり読める") {
                let url = storeURL()
                let clip = ClipRecord(id: "c1", dataPath: "/tmp/c1.data", title: "タイトル 😀", primaryType: "public.tiff",
                                      updateTime: 42, thumbnailPath: "42", isColorCode: true)
                let folder = SnippetFolderRecord(id: "f1", index: 0, title: "フォルダ", snippets: [
                    SnippetRecord(id: "s1", index: 0, title: "a", content: "本文\r\n"),
                    SnippetRecord(id: "s2", index: 1, enable: false, title: "b", content: "")
                ])
                autoreleasepool {
                    guard let library = try? SwiftDataLibrary.open(at: url, cipher: cipher) else { return }
                    let (history, snippets) = stores(library)
                    history.upsert(clip)
                    snippets.importFolders([folder])
                }
                guard let reopened = try? SwiftDataLibrary.open(at: url, cipher: cipher) else {
                    fail("開き直せない（前提が崩れている）")
                    return
                }
                let (history, snippets) = stores(reopened)
                expect(history.clip(id: "c1")) == clip
                expect(snippets.folders()) == [folder]
            }

            it("別の鍵で開くと、読めない行は読み飛ばされ、元の鍵で開けば読める（データは壊れない）") {
                let url = storeURL()
                autoreleasepool {
                    guard let library = try? SwiftDataLibrary.open(at: url, cipher: cipher) else { return }
                    let (history, snippets) = stores(library)
                    history.upsert(LibraryStoreContract.clip("c1", time: 1))
                    snippets.saveFolder(SnippetFolderRecord(id: "f1", index: 0, title: "folder"))
                }
                autoreleasepool {
                    guard let wrong = try? SwiftDataLibrary.open(at: url, cipher: otherCipher) else {
                        fail("別の鍵で開けない（前提が崩れている）")
                        return
                    }
                    let (history, snippets) = stores(wrong)
                    expect(history.clips(ascending: true)).to(beEmpty())
                    expect(snippets.folder(id: "f1")) == nil
                    // 行そのものは残っている（読めないだけで消していない）
                    expect(history.isEmpty) == false
                }
                guard let right = try? SwiftDataLibrary.open(at: url, cipher: cipher) else {
                    fail("元の鍵で開けない（前提が崩れている）")
                    return
                }
                let (history, snippets) = stores(right)
                expect(history.clip(id: "c1")?.title) == "title"
                expect(snippets.folder(id: "f1")?.title) == "folder"
            }
        }
    }

    // MARK: - Content ID

    private static func contentIDSpecs() {
        describe("履歴の id") {
            it("内容ハッシュをそのまま使わず、鍵付きハッシュ（64 桁の 16 進）にする") {
                guard let library = try? SwiftDataLibrary.inMemory(cipher: cipher) else {
                    fail("保存層を作れない（前提が崩れている）")
                    return
                }
                let id = SwiftDataHistoryStore(library: library).clipID(forContentHash: "12345")
                expect(id) == cipher.contentID(for: "12345")
                expect(id.count) == 64
                expect(id.contains("12345")) == false
            }
        }
    }

    // MARK: - Concurrency

    private static func concurrencySpecs() {
        describe("複数のスレッドからの利用") {
            it("複数のスレッドから同時に書き込み・読み出しをしても、すべて保存される") {
                guard let library = try? SwiftDataLibrary.inMemory(cipher: cipher) else {
                    fail("保存層を作れない（前提が崩れている）")
                    return
                }
                let history = SwiftDataHistoryStore(library: library)
                DispatchQueue.concurrentPerform(iterations: 40) { index in
                    history.upsert(LibraryStoreContract.clip("c\(index)", time: index))
                    _ = history.clips(ascending: false)
                }
                expect(history.clips(ascending: true).count) == 40
            }
        }
    }
}
