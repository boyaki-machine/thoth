//
//  SecureMenuItem.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Copyright © 2015-2018 Clipy Project.
//

import Foundation

// MARK: - SecureMenuItem

struct SecureMenuItem: Codable {
    let itemID: String
    var title: String
    var fields: [Field]
    var displayOrder: Int

    init(itemID: String = UUID().uuidString, title: String, fields: [Field] = [], displayOrder: Int = 0) {
        self.itemID = itemID
        self.title = title
        self.fields = fields
        self.displayOrder = displayOrder
    }

    /// 過去の Val 値と、その値が別の値に置き換えられた日時
    struct FieldHistoryEntry: Codable {
        let value: String
        let replacedAt: Date
    }

    struct Field: Codable {
        /// フィールドの安定 ID。Label を変更しても Val の変更履歴が追従できるようにするためのもの
        let fieldID: String
        let label: String
        let value: String
        let isPassword: Bool
        /// Val の変更履歴（新しい値に置き換えられた旧値のリスト）。
        /// 履歴の追記・上限管理は `SecureMenuService.save(_:)` が保存時に自動で行う。
        let history: [FieldHistoryEntry]

        init(fieldID: String = UUID().uuidString, label: String, value: String,
             isPassword: Bool = false, history: [FieldHistoryEntry] = []) {
            self.fieldID = fieldID
            self.label = label
            self.value = value
            self.isPassword = isPassword
            self.history = history
        }

        /// 旧形式（`fieldID` / `history` キーなし）の保存データ・エクスポートファイルも読めるようにする
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            fieldID = try container.decodeIfPresent(String.self, forKey: .fieldID) ?? UUID().uuidString
            label = try container.decode(String.self, forKey: .label)
            value = try container.decode(String.self, forKey: .value)
            isPassword = try container.decode(Bool.self, forKey: .isPassword)
            history = try container.decodeIfPresent([FieldHistoryEntry].self, forKey: .history) ?? []
        }
    }
}

// MARK: - SecureFieldSelection

final class SecureFieldSelection: NSObject {
    let parentItemID: String
    let fieldValue: String
    let fieldIndex: Int

    init(parentItemID: String, fieldValue: String, fieldIndex: Int) {
        self.parentItemID = parentItemID
        self.fieldValue = fieldValue
        self.fieldIndex = fieldIndex
    }
}

// MARK: - SecureSelectionContext

final class SecureSelectionContext {
    private(set) var lastParentItemID: String?
    private(set) var lastFieldIndex: Int?
    private(set) var lastSelectedDate: Date?

    static let recencyWindow: TimeInterval = 30

    var isWithinWindow: Bool {
        guard let date = lastSelectedDate else { return false }
        return Date().timeIntervalSince(date) < SecureSelectionContext.recencyWindow
    }

    func record(parentItemID: String, fieldIndex: Int) {
        lastParentItemID = parentItemID
        lastFieldIndex = fieldIndex
        lastSelectedDate = Date()
    }

    func clear() {
        lastParentItemID = nil
        lastFieldIndex = nil
        lastSelectedDate = nil
    }
}
