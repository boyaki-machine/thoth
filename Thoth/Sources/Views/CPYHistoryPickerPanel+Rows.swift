//
//  CPYHistoryPickerPanel+Rows.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Copyright © 2015-2018 Clipy Project.
//

import Cocoa

// MARK: - Data / Rows

extension CPYHistoryPickerPanel {

    /// タイトルまたは全文に全検索語が含まれるクリップを返す（純粋関数・テスト対象）。
    /// 空クエリのときは全件をそのまま返す。元の並び順を維持する
    static func filter(items: [ClipItem], fullText: [String: String], query: String) -> [ClipItem] {
        let terms = ClipFullTextIndexer.terms(from: query)
        guard !terms.isEmpty else { return items }
        return items.filter { item in
            if ClipFullTextIndexer.matches(item.lowercasedTitle, terms: terms) { return true }
            return fullText[item.dataHash].map { ClipFullTextIndexer.matches($0, terms: terms) } ?? false
        }
    }

    /// フィルタ結果を「元の位置」に基づいてインライン部と groupSize 件区切りのグループへ
    /// 振り分ける（純粋関数・テスト対象）。
    /// 検索時も前に詰めず、ヒットは元の位置のインライン枠 / グループに残る。
    /// ヒットの無いグループは含まれない。ラベルの範囲は全履歴数と番号開始値
    /// （numberOffset: 0 開始 or 1 開始）に基づく元の区切りを表す
    static func makeLayout(items: [ClipItem], fullText: [String: String], query: String,
                           totalCount: Int, spec: LayoutSpec) -> (inline: [ClipItem], groups: [ClipGroup]) {
        let matched = filter(items: items, fullText: fullText, query: query)
        var inline = [ClipItem]()
        var buckets = [Int: [ClipItem]]()
        for item in matched {
            if item.index < spec.placeInline {
                inline.append(item)
            } else {
                buckets[(item.index - spec.placeInline) / spec.groupSize, default: []].append(item)
            }
        }
        let groups = buckets.keys.sorted().map { bucket -> ClipGroup in
            let start = spec.placeInline + bucket * spec.groupSize
            let end = min(start + spec.groupSize - 1, totalCount - 1)
            return ClipGroup(startIndex: start,
                             title: "\(start + spec.numberOffset) - \(end + spec.numberOffset)",
                             clips: buckets[bucket] ?? [])
        }
        return (inline, groups)
    }

    /// 旧 NSMenu と同じセクション構成（コピー履歴 / スニペット / ツール / 設定）で
    /// 行を組み立てる。各セクションは区切り線と小さな見出し行で区切る
    func rebuildRows() {
        let query = searchField.stringValue
        let layout = Self.makeLayout(items: allClips, fullText: fullText, query: query,
                                     totalCount: allClips.count, spec: settings.layoutSpec)
        var result: [Row] = []
        // コピー履歴セクション（インライン項目 → グループの順）
        result.append(.sectionHeader(L10n.sectionCopyHistory))
        if layout.inline.isEmpty && layout.groups.isEmpty
            && !ClipFullTextIndexer.terms(from: query).isEmpty {
            result.append(.noResults)
        } else {
            result.append(contentsOf: layout.inline.map { .clip($0) })
            result.append(contentsOf: layout.groups.map { .group($0) })
        }
        // 固定セクションはメインメニュー表示時のみ（履歴ウィンドウでは履歴+検索のみ）
        if showsFixedSections {
            // スニペットセクション
            result.append(.separator)
            result.append(.sectionHeader(L10n.snippet))
            result.append(.action(.snippets))
            // ツールセクション
            result.append(.separator)
            result.append(.sectionHeader(L10n.tools))
            result.append(.action(.generatePassword))
            result.append(.action(.crypto))
            result.append(.action(.secureInfo))
            // 設定セクション
            result.append(.separator)
            result.append(.sectionHeader(L10n.sectionSettings))
            if settings.showsClearHistory {
                result.append(.action(.clearHistory))
            }
            result.append(.action(.editSnippets))
            result.append(.action(.preferences))
            // 終了は誤操作を避けるため区切り線で分離する（旧メニューと同じ）
            result.append(.separator)
            result.append(.action(.quit))
        }
        rows = result
        tableView.reloadData()
        sizePanel()
        // NSMenu と同じく初期状態では何も選択せず、カーソル（ホバー / j・k）が
        // 当たったときに初めてハイライト・サブパネル表示を行う
        if isVisible { updateSubPanel() }
    }

    func sizePanel() {
        let tableH = rows.reduce(CGFloat(0)) { acc, row in
            switch row {
            case .separator:     return acc + Layout.sepRowH
            case .sectionHeader: return acc + Layout.headerRowH
            default:             return acc + Layout.rowH
            }
        }
        let scrollH = min(max(tableH, Layout.rowH), Layout.maxTableH)
        let totalH  = Layout.vPad + Layout.searchH + (Layout.vPad - 2) + 1 + 2 + scrollH + 4
        setContentSize(NSSize(width: Layout.width, height: totalH))
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

    /// 選択中の行を確定する。インライン項目は即ペースト、グループはサブパネルへ、
    /// 固定行はアクション実行（クローズは onSelect / onAction 側で行う）
    func confirmSelection() {
        let idx = tableView.selectedRow
        guard idx >= 0, idx < rows.count else { return }
        switch rows[idx] {
        case .clip(let item):
            onSelect?(item.dataHash)
        case .group:
            enterSubPanel()
        case .action(let action):
            onAction?(action)
        default:
            break
        }
    }

    /// 数字キーで履歴アイテムを直接確定する（NSMenu の数字ショートカットに相当）。
    /// サブパネル表示中はグループ内番号（先頭 10 件）、それ以外はインライン項目の
    /// 番号（先頭 10 件）に対応する。番号は「番号を 0 から開始」設定に従う
    func confirmClip(withDigit digit: Int) {
        // グループ内番号のうち数字キー 1 打で表せるのは先頭 10 件
        // （offset..offset+9。1 開始時の 10 は数字キー 0 に対応する）
        func matches(_ number: Int) -> Bool {
            return number % 10 == digit && number < settings.numberOffset + 10
        }
        if let sub = subPanel, sub.isVisible {
            if let clipIndex = sub.entries.firstIndex(where: { matches($0.number) }) {
                confirmSubClip(at: clipIndex)
            }
            return
        }
        // インライン項目（元の位置 + 番号開始値で判定）
        let inlineClips: [ClipItem] = rows.compactMap {
            if case .clip(let item) = $0 { return item }
            return nil
        }
        if let item = inlineClips.first(where: { matches($0.index + settings.numberOffset) }) {
            onSelect?(item.dataHash)
        }
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
