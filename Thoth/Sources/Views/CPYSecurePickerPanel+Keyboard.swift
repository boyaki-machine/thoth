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

// MARK: - Sub-Panel

extension CPYSecurePickerPanel {
    func updateSubPanel() {
        guard isVisible else { return }
        let idx = tableView.selectedRow
        guard idx >= 0, idx < rows.count, case .parent(let item) = rows[idx],
              !item.fields.isEmpty else {
            closeSubPanel()
            return
        }
        openSubPanel(for: item, atRow: idx)
    }

    func openSubPanel(for item: SecureMenuItem, atRow rowIndex: Int) {
        let rowRectInTable  = tableView.rect(ofRow: rowIndex)
        let rowRectInWindow = tableView.convert(rowRectInTable, to: nil)
        let rowRectInScreen = convertToScreen(rowRectInWindow)

        let sub: CPYSecureSubPanel
        if let existing = subPanel {
            sub = existing
        } else {
            sub = CPYSecureSubPanel()
            sub.onFieldClicked = { [weak self] fieldIndex in
                self?.confirmField(at: fieldIndex)
            }
            // ホバーでフィールドが選択されたら、Enter で確定できるようサブパネルモードへ移る
            sub.onFieldHovered = { [weak self] _ in
                self?.isInSubPanelMode = true
            }
            subPanel = sub
            addChildWindow(sub, ordered: .above)
        }

        sub.setFields(item.fields)

        let mainFrame = frame
        let screen  = NSScreen.screens.first { $0.frame.intersects(mainFrame) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSScreen.main!.visibleFrame

        // 右側を優先し、画面右端に収まらない場合はメインパネルに被せず左側へ配置する。
        // 左側にも収まらない場合のみ右側でクランプ（被りは許容する最終手段）
        let rightX = mainFrame.maxX + 4
        let leftX  = mainFrame.minX - 4 - sub.frame.width
        let subX: CGFloat
        if rightX + sub.frame.width <= visible.maxX - 4 {
            subX = rightX
            subPanelOnLeft = false
        } else if leftX >= visible.minX + 4 {
            subX = leftX
            subPanelOnLeft = true
        } else {
            subX = max(visible.minX + 4, min(rightX, visible.maxX - sub.frame.width - 4))
            subPanelOnLeft = false
        }

        let targetTopY    = rowRectInScreen.maxY
        let targetOriginY = targetTopY - sub.frame.height
        let clampedY = max(visible.minY + 4, min(targetOriginY, visible.maxY - sub.frame.height - 4))
        sub.setFrameOrigin(NSPoint(x: subX, y: clampedY))
        sub.orderFront(nil)
    }

    func closeSubPanel() {
        guard let sub = subPanel else { return }
        sub.stopTOTPTimer()
        removeChildWindow(sub)
        sub.close()
        subPanel = nil
        isInSubPanelMode = false
        subPanelOnLeft = false
    }
}

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
            return handleSubPanelModeKey(event, searching: searching)
        }
        return handleNormalModeKey(event, searching: searching)
    }

    /// サブパネルモード（フィールド一覧の移動・確定）のキー処理
    private func handleSubPanelModeKey(_ event: NSEvent, searching: Bool) -> Bool {
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
        // → / l と ← / h はサブパネルの位置に合わせて意味を入れ替える:
        // サブが右側なら → で確定・← で親リストへ戻る、左側ならその逆
        // （検索入力中はカーソル移動を妨げないようガードする）
        case 124 where !searching, 37 where !searching:  // → / l
            if subPanelOnLeft {
                isInSubPanelMode = false
                subPanel?.deselect()
            } else {
                confirmCurrentSubPanelSelection()
            }
            return true
        case 123 where !searching, 4 where !searching:   // ← / h
            if subPanelOnLeft {
                confirmCurrentSubPanelSelection()
            } else {
                isInSubPanelMode = false
                subPanel?.deselect()
            }
            return true
        case 53:                        // Esc
            isInSubPanelMode = false
            subPanel?.deselect()
            return true
        case 44 where !searching:       // / → 検索ボックスにフォーカス
            makeFirstResponder(searchField)
            return true
        default:
            return false
        }
    }

    /// 通常モード（親アイテム一覧の移動・確定）のキー処理
    private func handleNormalModeKey(_ event: NSEvent, searching: Bool) -> Bool {
        switch Int(event.keyCode) {
        case 125:                         selectNext();                    return true  // ↓
        case 126:                         selectPrev();                    return true  // ↑
        case 38 where !searching:         selectNext();                    return true  // j
        case 40 where !searching:         selectPrev();                    return true  // k
        // → / l と ← / h はサブパネルの位置に合わせて意味を入れ替える:
        // サブが右側なら → でサブへ・← で閉じる、左側ならその逆
        // （検索入力中はカーソル移動を妨げないようガードする）
        case 124 where !searching, 37 where !searching:                                 // → / l
            if subPanelOnLeft {
                if subPanel != nil { closeSubPanel() } else { close() }
            } else {
                enterSubPanel()
            }
            return true
        case 123 where !searching, 4 where !searching:                                  // ← / h
            if subPanelOnLeft {
                enterSubPanel()
            } else {
                if subPanel != nil { closeSubPanel() } else { close() }
            }
            return true
        case 36, 76:                                                                    // Enter
            // search 中は field editor に渡す（日本語 IME の変換確定 Enter を横取りしない）
            guard !searching else { return false }
            let selectedRow = tableView.selectedRow
            if selectedRow >= 0, selectedRow < rows.count, case .manage = rows[selectedRow] {
                if isVisible { close() }; onManage?()
            } else {
                enterSubPanel()
            }
            return true
        case 53:                          handleEsc();                     return true  // Esc
        case 44 where !searching:         makeFirstResponder(searchField); return true  // /
        default:
            return false
        }
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
