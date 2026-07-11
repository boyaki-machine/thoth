//
//  CPYSecureSubPanel.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Copyright © 2015-2018 Clipy Project.
//

import Cocoa

// MARK: - PageControlView

/// ページネーションコントロール（◀ N/M ▶）を表示するテーブル行ビュー。
final class PageControlView: NSView {

    static let cellID = NSUserInterfaceItemIdentifier("SecurePageCtrl")

    private let prevButton = NSButton()
    private let nextButton = NSButton()
    private let pageLabel  = NSTextField(labelWithString: "")

    var onPrev: (() -> Void)?
    var onNext: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        identifier = Self.cellID

        for btn in [prevButton, nextButton] {
            btn.isBordered    = false
            btn.focusRingType = .none
            btn.font = .systemFont(ofSize: NSFont.systemFontSize - 1)
            btn.translatesAutoresizingMaskIntoConstraints = false
        }
        prevButton.title  = "◀"
        prevButton.target = self
        prevButton.action = #selector(prevTapped)

        nextButton.title  = "▶"
        nextButton.target = self
        nextButton.action = #selector(nextTapped)

        pageLabel.alignment  = .center
        pageLabel.font       = .systemFont(ofSize: NSFont.systemFontSize - 2)
        pageLabel.textColor  = .secondaryLabelColor
        pageLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(prevButton)
        addSubview(pageLabel)
        addSubview(nextButton)

        NSLayoutConstraint.activate([
            prevButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            prevButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            prevButton.widthAnchor.constraint(equalToConstant: 28),
            nextButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            nextButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            nextButton.widthAnchor.constraint(equalToConstant: 28),
            pageLabel.leadingAnchor.constraint(equalTo: prevButton.trailingAnchor),
            pageLabel.trailingAnchor.constraint(equalTo: nextButton.leadingAnchor),
            pageLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(current: Int, total: Int) {
        pageLabel.stringValue = "\(current) / \(total)"
        prevButton.isEnabled  = current > 1
        nextButton.isEnabled  = current < total
    }

    @objc private func prevTapped() { onPrev?() }
    @objc private func nextTapped() { onNext?() }
}

// MARK: - CPYSecureSubPanel

/// 選択された親アイテムのフィールド一覧を右側に表示するサブパネル。
/// canBecomeKey = false のためフォーカスは常にメインパネルに留まる。
final class CPYSecureSubPanel: NSPanel {

    // MARK: - Layout

    private enum Layout {
        static let width: CGFloat     = 220
        static let maxTableH: CGFloat = 300
        static let rowH: CGFloat      = 22
        static let corner: CGFloat    = 8
        static let vPad: CGFloat      = 4
        static let fontSize: CGFloat  = NSFont.systemFontSize - 1
    }

    private static let cellID = NSUserInterfaceItemIdentifier("SubField")

    // MARK: - UI

    private let effectView = NSVisualEffectView()
    private let scrollView = NSScrollView()
    private let tableView  = NSTableView()

    // MARK: - Data

    private(set) var currentFields: [SecureMenuItem.Field] = []
    private(set) var selectedFieldIndex: Int = -1

    // MARK: - Callback

    var onFieldClicked: ((Int) -> Void)?

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

    // MARK: - Public Interface

    func setFields(_ fields: [SecureMenuItem.Field]) {
        currentFields      = fields
        selectedFieldIndex = -1
        tableView.reloadData()
        tableView.deselectAll(nil)
        sizePanel()
    }

    /// 次フィールドへ移動。最下端では false を返す
    @discardableResult
    func selectNext() -> Bool {
        let next = selectedFieldIndex + 1
        guard next < currentFields.count else { return false }
        selectedFieldIndex = next
        tableView.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        tableView.scrollRowToVisible(next)
        return true
    }

    /// 前フィールドへ移動。最上端では false を返す
    @discardableResult
    func selectPrev() -> Bool {
        let prev = selectedFieldIndex - 1
        guard prev >= 0 else { return false }
        selectedFieldIndex = prev
        tableView.selectRowIndexes(IndexSet(integer: prev), byExtendingSelection: false)
        tableView.scrollRowToVisible(prev)
        return true
    }

    func selectFirst() {
        guard !currentFields.isEmpty else { return }
        selectedFieldIndex = 0
        tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        tableView.scrollRowToVisible(0)
    }

    func selectLast() {
        guard !currentFields.isEmpty else { return }
        let last = currentFields.count - 1
        selectedFieldIndex = last
        tableView.selectRowIndexes(IndexSet(integer: last), byExtendingSelection: false)
        tableView.scrollRowToVisible(last)
    }

    func deselect() {
        selectedFieldIndex = -1
        tableView.deselectAll(nil)
    }

    func selectField(at index: Int) {
        guard index >= 0, index < currentFields.count else { return }
        selectedFieldIndex = index
        tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        tableView.scrollRowToVisible(index)
    }

    func selectedField() -> SecureMenuItem.Field? {
        guard selectedFieldIndex >= 0, selectedFieldIndex < currentFields.count else { return nil }
        return currentFields[selectedFieldIndex]
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

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: effectView.topAnchor, constant: Layout.vPad),
            scrollView.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: effectView.bottomAnchor, constant: -Layout.vPad)
        ])
    }

    private func sizePanel() {
        let tableH  = CGFloat(currentFields.count) * Layout.rowH
        let scrollH = min(tableH, Layout.maxTableH)
        let totalH  = max(scrollH + Layout.vPad * 2, Layout.rowH + Layout.vPad * 2)
        setContentSize(NSSize(width: Layout.width, height: totalH))
    }

    @objc private func rowClicked() {
        let clicked = tableView.clickedRow
        guard clicked >= 0 else { return }
        selectedFieldIndex = clicked
        tableView.selectRowIndexes(IndexSet(integer: clicked), byExtendingSelection: false)
        onFieldClicked?(clicked)
    }
}

// MARK: - CPYSecureSubPanel TableView

extension CPYSecureSubPanel: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int { currentFields.count }

    func tableView(_ tableView: NSTableView,
                   viewFor tableColumn: NSTableColumn?,
                   row: Int) -> NSView? {
        let cell = (tableView.makeView(withIdentifier: Self.cellID, owner: nil) as? NSTableCellView)
                   ?? {
                        let newCell = NSTableCellView()
                        newCell.identifier = Self.cellID
                        let textField = NSTextField(labelWithString: "")
                        textField.lineBreakMode = .byTruncatingTail
                        textField.translatesAutoresizingMaskIntoConstraints = false
                        newCell.addSubview(textField)
                        newCell.textField = textField
                        NSLayoutConstraint.activate([
                            textField.leadingAnchor.constraint(equalTo: newCell.leadingAnchor, constant: 10),
                            textField.trailingAnchor.constraint(equalTo: newCell.trailingAnchor, constant: -6),
                            textField.centerYAnchor.constraint(equalTo: newCell.centerYAnchor)
                        ])
                        return newCell
                   }()
        let field   = currentFields[row]
        let preview = field.isPassword
            ? "••••••••"
            : (field.value.count > 26 ? String(field.value.prefix(26)) + "…" : field.value)
        cell.textField?.stringValue = "\(field.label): \(preview)"
        cell.textField?.font        = .systemFont(ofSize: Layout.fontSize)
        return cell
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat { Layout.rowH }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { true }
}
