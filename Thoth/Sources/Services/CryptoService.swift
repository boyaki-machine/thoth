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
import CryptoKit
import CommonCrypto

/// ファイル・フォルダをパスワードで暗号化・復号化するサービス。
///
/// 暗号化はすべてインプロセス（CryptoKit / CommonCrypto）で行う。
/// 以前は openssl コマンドを起動していたが、パスワードを argv で子プロセスに
/// 渡すと実行中に `ps` で他プロセスから見えてしまうため廃止した。
///
/// ## 現行形式（バージョン 2、openssl CLI 互換 + HMAC 認証）
/// 「アプリが無い端末でも openssl コマンドだけで復号できること」を要件とし、
/// 暗号化本体は openssl enc の出力と完全互換にして、その外側に HMAC-SHA256 による
/// 認証（Encrypt-then-MAC）を付与する。
///
/// - レイアウト:
///   ```
///   オフセット サイズ 内容
///   0          7     マジック "CLPYENC"
///   7          1     バージョン (0x02)
///   8          1     フラグ (bit0: フォルダ由来 → 復号後に tar 展開)
///   9          4     PBKDF2 反復回数 (UInt32 ビッグエンディアン)
///   13         32    HMAC-SHA256 タグ（先頭 13 バイト + 本体全体を認証）
///   45         ...   本体 = openssl enc 完全互換:
///                    "Salted__" + salt(8B) + AES-256-CBC 暗号文（PKCS7）
///   ```
/// - 鍵導出: PBKDF2-HMAC-SHA256 で 80 バイトを一度に導出し、
///   暗号鍵(32) + IV(16) + HMAC鍵(32) に分割する。
///   先頭 48 バイトは openssl enc `-pbkdf2` の導出（鍵+IV）と一致する
///   （PBKDF2 の出力はブロック単位で独立しており、長く導出しても前半は変わらない）。
/// - HMAC の検証により、改竄と誤パスワードを復号前に確実に検知できる
///   （CBC 単体では検知できないため）。
///
/// ### openssl コマンドでの復号手順（アプリ未インストール端末での復旧）
/// ```sh
/// # 先頭 45 バイトのヘッダーを取り除けば openssl enc がそのまま読める
/// tail -c +46 file.enc | openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 \
///   -pass pass:PASSWORD -out restored
/// # フォルダ由来（9 バイト目のフラグが 1）の場合は tar -xf restored で展開
/// ```
///
/// ## 復号のみ対応する過去形式
/// - バージョン 1（"CLPYENC" + 0x01）: AES-256-GCM 形式（旧実装、短期間のみ使用）
/// - レガシー: `マーカー 8 バイト + openssl enc 出力`。マーカーは "CLIPYDIR"（フォルダ）
///   またはゼロ 8 バイト（ファイル）、鍵導出は PBKDF2-HMAC-SHA256 100,000 回
///
/// フォルダは一旦 tar でまとめてから暗号化し、復号時に tar を展開して元の構造を復元する
/// （tar の argv に秘密情報は含まれないため外部コマンドのままでよい）。
///
/// 注意: 現状は入出力をメモリに全読み込みするため、巨大ファイルはメモリを圧迫する。
/// ストリーミング暗号化は将来課題。
final class CryptoService {

    // MARK: - Constants

    /// 現行形式の PBKDF2 ストレッチング回数（openssl の -iter に渡す値と同一）
    static let iterationCount = 200_000
    /// 暗号化ファイルの拡張子
    static let encryptedExtension = "enc"
    /// 本体（openssl 互換部分）が始まるオフセット。
    /// CLI 復号手順の `tail -c +46`（1 始まり）はこの値 +1
    static let bodyOffset = 45

    /// 共通マジックナンバー
    private static let magic = Data("CLPYENC".utf8)
    /// 現行形式のバージョン
    private static let formatVersion: UInt8 = 2
    /// フラグ: フォルダ由来（復号後に tar 展開する）
    private static let flagFolder: UInt8 = 0b0000_0001
    /// マジック〜反復回数までのヘッダー長（HMAC の認証対象に含める）
    private static let headerLength = 13
    /// HMAC-SHA256 タグ長
    private static let hmacLength = 32

    /// openssl enc の salt ヘッダー
    private static let saltHeader = Data("Salted__".utf8)
    /// レガシー形式でフォルダを示す内部マーカー（先頭 8 バイト）
    private static let legacyFolderMarker = Data("CLIPYDIR".utf8)
    /// レガシー形式の PBKDF2 ストレッチング回数
    private static let legacyIterationCount = 100_000

    enum CryptoError: LocalizedError {
        case emptyPassword
        case inputNotFound
        /// 復号失敗（誤パスワード・改竄・形式不正）。詳細はユーザーに区別して見せない
        case decryptFailed
        case encryptFailed
        case tarFailed(String)
        case outputExists

        var errorDescription: String? {
            switch self {
            case .emptyPassword:        return L10n.cryptoErrorEmptyPassword
            case .inputNotFound:        return L10n.cryptoErrorInputNotFound
            case .decryptFailed:        return L10n.cryptoErrorFailed
            case .encryptFailed:        return L10n.cryptoErrorFailed
            case .tarFailed:            return L10n.cryptoErrorFailed
            case .outputExists:         return L10n.cryptoErrorOutputExists
            }
        }
    }

    // MARK: - Public Interface

    /// アプリが無い環境でも復号できる openssl コマンド例を返す（README 記載の手順と同一）。
    /// パスワード部分は実値を埋め込まずプレースホルダーにする（画面表示・コピーされるため）。
    /// - Parameters:
    ///   - encryptedPath: 暗号化ファイルのパス
    ///   - outputName: 復号後のファイル名
    ///   - isFolder: フォルダ由来の場合 true（tar 展開の手順を付け加える）
    static func opensslDecryptCommand(encryptedPath: String, outputName: String, isFolder: Bool) -> String {
        let output = isFolder ? "\(outputName).tar" : outputName
        var command = "tail -c +\(bodyOffset + 1) '\(encryptedPath)' | "
            + "openssl enc -d -aes-256-cbc -pbkdf2 -iter \(iterationCount) -pass pass:PASSWORD -out '\(output)'"
        if isFolder {
            command += " && tar -xf '\(output)'"
        }
        return command
    }

    /// ファイル／フォルダを暗号化する。完了ハンドラはメインスレッドで呼ばれる。
    /// 出力は常に現行形式（openssl 互換 CBC + HMAC 認証）。
    /// - Parameters:
    ///   - inputURL: 暗号化対象のファイルまたはフォルダ
    ///   - outputURL: 出力先（暗号化ファイル）
    ///   - password: 暗号化パスワード
    func encrypt(inputURL: URL, outputURL: URL, password: String, completion: @escaping (Result<URL, Error>) -> Void) {
        runInBackground(completion: completion) {
            try self.performEncrypt(inputURL: inputURL, outputURL: outputURL, password: password)
        }
    }

    /// 暗号化ファイルを復号する。現行形式・旧 GCM 形式・レガシー形式を自動判別する。
    /// フォルダ由来の場合は tar を展開して復元する。
    func decrypt(inputURL: URL, outputURL: URL, password: String, completion: @escaping (Result<URL, Error>) -> Void) {
        runInBackground(completion: completion) {
            try self.performDecrypt(inputURL: inputURL, outputURL: outputURL, password: password)
        }
    }

    // MARK: - Encrypt Implementation

    private func performEncrypt(inputURL: URL, outputURL: URL, password: String) throws -> URL {
        guard !password.isEmpty else { throw CryptoError.emptyPassword }
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: inputURL.path, isDirectory: &isDirectory) else {
            throw CryptoError.inputNotFound
        }
        guard !fileManager.fileExists(atPath: outputURL.path) else { throw CryptoError.outputExists }

        // 暗号化の入力（フォルダなら tar にまとめる）
        let plainData: Data
        if isDirectory.boolValue {
            let workDirectory = try makeWorkDirectory()
            defer { try? fileManager.removeItem(at: workDirectory) }
            let tarURL = workDirectory.appendingPathComponent("archive.tar")
            try runTarCreate(folderURL: inputURL, tarURL: tarURL)
            plainData = try Data(contentsOf: tarURL)
        } else {
            plainData = try Data(contentsOf: inputURL)
        }

        let container = try seal(plainData, password: password, isFolder: isDirectory.boolValue)
        try container.write(to: outputURL, options: .atomic)
        return outputURL
    }

    /// 平文を現行形式コンテナ（ヘッダー + HMAC + openssl 互換本体）に封入する
    private func seal(_ plainData: Data, password: String, isFolder: Bool) throws -> Data {
        let salt = try randomBytes(count: 8)

        // 暗号鍵(32) + IV(16) + HMAC鍵(32) を一度に導出する。
        // 先頭 48 バイトは openssl enc -pbkdf2 の鍵導出と一致する
        let derived = try deriveKey(password: password, salt: salt,
                                    iterations: Self.iterationCount, length: 80)
        let encryptionKey = derived.subdata(in: 0..<32)
        let initialVector = derived.subdata(in: 32..<48)
        let hmacKey = derived.subdata(in: 48..<80)

        let ciphertext = try aesCBCEncrypt(plainData, key: encryptionKey, initialVector: initialVector)
        let body = Self.saltHeader + salt + ciphertext

        var header = Data()
        header.append(Self.magic)
        header.append(Self.formatVersion)
        header.append(isFolder ? Self.flagFolder : 0)
        var iterBE = UInt32(Self.iterationCount).bigEndian
        withUnsafeBytes(of: &iterBE) { header.append(contentsOf: $0) }

        // ヘッダーと本体全体を認証する（Encrypt-then-MAC）
        let tag = HMAC<SHA256>.authenticationCode(for: header + body, using: SymmetricKey(data: hmacKey))
        return header + Data(tag) + body
    }

    // MARK: - Decrypt Implementation

    private func performDecrypt(inputURL: URL, outputURL: URL, password: String) throws -> URL {
        guard !password.isEmpty else { throw CryptoError.emptyPassword }
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: inputURL.path) else { throw CryptoError.inputNotFound }
        guard !fileManager.fileExists(atPath: outputURL.path) else { throw CryptoError.outputExists }

        let container = try Data(contentsOf: inputURL)
        let (plainData, isFolder): (Data, Bool)
        if container.starts(with: Self.magic) {
            guard container.count > Self.headerLength else { throw CryptoError.decryptFailed }
            switch container[7] {
            case 2:  (plainData, isFolder) = try openSealed(container, password: password)
            case 1:  (plainData, isFolder) = try openSealedV1(container, password: password)
            default: throw CryptoError.decryptFailed
            }
        } else {
            (plainData, isFolder) = try openLegacy(container, password: password)
        }

        if isFolder {
            // tar を出力先（親ディレクトリ）に展開する
            let workDirectory = try makeWorkDirectory()
            defer { try? fileManager.removeItem(at: workDirectory) }
            let tarURL = workDirectory.appendingPathComponent("archive.tar")
            try plainData.write(to: tarURL, options: .atomic)
            try fileManager.createDirectory(at: outputURL, withIntermediateDirectories: true)
            try runTarExtract(tarURL: tarURL, destinationURL: outputURL)
        } else {
            try plainData.write(to: outputURL, options: .atomic)
        }
        return outputURL
    }

    /// 現行形式（バージョン 2）を開封する。HMAC 検証（改竄・誤パスワード検知）込み
    private func openSealed(_ container: Data, password: String) throws -> (Data, Bool) {
        // ヘッダー 13B + HMAC 32B + "Salted__" 8B + salt 8B + 暗号文 16B〜
        guard container.count >= Self.bodyOffset + 16 + kCCBlockSizeAES128 else { throw CryptoError.decryptFailed }
        let data = Data(container)  // スライスではなく 0 起点のインデックスで扱う

        let isFolder = (data[8] & Self.flagFolder) != 0
        let iterations = data.subdata(in: 9..<13).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        // 反復回数の異常値（DoS を招く巨大値・強度不足の小さい値）を拒否する
        guard (10_000...10_000_000).contains(Int(iterations)) else { throw CryptoError.decryptFailed }

        let header = data.subdata(in: 0..<Self.headerLength)
        let tag = data.subdata(in: Self.headerLength..<Self.bodyOffset)
        let body = data.subdata(in: Self.bodyOffset..<data.count)
        guard body.prefix(8) == Self.saltHeader else { throw CryptoError.decryptFailed }
        let salt = body.subdata(in: 8..<16)
        let ciphertext = body.subdata(in: 16..<body.count)

        let derived = try deriveKey(password: password, salt: salt,
                                    iterations: Int(iterations), length: 80)
        let encryptionKey = derived.subdata(in: 0..<32)
        let initialVector = derived.subdata(in: 32..<48)
        let hmacKey = derived.subdata(in: 48..<80)

        // 復号前に HMAC を検証する（Encrypt-then-MAC）。
        // 誤パスワードは HMAC 鍵の不一致として、改竄は本体の不一致としてここで検知される
        guard HMAC<SHA256>.isValidAuthenticationCode(tag, authenticating: header + body,
                                                     using: SymmetricKey(data: hmacKey)) else {
            throw CryptoError.decryptFailed
        }

        let plain = try aesCBCDecrypt(ciphertext, key: encryptionKey, initialVector: initialVector)
        return (plain, isFolder)
    }

    /// 旧バージョン 1 形式（AES-256-GCM）を開封する。復号のみ対応
    private func openSealedV1(_ container: Data, password: String) throws -> (Data, Bool) {
        // ヘッダー 29B + nonce 12B + タグ 16B が最小構成
        let headerLength = 29
        guard container.count >= headerLength + 12 + 16 else { throw CryptoError.decryptFailed }
        let data = Data(container)

        let isFolder = (data[8] & Self.flagFolder) != 0
        let salt = data.subdata(in: 9..<25)
        let iterations = data.subdata(in: 25..<29).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        guard (10_000...10_000_000).contains(Int(iterations)) else { throw CryptoError.decryptFailed }

        let header = data.subdata(in: 0..<headerLength)
        let nonceBytes = data.subdata(in: headerLength..<headerLength + 12)
        let ciphertextAndTag = data.subdata(in: headerLength + 12..<data.count)
        let ciphertext = ciphertextAndTag.dropLast(16)
        let tag = ciphertextAndTag.suffix(16)

        let key = try deriveKey(password: password, salt: salt, iterations: Int(iterations), length: 32)
        do {
            let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: nonceBytes),
                                            ciphertext: ciphertext, tag: tag)
            let plain = try AES.GCM.open(box, using: SymmetricKey(data: key), authenticating: header)
            return (plain, isFolder)
        } catch {
            throw CryptoError.decryptFailed
        }
    }

    /// レガシー形式（旧バージョンの openssl enc 出力）を復号する。
    /// openssl の `-pbkdf2 -iter 100000` は PBKDF2-HMAC-SHA256 で
    /// 48 バイト（鍵 32 + IV 16）を導出する仕様（LibreSSL / OpenSSL 共通）
    private func openLegacy(_ container: Data, password: String) throws -> (Data, Bool) {
        let data = Data(container)
        let markerLength = Self.legacyFolderMarker.count
        // マーカー 8B + "Salted__" 8B + salt 8B + 暗号文 16B 以上
        guard data.count >= markerLength + 16 + kCCBlockSizeAES128 else { throw CryptoError.decryptFailed }

        let marker = data.subdata(in: 0..<markerLength)
        let isFolder = marker == Self.legacyFolderMarker
        guard isFolder || marker == Data(repeating: 0, count: markerLength) else { throw CryptoError.decryptFailed }
        guard data.subdata(in: markerLength..<markerLength + 8) == Self.saltHeader else {
            throw CryptoError.decryptFailed
        }

        let salt = data.subdata(in: markerLength + 8..<markerLength + 16)
        let ciphertext = data.subdata(in: markerLength + 16..<data.count)
        let keyAndIV = try deriveKey(password: password, salt: salt,
                                     iterations: Self.legacyIterationCount, length: 48)
        let key = keyAndIV.subdata(in: 0..<32)
        let initialVector = keyAndIV.subdata(in: 32..<48)

        // レガシー形式には認証タグが無く、誤パスワードは高確率でパディングエラーになるが
        // 稀に成功してゴミが出る可能性は原理上残る（現行形式は HMAC で確実に検知できる）
        let plain = try aesCBCDecrypt(ciphertext, key: key, initialVector: initialVector)
        return (plain, isFolder)
    }

    // MARK: - Crypto Primitives

    /// AES-256-CBC + PKCS7 パディングで暗号化する（openssl enc と互換）
    private func aesCBCEncrypt(_ plainData: Data, key: Data, initialVector: Data) throws -> Data {
        var ciphertext = Data(count: plainData.count + kCCBlockSizeAES128)
        var encryptedLength = 0
        let status = ciphertext.withUnsafeMutableBytes { cipherPtr in
            plainData.withUnsafeBytes { plainPtr in
                key.withUnsafeBytes { keyPtr in
                    initialVector.withUnsafeBytes { ivPtr in
                        CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES),
                                CCOptions(kCCOptionPKCS7Padding),
                                keyPtr.baseAddress, 32, ivPtr.baseAddress,
                                plainPtr.baseAddress, plainData.count,
                                cipherPtr.baseAddress, cipherPtr.count, &encryptedLength)
                    }
                }
            }
        }
        guard status == kCCSuccess else { throw CryptoError.encryptFailed }
        return ciphertext.prefix(encryptedLength)
    }

    /// AES-256-CBC で復号し、PKCS7 パディングを厳密に検証して取り除く。
    /// CCCrypt の PKCS7 オプションは最終バイトの範囲しか検証しないため、
    /// パディングなしで復号してから openssl と同等の検証を手動で行う
    private func aesCBCDecrypt(_ ciphertext: Data, key: Data, initialVector: Data) throws -> Data {
        guard !ciphertext.isEmpty, ciphertext.count % kCCBlockSizeAES128 == 0 else {
            throw CryptoError.decryptFailed
        }
        var plain = Data(count: ciphertext.count)
        var decryptedLength = 0
        let status = plain.withUnsafeMutableBytes { plainPtr in
            ciphertext.withUnsafeBytes { cipherPtr in
                key.withUnsafeBytes { keyPtr in
                    initialVector.withUnsafeBytes { ivPtr in
                        CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES),
                                CCOptions(0),
                                keyPtr.baseAddress, 32, ivPtr.baseAddress,
                                cipherPtr.baseAddress, ciphertext.count,
                                plainPtr.baseAddress, plainPtr.count, &decryptedLength)
                    }
                }
            }
        }
        guard status == kCCSuccess else { throw CryptoError.decryptFailed }
        plain = plain.prefix(decryptedLength)

        // PKCS7 パディングの厳密検証: 長さ 1〜16、かつ全パディングバイトが同値であること
        guard let padLength = plain.last.map(Int.init),
              (1...kCCBlockSizeAES128).contains(padLength),
              plain.count >= padLength,
              plain.suffix(padLength).allSatisfy({ Int($0) == padLength }) else {
            throw CryptoError.decryptFailed
        }
        return plain.prefix(plain.count - padLength)
    }

    /// PBKDF2-HMAC-SHA256 で鍵材料を導出する
    private func deriveKey(password: String, salt: Data, iterations: Int, length: Int) throws -> Data {
        var derived = Data(count: length)
        let status = derived.withUnsafeMutableBytes { derivedPtr in
            salt.withUnsafeBytes { saltPtr in
                CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2),
                                     password, password.utf8.count,
                                     saltPtr.baseAddress?.assumingMemoryBound(to: UInt8.self), salt.count,
                                     CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(iterations),
                                     derivedPtr.baseAddress?.assumingMemoryBound(to: UInt8.self), length)
            }
        }
        guard status == kCCSuccess else { throw CryptoError.encryptFailed }
        return derived
    }

    /// OS の CSPRNG から乱数バイト列を取得する
    private func randomBytes(count: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        guard SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess else {
            throw CryptoError.encryptFailed
        }
        return Data(bytes)
    }

    // MARK: - Command Runners

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
