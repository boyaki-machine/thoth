import Quick
import Nimble
import Foundation
@testable import Clipy

class CryptoServiceSpec: QuickSpec {

    private let service = CryptoService()

    override func spec() {
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
