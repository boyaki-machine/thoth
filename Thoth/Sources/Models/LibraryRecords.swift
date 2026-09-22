//
//  LibraryRecords.swift
//
//  Thoth
//  GitHub: https://github.com/boyaki-machine/Thoth
//

import Foundation

// 保存層（HistoryStore / SnippetStore）とアプリの間でやり取りする値型。
//
// 保存先（Realm / SwiftData）のオブジェクトはスレッドをまたげず、暗号化も
// 保存層の中に閉じ込めたいため、UI・サービスはこの値型だけを扱う。
// 中身は常に平文（復号済み）。

/// 履歴クリップ 1 件
struct ClipRecord: Equatable {
    /// 主キー。「同じ内容を上書き」設定では内容から決まり、同じ内容なら同じ値になる
    var id: String
    /// クリップ実データ（.data ファイル）の絶対パス
    var dataPath: String
    /// メニューに表示するタイトル（文字列値の先頭部分）
    var title: String
    /// 代表のペーストボード型（アイコン・特殊タイトルの判定に使用）
    var primaryType: String
    /// コピーされた時刻（UNIX 時間。並び順・上限判定に使用）
    var updateTime: Int
    /// サムネイル画像のキャッシュキー（画像クリップのみ。無ければ空）
    var thumbnailPath: String
    /// HEX カラーコードとして解釈できる内容か（カラープレビュー表示用）
    var isColorCode: Bool
}

/// スニペットフォルダ 1 件（中のスニペットを index 順に持つ）
struct SnippetFolderRecord: Equatable {
    var id: String
    var index: Int
    var enable: Bool
    var title: String
    var snippets: [SnippetRecord]

    init(id: String = UUID().uuidString, index: Int, enable: Bool = true, title: String,
         snippets: [SnippetRecord] = []) {
        self.id = id
        self.index = index
        self.enable = enable
        self.title = title
        self.snippets = snippets
    }
}

/// スニペット 1 件
struct SnippetRecord: Equatable {
    var id: String
    var index: Int
    var enable: Bool
    var title: String
    var content: String

    init(id: String = UUID().uuidString, index: Int, enable: Bool = true, title: String,
         content: String = "") {
        self.id = id
        self.index = index
        self.enable = enable
        self.title = title
        self.content = content
    }
}
