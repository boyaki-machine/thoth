//
//  ClipFullTextIndexer.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Copyright © 2015-2018 Clipy Project.
//

import Foundation
import AppKit

/// 履歴クリップの全文検索用インメモリインデックスを構築するユーティリティ。
///
/// クリップの実データは暗号化された `.data` ファイルにあるため、検索パネルの
/// 表示時にバックグラウンドで順次復号・アンアーカイブして本文文字列を取り出す。
/// 平文はメモリ上にのみ保持し、パネルを閉じたら `cancel()` とともに破棄される
/// （保存時暗号化の方針を崩さないためのプライバシー配慮）。
///
/// Realm オブジェクトはスレッドを跨げないため、呼び出し側がメインスレッドで
/// `ClipRef`（値型スナップショット）を作ってから渡す（PasteService と同じ流儀）。
final class ClipFullTextIndexer {

    /// インデックス対象クリップへの参照（Realm 非依存の値型スナップショット）
    struct ClipRef {
        let dataHash: String
        let dataPath: String
        let primaryType: String
    }

    /// クリップ 1 件あたりのインデックス対象文字数上限（巨大クリップでのメモリ膨張防止）
    static let defaultMaxIndexedCharacters = 1_000_000
    /// 進捗コールバックを発火するバッチ単位
    static let batchSize = 20

    private let store: ClipDataStore
    private let maxIndexedCharacters: Int
    private let queue = DispatchQueue(label: "io.github.boyaki-machine.Thoth.history-indexer", qos: .userInitiated)
    private let lock = NSLock()
    private var cancelled = false

    init(store: ClipDataStore = .shared, maxIndexedCharacters: Int = ClipFullTextIndexer.defaultMaxIndexedCharacters) {
        self.store = store
        self.maxIndexedCharacters = maxIndexedCharacters
    }

    // MARK: - Build

    /// バックグラウンドで順次復号+アンアーカイブし、`batchSize` 件ごと（および完了時）に
    /// 累積インデックス（dataHash → 小文字化済み本文）のコピーをメインスレッドへ通知する。
    /// clips は表示順（新しい順）で渡すことで、直近のクリップから検索可能になっていく
    func build(clips: [ClipRef], onProgress: @escaping ([String: String]) -> Void) {
        queue.async { [weak self] in
            guard let self = self else { return }
            var index = [String: String]()
            var sinceLastNotify = 0
            for ref in clips {
                if self.isCancelled { return }
                if let text = self.extractIndexableText(from: ref) {
                    index[ref.dataHash] = text
                }
                sinceLastNotify += 1
                if sinceLastNotify >= Self.batchSize {
                    self.notify(index, onProgress)
                    sinceLastNotify = 0
                }
            }
            if sinceLastNotify > 0 || clips.isEmpty {
                self.notify(index, onProgress)
            }
        }
    }

    /// ビルドを中断し、以後のコールバックを抑止する（パネルを閉じたときに呼ぶ）
    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    private var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    private func notify(_ index: [String: String], _ onProgress: @escaping ([String: String]) -> Void) {
        let snapshot = index
        DispatchQueue.main.async { [weak self] in
            guard let self = self, !self.isCancelled else { return }
            onProgress(snapshot)
        }
    }

    // MARK: - Extraction

    /// 1 クリップの本文を復号・アンアーカイブして取り出す（小文字化・上限切り詰め済み）。
    /// TIFF / PDF クリップは NSImage 等の展開コストを避けるためファイルを読まずスキップする
    func extractIndexableText(from ref: ClipRef) -> String? {
        let type = NSPasteboard.PasteboardType(rawValue: ref.primaryType)
        guard type != .deprecatedTIFF, type != .deprecatedPDF else { return nil }
        // requiresSecureCoding=false の理由は PasteService.unarchiveClipData と同じ
        // （旧式 NSCoding のため。改竄検知は ClipDataStore の GCM 認証タグが担う）
        guard let fileData = store.read(fromPath: ref.dataPath),
              let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: fileData) else { return nil }
        unarchiver.requiresSecureCoding = false
        guard let clipData = unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey) as? CPYClipData else { return nil }
        let text = clipData.stringValue
        guard !text.isEmpty else { return nil }
        return String(text.prefix(maxIndexedCharacters)).lowercased()
    }

    // MARK: - Matching（純粋関数・セキュアメニュー検索と同じルール）

    /// クエリを検索語に分解する（トリム → 小文字化 → 空白区切り）
    static func terms(from query: String) -> [String] {
        return query.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
    }

    /// すべての検索語が部分一致するか（AND 条件）。検索語が空なら常に true
    static func matches(_ lowercasedText: String, terms: [String]) -> Bool {
        return terms.allSatisfy { lowercasedText.contains($0) }
    }
}
