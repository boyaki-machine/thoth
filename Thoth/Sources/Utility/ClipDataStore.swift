//
//  ClipDataStore.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Copyright © 2015-2018 Clipy Project.
//

import Foundation
import CryptoKit

/// クリップ本体（.data ファイル）の暗号化読み書きを担うストア。
///
/// クリップボード履歴の実データ（NSKeyedArchiver でシリアライズした CPYClipData）は
/// 従来 Application Support に平文で保存されていた。本ストアは AES-256-GCM で
/// 暗号化して保存する。鍵はアプリ内部専用（ユーザーが覚えるパスワードではない）ため、
/// openssl CLI 互換の要件は無く、認証付きの GCM をそのまま使う。
///
/// ## ファイル形式
/// `"CLPYDAT"(7B) + バージョン 0x01(1B) + AES-GCM combined（nonce 12B + 暗号文 + タグ 16B）`
///
/// ## 互換性・フェイルセーフ
/// - 読み込みはマジックナンバーで判別し、旧形式（平文アーカイブ）もそのまま返す（遅延互換）
/// - 鍵が用意できない場合（ad-hoc 署名で鍵作成を延期中・Keychain 障害）は
///   平文で読み書きして機能を維持する（暗号化は次回起動以降のスイープで追いつく）
/// - 鍵はアプリ生成鍵（app-keys）の 1 つとして AppKeyStore が管理する
///   （作成は安定署名時のみ・読み戻し検証つき）
final class ClipDataStore {

    // MARK: - Properties

    /// 暗号鍵（32 バイト）。nil の場合は平文で読み書きする
    private let key: SymmetricKey?

    /// 本番用の共有インスタンス。初回アクセス時に Keychain から鍵を読み込む
    /// （static let は初期化がスレッドセーフに一度だけ行われる）
    static let shared = ClipDataStore(key: ClipDataStore.defaultKey())

    // MARK: - Constants

    /// 暗号化ファイルのマジックナンバー
    private static let magic = Data("CLPYDAT".utf8)
    /// 形式バージョン
    private static let formatVersion: UInt8 = 1
    /// ヘッダー長（マジック + バージョン）
    private static let headerLength = 8

    // MARK: - Initialize

    init(key: Data?) {
        self.key = key.map { SymmetricKey(data: $0) }
    }

    /// 本番用の鍵を Keychain（app-keys エントリ）から取得する（無ければ安定署名時のみ作成）。
    /// テスト実行時は nil（各テストが専用インスタンスに鍵を注入する）
    private static func defaultKey() -> Data? {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return nil }
        return AppKeyStore.appEncryptionKey(for: .clipData)
    }

    // MARK: - Read / Write

    /// データを暗号化して書き込む。鍵が無い場合は平文で書き込む
    @discardableResult
    func write(_ data: Data, toPath path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        guard let key = key else {
            return (try? data.write(to: url, options: .atomic)) != nil
        }
        do {
            let sealed = try AES.GCM.seal(data, using: key)
            var container = Self.magic
            container.append(Self.formatVersion)
            container.append(sealed.combined!)  // nonce + 暗号文 + タグ
            try container.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// データを読み込む。CLPYDAT 形式なら復号し、旧形式（平文）はそのまま返す
    func read(fromPath path: String) -> Data? {
        guard let raw = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        guard raw.starts(with: Self.magic) else { return raw }  // 旧平文アーカイブ
        return open(raw)
    }

    /// クリップ本体を読み戻す。**.data からクリップを作るときは必ずこれを使う。**
    ///
    /// CLPYDAT 形式は GCM の認証タグで改ざんを検知できるが、旧形式（平文）には検知の手段が無い。
    /// 同じユーザーの他のプロセスが置いた細工済みのファイルを `requiresSecureCoding = false` で読むと
    /// 任意のクラスが Thoth の中で生成されるので、参照するクラスを検査してから読む
    func readClip(fromPath path: String) -> CPYClipData? {
        guard let raw = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        if raw.starts(with: Self.magic) {
            return open(raw).flatMap(CPYClipData.unarchived(from:))
        }
        guard Self.isAllowedLegacyArchive(raw) else { return nil }
        return CPYClipData.unarchived(from: raw)
    }

    private func open(_ raw: Data) -> Data? {
        guard raw.count > Self.headerLength, raw[Self.magic.count] == Self.formatVersion,
              let key = key else { return nil }
        let combined = raw.subdata(in: Self.headerLength..<raw.count)
        guard let box = try? AES.GCM.SealedBox(combined: combined),
              let plain = try? AES.GCM.open(box, using: key) else { return nil }
        return plain
    }

    private static func isAllowedLegacyArchive(_ raw: Data) -> Bool {
        return KeyedArchiveGuard.referencesOnlyAllowedClasses(raw, allowedClassNames: CPYClipData.archiveClassNames)
    }

    // MARK: - Migration Sweep

    /// ディレクトリ内の平文 .data ファイルを暗号化形式へ変換する。
    /// 起動後にバックグラウンド（.utility）で一度呼ぶ想定。1 ファイルずつ処理し、
    /// 失敗したファイルはスキップする（次回起動時に再試行される）
    func encryptPlaintextFiles(inDirectory directory: String) {
        guard key != nil else { return }
        let fileManager = FileManager.default
        guard let fileNames = try? fileManager.contentsOfDirectory(atPath: directory) else { return }
        for fileName in fileNames where fileName.hasSuffix(".data") {
            let path = (directory as NSString).appendingPathComponent(fileName)
            guard let raw = try? Data(contentsOf: URL(fileURLWithPath: path)),
                  !raw.starts(with: Self.magic),  // 暗号化済みはスキップ
                  // 検査に通らないファイルを暗号化すると、認証タグ付きの正規のデータになってしまう
                  Self.isAllowedLegacyArchive(raw) else { continue }
            write(raw, toPath: path)
        }
    }
}
