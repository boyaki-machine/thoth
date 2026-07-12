//
//  CodeSignService.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Copyright © 2015-2018 Clipy Project.
//

import AppKit
import Foundation
import Security

/// アプリ自身の署名をデバイス固有の自己署名証明書で安定化させるサービス。
///
/// セキュアアイテムの Keychain ACL は「作成したアプリのコード署名」に紐付くため、
/// ad-hoc 署名のままではビルド（バージョン）のたびに別アプリと判定され、
/// 既存アイテムを読み出せなくなる。起動時に以下を行うことで、
/// 同じデバイス上ではバージョンによらず同一の署名を維持する。
///
/// 1. 既に本サービスの証明書で署名済みなら何もしない
/// 2. ログインキーチェーンに証明書（"Clipy Local Signing"）があれば再利用し、
///    なければ生成してキーチェーンに保存する（デバイス上で一度だけ生成される）
/// 3. 自身の .app バンドルを再署名し、アプリを再起動する
///
/// 初回のみ macOS の確認ダイアログ（証明書の信頼設定・署名鍵の使用許可）が
/// 表示されることがある。いずれかの手順が失敗した場合は ad-hoc 署名のまま起動を続ける。
final class CodeSignService {

    // MARK: - Constants

    /// キーチェーンに保存する証明書の Common Name（＝署名 identity 名）
    static let certificateCommonName = "Clipy Local Signing"
    /// 再署名後の再起動時に付与する引数（再署名の無限ループ防止）
    static let resignedArgument = "--clipy-resigned"
    /// 再署名を無効化したい場合の引数（開発・デバッグ用）
    static let skipResignArgument = "--clipy-skip-resign"

    // MARK: - Public Interface

    /// 起動時に呼び出す。再署名を行った場合はアプリを再起動する。
    /// - Returns: 再署名して再起動を予約した場合 true。
    ///   呼び出し側は true の場合、以降の起動処理（特にアクセシビリティ確認などの
    ///   TCC 登録を伴う処理）をスキップすること。再署名前の ad-hoc バイナリが
    ///   TCC に登録されると、アクセシビリティ設定に重複エントリが増えてしまう。
    @discardableResult
    func ensureStableSignatureAtLaunch() -> Bool {
        let processInfo = ProcessInfo.processInfo
        // ユニットテスト実行時はスキップする（再起動するとテストホストが終了してしまう）
        guard processInfo.environment["XCTestConfigurationFilePath"] == nil else { return false }
        let arguments = processInfo.arguments
        // 再起動後は成否に関わらず再試行しない（ループ防止）
        guard !arguments.contains(Self.resignedArgument), !arguments.contains(Self.skipResignArgument) else { return false }
        // 既に安定署名済みなら何もしない
        guard currentSigningCommonName() != Self.certificateCommonName else { return false }

        let bundlePath = Bundle.main.bundlePath
        guard bundlePath.hasSuffix(".app"), FileManager.default.isWritableFile(atPath: bundlePath) else {
            NSLog("[CodeSignService] bundle is not writable, skip re-signing: \(bundlePath)")
            return false
        }
        guard ensureSigningIdentity() else {
            NSLog("[CodeSignService] failed to prepare signing identity, continue with current signature")
            return false
        }
        guard resignBundle(at: bundlePath) else {
            NSLog("[CodeSignService] failed to re-sign bundle, continue with current signature")
            return false
        }
        NSLog("[CodeSignService] re-signed successfully, relaunching")
        relaunch(bundlePath: bundlePath)
        return true
    }

    // MARK: - Signing Information

    /// 現在のバイナリが安定署名（Clipy Local Signing）で署名されているか。
    /// Keychain 項目（セキュアアイテム・DB 暗号鍵）は署名に紐づくため、
    /// ad-hoc 署名のまま Keychain に鍵を作成すると再署名後に読めなくなる。
    /// 鍵を新規作成する側はこのフラグで安定署名を確認すること。
    var isStablySigned: Bool {
        return currentSigningCommonName() == Self.certificateCommonName
    }

    /// 現在実行中のバイナリの署名証明書（リーフ）の Common Name を返す。ad-hoc 署名の場合は nil。
    private func currentSigningCommonName() -> String? {
        var codeRef: SecCode?
        guard SecCodeCopySelf([], &codeRef) == errSecSuccess, let code = codeRef else { return nil }
        var staticCodeRef: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCodeRef) == errSecSuccess, let staticCode = staticCodeRef else { return nil }
        var infoRef: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(staticCode, flags, &infoRef) == errSecSuccess,
              let info = infoRef as? [String: Any],
              let certificates = info[kSecCodeInfoCertificates as String] as? [SecCertificate],
              let leafCertificate = certificates.first else { return nil }
        return SecCertificateCopySubjectSummary(leafCertificate) as String?
    }

    // MARK: - Signing Identity

    /// キーチェーンに署名 identity があれば再利用し、なければ生成する。
    private func ensureSigningIdentity() -> Bool {
        if findSigningIdentity() {
            NSLog("[CodeSignService] reusing existing signing identity in keychain")
            return true
        }
        NSLog("[CodeSignService] signing identity not found, creating a new one")
        return createSigningIdentity()
    }

    private func findSigningIdentity() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecAttrLabel as String: Self.certificateCommonName,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnRef as String: true
        ]
        var result: AnyObject?
        return SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess
    }

    /// 自己署名のコード署名証明書を生成してログインキーチェーンに保存する。
    /// 生成は openssl(LibreSSL) で行い、`security import` でキーチェーンへ取り込む。
    private func createSigningIdentity() -> Bool {
        let fileManager = FileManager.default
        let workDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("clipy-codesign-\(UUID().uuidString)", isDirectory: true)
        do {
            try fileManager.createDirectory(at: workDirectory, withIntermediateDirectories: true,
                                            attributes: [.posixPermissions: 0o700])
        } catch {
            NSLog("[CodeSignService] failed to create work directory: \(error)")
            return false
        }
        // 秘密鍵を含む一時ファイルは必ず削除する
        defer { try? fileManager.removeItem(at: workDirectory) }

        let configPath = workDirectory.appendingPathComponent("cert.cnf").path
        let keyPath = workDirectory.appendingPathComponent("key.pem").path
        let certificatePath = workDirectory.appendingPathComponent("cert.pem").path
        let identityPath = workDirectory.appendingPathComponent("identity.p12").path
        // p12 の一時パスフレーズ（インポート直後にファイルごと削除するため固定で問題ない）
        let passphrase = "clipy-local-signing"

        let config = """
        [req]
        distinguished_name = dn
        x509_extensions = v3_code
        prompt = no
        [dn]
        CN = \(Self.certificateCommonName)
        [v3_code]
        basicConstraints = critical,CA:FALSE
        keyUsage = critical,digitalSignature
        extendedKeyUsage = critical,codeSigning
        """
        do {
            try config.write(toFile: configPath, atomically: true, encoding: .utf8)
        } catch {
            NSLog("[CodeSignService] failed to write openssl config: \(error)")
            return false
        }

        // 1. 自己署名証明書と秘密鍵を生成（有効期間 10 年）
        guard runCommand("/usr/bin/openssl",
                         ["req", "-x509", "-newkey", "rsa:2048", "-sha256", "-days", "3650", "-nodes",
                          "-keyout", keyPath, "-out", certificatePath, "-config", configPath]) else { return false }
        // 2. identity(p12) 形式へ変換
        guard runCommand("/usr/bin/openssl",
                         ["pkcs12", "-export", "-inkey", keyPath, "-in", certificatePath,
                          "-out", identityPath, "-passout", "pass:\(passphrase)"]) else { return false }
        // 3. ログインキーチェーンへ取り込む（codesign から鍵を使えるように -T を指定）
        guard runCommand("/usr/bin/security",
                         ["import", identityPath, "-P", passphrase,
                          "-T", "/usr/bin/codesign"]) else { return false }
        // 4. コード署名用として信頼する（macOS の確認ダイアログが表示されることがある）
        guard runCommand("/usr/bin/security",
                         ["add-trusted-cert", "-r", "trustRoot", "-p", "codeSign", certificatePath]) else {
            NSLog("[CodeSignService] add-trusted-cert failed (user may have cancelled)")
            return false
        }
        return true
    }

    // MARK: - Re-sign & Relaunch

    private func resignBundle(at bundlePath: String) -> Bool {
        return runCommand("/usr/bin/codesign",
                          ["--force", "--deep", "--sign", Self.certificateCommonName, bundlePath])
    }

    /// 自身を終了して再署名済みのバンドルを起動し直す。
    /// 旧インスタンスの終了を待ってから起動するため、シェル経由で遅延実行する。
    private func relaunch(bundlePath: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 1; /usr/bin/open -n \"\(bundlePath)\" --args \(Self.resignedArgument)"]
        do {
            try process.run()
        } catch {
            NSLog("[CodeSignService] failed to schedule relaunch: \(error)")
            return
        }
        NSApp.terminate(nil)
    }

    // MARK: - Command Helper

    @discardableResult
    private func runCommand(_ executablePath: String, _ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            NSLog("[CodeSignService] failed to run \(executablePath): \(error)")
            return false
        }
        guard process.terminationStatus == 0 else {
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: outputData, encoding: .utf8) ?? ""
            NSLog("[CodeSignService] \(executablePath) \(arguments.first ?? "") failed (status \(process.terminationStatus)): \(output)")
            return false
        }
        return true
    }
}
