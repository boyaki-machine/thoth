import Foundation
import Quick
import Nimble
import RealmSwift
@testable import Thoth

/// RealmProvider の平文→暗号化移行を担保するスペック。
/// 実運用の default.realm には触れず、一時ディレクトリ上の Realm ファイルで検証する。
class RealmEncryptionSpec: QuickSpec {
    override class func spec() {
        var workDirectory: URL!
        var fileURL: URL!
        // Realm の暗号鍵は 64 バイト固定
        let key = Data((0..<64).map { UInt8($0) })

        beforeEach {
            workDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("clipy-realm-test-\(UUID().uuidString)", isDirectory: true)
            try? FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
            fileURL = workDirectory.appendingPathComponent("test.realm")
        }
        afterEach {
            try? FileManager.default.removeItem(at: workDirectory)
        }

        /// 平文 Realm を作成してクリップ1件とスニペット1件を保存する
        func makePlaintextRealm() {
            var config = RealmProvider.makeBaseConfiguration()
            config.fileURL = fileURL
            try! autoreleasepool {
                let realm = try Realm(configuration: config)
                try realm.write {
                    let clip = CPYClip()
                    clip.dataHash = "test-hash"
                    clip.title = "test clip"
                    realm.add(clip)
                    let snippet = CPYSnippet()
                    snippet.title = "test snippet"
                    snippet.content = "snippet content"
                    realm.add(snippet)
                }
            }
        }

        func openEncrypted() -> Realm? {
            var config = RealmProvider.makeBaseConfiguration()
            config.fileURL = fileURL
            config.encryptionKey = key
            return try? Realm(configuration: config)
        }

        func openPlaintext() -> Realm? {
            var config = RealmProvider.makeBaseConfiguration()
            config.fileURL = fileURL
            return try? Realm(configuration: config)
        }

        describe("Plaintext to encrypted migration") {

            it("Migrates a plaintext database preserving its contents") {
                makePlaintextRealm()

                expect(RealmProvider.migrateToEncryptedIfNeeded(at: fileURL, key: key)) == true

                // 暗号化構成で開けて、データが無傷であること
                let realm = openEncrypted()
                expect(realm) != nil
                expect(realm?.objects(CPYClip.self).count) == 1
                expect(realm?.objects(CPYClip.self).first?.title) == "test clip"
                expect(realm?.objects(CPYSnippet.self).count) == 1
                expect(realm?.objects(CPYSnippet.self).first?.content) == "snippet content"
            }

            it("Migrated file can no longer be opened as plaintext") {
                makePlaintextRealm()
                _ = RealmProvider.migrateToEncryptedIfNeeded(at: fileURL, key: key)

                expect(openPlaintext()) == nil
            }

            it("Is idempotent (second call succeeds without changes)") {
                makePlaintextRealm()
                expect(RealmProvider.migrateToEncryptedIfNeeded(at: fileURL, key: key)) == true
                // 2回目: 既に暗号化済み → そのまま成功
                expect(RealmProvider.migrateToEncryptedIfNeeded(at: fileURL, key: key)) == true

                expect(openEncrypted()?.objects(CPYClip.self).count) == 1
            }

            it("Succeeds when no database exists yet (fresh install)") {
                expect(FileManager.default.fileExists(atPath: fileURL.path)) == false
                expect(RealmProvider.migrateToEncryptedIfNeeded(at: fileURL, key: key)) == true
            }

            it("Does not leave a plaintext backup file after successful migration") {
                makePlaintextRealm()
                _ = RealmProvider.migrateToEncryptedIfNeeded(at: fileURL, key: key)

                let backupURL = fileURL.appendingPathExtension("bak")
                expect(FileManager.default.fileExists(atPath: backupURL.path)) == false
            }

            it("Plaintext title is not present in the encrypted file bytes") {
                makePlaintextRealm()
                _ = RealmProvider.migrateToEncryptedIfNeeded(at: fileURL, key: key)

                // 暗号化後のファイルに平文文字列が残っていないこと
                let raw = try! Data(contentsOf: fileURL)
                expect(raw.range(of: Data("test clip".utf8))) == nil
                expect(raw.range(of: Data("snippet content".utf8))) == nil
            }
        }
    }
}
