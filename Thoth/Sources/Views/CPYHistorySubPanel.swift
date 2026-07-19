//
//  CPYHistorySubPanel.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Copyright © 2015-2018 Clipy Project.
//

import Cocoa

// MARK: - CPYHistorySubPanel

/// 選択された履歴グループ（10 件区切り）のクリップ一覧を右側に表示するサブパネル。
/// セキュアアイテムの CPYSecureSubPanel と同じ構成で、
/// canBecomeKey = false のためフォーカスは常にメインパネルに留まる。
final class CPYHistorySubPanel: NSPanel {

    // MARK: - Layout

    private enum Layout {
        static let width: CGFloat     = 300
        static let maxTableH: CGFloat = 300
        static let rowH: CGFloat      = 22
        static let corner: CGFloat    = 8
        static let vPad: CGFloat      = 4
        static let fontSize: CGFloat  = NSFont.systemFontSize - 1
    }

    private static let cellID = NSUserInterfaceItemIdentifier("HistorySubClip")

    // MARK: - UI

    private let effectView = NSVisualEffectView()
    private let scrollView = NSScrollView()
    private let tableView  = NSTableView()

    // MARK: - Data

    private(set) var currentClips: [CPYHistoryPickerPanel.ClipItem] = []
    private(set) var selectedClipIndex: Int = -1

    // MARK: - Callback

    var onClipClicked: ((Int) -> Void)?
    /// マウスホバーでクリップが選択されたときに呼ばれる（メインパネルのモード連動用）
    var onClipHovered: ((Int) -> Void)?

    // MARK: - Init

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: Layout.width, height: Layout.rowH + Layout.vPad * 2),
                   styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque           = false
        backgroundColor    = .clear
        hasShadow          = true
        level              = .popUpMenu
        animationBehavior  = .utilityWindow
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        buildViews()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// NSMenu と同じく、マウスカーソルが当たった行をハイライトする
    /// （確定はクリック / Enter で行う）
    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        let pointInTable = tableView.convert(event.locationInWindow, from: nil)
        let row = tableView.row(at: pointInTable)
        guard row >= 0, row < currentClips.count, row != selectedClipIndex else { return }
        selectedClipIndex = row
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        onClipHovered?(row)
    }

    // MARK: - Public Interface

    func setClips(_ clips: [CPYHistoryPickerPanel.ClipItem]) {
        currentClips      = clips
        selectedClipIndex = -1
        tableView.reloadData()
        tableView.deselectAll(nil)
        sizePanel()
    }

    /// 次クリップへ移動。最下端では false を返す
    @discardableResult
    func selectNext() -> Bool {
        let next = selectedClipIndex + 1
        guard next < currentClips.count else { return false }
        selectedClipIndex = next
        tableView.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        tableView.scrollRowToVisible(next)
        return true
    }

    /// 前クリップへ移動。最上端では false を返す
    @discardableResult
    func selectPrev() -> Bool {
        let prev = selectedClipIndex - 1
        guard prev >= 0 else { return false }
        selectedClipIndex = prev
        tableView.selectRowIndexes(IndexSet(integer: prev), byExtendingSelection: false)
        tableView.scrollRowToVisible(prev)
        return true
    }

    func selectFirst() {
        guard !currentClips.isEmpty else { return }
        selectedClipIndex = 0
        tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        tableView.scrollRowToVisible(0)
    }

    func selectLast() {
        guard !currentClips.isEmpty else { return }
        let last = currentClips.count - 1
        selectedClipIndex = last
        tableView.selectRowIndexes(IndexSet(integer: last), byExtendingSelection: false)
        tableView.scrollRowToVisible(last)
    }

    func deselect() {
        selectedClipIndex = -1
        tableView.deselectAll(nil)
    }

    func selectedClip() -> CPYHistoryPickerPanel.ClipItem? {
        guard selectedClipIndex >= 0, selectedClipIndex < currentClips.count else { return nil }
        return currentClips[selectedClipIndex]
    }

    // MARK: - Build Views

    private func buildViews() {
        effectView.material             = .menu
        effectView.blendingMode         = .behindWindow
        effectView.state                = .active
        effectView.wantsLayer           = true
        effectView.layer?.cornerRadius  = Layout.corner
        effectView.layer?.masksToBounds = true
        contentView = effectView

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

        // マウスホバーで行をハイライトするためのトラッキング（NSMenu と同じ操作感）
        tableView.addTrackingArea(NSTrackingArea(rect: .zero,
                                                 options: [.mouseMoved, .activeAlways, .inVisibleRect],
                                                 owner: self, userInfo: nil))

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: effectView.topAnchor, constant: Layout.vPad),
            scrollView.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: effectView.bottomAnchor, constant: -Layout.vPad)
        ])
    }

    private func sizePanel() {
        let tableH  = CGFloat(currentClips.count) * Layout.rowH
        let scrollH = min(tableH, Layout.maxTableH)
        let totalH  = max(scrollH + Layout.vPad * 2, Layout.rowH + Layout.vPad * 2)
        setContentSize(NSSize(width: Layout.width, height: totalH))
    }

    @objc private func rowClicked() {
        let clicked = tableView.clickedRow
        guard clicked >= 0 else { return }
        selectedClipIndex = clicked
        tableView.selectRowIndexes(IndexSet(integer: clicked), byExtendingSelection: false)
        onClipClicked?(clicked)
    }
}

// MARK: - CPYHistorySubPanel TableView

extension CPYHistorySubPanel: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int { currentClips.count }

    func tableView(_ tableView: NSTableView,
                   viewFor tableColumn: NSTableColumn?,
                   row: Int) -> NSView? {
        let cell = (tableView.makeView(withIdentifier: Self.cellID, owner: nil) as? NSTableCellView)
                   ?? {
                        let newCell = NSTableCellView()
                        newCell.identifier = Self.cellID
                        let iconView = NSImageView()
                        iconView.translatesAutoresizingMaskIntoConstraints = false
                        newCell.addSubview(iconView)
                        newCell.imageView = iconView
                        let textField = NSTextField(labelWithString: "")
                        textField.lineBreakMode = .byTruncatingTail
                        textField.translatesAutoresizingMaskIntoConstraints = false
                        newCell.addSubview(textField)
                        newCell.textField = textField
                        NSLayoutConstraint.activate([
                            iconView.leadingAnchor.constraint(equalTo: newCell.leadingAnchor, constant: 8),
                            iconView.centerYAnchor.constraint(equalTo: newCell.centerYAnchor),
                            iconView.widthAnchor.constraint(equalToConstant: 14),
                            iconView.heightAnchor.constraint(equalToConstant: 14),
                            textField.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
                            textField.trailingAnchor.constraint(equalTo: newCell.trailingAnchor, constant: -6),
                            textField.centerYAnchor.constraint(equalTo: newCell.centerYAnchor)
                        ])
                        return newCell
                   }()
        let clip = currentClips[row]
        // 数字ショートカット（元の位置の下 1 桁）を番号として表示する
        cell.textField?.stringValue = "\(clip.index % CPYHistoryPickerPanel.Layout.groupSize). \(clip.title)"
        cell.textField?.font        = .systemFont(ofSize: Layout.fontSize)
        cell.imageView?.image       = Self.typeIcon(for: clip)
        cell.imageView?.contentTintColor = .secondaryLabelColor
        return cell
    }

    /// クリップの種別（テキスト / 画像 / PDF / ファイル / URL / RTF）に応じた SF Symbols アイコン
    static func typeIcon(for clip: CPYHistoryPickerPanel.ClipItem) -> NSImage? {
        let type = NSPasteboard.PasteboardType(rawValue: clip.ref.primaryType)
        let symbolName: String
        switch type {
        case .deprecatedTIFF:      symbolName = "photo"
        case .deprecatedPDF:       symbolName = "doc.richtext"
        case .deprecatedFilenames: symbolName = "doc.on.doc"
        case .deprecatedURL:       symbolName = "link"
        case .deprecatedRTF, .deprecatedRTFD: symbolName = "doc.text"
        default:                   symbolName = "doc.plaintext"
        }
        return NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat { Layout.rowH }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { true }
}
