//
//  SnippetEditorNodes.swift
//
//  Thoth
//  GitHub: https://github.com/boyaki-machine/Thoth
//

import Foundation

// スニペット編集ウィンドウのアウトラインに並べる項目。
//
// NSOutlineView は項目を参照の同一性で追う（行の検索・展開状態・選択）ため、
// 値型の SnippetFolderRecord / SnippetRecord をそのまま渡さず、編集中の状態を
// 持つクラスに包む。保存は SnippetStore を通し、ここでは画面上の状態だけを持つ。

final class SnippetFolderNode {
    let id: String
    var index: Int
    var enable: Bool
    var title: String
    var snippets: [SnippetNode]

    init(_ record: SnippetFolderRecord) {
        id = record.id
        index = record.index
        enable = record.enable
        title = record.title
        snippets = record.snippets.map(SnippetNode.init)
    }

    /// 保存用の値（中のスニペットを含む）
    var record: SnippetFolderRecord {
        return SnippetFolderRecord(id: id, index: index, enable: enable, title: title,
                                   snippets: snippets.map(\.record))
    }
}

final class SnippetNode {
    let id: String
    var index: Int
    var enable: Bool
    var title: String
    var content: String

    init(_ record: SnippetRecord) {
        id = record.id
        index = record.index
        enable = record.enable
        title = record.title
        content = record.content
    }

    var record: SnippetRecord {
        return SnippetRecord(id: id, index: index, enable: enable, title: title, content: content)
    }
}
