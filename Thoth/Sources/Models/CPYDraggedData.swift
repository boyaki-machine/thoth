//
//  CPYDraggedData.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Econa77 on 2016/07/14.
//
//  Copyright © 2015-2018 Clipy Project.
//

import Foundation

/// スニペットエディタのドラッグ&ドロップで、ペーストボードに載せて運ぶ「何をどこから動かすか」。
///
/// ドラッグ用のペーストボードは他のアプリからも書き込めるため、復元は NSSecureCoding で
/// この型と文字列だけに限る（任意のクラスを生成させない）。
final class CPYDraggedData: NSObject, NSSecureCoding {

    static var supportsSecureCoding: Bool { true }

    // MARK: - Properties
    let type: DragType
    let folderIdentifier: String?
    let snippetIdentifier: String?
    let index: Int

    // MARK: - Enums
    enum DragType: Int {
        case folder, snippet
    }

    // MARK: - Initialize
    init(type: DragType, folderIdentifier: String?, snippetIdentifier: String?, index: Int) {
        self.type = type
        self.folderIdentifier = folderIdentifier
        self.snippetIdentifier = snippetIdentifier
        self.index = index
        super.init()
    }

    // MARK: - NSCoding
    required init?(coder aDecoder: NSCoder) {
        self.type = DragType(rawValue: aDecoder.decodeInteger(forKey: "type")) ?? .folder
        self.folderIdentifier = aDecoder.decodeObject(of: NSString.self, forKey: "folderIdentifier") as String?
        self.snippetIdentifier = aDecoder.decodeObject(of: NSString.self, forKey: "snippetIdentifier") as String?
        self.index = aDecoder.decodeInteger(forKey: "index")
        super.init()
    }

    func encode(with aCoder: NSCoder) {
        aCoder.encode(type.rawValue, forKey: "type")
        aCoder.encode(folderIdentifier, forKey: "folderIdentifier")
        aCoder.encode(snippetIdentifier, forKey: "snippetIdentifier")
        aCoder.encode(index, forKey: "index")
    }
}

// MARK: - Pasteboard
extension CPYDraggedData {
    /// ペーストボードに載せるデータ
    func archivedData() -> Data? {
        return try? NSKeyedArchiver.archivedData(withRootObject: self, requiringSecureCoding: true)
    }

    /// ペーストボードのデータから復元する。この型以外（細工されたデータ・別の型）は nil
    static func unarchived(from data: Data) -> CPYDraggedData? {
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: CPYDraggedData.self, from: data)
    }

    /// `source` にある要素を、ドロップ位置 `destination`（動かす前の並びでの挿入位置。
    /// NSOutlineView の childIndex）へ動かした並びを返す。位置が範囲外・動かない場合は nil
    static func reordered<Element>(_ items: [Element], from source: Int, to destination: Int) -> [Element]? {
        guard items.indices.contains(source), (0...items.count).contains(destination),
              destination != source, destination != source + 1 else { return nil }
        var result = items
        result.insert(result[source], at: destination)
        result.remove(at: destination < source ? source + 1 : source)
        return result
    }
}
