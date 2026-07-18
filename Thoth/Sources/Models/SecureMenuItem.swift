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

        /// フィールドの種別。`.totp` の場合、`value` には TOTP secret（`otpauth://` URI または Base32 secret）を保持し、
        /// 選択時にその時点のワンタイムコードを計算して出力する。
        enum Kind: String, Codable {
            case plain
            case totp
        }

        /// フィールドの安定 ID。Label を変更しても Val の変更履歴が追従できるようにするためのもの
        let fieldID: String
        let label: String
        let value: String
        let isPassword: Bool
        /// フィールド種別（旧データには存在しないため decode 時は `.plain` にフォールバック）
        let kind: Kind
        /// Val の変更履歴（新しい値に置き換えられた旧値のリスト）。
        /// 履歴の追記・上限管理は `SecureMenuService.save(_:)` が保存時に自動で行う。
        let history: [FieldHistoryEntry]
        /// フィールド作成日時。TOTP フィールドの場合、編集画面で作成日時をプレースホルダーに表示する。
        let createdAt: Date

        var isTOTP: Bool { kind == .totp }

        init(fieldID: String = UUID().uuidString, label: String, value: String,
             isPassword: Bool = false, kind: Kind = .plain, history: [FieldHistoryEntry] = [],
             createdAt: Date = Date()) {
            self.fieldID = fieldID
            self.label = label
            self.value = value
            self.isPassword = isPassword
            self.kind = kind
            self.history = history
            self.createdAt = createdAt
        }

        /// 旧形式（`fieldID` / `kind` / `history` / `createdAt` キーなし）の保存データ・エクスポートファイルも読めるようにする
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            fieldID = try container.decodeIfPresent(String.self, forKey: .fieldID) ?? UUID().uuidString
            label = try container.decode(String.self, forKey: .label)
            value = try container.decode(String.self, forKey: .value)
            isPassword = try container.decode(Bool.self, forKey: .isPassword)
            kind = try container.decodeIfPresent(Kind.self, forKey: .kind) ?? .plain
            history = try container.decodeIfPresent([FieldHistoryEntry].self, forKey: .history) ?? []
            createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        }
    }
}

// MARK: - SecureFieldSelection

final class SecureFieldSelection: NSObject {
    let parentItemID: String
    /// 通常フィールドはペーストする文字列。TOTP フィールドの場合は secret（`value`）を保持し、
    /// 出力時に TOTPService でその時点のコードを計算する。
    let fieldValue: String
    let fieldIndex: Int
    let kind: SecureMenuItem.Field.Kind

    var isTOTP: Bool { kind == .totp }

    init(parentItemID: String, fieldValue: String, fieldIndex: Int,
         kind: SecureMenuItem.Field.Kind = .plain) {
        self.parentItemID = parentItemID
        self.fieldValue = fieldValue
        self.fieldIndex = fieldIndex
        self.kind = kind
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
