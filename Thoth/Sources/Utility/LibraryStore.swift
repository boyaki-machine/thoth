//
//  LibraryStore.swift
//
//  Thoth
//  GitHub: https://github.com/boyaki-machine/Thoth
//

import Foundation

// クリップボード履歴とスニペットの保存層。
//
// UI・サービスは保存先（Realm / SwiftData）を直接触らず、このプロトコルと
// 値型（LibraryRecords.swift）だけを使う。保存先の差し替え・暗号化は実装側に閉じる。
// どの実装も、書き込みのあとにメインスレッドで `.thothLibraryDidChange` を通知する。
//
// スレッド: 呼び出しはどのスレッドからでもよい（戻り値は値型なのでスレッドをまたげる）。

extension Notification.Name {
    /// 履歴またはスニペットが書き換わった（メニューの再構築に使う）
    static let thothLibraryDidChange = Notification.Name("io.github.boyaki-machine.Thoth.libraryDidChange")
}

/// クリップボード履歴の保存層
protocol HistoryStore: AnyObject {
    /// 内容から決まる識別子（CPYClipData.hash）から、保存に使う id を作る。
    /// 同じ内容なら同じ id になる（「同じ内容を上書き」の判定に使う）。
    /// 保存先によっては平文で置いても手掛かりにならない値へ変換する（SwiftData 版は HMAC）
    func clipID(forContentHash hash: String) -> String
    /// 全履歴を日時順に返す（ascending が true なら古い順）
    func clips(ascending: Bool) -> [ClipRecord]
    func clip(id: String) -> ClipRecord?

    var isEmpty: Bool { get }

    /// 同じ id があれば置き換え、無ければ追加する。
    /// - Parameter thumbnail: 縮小済みのサムネイル（PNG）。nil ならサムネイル無しになる
    func upsert(_ clip: ClipRecord, thumbnail: Data?)
    /// サムネイル（縮小済みの PNG）。無ければ nil。一覧の取得では読み込まず、表示するときだけ引く
    func thumbnail(forClipID id: String) -> Data?
    /// - Returns: 削除した履歴（無ければ nil）。サムネイルの後始末に使う
    @discardableResult
    func deleteClip(id: String) -> ClipRecord?
    /// - Returns: 削除した履歴
    @discardableResult
    func deleteAllClips() -> [ClipRecord]
    /// updateTime が指定より**小さい**履歴を削除する（等しいものは残す）
    /// - Returns: 削除した履歴
    @discardableResult
    func deleteClips(olderThan updateTime: Int) -> [ClipRecord]
}

/// スニペットの保存層
protocol SnippetStore: AnyObject {
    /// 全フォルダを index 順に返す（中のスニペットも index 順）
    func folders() -> [SnippetFolderRecord]
    func folder(id: String) -> SnippetFolderRecord?
    func snippet(id: String) -> SnippetRecord?
    /// フォルダの名前・番号・有効を保存する。無ければ作る。中のスニペットには触れない
    func saveFolder(_ folder: SnippetFolderRecord)
    /// フォルダを中のスニペットごと削除する
    func deleteFolder(id: String)
    /// スニペットの名前・本文・番号・有効を保存する。
    /// 既にあればその場で更新し（フォルダは移さない）、無ければ folderID のフォルダに作る
    func saveSnippet(_ snippet: SnippetRecord, folderID: String)
    func deleteSnippet(id: String)
    /// フォルダの並び順を ids の順に揃える（index を 0 から振り直す）
    func reorderFolders(_ ids: [String])
    /// フォルダ内のスニペットを ids の順に揃える（index を 0 から振り直す）。
    /// ids に他のフォルダのスニペットが含まれていれば、このフォルダへ移す
    func reorderSnippets(_ ids: [String], inFolder folderID: String)
    /// フォルダをスニペットごとまとめて追加する（XML の読み込み用）
    func importFolders(_ folders: [SnippetFolderRecord])
}

extension HistoryStore {
    /// サムネイル無しで追加・置き換えする
    func upsert(_ clip: ClipRecord) {
        upsert(clip, thumbnail: nil)
    }
}

extension SnippetStore {
    /// 新しく作るフォルダの番号（末尾の次）
    func nextFolderIndex() -> Int {
        return (folders().last?.index ?? -1) + 1
    }
}
