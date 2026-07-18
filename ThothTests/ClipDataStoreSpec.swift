import Quick
import Nimble
@testable import Thoth

/// クリップ .data ファイルの暗号化ストアのスペック。
/// 鍵はテスト専用のものを注入する（Keychain には触れない）。
class ClipDataStoreSpec: QuickSpec {
    override func spec() {
        var workDirectory: URL!
        let testKey = Data((0..<32).map { UInt8($0 &+ 7) })

        beforeEach {
            workDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("clipy-clipdata-test-\(UUID().uuidString)", isDirectory: true)
            try? FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        }
        afterEach {
            try? FileManager.default.removeItem(at: workDirectory)
        }

        func path(_ name: String) -> String {
            return workDirectory.appendingPathComponent(name).path
        }

        describe("Encrypted read/write") {

            it("Round-trips data through encryption") {
                let store = ClipDataStore(key: testKey)
                let original = Data("clip content 日本語".utf8)

                expect(store.write(original, toPath: path("clip.data"))) == true
                expect(store.read(fromPath: path("clip.data"))) == original
            }

            it("Writes the CLPYDAT magic and does not store plaintext") {
                let store = ClipDataStore(key: testKey)
                let original = Data("visible secret text".utf8)
                _ = store.write(original, toPath: path("clip.data"))

                let raw = try! Data(contentsOf: URL(fileURLWithPath: path("clip.data")))
                expect(raw.prefix(7)) == Data("CLPYDAT".utf8)
                expect(raw.range(of: original)).to(beNil())
            }

            it("Fails to read with a different key (GCM tag mismatch)") {
                let store = ClipDataStore(key: testKey)
                _ = store.write(Data("secret".utf8), toPath: path("clip.data"))

                let otherStore = ClipDataStore(key: Data((0..<32).map { UInt8($0 &+ 99) }))
                expect(otherStore.read(fromPath: path("clip.data"))).to(beNil())
            }

            it("Fails to read tampered ciphertext") {
                let store = ClipDataStore(key: testKey)
                _ = store.write(Data("secret".utf8), toPath: path("clip.data"))

                var raw = try! Data(contentsOf: URL(fileURLWithPath: path("clip.data")))
                raw[raw.count - 1] ^= 0x01
                try! raw.write(to: URL(fileURLWithPath: path("clip.data")))
                expect(store.read(fromPath: path("clip.data"))).to(beNil())
            }
        }

        describe("Legacy plaintext compatibility") {

            it("Reads a legacy plaintext file as-is") {
                let legacy = Data("legacy plaintext archive".utf8)
                try! legacy.write(to: URL(fileURLWithPath: path("legacy.data")))

                let store = ClipDataStore(key: testKey)
                expect(store.read(fromPath: path("legacy.data"))) == legacy
            }

            it("Falls back to plaintext write when no key is available") {
                let store = ClipDataStore(key: nil)
                let original = Data("no key data".utf8)
                expect(store.write(original, toPath: path("plain.data"))) == true

                let raw = try! Data(contentsOf: URL(fileURLWithPath: path("plain.data")))
                expect(raw) == original
                expect(store.read(fromPath: path("plain.data"))) == original
            }
        }

        describe("Plaintext sweep") {

            it("Encrypts existing plaintext .data files and skips encrypted ones") {
                let store = ClipDataStore(key: testKey)
                // 平文2つ + 暗号化済み1つ + 対象外拡張子1つ
                try! Data("plain-1".utf8).write(to: URL(fileURLWithPath: path("a.data")))
                try! Data("plain-2".utf8).write(to: URL(fileURLWithPath: path("b.data")))
                _ = store.write(Data("already".utf8), toPath: path("c.data"))
                try! Data("not-a-clip".utf8).write(to: URL(fileURLWithPath: path("d.txt")))

                store.encryptPlaintextFiles(inDirectory: workDirectory.path)

                // すべての .data が暗号化形式になり、内容は保持される
                for (file, content) in [("a.data", "plain-1"), ("b.data", "plain-2"), ("c.data", "already")] {
                    let raw = try! Data(contentsOf: URL(fileURLWithPath: path(file)))
                    expect(raw.prefix(7)) == Data("CLPYDAT".utf8)
                    expect(store.read(fromPath: path(file))) == Data(content.utf8)
                }
                // .data 以外は触らない
                let untouched = try! Data(contentsOf: URL(fileURLWithPath: path("d.txt")))
                expect(untouched) == Data("not-a-clip".utf8)
            }
        }
    }
}
