//
//  CryptoService.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Copyright © 2015-2018 Clipy Project.
//

import Foundation

/// ファイル・フォルダを openssl で暗号化・復号化するサービス。
///
/// 暗号化強度を高めるため、以下を組み合わせて openssl コマンドをバックグラウンド実行する。
/// - アルゴリズム: AES-256-CBC
/// - 鍵導出: PBKDF2（`-pbkdf2`）、ストレッチング回数 100,000 回（`-iter 100000`）
/// - salt 付き（`-salt`）
///
/// フォルダは一旦 tar でまとめてから暗号化し、復号時に tar を展開して元の構造を復元する。
final class CryptoService {

    // MARK: - Constants

    /// PBKDF2 のストレッチング回数（10 万回以上）
    static let iterationCount = 100_000
    /// 暗号化ファイルの拡張子
    static let encryptedExtension = "enc"
    /// フォルダを暗号化した場合に付与する内部マーカー（復号時に tar 展開すべきか判定する）
    private static let folderMarkerPrefix = Data("CLIPYDIR".utf8)

    enum CryptoError: LocalizedError {
        case emptyPassword
        case inputNotFound
        case opensslFailed(String)
        case tarFailed(String)
        case outputExists

        var errorDescription: String? {
            switch self {
            case .emptyPassword:        return L10n.cryptoErrorEmptyPassword
            case .inputNotFound:        return L10n.cryptoErrorInputNotFound
            case .opensslFailed:        return L10n.cryptoErrorFailed
            case .tarFailed:            return L10n.cryptoErrorFailed
            case .outputExists:         return L10n.cryptoErrorOutputExists
            }
        }
    }

    // MARK: - Public Interface

    /// ファイル／フォルダを暗号化する。完了ハンドラはメインスレッドで呼ばれる。
    /// - Parameters:
    ///   - inputURL: 暗号化対象のファイルまたはフォルダ
    ///   - outputURL: 出力先（暗号化ファイル）
    ///   - password: 暗号化パスワード
    func encrypt(inputURL: URL, outputURL: URL, password: String, completion: @escaping (Result<URL, Error>) -> Void) {
        runInBackground(completion: completion) {
            try self.performEncrypt(inputURL: inputURL, outputURL: outputURL, password: password)
        }
    }

    /// 暗号化ファイルを復号する。フォルダ由来の場合は tar を展開して復元する。
    func decrypt(inputURL: URL, outputURL: URL, password: String, completion: @escaping (Result<URL, Error>) -> Void) {
        runInBackground(completion: completion) {
            try self.performDecrypt(inputURL: inputURL, outputURL: outputURL, password: password)
        }
    }

    // MARK: - Encrypt / Decrypt Implementation

    private func performEncrypt(inputURL: URL, outputURL: URL, password: String) throws -> URL {
        guard !password.isEmpty else { throw CryptoError.emptyPassword }
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: inputURL.path, isDirectory: &isDirectory) else {
            throw CryptoError.inputNotFound
        }
        guard !fileManager.fileExists(atPath: outputURL.path) else { throw CryptoError.outputExists }

        let workDirectory = try makeWorkDirectory()
        defer { try? fileManager.removeItem(at: workDirectory) }

        // 暗号化の入力（フォルダなら tar にまとめる）
        let sourceURL: URL
        if isDirectory.boolValue {
            let tarURL = workDirectory.appendingPathComponent("archive.tar")
            try runTarCreate(folderURL: inputURL, tarURL: tarURL)
            sourceURL = tarURL
        } else {
            sourceURL = inputURL
        }

        let encryptedURL = workDirectory.appendingPathComponent("payload.enc")
        try runOpenSSL(encrypt: true, inputURL: sourceURL, outputURL: encryptedURL, password: password)

        // フォルダ由来かどうかを示すマーカー（先頭 8 バイト）を付けて出力する
        let marker = isDirectory.boolValue ? Self.folderMarkerPrefix : Data(repeating: 0, count: Self.folderMarkerPrefix.count)
        let encryptedData = try Data(contentsOf: encryptedURL)
        try (marker + encryptedData).write(to: outputURL, options: .atomic)
        return outputURL
    }

    private func performDecrypt(inputURL: URL, outputURL: URL, password: String) throws -> URL {
        guard !password.isEmpty else { throw CryptoError.emptyPassword }
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: inputURL.path) else { throw CryptoError.inputNotFound }

        let container = try Data(contentsOf: inputURL)
        let markerLength = Self.folderMarkerPrefix.count
        guard container.count > markerLength else { throw CryptoError.opensslFailed("invalid file") }
        let marker = container.prefix(markerLength)
        let isFolder = marker == Self.folderMarkerPrefix
        let payload = container.suffix(from: container.startIndex + markerLength)

        let workDirectory = try makeWorkDirectory()
        defer { try? fileManager.removeItem(at: workDirectory) }

        let encryptedURL = workDirectory.appendingPathComponent("payload.enc")
        try payload.write(to: encryptedURL, options: .atomic)
        let decryptedURL = workDirectory.appendingPathComponent("payload.dec")
        try runOpenSSL(encrypt: false, inputURL: encryptedURL, outputURL: decryptedURL, password: password)

        if isFolder {
            // tar を出力先（親ディレクトリ）に展開する
            guard !fileManager.fileExists(atPath: outputURL.path) else { throw CryptoError.outputExists }
            try fileManager.createDirectory(at: outputURL, withIntermediateDirectories: true)
            try runTarExtract(tarURL: decryptedURL, destinationURL: outputURL)
        } else {
            guard !fileManager.fileExists(atPath: outputURL.path) else { throw CryptoError.outputExists }
            try fileManager.moveItem(at: decryptedURL, to: outputURL)
        }
        return outputURL
    }

    // MARK: - Command Runners

    private func runOpenSSL(encrypt: Bool, inputURL: URL, outputURL: URL, password: String) throws {
        var arguments = ["enc"]
        if !encrypt { arguments.append("-d") }
        arguments += ["-aes-256-cbc", "-pbkdf2", "-iter", String(Self.iterationCount), "-salt",
                      "-in", inputURL.path, "-out", outputURL.path,
                      "-pass", "pass:\(password)"]
        let result = runCommand("/usr/bin/openssl", arguments)
        guard result.status == 0 else { throw CryptoError.opensslFailed(result.output) }
    }

    private func runTarCreate(folderURL: URL, tarURL: URL) throws {
        // 親ディレクトリを基準にフォルダ名だけを相対パスで格納する
        let parent = folderURL.deletingLastPathComponent().path
        let name = folderURL.lastPathComponent
        let result = runCommand("/usr/bin/tar", ["-cf", tarURL.path, "-C", parent, name])
        guard result.status == 0 else { throw CryptoError.tarFailed(result.output) }
    }

    private func runTarExtract(tarURL: URL, destinationURL: URL) throws {
        let result = runCommand("/usr/bin/tar", ["-xf", tarURL.path, "-C", destinationURL.path])
        guard result.status == 0 else { throw CryptoError.tarFailed(result.output) }
    }

    // MARK: - Helpers

    private func makeWorkDirectory() throws -> URL {
        let workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("clipy-crypto-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        return workDirectory
    }

    private func runInBackground(completion: @escaping (Result<URL, Error>) -> Void,
                                 work: @escaping () throws -> URL) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result: Result<URL, Error>
            do {
                result = .success(try work())
            } catch {
                result = .failure(error)
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    private func runCommand(_ executablePath: String, _ arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        do {
            try process.run()
        } catch {
            return (-1, error.localizedDescription)
        }
        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}
