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

    /// レイアウト計算（makeLayout）へ渡す設定の抜粋。
    /// 純粋関数を UserDefaults 非依存に保つための値型
    struct LayoutSpec {
        let placeInline: Int
        let groupSize: Int
        let numberOffset: Int
    }

    /// メニュータブの設定のスナップショット（パネル表示時に取得）。
    /// `init(defaults:)` は extension 側に定義し、テストからは memberwise init で
    /// 任意の組み合わせを注入できるようにしている
    struct DisplaySettings {
        /// メニュー項目に番号を付ける
        let markWithNumber: Bool
        /// 数字キーショートカットの有効/無効
        let numericKeysEnabled: Bool
        /// 番号の開始値（0 から開始なら 0、それ以外は 1）
        let numberOffset: Int
        /// 種別アイコンの表示
        let showIcon: Bool
        /// ツールチップの表示と最大長
        let showToolTip: Bool
        let maxToolTipLength: Int
        /// インライン（グループ化せず直接）表示する件数
        let placeInline: Int
        /// 1 グループあたりの件数（旧「フォルダ内に表示する項目数」）
        let groupSize: Int
        /// 画像サムネイル / カラーコードプレビューの表示
        let showImage: Bool
        let showColorCode: Bool
        /// タイトルの最大表示文字数
        let maxTitleLength: Int
        /// 「履歴を消去」行を表示するか
        let showsClearHistory: Bool

        var layoutSpec: LayoutSpec {
            return LayoutSpec(placeInline: placeInline, groupSize: groupSize, numberOffset: numberOffset)
        }
    }

    /// 履歴クリップの表示用スナップショット（Realm 非依存）
    struct ClipItem {
        /// 全履歴（未フィルタ）での元の位置。検索時のグループ判定・番号表示に使う
        let index: Int
        let dataHash: String
        /// 表示用タイトル（1 行目・最大表示文字数で切り詰め済み）
        let title: String
        /// ツールチップ用のタイトル全体（DB に保存された先頭部分）
        let fullTitle: String
        /// 検索用（切り詰め前の 1 行目を小文字化）
        let lowercasedTitle: String
        let thumbnailPath: String
        let isColorCode: Bool
        let ref: ClipFullTextIndexer.ClipRef

        /// - Parameter maxTitleLength: 0 なら切り詰めなし
        init(clip: CPYClip, index: Int, maxTitleLength: Int = 0) {
            let primaryType = NSPasteboard.PasteboardType(rawValue: clip.primaryType)
            let firstLine = clip.title
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: .newlines).first ?? ""
            // メニュー表示（makeClipMenuItem）と同じ特殊タイトル置換
            var display: String
            if primaryType == .deprecatedTIFF {
                display = "(Image)"
            } else if primaryType == .deprecatedPDF {
                display = "(PDF)"
            } else if primaryType == .deprecatedFilenames && firstLine.isEmpty {
                display = "(Filenames)"
            } else {
                display = firstLine
            }
            // 「メニュー項目タイトルの最大長」設定に従って切り詰める（trimTitle と同じ流儀）
            if maxTitleLength > 3, display.count > maxTitleLength {
                display = String(display.prefix(maxTitleLength - 3)) + "..."
            }
            self.index = index
            self.dataHash = clip.dataHash
            self.title = display
            self.fullTitle = clip.title
            self.lowercasedTitle = firstLine.lowercased()
            self.thumbnailPath = clip.thumbnailPath
            self.isColorCode = clip.isColorCode
            self.ref = ClipFullTextIndexer.ClipRef(dataHash: clip.dataHash,
                                                   dataPath: clip.dataPath,
                                                   primaryType: clip.primaryType)
        }
    }

    /// groupSize 件区切りの履歴グループ（検索時はヒットしたクリップのみを含む）
    struct ClipGroup {
        /// グループ先頭の元の位置（グループ内番号の計算に使う）
        let startIndex: Int
        /// 表示ラベル（元の位置 + 番号開始値に基づく "0 - 9" / "1 - 10" など）
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
        /// インライン表示のクリップ（「インラインに表示する項目数」の範囲）
        case clip(ClipItem)
        case group(ClipGroup)
        case separator
        case action(PanelAction)
        case noResults

        var isSelectable: Bool {
            switch self {
            case .clip, .group, .action: return true
            default: return false
            }
        }
    }

    // MARK: - Cell Reuse Identifiers

    enum CellID {
        static let header = NSUserInterfaceItemIdentifier("HistoryHeader")
        static let clip   = NSUserInterfaceItemIdentifier("HistoryClip")
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
    /// メニュータブの表示設定（表示時のスナップショット）
    let settings: DisplaySettings
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
         indexer: ClipFullTextIndexer = ClipFullTextIndexer(),
         settings: DisplaySettings = DisplaySettings()) {
        self.allClips = clips
        self.showsFixedSections = showsFixedSections
        self.indexer  = indexer
        self.settings = settings
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

// MARK: - DisplaySettings Loading

extension CPYHistoryPickerPanel.DisplaySettings {
    /// UserDefaults（メニュータブの設定値）からスナップショットを構築する
    init(defaults: UserDefaults = AppEnvironment.current.defaults) {
        self.init(markWithNumber: defaults.bool(forKey: Constants.UserDefaults.menuItemsAreMarkedWithNumbers),
                  numericKeysEnabled: defaults.bool(forKey: Constants.UserDefaults.addNumericKeyEquivalents),
                  numberOffset: defaults.bool(forKey: Constants.UserDefaults.menuItemsTitleStartWithZero) ? 0 : 1,
                  showIcon: defaults.bool(forKey: Constants.UserDefaults.showIconInTheMenu),
                  showToolTip: defaults.bool(forKey: Constants.UserDefaults.showToolTipOnMenuItem),
                  maxToolTipLength: max(0, defaults.integer(forKey: Constants.UserDefaults.maxLengthOfToolTip)),
                  placeInline: max(0, defaults.integer(forKey: Constants.UserDefaults.numberOfItemsPlaceInline)),
                  groupSize: max(1, defaults.integer(forKey: Constants.UserDefaults.numberOfItemsPlaceInsideFolder)),
                  showImage: defaults.bool(forKey: Constants.UserDefaults.showImageInTheMenu),
                  showColorCode: defaults.bool(forKey: Constants.UserDefaults.showColorPreviewInTheMenu),
                  maxTitleLength: max(0, defaults.integer(forKey: Constants.UserDefaults.maxMenuItemTitleLength)),
                  showsClearHistory: defaults.bool(forKey: Constants.UserDefaults.addClearHistoryMenuItem))
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
