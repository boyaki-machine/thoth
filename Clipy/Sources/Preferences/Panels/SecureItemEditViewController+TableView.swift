//
//  SecureItemEditViewController+TableView.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Copyright © 2015-2018 Clipy Project.
//

import Cocoa

// MARK: - NSTableViewDataSource / NSTableViewDelegate (Edit Sheet)

extension SecureItemEditViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int { fields.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let field = fields[row]
        switch tableColumn?.identifier {

        case ColID.dragHandle:
            let cellID = NSUserInterfaceItemIdentifier("editDragHandleCell")
            let cell: DragHandleCell
            if let existingCell = tableView.makeView(withIdentifier: cellID, owner: nil) as? DragHandleCell {
                cell = existingCell
            } else {
                cell = makeDragHandleCell(identifier: cellID)
            }
            cell.rowIndex = row
            return cell

        case ColID.label:
            let cellID = NSUserInterfaceItemIdentifier("editLabelCell")
            let cell = (tableView.makeView(withIdentifier: cellID, owner: nil) as? NSTableCellView)
                       ?? makeEditableTextCell(identifier: cellID, placeholder: L10n.secureFieldLabelPlaceholder)
            cell.textField?.stringValue = field.label
            cell.textField?.target = self
            cell.textField?.action = #selector(labelFieldChanged(_:))
            return cell

        case ColID.value:
            let cell = (tableView.makeView(withIdentifier: ColID.value, owner: nil) as? FieldValueCell)
                       ?? FieldValueCell()
            cell.configure(value: field.value, isPassword: field.isPassword, isTOTP: field.isTOTP,
                           createdAt: field.createdAt, target: self, action: #selector(valueFieldChanged(_:)))
            return cell

        case ColID.pass:
            let cellID = NSUserInterfaceItemIdentifier("editPassCell")
            let cell = (tableView.makeView(withIdentifier: cellID, owner: nil) as? NSTableCellView)
                       ?? makeCheckboxCell(identifier: cellID)
            if field.isTOTP {
                cell.subviews.forEach { $0.isHidden = true }
            } else {
                if let button = cell.subviews.first(where: { $0 is TabCapturingButton }) as? TabCapturingButton {
                    button.isHidden = false
                    button.state = field.isPassword ? .on : .off
                    button.target = self
                    button.action = #selector(passwordCheckboxChanged(_:))
                }
            }
            return cell

        case ColID.history:
            let cellID = NSUserInterfaceItemIdentifier("editHistoryCell")
            let cell = (tableView.makeView(withIdentifier: cellID, owner: nil) as? NSTableCellView)
                       ?? makeHistoryButtonCell(identifier: cellID)
            if field.isTOTP {
                cell.subviews.forEach { $0.isHidden = true }
            } else {
                if let button = cell.subviews.first(where: { $0 is NSButton }) as? NSButton {
                    button.isHidden = false
                    button.target = self
                    button.action = #selector(showValueHistory(_:))
                }
            }
            return cell

        default:
            return nil
        }
    }

    private func makeEditableTextCell(identifier: NSUserInterfaceItemIdentifier,
                                      placeholder: String) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = identifier
        let textField = NSTextField()
        textField.isBordered = false
        textField.drawsBackground = false
        textField.isEditable = true
        textField.placeholderString = placeholder
        textField.lineBreakMode = .byTruncatingTail
        textField.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(textField)
        cell.textField = textField
        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
            textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        return cell
    }

    private func makeCheckboxCell(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = identifier
        let button = TabCapturingButton()
        button.setButtonType(.switch)
        button.title = ""
        button.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(button)
        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: cell.centerXAnchor),
            button.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        return cell
    }

    // MARK: - Value History

    /// 指定行の Val 変更履歴をポップアップ表示する。
    /// 各項目は「置き換えられた日時 + 過去の値」で、サブメニューからコピー・削除ができる。
    /// 削除は Save で保存したタイミングで確定する。
    @objc fileprivate func showValueHistory(_ sender: NSButton) {
        let row = fieldsTable.row(for: sender)
        guard row >= 0, row < fields.count else { return }
        let menu = NSMenu()
        // 削除時に参照するため、元配列のインデックスを保持したまま新しい順に並べる
        let history = fields[row].history
        let sortedIndices = history.indices.sorted { history[$0].replacedAt > history[$1].replacedAt }
        if sortedIndices.isEmpty {
            let emptyItem = NSMenuItem(title: L10n.noValueHistory, action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy/MM/dd HH:mm"
            for originalIndex in sortedIndices {
                let entry = history[originalIndex]
                let historyItem = NSMenuItem(title: "\(formatter.string(from: entry.replacedAt))   \(entry.value)",
                                             action: nil, keyEquivalent: "")
                let submenu = NSMenu()
                let copyItem = NSMenuItem(title: L10n.copyPassword, action: #selector(copyHistoryValue(_:)), keyEquivalent: "")
                copyItem.target = self
                copyItem.representedObject = entry.value
                submenu.addItem(copyItem)
                let deleteItem = NSMenuItem(title: L10n.deleteSecureItem, action: #selector(deleteHistoryEntry(_:)), keyEquivalent: "")
                deleteItem.target = self
                deleteItem.representedObject = [row, originalIndex]
                submenu.addItem(deleteItem)
                historyItem.submenu = submenu
                menu.addItem(historyItem)
            }
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    @objc private func copyHistoryValue(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        // 過去のパスワード値のコピーなので秘匿マーカー付きで書き込み、
        // 一定時間後（他のコピーが無ければ）自動クリアする
        AppEnvironment.current.pasteService.copyConcealedToPasteboard(with: value)
        AppEnvironment.current.pasteService.scheduleConcealedClear()
    }

    /// 対象の履歴エントリをフィールドから取り除く（Save 押下で保存に反映される）
    @objc private func deleteHistoryEntry(_ sender: NSMenuItem) {
        guard let reference = sender.representedObject as? [Int], reference.count == 2 else { return }
        let row = reference[0]
        let historyIndex = reference[1]
        guard row >= 0, row < fields.count else { return }
        let field = fields[row]
        guard historyIndex >= 0, historyIndex < field.history.count else { return }
        var history = field.history
        history.remove(at: historyIndex)
        fields[row] = SecureMenuItem.Field(fieldID: field.fieldID, label: field.label,
                                           value: field.value, isPassword: field.isPassword,
                                           kind: field.kind, history: history)
    }

    /// Val 変更履歴のポップアップを開くボタンセル
    private func makeHistoryButtonCell(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = identifier
        let button = NSButton()
        button.title = "🕘"
        button.bezelStyle = .smallSquare
        button.toolTip = L10n.valueHistory
        button.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(button)
        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: cell.centerXAnchor),
            button.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            button.widthAnchor.constraint(equalToConstant: 26),
            button.heightAnchor.constraint(equalToConstant: 20)
        ])
        return cell
    }

    /// ドラッグハンドル列のセル（≡ アイコン）
    /// テキストフィールドの代わりにカスタムビューを使用して、マウスイベントをテーブルビューに伝播させる
    private func makeDragHandleCell(identifier: NSUserInterfaceItemIdentifier) -> DragHandleCell {
        let cell = DragHandleCell()
        cell.identifier = identifier
        cell.tableView = fieldsTable
        let labelView = DragHandleLabel()
        labelView.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(labelView)
        NSLayoutConstraint.activate([
            labelView.leadingAnchor.constraint(equalTo: cell.leadingAnchor),
            labelView.trailingAnchor.constraint(equalTo: cell.trailingAnchor),
            labelView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            labelView.heightAnchor.constraint(equalToConstant: 20)
        ])
        return cell
    }
}

// MARK: - DragHandleLabel

/// ドラッグハンドル列のラベルビュー。
/// マウスイベントを処理せず、親ビュー（テーブルビュー）に伝播させる。
final class DragHandleLabel: NSView {
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let string = "≡"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.tertiaryLabelColor
        ]
        let attributedString = NSAttributedString(string: string, attributes: attributes)
        let size = attributedString.size()
        let point = NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2)
        attributedString.draw(at: point)
    }

    /// マウスイベントを受け付けない（hitTest で常に nil を返す）
    /// これにより、イベントは親ビュー（テーブルビュー）に伝播する
    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }
}

// MARK: - DragHandleCell

/// ドラッグハンドル列のカスタムセル。
/// NSTableView が行選択とドラッグ処理を自動的に行うよう、
/// セル内のビューがマウスイベントを消費しないようにする。
final class DragHandleCell: NSTableCellView {
    weak var tableView: NSTableView?
    var rowIndex: Int = -1
}

// MARK: - FieldValueCell

/// Value 列のセルビュー。
/// プレーンテキスト用 NSTextField と、パスワード用 NSSecureTextField を重ねて配置し、
/// `configure(value:isPassword:target:action:)` で一方を表示・他方を非表示に切り替える。
/// Tab ナビゲーションでは `textField`（アクティブな方）に直接フォーカスする。
final class FieldValueCell: NSTableCellView {
    let plainField  = NSTextField()
    let secureField = NSSecureTextField()

    override init(frame: NSRect) {
        super.init(frame: frame)
        identifier = NSUserInterfaceItemIdentifier("fValue")
        for textField in [plainField, secureField] as [NSTextField] {
            textField.isBordered = false
            textField.drawsBackground = false
            textField.isEditable = true
            textField.lineBreakMode = .byTruncatingTail
            textField.placeholderString = L10n.secureFieldValuePlaceholder
            textField.translatesAutoresizingMaskIntoConstraints = false
            addSubview(textField)
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
                textField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
                textField.centerYAnchor.constraint(equalTo: centerYAnchor)
            ])
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// フィールドの表示モードを設定する。
    /// `isPassword` が `true` の場合は secureField を、`false` の場合は plainField を表示する。
    /// `isTOTP` が `true` の場合は値を表示せず、プレースホルダーに作成日時を表示し、編集不可にする。
    /// `textField` プロパティにアクティブなフィールドを設定することで
    /// Tab ナビゲーションからのフォーカスを可能にする。
    func configure(value: String, isPassword: Bool, isTOTP: Bool = false, createdAt: Date = Date(),
                   target: AnyObject, action: Selector) {
        if isTOTP {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            plainField.stringValue = ""
            plainField.placeholderString = formatter.string(from: createdAt) + " 登録"
            plainField.isEditable = false
            plainField.target = nil
            plainField.action = nil
            secureField.isHidden = true
            plainField.isHidden = false
            textField = plainField
        } else if isPassword {
            secureField.stringValue = value
            secureField.target = target
            secureField.action = action
            secureField.isEditable = true
            plainField.isHidden  = true
            secureField.isHidden = false
            textField = secureField
        } else {
            plainField.stringValue = value
            plainField.target = target
            plainField.action = action
            plainField.isEditable = true
            secureField.isHidden = true
            plainField.isHidden  = false
            textField = plainField
        }
    }

    /// 現在表示中のフィールドの入力値を返す。
    var currentValue: String {
        secureField.isHidden ? plainField.stringValue : secureField.stringValue
    }
}

// MARK: - TabCapturingButton

/// `acceptsFirstResponder` を `true` にオーバーライドした NSButton。
/// `makeFirstResponder` で確実にフォーカスを受け取れるようにするため、
/// Tab ナビゲーションのフォーカス対象ボタン（+/-/Cancel/Save）に使用する。
/// Tab イベント自体は `SecureItemEditViewController` のローカルイベントモニターが処理する。
final class TabCapturingButton: NSButton {
    override var acceptsFirstResponder: Bool { true }
}
