//
//  CPYSecurePickerPanel+Keyboard.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Copyright © 2015-2018 Clipy Project.
//

import Cocoa

// MARK: - Page Navigation

extension CPYSecurePickerPanel {
    func goToPrevPage() {
        guard currentPage > 0 else { return }
        isInSubPanelMode = false
        currentPage -= 1
        rebuildRows()
    }

    func goToNextPage() {
        let total = max(1, (allFilteredItems.count + Layout.pageSize - 1) / Layout.pageSize)
        guard currentPage < total - 1 else { return }
        isInSubPanelMode = false
        currentPage += 1
        rebuildRows()
    }
}

// MARK: - Keyboard

extension CPYSecurePickerPanel {
    /// keyDown イベントを処理する。処理した場合は true を返し、
    /// false の場合は呼び出し元（`sendEvent`）が super へ委譲する。
    func handleKeyDown(_ event: NSEvent) -> Bool {
        let searching = searchField.currentEditor() != nil

        // ── グローバルホットキー（サブパネルモード問わず動作）────────────
        if !searching {
            let ctrl = event.modifierFlags.contains(.control)
            switch Int(event.keyCode) {
            case 37 where ctrl:  goToNextPage(); return true   // Ctrl+L → 次ページ
            case 124 where ctrl: goToNextPage(); return true   // Ctrl+→ → 次ページ
            case 4 where ctrl:   goToPrevPage(); return true   // Ctrl+H → 前ページ
            case 123 where ctrl: goToPrevPage(); return true   // Ctrl+← → 前ページ
            case 35:             if isVisible { close() }; onManage?(); return true  // p → 管理
            default: break
            }
        }

        if isInSubPanelMode {
            switch Int(event.keyCode) {
            case 125:                       // ↓
                if !(subPanel?.selectNext() ?? false) {
                    isInSubPanelMode = false
                    selectNext()
                    if subPanel != nil { isInSubPanelMode = true; subPanel?.selectFirst() }
                }
                return true
            case 38 where !searching:       // j
                if !(subPanel?.selectNext() ?? false) {
                    isInSubPanelMode = false
                    selectNext()
                    if subPanel != nil { isInSubPanelMode = true; subPanel?.selectFirst() }
                }
                return true
            case 126:                       // ↑
                if !(subPanel?.selectPrev() ?? false) {
                    isInSubPanelMode = false
                    selectPrev()
                    if subPanel != nil { isInSubPanelMode = true; subPanel?.selectLast() }
                }
                return true
            case 40 where !searching:       // k
                if !(subPanel?.selectPrev() ?? false) {
                    isInSubPanelMode = false
                    selectPrev()
                    if subPanel != nil { isInSubPanelMode = true; subPanel?.selectLast() }
                }
                return true
            case 36, 76:                    // Enter / Numpad Enter
                confirmCurrentSubPanelSelection(); return true
            case 124:                       // →
                confirmCurrentSubPanelSelection(); return true
            case 37 where !searching:       // l
                confirmCurrentSubPanelSelection(); return true
            case 123, 4 where !searching:   // ← / h → サブパネルモードを抜ける
                isInSubPanelMode = false
                subPanel?.deselect()
                return true
            case 53:                        // Esc
                isInSubPanelMode = false
                subPanel?.deselect()
                return true
            case 44 where !searching:       // / → 検索ボックスにフォーカス
                makeFirstResponder(searchField)
                return true
            default: break
            }
        } else {
            switch Int(event.keyCode) {
            case 125:                         selectNext();                    return true  // ↓
            case 126:                         selectPrev();                    return true  // ↑
            case 38 where !searching:         selectNext();                    return true  // j
            case 40 where !searching:         selectPrev();                    return true  // k
            case 124, 37 where !searching:    enterSubPanel();                 return true  // → / l
            case 36, 76:                                                                    // Enter
                // search 中は field editor に渡す（日本語 IME の変換確定 Enter を横取りしない）
                guard !searching else { break }
                let selectedRow = tableView.selectedRow
                if selectedRow >= 0, selectedRow < rows.count, case .manage = rows[selectedRow] {
                    if isVisible { close() }; onManage?()
                } else {
                    enterSubPanel()
                }
                return true
            case 123, 4 where !searching:                                                   // ← / h
                if subPanel != nil { closeSubPanel() } else { close() }
                return true
            case 53:                          handleEsc();                     return true  // Esc
            case 44 where !searching:         makeFirstResponder(searchField); return true  // /
            default: break
            }
        }
        return false
    }
}

// MARK: - Click

extension CPYSecurePickerPanel {
    @objc func rowClicked() {
        let clicked = tableView.clickedRow
        guard clicked >= 0 else { return }
        tableView.selectRowIndexes(IndexSet(integer: clicked), byExtendingSelection: false)
        switch rows[clicked] {
        case .parent:
            isInSubPanelMode = false
            updateSubPanel()
        case .manage:
            if isVisible { close() }; onManage?()
        default: break
        }
    }

    func makeTextCell(identifier: NSUserInterfaceItemIdentifier,
                      indent: CGFloat = 6) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = identifier
        let textField = NSTextField(labelWithString: "")
        textField.lineBreakMode = .byTruncatingTail
        textField.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(textField)
        cell.textField = textField
        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: indent),
            textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
            textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        return cell
    }
}
