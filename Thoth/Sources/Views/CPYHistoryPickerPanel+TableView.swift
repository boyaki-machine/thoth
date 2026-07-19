//
//  CPYHistoryPickerPanel+TableView.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Copyright © 2015-2018 Clipy Project.
//

import Cocoa

// MARK: - Sub-Panel

extension CPYHistoryPickerPanel {
    /// 選択中の行がグループなら右側サブパネルにそのクリップ一覧を表示する
    func updateSubPanel() {
        guard isVisible else { return }
        let idx = tableView.selectedRow
        guard idx >= 0, idx < rows.count, case .group(let group) = rows[idx],
              !group.clips.isEmpty else {
            closeSubPanel()
            return
        }
        openSubPanel(for: group, atRow: idx)
    }

    func openSubPanel(for group: ClipGroup, atRow rowIndex: Int) {
        let rowRectInTable  = tableView.rect(ofRow: rowIndex)
        let rowRectInWindow = tableView.convert(rowRectInTable, to: nil)
        let rowRectInScreen = convertToScreen(rowRectInWindow)

        let sub: CPYHistorySubPanel
        if let existing = subPanel {
            sub = existing
        } else {
            sub = CPYHistorySubPanel()
            sub.onClipClicked = { [weak self] clipIndex in
                self?.confirmSubClip(at: clipIndex)
            }
            // ホバーでクリップが選択されたら、Enter で確定できるようサブパネルモードへ移る
            sub.onClipHovered = { [weak self] _ in
                self?.isInSubPanelMode = true
            }
            subPanel = sub
            addChildWindow(sub, ordered: .above)
        }

        sub.setClips(group.clips)

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
        removeChildWindow(sub)
        sub.close()
        subPanel = nil
        isInSubPanelMode = false
        subPanelOnLeft = false
    }

    /// サブパネルへキーボード操作の対象を移す（→ / l / Enter）
    func enterSubPanel() {
        guard let sub = subPanel, !sub.currentClips.isEmpty else { return }
        isInSubPanelMode = true
        sub.selectFirst()
    }

    /// サブパネル内の指定クリップを確定する（クリック・Enter の両方から呼ばれる）
    func confirmSubClip(at clipIndex: Int) {
        guard let sub = subPanel,
              clipIndex >= 0, clipIndex < sub.currentClips.count else { return }
        onSelect?(sub.currentClips[clipIndex].dataHash)
    }
}

// MARK: - Selection / Navigation

extension CPYHistoryPickerPanel {
    func selectNext() {
        var nextIdx = tableView.selectedRow + 1
        while nextIdx < rows.count, !rows[nextIdx].isSelectable { nextIdx += 1 }
        guard nextIdx < rows.count else { return }
        tableView.selectRowIndexes(IndexSet(integer: nextIdx), byExtendingSelection: false)
        tableView.scrollRowToVisible(nextIdx)
        isInSubPanelMode = false
        updateSubPanel()
    }

    func selectPrev() {
        var prevIdx = tableView.selectedRow - 1
        while prevIdx >= 0, !rows[prevIdx].isSelectable { prevIdx -= 1 }
        guard prevIdx >= 0 else { return }
        tableView.selectRowIndexes(IndexSet(integer: prevIdx), byExtendingSelection: false)
        tableView.scrollRowToVisible(prevIdx)
        isInSubPanelMode = false
        updateSubPanel()
    }

    /// 選択中の行を確定する。グループはサブパネルへ、固定行はアクション実行
    /// （クローズは onSelect / onAction 側で行う）
    func confirmSelection() {
        let idx = tableView.selectedRow
        guard idx >= 0, idx < rows.count else { return }
        switch rows[idx] {
        case .group:
            enterSubPanel()
        case .action(let action):
            onAction?(action)
        default:
            break
        }
    }

    /// 数字キーで、表示中のサブパネル内のアイテムを直接確定する（NSMenu の
    /// フォルダ内数字ショートカットに相当）。数字は元の位置の下 1 桁に対応し、
    /// 例えばグループ "10 - 19" 表示中に 5 を押すと元 15 番目のクリップが確定する。
    /// サブパネルが表示されていない場合は何もしない
    func confirmSubClip(withDigit digit: Int) {
        guard let sub = subPanel, sub.isVisible else { return }
        guard let clipIndex = sub.currentClips.firstIndex(where: { $0.index % Layout.groupSize == digit }) else { return }
        confirmSubClip(at: clipIndex)
    }

    /// Esc の段階制: サブパネルを抜ける → クエリ消去 → リストへフォーカス → クローズ
    func handleEsc() {
        if isInSubPanelMode {
            isInSubPanelMode = false
            subPanel?.deselect()
        } else if !searchField.stringValue.isEmpty {
            searchField.stringValue = ""
            rebuildRows()
        } else if searchField.currentEditor() != nil {
            makeFirstResponder(tableView)
        } else {
            close()
        }
    }
}

// MARK: - NSTableViewDataSource

extension CPYHistoryPickerPanel: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
}

// MARK: - NSTableViewDelegate

extension CPYHistoryPickerPanel: NSTableViewDelegate {

    func tableView(_ tableView: NSTableView,
                   viewFor tableColumn: NSTableColumn?,
                   row: Int) -> NSView? {
        switch rows[row] {
        case .sectionHeader(let title):
            let cell = (tableView.makeView(withIdentifier: CellID.header, owner: nil) as? NSTableCellView)
                       ?? makeTextCell(identifier: CellID.header)
            cell.textField?.stringValue = title
            cell.textField?.font      = .systemFont(ofSize: NSFont.smallSystemFontSize)
            cell.textField?.textColor = .secondaryLabelColor
            return cell

        case .group(let group):
            let cell = (tableView.makeView(withIdentifier: CellID.group, owner: nil) as? NSTableCellView)
                       ?? makeTextCell(identifier: CellID.group)
            cell.textField?.stringValue = "▸ \(group.title)"
            cell.textField?.font = .boldSystemFont(ofSize: Layout.fontSize)
            return cell

        case .separator:
            if let existing = tableView.makeView(withIdentifier: CellID.sep, owner: nil) { return existing }
            let sepView = NSView()
            sepView.identifier = CellID.sep
            let box = NSBox()
            box.boxType = .separator
            box.translatesAutoresizingMaskIntoConstraints = false
            sepView.addSubview(box)
            NSLayoutConstraint.activate([
                box.leadingAnchor.constraint(equalTo: sepView.leadingAnchor),
                box.trailingAnchor.constraint(equalTo: sepView.trailingAnchor),
                box.centerYAnchor.constraint(equalTo: sepView.centerYAnchor)
            ])
            return sepView

        case .action(let action):
            let cell = (tableView.makeView(withIdentifier: CellID.action, owner: nil) as? NSTableCellView)
                       ?? makeTextCell(identifier: CellID.action)
            cell.textField?.stringValue = action.title
            cell.textField?.font = .systemFont(ofSize: Layout.fontSize)
            return cell

        case .noResults:
            let cell = (tableView.makeView(withIdentifier: CellID.info, owner: nil) as? NSTableCellView)
                       ?? makeTextCell(identifier: CellID.info, indent: 14)
            cell.textField?.stringValue = L10n.secureMenuNoResults
            cell.textField?.font        = .systemFont(ofSize: Layout.fontSize)
            cell.textField?.textColor   = .secondaryLabelColor
            return cell
        }
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        switch rows[row] {
        case .separator:     return Layout.sepRowH
        case .sectionHeader: return Layout.headerRowH
        default:             return Layout.rowH
        }
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        rows[row].isSelectable
    }
}

// MARK: - NSSearchFieldDelegate

extension CPYHistoryPickerPanel: NSSearchFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        guard (obj.object as? NSSearchField) === searchField else { return }
        rebuildRows()
    }
}

// MARK: - Keyboard

extension CPYHistoryPickerPanel {
    /// keyDown イベントを処理する。処理した場合は true を返し、
    /// false の場合は呼び出し元（`sendEvent`）が super へ委譲する。
    ///
    /// セキュアアイテムパネルと同じ 2 モード制:
    /// - 通常モード: グループ行・固定行を移動。→ / l / Enter でサブパネルへ
    /// - サブパネルモード: グループ内クリップを移動。端で隣のグループへロールオーバー
    ///
    /// 検索欄フォーカス中（searching）でも ↓↑ と Enter はリスト操作として扱う。
    /// ただし IME 変換中（composing）は候補ウィンドウの操作を奪わないよう素通しする
    /// （変換確定の Enter・候補移動の ↓↑ を横取りしない）
    func handleKeyDown(_ event: NSEvent) -> Bool {
        let searching = searchField.currentEditor() != nil
        let composing = (searchField.currentEditor() as? NSTextView)?.hasMarkedText() == true

        // 旧メニューのショートカットとの互換: 非検索時の p / e / 数字キー
        if !searching, let chars = event.charactersIgnoringModifiers,
           event.modifierFlags.isDisjoint(with: [.command, .option, .control]) {
            switch chars {
            case "p":
                onAction?(.generatePassword)
                return true
            case "e":
                onAction?(.crypto)
                return true
            case "0"..."9":
                if let number = Int(chars) {
                    confirmSubClip(withDigit: number)
                    return true
                }
            default:
                break
            }
        }

        if isInSubPanelMode {
            return handleSubPanelModeKey(event, searching: searching, composing: composing)
        }
        return handleNormalModeKey(event, searching: searching, composing: composing)
    }

    /// 通常モード（グループ行・固定行の移動）のキー処理
    private func handleNormalModeKey(_ event: NSEvent, searching: Bool, composing: Bool) -> Bool {
        switch Int(event.keyCode) {
        case 125:                       // ↓
            if composing { return false }
            selectNext()
            return true
        case 126:                       // ↑
            if composing { return false }
            selectPrev()
            return true
        case 38 where !searching:       // j
            selectNext()
            return true
        case 40 where !searching:       // k
            selectPrev()
            return true
        // → / l と ← / h はサブパネルの位置に合わせて意味を入れ替える:
        // サブが右側なら → でサブへ・← で閉じる、左側なら ← でサブへ・→ で閉じる
        // （検索入力中はカーソル移動を妨げないようガードする）
        case 124 where !searching, 37 where !searching:  // → / l
            if subPanelOnLeft { close() } else { enterSubPanel() }
            return true
        case 123 where !searching, 4 where !searching:  // ← / h
            if subPanelOnLeft { enterSubPanel() } else { close() }
            return true
        case 36, 76:                    // Enter / Numpad Enter
            if searching && composing { return false }
            confirmSelection()
            return true
        case 53:                        // Esc（サブ解除 → クエリ消去 → リストへ → クローズの段階制）
            handleEsc()
            return true
        case 44 where !searching:       // / → 検索ボックスにフォーカス
            makeFirstResponder(searchField)
            return true
        default:
            return false
        }
    }

    /// サブパネルモード（グループ内クリップの移動・確定）のキー処理。
    /// 端に達したら隣のグループへロールオーバーする（セキュアパネルと同じ）
    private func handleSubPanelModeKey(_ event: NSEvent, searching: Bool, composing: Bool) -> Bool {
        switch Int(event.keyCode) {
        case 125, 38 where !searching:  // ↓ / j
            if composing { return false }
            if !(subPanel?.selectNext() ?? false) {
                isInSubPanelMode = false
                selectNextGroupOnly()
                if subPanel != nil { isInSubPanelMode = true; subPanel?.selectFirst() }
            }
            return true
        case 126, 40 where !searching:  // ↑ / k
            if composing { return false }
            if !(subPanel?.selectPrev() ?? false) {
                isInSubPanelMode = false
                selectPrevGroupOnly()
                if subPanel != nil { isInSubPanelMode = true; subPanel?.selectLast() }
            }
            return true
        case 36, 76:                    // Enter / Numpad Enter
            if searching && composing { return false }
            if let sub = subPanel { confirmSubClip(at: sub.selectedClipIndex) }
            return true
        // → / l と ← / h はサブパネルの位置に合わせて意味を入れ替える:
        // サブが右側なら → で確定・← でグループ列へ戻る、左側ならその逆
        // （検索入力中はカーソル移動を妨げないようガードする）
        case 124 where !searching, 37 where !searching:  // → / l
            if subPanelOnLeft {
                isInSubPanelMode = false
                subPanel?.deselect()
            } else if let sub = subPanel {
                confirmSubClip(at: sub.selectedClipIndex)
            }
            return true
        case 123 where !searching, 4 where !searching:  // ← / h
            if subPanelOnLeft {
                if let sub = subPanel { confirmSubClip(at: sub.selectedClipIndex) }
            } else {
                isInSubPanelMode = false
                subPanel?.deselect()
            }
            return true
        case 53:                        // Esc
            handleEsc()
            return true
        case 44 where !searching:       // / → 検索ボックスにフォーカス
            makeFirstResponder(searchField)
            return true
        default:
            return false
        }
    }

    /// グループ行のみを対象に次の行へ移動する（固定行へは進まない。ロールオーバー用）
    private func selectNextGroupOnly() {
        let current = tableView.selectedRow
        var nextIdx = current + 1
        while nextIdx < rows.count {
            if case .group = rows[nextIdx] { break }
            nextIdx += 1
        }
        guard nextIdx < rows.count, case .group = rows[nextIdx] else { return }
        tableView.selectRowIndexes(IndexSet(integer: nextIdx), byExtendingSelection: false)
        tableView.scrollRowToVisible(nextIdx)
        updateSubPanel()
    }

    /// グループ行のみを対象に前の行へ移動する（ロールオーバー用）
    private func selectPrevGroupOnly() {
        let current = tableView.selectedRow
        var prevIdx = current - 1
        while prevIdx >= 0 {
            if case .group = rows[prevIdx] { break }
            prevIdx -= 1
        }
        guard prevIdx >= 0, case .group = rows[prevIdx] else { return }
        tableView.selectRowIndexes(IndexSet(integer: prevIdx), byExtendingSelection: false)
        tableView.scrollRowToVisible(prevIdx)
        updateSubPanel()
    }
}

// MARK: - Click

extension CPYHistoryPickerPanel {
    @objc func rowClicked() {
        let clicked = tableView.clickedRow
        guard clicked >= 0, clicked < rows.count else { return }
        switch rows[clicked] {
        case .group:
            // グループはクリックで選択し、サブパネルを表示する（確定はサブパネル側で）
            tableView.selectRowIndexes(IndexSet(integer: clicked), byExtendingSelection: false)
            isInSubPanelMode = false
            updateSubPanel()
        case .action:
            tableView.selectRowIndexes(IndexSet(integer: clicked), byExtendingSelection: false)
            confirmSelection()
        default:
            break
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
