//
//  CPYSecurePickerPanel.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Copyright © 2015-2018 Clipy Project.
//

import Cocoa

// MARK: - CPYSecurePickerPanel

/// Touch ID 認証後に表示するセキュアアイテム選択パネル（メインパネル）。
/// NSPanel ベースのため日本語など多言語 IME に対応する。
/// 親アイテムのみを表示し、フィールドは右側のサブパネル（CPYSecureSubPanel）に表示する。
/// 通常時は pageSize 件ごとにページングし、検索時は全件インクリメンタルサーチを行う。
final class CPYSecurePickerPanel: NSPanel {

    // MARK: - Row Data Model

    /// 末尾の「セキュア情報確認」行を呼び出す単キー。
    /// **表示ラベルとキー処理の唯一の定義元**（`PanelAction.shortcutKey` と同じ考え方）
    static let secureInfoShortcutKey = "s"

    enum Row {
        case parent(SecureMenuItem)
        case separator
        case noResults
        /// 一覧の末尾に置く「セキュア情報確認」の行（v1.3.0 で宛先とキーを変更）
        case manage
        case pageControl

        var isSelectable: Bool {
            switch self {
            case .parent, .manage: return true
            default: return false
            }
        }
    }

    // MARK: - Cell Reuse Identifiers

    enum CellID {
        static let parent = NSUserInterfaceItemIdentifier("SecureParent")
        static let sep    = NSUserInterfaceItemIdentifier("SecureSep")
        static let info   = NSUserInterfaceItemIdentifier("SecureInfo")
        static let manage = NSUserInterfaceItemIdentifier("SecureManage")
        static let page   = PageControlView.cellID
    }

    // MARK: - Layout

    enum Layout {
        static let width: CGFloat        = 260
        static let maxTableH: CGFloat    = 420
        static let searchH: CGFloat      = 22
        static let rowH: CGFloat         = 22
        static let sepRowH: CGFloat      = 8
        static let pageControlH: CGFloat = 28
        static let vPad: CGFloat         = 8
        static let hPad: CGFloat         = 8
        static let corner: CGFloat       = 8
        static let fontSize: CGFloat     = NSFont.systemFontSize - 1
        static let pageSize: Int         = 10
    }

    // MARK: - UI

    let effectView  = NSVisualEffectView()
    let searchField = NSSearchField()
    let divider     = NSBox()
    let scrollView  = NSScrollView()
    let tableView   = NSTableView()

    // MARK: - Data

    var allItems: [SecureMenuItem]
    var allFilteredItems: [SecureMenuItem] = []
    var rows: [Row] = []
    var currentPage = 0
    let context: SecureSelectionContext
    var isBeingShown = false
    private(set) var callerApp: NSRunningApplication?
    var subPanel: CPYSecureSubPanel?
    var isInSubPanelMode = false
    /// サブパネルが左側に配置されているか（右側にスペースが無い場合のフォールバック）。
    /// ← → / h l の操作方向の入れ替えに使う
    var subPanelOnLeft = false
    /// パネル外クリックで閉じるためのイベントモニタ（グローバル/ローカル）
    private var dismissMonitors: [Any] = []
    /// 登録中のモニタ数（テストでのライフサイクル検証用）
    var dismissMonitorCount: Int { dismissMonitors.count }

    // MARK: - Callbacks

    var onSelect: ((SecureFieldSelection) -> Void)?
    /// 末尾の `.manage` 行が選ばれた（セキュア情報確認ウィンドウを開く）
    var onManage: (() -> Void)?

    // MARK: - Init

    init(items: [SecureMenuItem], context: SecureSelectionContext) {
        self.allItems = items
        self.context  = context
        super.init(contentRect: .zero, styleMask: [.borderless],
                   backing: .buffered, defer: false)
        isOpaque                    = false
        backgroundColor             = .clear
        hasShadow                   = true
        // Chrome の iCloud パスワード等、システムの AutoFill ポップアップは高い
        // ウィンドウレベルで前面に出るため、その背後に隠れないよう .screenSaver
        // （.popUpMenu より上）で表示する
        level                       = .screenSaver
        isMovableByWindowBackground = false
        animationBehavior           = .utilityWindow
        collectionBehavior          = [.canJoinAllSpaces, .fullScreenAuxiliary]
        buildViews()
        rebuildRows()
        sizePanel()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // MARK: - Keyboard

    /// キー処理の実体は CPYSecurePickerPanel+Keyboard.swift の `handleKeyDown(_:)` に委譲する
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, handleKeyDown(event) { return }
        super.sendEvent(event)
    }

    // MARK: - Mouse Hover

    /// NSMenu と同じく、マウスカーソルが当たった行をハイライトし、
    /// 親アイテム行ならサブパネルを表示する（tableView の NSTrackingArea 経由で呼ばれる）
    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        let pointInTable = tableView.convert(event.locationInWindow, from: nil)
        let row = tableView.row(at: pointInTable)
        guard row >= 0, row < rows.count, rows[row].isSelectable,
              row != tableView.selectedRow else { return }
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        isInSubPanelMode = false
        updateSubPanel()
    }

    // MARK: - Window Lifecycle

    // キーウィンドウでなくなっても閉じない。システムの AutoFill ポップアップ等と
    // 最前面を奪い合って点滅・自動クローズするのを避けるため、パネルの解除は
    // 「ユーザーが実際にパネル外をクリックする」ことだけを契機にする（下記 dismissMonitors）。
    // resignKey では何もしない。

    override func close() {
        removeDismissMonitors()
        if let sub = subPanel {
            removeChildWindow(sub)
            sub.close()
            subPanel = nil
        }
        isInSubPanelMode = false
        super.close()
    }

    // MARK: - Dismiss on Outside Click

    /// パネル外クリックで閉じるためのイベントモニタを開始する。
    /// 他アプリのクリック（別ウィンドウへのフォーカス）や、自アプリ内でパネル
    /// 以外へのクリックで閉じる。パネル/サブパネルへのクリックでは閉じない。
    /// キー喪失では閉じないため、フォーカスを取れなくてもユーザー操作まで残る。
    func installDismissMonitors() {
        removeDismissMonitors()
        let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.dismissByOutsideClick()
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self else { return event }
            if !self.belongsToPanelGroup(event.window) { self.dismissByOutsideClick() }
            return event
        }
        dismissMonitors = [global, local].compactMap { $0 }
    }

    private func removeDismissMonitors() {
        dismissMonitors.forEach { NSEvent.removeMonitor($0) }
        dismissMonitors = []
    }

    /// クリックされたウィンドウがこのパネル群（本体またはサブパネル）に属するか
    func belongsToPanelGroup(_ window: NSWindow?) -> Bool {
        if window === self { return true }
        if let children = childWindows, children.contains(where: { $0 === window }) { return true }
        return false
    }

    private func dismissByOutsideClick() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.isVisible else { return }
            self.close()
        }
    }
}

// MARK: - Show

extension CPYSecurePickerPanel {
    /// - Parameter callerApp: 貼り付け先として覚えておくアプリ（ホットキーを押した時点の最前面）。
    ///   使えない場合（nil・Thoth 自身）は表示する時点の最前面を使う
    func show(near point: NSPoint, callerApp hotKeyApp: NSRunningApplication? = nil) {
        Diagnostics.secureMenu.info("picker show requested")
        callerApp = CallerAppActivator.returnTarget(atHotKey: hotKeyApp, atShow: NSWorkspace.shared.frontmostApplication)
        let screen  = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSScreen.main!.visibleFrame
        var origin = NSPoint(x: point.x + 15, y: point.y - frame.height + 15)
        origin.x = max(visible.minX + 4, min(origin.x, visible.maxX - frame.width - 4))
        origin.y = max(visible.minY + 4, min(origin.y, visible.maxY - frame.height - 4))
        setFrameOrigin(origin)
        isBeingShown = true
        // アプリのアクティブ化が制限される状況（他アプリの AutoFill ポップアップ表示中など）
        // でも最低限パネルを描画するため、まず無条件に前面へ出す
        orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self = self else { return }
            NSApp.activate(ignoringOtherApps: true)
            self.makeKeyAndOrderFront(nil)
            self.makeFirstResponder(self.tableView)
            let caller = self.callerApp?.bundleIdentifier ?? "nil"
            Diagnostics.secureMenu.info("picker shown: visible=\(self.isVisible, privacy: .public) key=\(self.isKeyWindow, privacy: .public) thothActive=\(NSApp.isActive, privacy: .public)")
            Diagnostics.secureMenu.info("picker state: onScreen=\(self.occlusionState.contains(.visible), privacy: .public) level=\(self.level.rawValue, privacy: .public) caller=\(caller, privacy: .public)")
            if self.context.isWithinWindow, let parentItemID = self.context.lastParentItemID {
                self.preselectParent(parentItemID: parentItemID, thenOpenSubWithField: self.context.lastFieldIndex)
            } else {
                self.updateSubPanel()
            }
            self.isBeingShown = false
            // パネル起動時のクリック（ホットキー/ステータスバー等）を誤検知しないよう、
            // 表示が落ち着いてから外部クリック監視を開始する
            self.installDismissMonitors()
        }
    }
}

// MARK: - Build Views

extension CPYSecurePickerPanel {
    func buildViews() {
        effectView.material             = .menu
        effectView.blendingMode         = .behindWindow
        effectView.state                = .active
        effectView.wantsLayer           = true
        effectView.layer?.cornerRadius  = Layout.corner
        effectView.layer?.masksToBounds = true
        contentView = effectView

        searchField.placeholderString            = L10n.secureMenuSearchPlaceholder
        searchField.sendsSearchStringImmediately = true
        searchField.focusRingType                = .none
        searchField.delegate                     = self
        searchField.translatesAutoresizingMaskIntoConstraints = false
        effectView.addSubview(searchField)

        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        effectView.addSubview(divider)

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("col"))
        col.isEditable = false
        tableView.addTableColumn(col)
        tableView.headerView              = nil
        tableView.intercellSpacing        = .zero
        tableView.backgroundColor         = .clear
        tableView.focusRingType           = .none
        tableView.selectionHighlightStyle = .regular
        tableView.style = .plain
        tableView.usesAutomaticRowHeights = false
        tableView.delegate                = self
        tableView.dataSource              = self
        tableView.target                  = self
        tableView.action                  = #selector(rowClicked)

        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers  = true
        scrollView.drawsBackground     = false
        scrollView.documentView        = tableView
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        effectView.addSubview(scrollView)

        // マウスホバーで行をハイライトするためのトラッキング（NSMenu と同じ操作感）。
        // .inVisibleRect によりサイズ変更へ自動追従する
        tableView.addTrackingArea(NSTrackingArea(rect: .zero,
                                                 options: [.mouseMoved, .activeAlways, .inVisibleRect],
                                                 owner: self, userInfo: nil))

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: effectView.topAnchor, constant: Layout.vPad),
            searchField.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: Layout.hPad),
            searchField.trailingAnchor.constraint(equalTo: effectView.trailingAnchor, constant: -Layout.hPad),
            searchField.heightAnchor.constraint(equalToConstant: Layout.searchH),
            divider.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: Layout.vPad - 2),
            divider.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 2),
            scrollView.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: effectView.bottomAnchor, constant: -4)
        ])
    }
}

// MARK: - Data / Rows

extension CPYSecurePickerPanel {
    func rebuildRows() {
        let searching = !searchField.stringValue.isEmpty
        allFilteredItems = filteredItems()
        var result: [Row] = []

        if allFilteredItems.isEmpty && searching {
            result.append(.noResults)
        } else {
            // 通常・検索中ともに pageSize 件ごとにページング
            let totalPages = max(1, (allFilteredItems.count + Layout.pageSize - 1) / Layout.pageSize)
            currentPage = max(0, min(currentPage, totalPages - 1))
            let start = currentPage * Layout.pageSize
            let end   = min(start + Layout.pageSize, allFilteredItems.count)
            result.append(contentsOf: allFilteredItems[start..<end].map { .parent($0) })
            if allFilteredItems.count > Layout.pageSize {
                result.append(.pageControl)
            }
        }

        if !result.isEmpty { result.append(.separator) }
        result.append(.manage)

        rows = result
        tableView.reloadData()
        sizePanel()
        // NSMenu と同じく初期状態では何も選択せず、カーソル（ホバー / j・k）が
        // 当たったときに初めてハイライト・サブパネル表示を行う
        // （継続ペーストモードの復元は preselectParent が明示的に選択する）
        if isVisible { updateSubPanel() }
    }

    /// 検索窓のクエリで親アイテムを絞り込む。
    ///
    /// 条件は確認ウィンドウと共通で `SecureItemSearch` に集約している
    /// （v1.3.1 以前はここに独自の実装があり、値では探せず、
    /// 複数語も 1 つのラベル内でしか AND が効かなかった）。
    /// サブパネルに出ないメモも対象に含まれるが、一致した値そのものは
    /// パネルに表示されない（表示するのは親アイテムの一覧だけ）。
    func filteredItems() -> [SecureMenuItem] {
        return SecureItemSearch.filter(allItems, query: searchField.stringValue)
    }

    func sizePanel() {
        let tableH = rows.reduce(CGFloat(0)) { acc, row in
            switch row {
            case .separator:   return acc + Layout.sepRowH
            case .pageControl: return acc + Layout.pageControlH
            default:           return acc + Layout.rowH
            }
        }
        let scrollH = min(tableH, Layout.maxTableH)
        let totalH  = Layout.vPad + Layout.searchH + (Layout.vPad - 2) + 1 + 2 + scrollH + 4
        setContentSize(NSSize(width: Layout.width, height: totalH))
    }
}

// MARK: - Selection / Navigation

extension CPYSecurePickerPanel {
    func selectFirstSelectable() {
        guard let idx = rows.indices.first(where: { rows[$0].isSelectable }) else { return }
        tableView.selectRowIndexes(IndexSet(integer: idx), byExtendingSelection: false)
    }

    /// 現在ページの最後の parent 行を選択する（前ページへ移動した際の末尾選択に使用）
    func selectLastParent() {
        guard let idx = rows.indices.last(where: {
            if case .parent = rows[$0] { return true }; return false
        }) else { return }
        tableView.selectRowIndexes(IndexSet(integer: idx), byExtendingSelection: false)
        tableView.scrollRowToVisible(idx)
    }

    func selectNext() {
        let currentIdx = tableView.selectedRow
        var nextIdx    = currentIdx + 1
        while nextIdx < rows.count, !rows[nextIdx].isSelectable { nextIdx += 1 }
        guard nextIdx < rows.count else { return }

        // 最後の parent から manage へ進む直前: 次ページがあれば先に進む（検索中も有効）
        let atParent: Bool = {
            guard currentIdx >= 0, currentIdx < rows.count else { return false }
            if case .parent = rows[currentIdx] { return true }; return false
        }()
        let nextIsManage: Bool = {
            if case .manage = rows[nextIdx] { return true }; return false
        }()
        if atParent, nextIsManage {
            let total = max(1, (allFilteredItems.count + Layout.pageSize - 1) / Layout.pageSize)
            if currentPage < total - 1 {
                isInSubPanelMode = false
                currentPage += 1
                rebuildRows()
                return
            }
        }

        tableView.selectRowIndexes(IndexSet(integer: nextIdx), byExtendingSelection: false)
        tableView.scrollRowToVisible(nextIdx)
        isInSubPanelMode = false
        updateSubPanel()
    }

    func selectPrev() {
        let currentIdx = tableView.selectedRow
        var prevIdx    = currentIdx - 1
        while prevIdx >= 0, !rows[prevIdx].isSelectable { prevIdx -= 1 }

        if prevIdx >= 0 {
            tableView.selectRowIndexes(IndexSet(integer: prevIdx), byExtendingSelection: false)
            tableView.scrollRowToVisible(prevIdx)
            isInSubPanelMode = false
            updateSubPanel()
        } else {
            // 先頭の selectable から上: 前ページがあれば戻り、末尾 parent を選択（検索中も有効）
            guard currentPage > 0 else { return }
            isInSubPanelMode = false
            currentPage -= 1
            rebuildRows()
            selectLastParent()
            updateSubPanel()
        }
    }

    func enterSubPanel() {
        guard let sub = subPanel, !sub.currentFields.isEmpty else { return }
        isInSubPanelMode = true
        sub.selectFirst()
    }

    func confirmField(at fieldIndex: Int) {
        guard let sub = subPanel else { return }
        let fields = sub.currentFields
        guard fieldIndex >= 0, fieldIndex < fields.count else { return }
        let field = fields[fieldIndex]
        let selectedRow = tableView.selectedRow
        guard selectedRow >= 0, selectedRow < rows.count, case .parent(let item) = rows[selectedRow] else { return }
        let selection = SecureFieldSelection(parentItemID: item.itemID, fieldValue: field.value,
                                             fieldIndex: fieldIndex, kind: field.kind)
        if isVisible { close() }
        onSelect?(selection)
    }

    func confirmCurrentSubPanelSelection() {
        guard let sub = subPanel else { return }
        confirmField(at: sub.selectedFieldIndex)
    }

    /// 継続ペーストモード: 前回選択の親を正しいページで復元してサブパネルを開く
    func preselectParent(parentItemID: String, thenOpenSubWithField fieldIndex: Int?) {
        if let allIndex = allFilteredItems.firstIndex(where: { $0.itemID == parentItemID }) {
            let targetPage = allIndex / Layout.pageSize
            if targetPage != currentPage {
                currentPage = targetPage
                rebuildRows()
            }
        }
        guard let rowIndex = rows.indices.first(where: {
            if case .parent(let item) = rows[$0] { return item.itemID == parentItemID }
            return false
        }) else { return }
        tableView.selectRowIndexes(IndexSet(integer: rowIndex), byExtendingSelection: false)
        tableView.scrollRowToVisible(rowIndex)
        updateSubPanel()
        if let selectedFieldIndex = fieldIndex {
            subPanel?.selectField(at: selectedFieldIndex)
            isInSubPanelMode = true
        }
    }

    func handleEsc() {
        if !searchField.stringValue.isEmpty {
            searchField.stringValue = ""
            rebuildRows()
        } else if searchField.currentEditor() != nil {
            makeFirstResponder(tableView)
        } else {
            close()
        }
    }
}
