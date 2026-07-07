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
    let id: String
    var title: String
    var fields: [Field]
    var displayOrder: Int

    init(id: String = UUID().uuidString, title: String, fields: [Field] = [], displayOrder: Int = 0) {
        self.id = id
        self.title = title
        self.fields = fields
        self.displayOrder = displayOrder
    }

    struct Field: Codable {
        let label: String
        let value: String
        let isPassword: Bool

        init(label: String, value: String, isPassword: Bool = false) {
            self.label = label
            self.value = value
            self.isPassword = isPassword
        }
    }
}

// MARK: - SecureFieldSelection

final class SecureFieldSelection: NSObject {
    let parentItemId: String
    let fieldValue: String
    let fieldIndex: Int

    init(parentItemId: String, fieldValue: String, fieldIndex: Int) {
        self.parentItemId = parentItemId
        self.fieldValue = fieldValue
        self.fieldIndex = fieldIndex
    }
}

// MARK: - SecureSelectionContext

final class SecureSelectionContext {
    private(set) var lastParentItemId: String?
    private(set) var lastFieldIndex: Int?
    private(set) var lastSelectedDate: Date?

    static let recencyWindow: TimeInterval = 30

    var isWithinWindow: Bool {
        guard let date = lastSelectedDate else { return false }
        return Date().timeIntervalSince(date) < SecureSelectionContext.recencyWindow
    }

    func record(parentItemId: String, fieldIndex: Int) {
        lastParentItemId = parentItemId
        lastFieldIndex = fieldIndex
        lastSelectedDate = Date()
    }

    func clear() {
        lastParentItemId = nil
        lastFieldIndex = nil
        lastSelectedDate = nil
    }
}
