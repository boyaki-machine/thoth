//
//  CPYHistoryPickerPanel.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Copyright © 2015-2018 Clipy Project.
//

import Cocoa

// MARK: - CPYHistoryPickerPanel

/// コピー履歴の一覧・検索パネル（メイン/履歴ホットキー・ステータスバーの表示先）。
/// セキュアアイテム選択パネル（親アイテム → フィールド）と同じ 2 階層 UI で、
/// メインリストには履歴を 10 件ずつ区切ったグループ（"0 - 9" など）が並び、
/// グループを選ぶと右側のサブパネルにそのグループのクリップ一覧が表示される。
///
/// "/" キーで検索ボックスへ移り、インクリメンタルサーチで絞り込む。
/// 検索時も**元の並び順・グループ位置を維持**する: ヒットが元の 3 番目と 15 番目なら
/// "0 - 9" グループに 3 番目、"10 - 19" グループに 15 番目が表示される
/// （前に詰めない。ヒットの無いグループは非表示）。
///
/// NSMenu には生きた検索ボックスを置けないため、CPYSecurePickerPanel と同じ
/// NSPanel ベースの構成（上部に検索欄・下にリスト・sendEvent でキー処理）を採る。
///
/// 検索対象はタイトルに加えてコピー内容の全文。全文は表示時に
/// `ClipFullTextIndexer` がバックグラウンドで復号して索引化し、
/// 進捗に応じてヒットが順次追加表示される（索引はパネルを閉じると破棄）。
final class CPYHistoryPickerPanel: NSPanel {

    // MARK: - Row Data Model

    /// 履歴クリップの表示用スナップショット（Realm 非依存）
    struct ClipItem {
        /// 全履歴（未フィルタ）での元の位置。検索時のグループ判定に使う
        let index: Int
        let dataHash: String
        let title: String
        let lowercasedTitle: String
        let ref: ClipFullTextIndexer.ClipRef

        init(clip: CPYClip, index: Int) {
            let primaryType = NSPasteboard.PasteboardType(rawValue: clip.primaryType)
            let firstLine = clip.title
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: .newlines).first ?? ""
            // メニュー表示（makeClipMenuItem）と同じ特殊タイトル置換
            let display: String
            if primaryType == .deprecatedTIFF {
                display = "(Image)"
            } else if primaryType == .deprecatedPDF {
                display = "(PDF)"
            } else if primaryType == .deprecatedFilenames && firstLine.isEmpty {
                display = "(Filenames)"
            } else {
                display = firstLine
            }
            self.index = index
            self.dataHash = clip.dataHash
            self.title = display
            self.lowercasedTitle = display.lowercased()
            self.ref = ClipFullTextIndexer.ClipRef(dataHash: clip.dataHash,
                                                   dataPath: clip.dataPath,
                                                   primaryType: clip.primaryType)
        }
    }

    /// 10 件区切りの履歴グループ（検索時はヒットしたクリップのみを含む）
    struct ClipGroup {
        /// 表示ラベル（元の位置に基づく "0 - 9" など）
        let title: String
        /// グループ内のクリップ（元順・検索時はヒットのみ）
        let clips: [ClipItem]
    }

    /// 下部固定行のアクション（旧メインメニューのスニペット・ツール・管理系に相当）
    enum PanelAction {
        case snippets
        case generatePassword
        case crypto
        case clearHistory
        case editSnippets
        case preferences
        case quit

        var title: String {
            switch self {
            case .snippets:         return L10n.showSnippetMenu
            case .generatePassword: return "\(L10n.generateNewPassword) (&p)"
            case .crypto:           return "\(L10n.encryptDecrypt) (&E)"
            case .clearHistory:     return L10n.clearHistory
            case .editSnippets:     return L10n.editSnippets
            case .preferences:      return L10n.preferences
            case .quit:             return L10n.quitThoth
            }
        }
    }

    enum Row {
        case sectionHeader(String)
        case group(ClipGroup)
        case separator
        case action(PanelAction)
        case noResults

        var isSelectable: Bool {
            switch self {
            case .group, .action: return true
            default: return false
            }
        }
    }

    // MARK: - Cell Reuse Identifiers

    enum CellID {
        static let header = NSUserInterfaceItemIdentifier("HistoryHeader")
        static let group  = NSUserInterfaceItemIdentifier("HistoryGroup")
        static let sep    = NSUserInterfaceItemIdentifier("HistorySep")
        static let action = NSUserInterfaceItemIdentifier("HistoryAction")
        static let info   = NSUserInterfaceItemIdentifier("HistoryInfo")
    }

    // MARK: - Layout

    enum Layout {
        static let width: CGFloat     = 260
        static let maxTableH: CGFloat = 420
        static let searchH: CGFloat   = 22
        static let rowH: CGFloat      = 22
        static let sepRowH: CGFloat   = 8
        static let headerRowH: CGFloat = 16
        static let vPad: CGFloat      = 8
        static let hPad: CGFloat      = 8
        static let corner: CGFloat    = 8
        static let fontSize: CGFloat  = NSFont.systemFontSize - 1
        /// 1 グループあたりの履歴件数
        static let groupSize = 10
    }

    // MARK: - UI

    let effectView  = NSVisualEffectView()
    let searchField = NSSearchField()
    let divider     = NSBox()
    let scrollView  = NSScrollView()
    let tableView   = NSTableView()

    // MARK: - Data

    let allClips: [ClipItem]
    /// dataHash → 小文字化済み本文（索引ビルドの進捗に応じて増える）
    var fullText: [String: String] = [:]
    let indexer: ClipFullTextIndexer
    /// 「履歴を消去」行を表示するか（環境設定のスイッチに連動）
    let showsClearHistory: Bool
    /// スニペット・ツール・設定の固定セクションを表示するか。
    /// メインメニュー（⌘⇧V・ステータスバー）では true、
    /// コピー履歴ウィンドウ（⌘⌃V）では false で履歴と検索のみを表示する
    let showsFixedSections: Bool
    var rows: [Row] = []
    var isBeingShown = false
    private(set) var callerApp: NSRunningApplication?
    /// 選択中グループのクリップ一覧を表示するサブパネル
    var subPanel: CPYHistorySubPanel?
    var isInSubPanelMode = false
    /// サブパネルが左側に配置されているか（右側にスペースが無い場合のフォールバック）。
    /// ← → / h l の操作方向の入れ替えに使う
    var subPanelOnLeft = false

    // MARK: - Callbacks

    /// 履歴行の確定時に選択クリップの dataHash（主キー）を返す
    var onSelect: ((String) -> Void)?
    /// 下部固定行の確定時に呼ばれる
    var onAction: ((PanelAction) -> Void)?

    // MARK: - Init

    init(clips: [ClipItem], showsFixedSections: Bool = true,
         indexer: ClipFullTextIndexer = ClipFullTextIndexer()) {
        self.allClips = clips
        self.showsFixedSections = showsFixedSections
        self.indexer  = indexer
        self.showsClearHistory = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.addClearHistoryMenuItem)
        super.init(contentRect: .zero, styleMask: [.borderless],
                   backing: .buffered, defer: false)
        isOpaque                    = false
        backgroundColor             = .clear
        hasShadow                   = true
        level                       = .popUpMenu
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

    /// キー処理の実体は CPYHistoryPickerPanel+TableView.swift の `handleKeyDown(_:)` に委譲する
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, handleKeyDown(event) { return }
        super.sendEvent(event)
    }

    // MARK: - Mouse Hover

    /// NSMenu と同じく、マウスカーソルが当たった行をハイライトし、
    /// グループ行ならサブパネルを表示する（tableView の NSTrackingArea 経由で呼ばれる）
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

    override func resignKey() {
        super.resignKey()
        // 表示直後はメニュー閉鎖に伴う「元アプリへのアクティベーション返却」と
        // 競合してキーを失うことがある。この間は閉じずにキー状態を取り返す
        // （メニュー項目から開く経路があるため、セキュアパネルより一歩強い対策が必要）
        if isBeingShown {
            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.isVisible, self.isBeingShown else { return }
                NSApp.activate(ignoringOtherApps: true)
                self.makeKeyAndOrderFront(nil)
            }
            return
        }
        if isVisible { close() }
    }

    override func close() {
        if let sub = subPanel {
            removeChildWindow(sub)
            sub.close()
            subPanel = nil
        }
        isInSubPanelMode = false
        // 平文索引はパネルの生存期間のみ保持する（プライバシー配慮）
        indexer.cancel()
        fullText = [:]
        super.close()
    }
}

// MARK: - Show

extension CPYHistoryPickerPanel {
    func show(near point: NSPoint) {
        callerApp = NSWorkspace.shared.frontmostApplication
        let screen  = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSScreen.main!.visibleFrame
        var origin = NSPoint(x: point.x + 15, y: point.y - frame.height + 15)
        origin.x = max(visible.minX + 4, min(origin.x, visible.maxX - frame.width - 4))
        origin.y = max(visible.minY + 4, min(origin.y, visible.maxY - frame.height - 4))
        setFrameOrigin(origin)
        isBeingShown = true
        // メニューが閉じた直後の空白を作らないよう、まず即座に表示だけ行う
        // （キーウィンドウ化はアクティベーションが落ち着いてから行う）
        orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self = self else { return }
            NSApp.activate(ignoringOtherApps: true)
            self.makeKeyAndOrderFront(nil)
            // セキュアアイテム選択パネルと同じく初期フォーカスはリスト側に置く
            // （j/k で即移動でき、"/" キーで検索ボックスへ移る）
            self.makeFirstResponder(self.tableView)
            self.updateSubPanel()
        }
        // メニュー項目経由ではアクティベーション返却が遅れて届くことがあるため、
        // セキュアパネル（0.65 秒）より長めに猶予を取る
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.isBeingShown = false
        }
        // 全文索引のビルドを開始。進捗が届くたびに再フィルタして
        // 本文ヒットを順次追加表示する（空クエリ時は表示が変わらないため省略）
        indexer.build(clips: allClips.map { $0.ref }) { [weak self] partial in
            guard let self = self else { return }
            self.fullText.merge(partial) { _, new in new }
            if !self.searchField.stringValue.isEmpty {
                self.rebuildRows()
            }
        }
    }
}

// MARK: - Build Views

extension CPYHistoryPickerPanel {
    func buildViews() {
        effectView.material             = .menu
        effectView.blendingMode         = .behindWindow
        effectView.state                = .active
        effectView.wantsLayer           = true
        effectView.layer?.cornerRadius  = Layout.corner
        effectView.layer?.masksToBounds = true
        contentView = effectView

        searchField.placeholderString            = L10n.historySearchPlaceholder
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
        if #available(macOS 11.0, *) { tableView.style = .plain }
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

    /// フィルタ結果を「元の位置」に基づいて groupSize 件区切りのグループへ振り分ける
    /// （純粋関数・テスト対象）。
    /// 検索時も前に詰めず、元 3 番目のヒットは "0 - 9"、元 15 番目のヒットは "10 - 19" に入る。
    /// ヒットの無いグループは含まれない。ラベルの範囲は全履歴数に基づく元の区切りを表す
    static func groups(items: [ClipItem], fullText: [String: String],
                       query: String, totalCount: Int,
                       groupSize: Int = Layout.groupSize) -> [ClipGroup] {
        let matched = filter(items: items, fullText: fullText, query: query)
        guard !matched.isEmpty else { return [] }
        var buckets = [Int: [ClipItem]]()
        for item in matched {
            buckets[item.index / groupSize, default: []].append(item)
        }
        return buckets.keys.sorted().map { bucket in
            let start = bucket * groupSize
            let end = min(start + groupSize - 1, totalCount - 1)
            return ClipGroup(title: "\(start) - \(end)", clips: buckets[bucket] ?? [])
        }
    }

    /// 旧 NSMenu と同じセクション構成（コピー履歴 / スニペット / ツール / 設定）で
    /// 行を組み立てる。各セクションは区切り線と小さな見出し行で区切る
    func rebuildRows() {
        let query = searchField.stringValue
        let grouped = Self.groups(items: allClips, fullText: fullText,
                                  query: query, totalCount: allClips.count)
        var result: [Row] = []
        // コピー履歴セクション
        result.append(.sectionHeader(L10n.sectionCopyHistory))
        if grouped.isEmpty && !ClipFullTextIndexer.terms(from: query).isEmpty {
            result.append(.noResults)
        } else {
            result.append(contentsOf: grouped.map { .group($0) })
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
            // 設定セクション
            result.append(.separator)
            result.append(.sectionHeader(L10n.sectionSettings))
            if showsClearHistory {
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
