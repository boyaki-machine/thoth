import Quick
import Nimble
import Foundation
@testable import Thoth

class CryptoServiceSpec: QuickSpec {

    private static let service = CryptoService()

    // BDD スペックの spec() は多数の it ブロックを含み長くなるため関数長ルールを緩める
    // swiftlint:disable:next function_body_length
    override class func spec() {
        var workDirectory: URL!

        beforeEach {
            workDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("clipy-crypto-test-\(UUID().uuidString)", isDirectory: true)
            try? FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        }
        afterEach {
            try? FileManager.default.removeItem(at: workDirectory)
        }

        // MARK: - Helpers

        func makeFile(named name: String, contents: String) -> URL {
            let url = workDirectory.appendingPathComponent(name)
            try! contents.write(to: url, atomically: true, encoding: .utf8)
            return url
        }

        /// completion ベースの API を同期的に扱うヘルパー
        func encryptSync(_ input: URL, to output: URL, password: String) -> Result<URL, Error> {
            var captured: Result<URL, Error>!
            waitUntil(timeout: .seconds(30)) { done in
                self.service.encrypt(inputURL: input, outputURL: output, password: password) { result in
                    captured = result
                    done()
                }
            }
            return captured
        }

        func decryptSync(_ input: URL, to output: URL, password: String) -> Result<URL, Error> {
            var captured: Result<URL, Error>!
            waitUntil(timeout: .seconds(30)) { done in
                self.service.decrypt(inputURL: input, outputURL: output, password: password) { result in
                    captured = result
                    done()
                }
            }
            return captured
        }

        // MARK: - File Round Trip

        describe("File encryption") {

            it("Encrypts and decrypts a file back to the original content") {
                let original = makeFile(named: "secret.txt", contents: "top secret content 日本語もOK")
                let encrypted = workDirectory.appendingPathComponent("secret.txt.enc")
                let decrypted = workDirectory.appendingPathComponent("secret-decrypted.txt")

                expect(try? encryptSync(original, to: encrypted, password: "pass1234").get()) != nil
                expect(FileManager.default.fileExists(atPath: encrypted.path)) == true
                // 暗号化ファイルの中身は平文と異なる
                let cipherData = try! Data(contentsOf: encrypted)
                expect(cipherData) != (try! Data(contentsOf: original))

                expect(try? decryptSync(encrypted, to: decrypted, password: "pass1234").get()) != nil
                let restored = try! String(contentsOf: decrypted, encoding: .utf8)
                expect(restored) == "top secret content 日本語もOK"
            }

            it("Fails to decrypt with a wrong password") {
                let original = makeFile(named: "secret.txt", contents: "secret")
                let encrypted = workDirectory.appendingPathComponent("secret.enc")
                let decrypted = workDirectory.appendingPathComponent("out.txt")
                _ = encryptSync(original, to: encrypted, password: "correct")

                let result = decryptSync(encrypted, to: decrypted, password: "wrong")
                switch result {
                case .success:
                    fail("decryption with a wrong password should fail")
                case .failure:
                    expect(FileManager.default.fileExists(atPath: decrypted.path)) == false
                }
            }
        }

        // MARK: - Folder Round Trip

        describe("Folder encryption") {

            it("Encrypts and decrypts a folder preserving its structure") {
                let folder = workDirectory.appendingPathComponent("myfolder", isDirectory: true)
                let subFolder = folder.appendingPathComponent("sub", isDirectory: true)
                try! FileManager.default.createDirectory(at: subFolder, withIntermediateDirectories: true)
                try! "file a".write(to: folder.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
                try! "file b".write(to: subFolder.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)

                let encrypted = workDirectory.appendingPathComponent("myfolder.enc")
                let restoreRoot = workDirectory.appendingPathComponent("restored", isDirectory: true)

                expect(try? encryptSync(folder, to: encrypted, password: "pw").get()) != nil
                expect(try? decryptSync(encrypted, to: restoreRoot, password: "pw").get()) != nil

                // restored/myfolder/a.txt と restored/myfolder/sub/b.txt が復元される
                let restoredA = restoreRoot.appendingPathComponent("myfolder/a.txt")
                let restoredB = restoreRoot.appendingPathComponent("myfolder/sub/b.txt")
                expect(try? String(contentsOf: restoredA, encoding: .utf8)) == "file a"
                expect(try? String(contentsOf: restoredB, encoding: .utf8)) == "file b"
            }

            // "-" で始まるフォルダ名を tar のオプションとして解釈させない（"--" で区切る）
            it("Encrypts and decrypts a folder whose name starts with a hyphen") {
                let folder = workDirectory.appendingPathComponent("--checkpoint=1", isDirectory: true)
                try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try! "hyphen".write(to: folder.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)

                let encrypted = workDirectory.appendingPathComponent("hyphen.enc")
                let restoreRoot = workDirectory.appendingPathComponent("restored-hyphen", isDirectory: true)

                expect(try? encryptSync(folder, to: encrypted, password: "pw").get()) != nil
                expect(try? decryptSync(encrypted, to: restoreRoot, password: "pw").get()) != nil
                let restored = restoreRoot.appendingPathComponent("--checkpoint=1/a.txt")
                expect(try? String(contentsOf: restored, encoding: .utf8)) == "hyphen"
            }
        }

        // MARK: - Integrity (Encrypt-then-MAC)

        describe("Ciphertext integrity") {

            // HMAC-SHA256 の検証により、暗号文の 1 バイト改竄でも復号が失敗することを担保する
            it("Fails to decrypt tampered ciphertext") {
                let original = makeFile(named: "secret.txt", contents: "integrity check")
                let encrypted = workDirectory.appendingPathComponent("secret.enc")
                let decrypted = workDirectory.appendingPathComponent("out.txt")
                _ = encryptSync(original, to: encrypted, password: "pw")

                // 暗号文部分（末尾から 20 バイト目 = タグより前）を 1 ビット反転する
                var data = try! Data(contentsOf: encrypted)
                data[data.count - 20] ^= 0x01
                try! data.write(to: encrypted)

                let result = decryptSync(encrypted, to: decrypted, password: "pw")
                if case .success = result { fail("tampered ciphertext should fail to decrypt") }
            }

            it("Fails to decrypt tampered header") {
                let original = makeFile(named: "secret.txt", contents: "header check")
                let encrypted = workDirectory.appendingPathComponent("secret.enc")
                let decrypted = workDirectory.appendingPathComponent("out.txt")
                _ = encryptSync(original, to: encrypted, password: "pw")

                // フラグバイト（オフセット 8）を書き換える → HMAC がヘッダーも認証しているため失敗するべき
                var data = try! Data(contentsOf: encrypted)
                data[8] ^= 0x01
                try! data.write(to: encrypted)

                let result = decryptSync(encrypted, to: decrypted, password: "pw")
                if case .success = result { fail("tampered header should fail to decrypt") }
            }
        }

        // MARK: - Legacy Format Compatibility

        describe("Legacy format decryption") {

            // 旧バージョン（openssl enc -aes-256-cbc -pbkdf2 -iter 100000）で暗号化した
            // 固定フィクスチャ。パスワード "legacy-pass"、平文 "legacy secret content 日本語"。
            // このテストが落ちる変更は、過去に暗号化したファイルが開けなくなることを意味する
            let legacyFileFixture = "AAAAAAAAAABTYWx0ZWRfXzcA2ofErOWPOboodNYd9Zz3NDY2EOUpUGvHM+rgu+cBlvHqHJUQIdE="

            it("Decrypts a fixed legacy file fixture") {
                let encrypted = workDirectory.appendingPathComponent("legacy.enc")
                try! Data(base64Encoded: legacyFileFixture)!.write(to: encrypted)
                let decrypted = workDirectory.appendingPathComponent("legacy-out.txt")

                expect(try? decryptSync(encrypted, to: decrypted, password: "legacy-pass").get()) != nil
                expect(try? String(contentsOf: decrypted, encoding: .utf8)) == "legacy secret content 日本語"
            }

            it("Fails to decrypt a legacy fixture with a wrong password") {
                let encrypted = workDirectory.appendingPathComponent("legacy.enc")
                try! Data(base64Encoded: legacyFileFixture)!.write(to: encrypted)
                let decrypted = workDirectory.appendingPathComponent("legacy-out.txt")

                let result = decryptSync(encrypted, to: decrypted, password: "wrong")
                if case .success = result { fail("wrong password should fail") }
            }

            // 実際の openssl コマンドで旧形式ファイルを生成し、相互運用性を検証する
            // （固定フィクスチャと違い、この環境の openssl 実装との互換を直接確認できる）
            func makeLegacyContainer(of sourceURL: URL, marker: Data, password: String) -> Data? {
                let encBody = workDirectory.appendingPathComponent("legacy-body-\(UUID().uuidString)")
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
                process.arguments = ["enc", "-aes-256-cbc", "-pbkdf2", "-iter", "100000", "-salt",
                                     "-in", sourceURL.path, "-out", encBody.path, "-pass", "pass:\(password)"]
                try? process.run()
                process.waitUntilExit()
                guard process.terminationStatus == 0, let body = try? Data(contentsOf: encBody) else { return nil }
                return marker + body
            }

            it("Decrypts a legacy file produced by the openssl command") {
                let original = makeFile(named: "interop.txt", contents: "openssl interop")
                guard let container = makeLegacyContainer(of: original,
                                                          marker: Data(repeating: 0, count: 8),
                                                          password: "pw123") else {
                    fail("failed to build legacy container with openssl")
                    return
                }
                let encrypted = workDirectory.appendingPathComponent("interop.enc")
                try! container.write(to: encrypted)
                let decrypted = workDirectory.appendingPathComponent("interop-out.txt")

                expect(try? decryptSync(encrypted, to: decrypted, password: "pw123").get()) != nil
                expect(try? String(contentsOf: decrypted, encoding: .utf8)) == "openssl interop"
            }

            it("Decrypts a legacy folder produced by tar + openssl") {
                // 旧形式のフォルダ暗号化を再現: tar でまとめて openssl 暗号化、CLIPYDIR マーカー
                let folder = workDirectory.appendingPathComponent("legacydir", isDirectory: true)
                try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try! "in folder".write(to: folder.appendingPathComponent("f.txt"), atomically: true, encoding: .utf8)

                let tarURL = workDirectory.appendingPathComponent("legacy.tar")
                let tar = Process()
                tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
                tar.arguments = ["-cf", tarURL.path, "-C", workDirectory.path, "legacydir"]
                try? tar.run()
                tar.waitUntilExit()

                guard let container = makeLegacyContainer(of: tarURL,
                                                          marker: Data("CLIPYDIR".utf8),
                                                          password: "pw123") else {
                    fail("failed to build legacy folder container with openssl")
                    return
                }
                let encrypted = workDirectory.appendingPathComponent("legacydir.enc")
                try! container.write(to: encrypted)
                let restoreRoot = workDirectory.appendingPathComponent("legacy-restored", isDirectory: true)

                expect(try? decryptSync(encrypted, to: restoreRoot, password: "pw123").get()) != nil
                let restored = restoreRoot.appendingPathComponent("legacydir/f.txt")
                expect(try? String(contentsOf: restored, encoding: .utf8)) == "in folder"
            }
        }

        // MARK: - New Format Layout & openssl CLI Interop

        describe("New format layout") {

            it("Writes the CLPYENC v2 header with an openssl-compatible body") {
                let original = makeFile(named: "a.txt", contents: "x")
                let encrypted = workDirectory.appendingPathComponent("a.enc")
                _ = encryptSync(original, to: encrypted, password: "pw")

                let data = try! Data(contentsOf: encrypted)
                expect(data.prefix(7)) == Data("CLPYENC".utf8)
                expect(data[7]) == 2  // バージョン
                // オフセット 45 以降は openssl enc がそのまま読める "Salted__" 形式
                expect(data.subdata(in: CryptoService.bodyOffset..<CryptoService.bodyOffset + 8)) == Data("Salted__".utf8)
            }

            // 「アプリが無い端末でも openssl コマンドだけで復号できる」要件の end-to-end 検証。
            // README に記載している復旧手順そのものを実行する
            it("Can be decrypted by the openssl CLI after stripping the header") {
                let original = makeFile(named: "interop-out.txt", contents: "openssl CLI recovery 日本語")
                let encrypted = workDirectory.appendingPathComponent("cli.enc")
                _ = encryptSync(original, to: encrypted, password: "cli-pass")

                // ヘッダー 45 バイトを取り除いた本体を openssl enc -d に渡す
                let container = try! Data(contentsOf: encrypted)
                let bodyURL = workDirectory.appendingPathComponent("cli.body")
                try! container.suffix(from: CryptoService.bodyOffset).write(to: bodyURL)

                let restored = workDirectory.appendingPathComponent("cli-restored.txt")
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
                process.arguments = ["enc", "-d", "-aes-256-cbc", "-pbkdf2",
                                     "-iter", String(CryptoService.iterationCount),
                                     "-in", bodyURL.path, "-out", restored.path, "-pass", "pass:cli-pass"]
                try? process.run()
                process.waitUntilExit()

                expect(process.terminationStatus) == 0
                expect(try? String(contentsOf: restored, encoding: .utf8)) == "openssl CLI recovery 日本語"
            }
        }

        // MARK: - V1 (GCM) Format Compatibility

        describe("V1 format decryption") {

            // 旧バージョン 1（AES-256-GCM）で暗号化した固定フィクスチャ。
            // パスワード "v1-pass"、平文 "v1 gcm secret 日本語"
            let v1Fixture = "Q0xQWUVOQwEAAAECAwQFBgcICQoLDA0ODwADDUBkZWZnaGlqa2xtbm9C0V2PI2ldqIGqguUhXWxmmoMOVWau3xXelU9DiZybTMjik7zt6es="

            it("Decrypts a fixed v1 (GCM) fixture") {
                let encrypted = workDirectory.appendingPathComponent("v1.enc")
                try! Data(base64Encoded: v1Fixture)!.write(to: encrypted)
                let decrypted = workDirectory.appendingPathComponent("v1-out.txt")

                expect(try? decryptSync(encrypted, to: decrypted, password: "v1-pass").get()) != nil
                expect(try? String(contentsOf: decrypted, encoding: .utf8)) == "v1 gcm secret 日本語"
            }

            it("Fails to decrypt a v1 fixture with a wrong password") {
                let encrypted = workDirectory.appendingPathComponent("v1.enc")
                try! Data(base64Encoded: v1Fixture)!.write(to: encrypted)
                let decrypted = workDirectory.appendingPathComponent("v1-out.txt")

                let result = decryptSync(encrypted, to: decrypted, password: "wrong")
                if case .success = result { fail("wrong password should fail") }
            }
        }

        // MARK: - Validation

        describe("Validation") {

            it("Fails with an empty password") {
                let original = makeFile(named: "a.txt", contents: "x")
                let output = workDirectory.appendingPathComponent("a.enc")
                let result = encryptSync(original, to: output, password: "")
                if case .success = result { fail("empty password should fail") }
            }

            it("Fails when the input does not exist") {
                let missing = workDirectory.appendingPathComponent("missing.txt")
                let output = workDirectory.appendingPathComponent("out.enc")
                let result = encryptSync(missing, to: output, password: "pw")
                if case .success = result { fail("missing input should fail") }
            }

            it("Fails when the output already exists") {
                let original = makeFile(named: "a.txt", contents: "x")
                let output = makeFile(named: "exists.enc", contents: "already here")
                let result = encryptSync(original, to: output, password: "pw")
                if case .success = result { fail("existing output should fail") }
            }
        }
    }
}
