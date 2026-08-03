//
//  CPYSecureInfoListViewController.swift
//
//  Thoth
//  GitHub: https://github.com/boyaki-machine/Thoth
//

import Cocoa

/// セキュア情報確認ウィンドウの左ペイン。
/// 検索欄とアイテム一覧を表示し、選択の変更を `onSelectionChange` で通知する。
///
/// 状態（一覧・クエリ・選択）は `SecureInfoEditor` が保持し、
/// このコントローラは表示の組み立てとイベントの受け渡しだけを行う。
final class CPYSecureInfoListViewController: NSViewController {

    /// 選択が変わったときに呼ばれる（絞り込みで選択が隠れた場合は nil）
    var onSelectionChange: ((SecureMenuItem?) -> Void)?
    /// アイテムの新規追加が要求された
    var onAddItemRequested: (() -> Void)?
    /// 選択中アイテムの削除が要求された
    var onDeleteItemRequested: (() -> Void)?

    private let editor: SecureInfoEditor
    let searchField = NSSearchField()
    let tableView   = NSTableView()
    let addButton    = NSButton()
    let removeButton = NSButton()
    private let scrollView = NSScrollView()

    private enum Layout {
        static let width: CGFloat        = 220
        static let searchHeight: CGFloat = 24
        static let rowHeight: CGFloat    = 28
        static let padding: CGFloat      = 8
        static let buttonSize: CGFloat   = 22
    }

    init(editor: SecureInfoEditor) {
        self.editor = editor
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: Layout.width, height: 520))
        setupUI()
    }

    private func setupUI() {
        searchField.placeholderString = L10n.secureMenuSearchPlaceholder
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(searchField)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("secureInfoTitle"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = Layout.rowHeight
        tableView.dataSource = self
        tableView.delegate = self
        tableView.allowsMultipleSelection = false
        // サイドバー用の外観。macOS 11+ では選択色やインセットが自動で調整される
        tableView.selectionHighlightStyle = .sourceList
        tableView.backgroundColor = .clear

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        setupItemButtons()

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: view.topAnchor, constant: Layout.padding),
            searchField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Layout.padding),
            searchField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Layout.padding),
            searchField.heightAnchor.constraint(equalToConstant: Layout.searchHeight),

            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: Layout.padding),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: addButton.topAnchor, constant: -4),

            addButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Layout.padding),
            addButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -Layout.padding),
            addButton.widthAnchor.constraint(equalToConstant: Layout.buttonSize),
            addButton.heightAnchor.constraint(equalToConstant: Layout.buttonSize),
            removeButton.leadingAnchor.constraint(equalTo: addButton.trailingAnchor, constant: 2),
            removeButton.centerYAnchor.constraint(equalTo: addButton.centerYAnchor),
            removeButton.widthAnchor.constraint(equalToConstant: Layout.buttonSize),
            removeButton.heightAnchor.constraint(equalToConstant: Layout.buttonSize)
        ])
    }

    /// アイテムの追加・削除ボタンを組み立てる
    private func setupItemButtons() {
        addButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)
        addButton.toolTip = L10n.addSecureItem
        addButton.target = self
        addButton.action = #selector(addItemTapped)

        removeButton.image = NSImage(systemSymbolName: "minus", accessibilityDescription: nil)
        removeButton.toolTip = L10n.deleteSecureItem
        removeButton.target = self
        removeButton.action = #selector(removeItemTapped)

        for button in [addButton, removeButton] {
            button.bezelStyle = .smallSquare
            button.isBordered = false
            button.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(button)
        }
    }

    @objc private func addItemTapped() {
        onAddItemRequested?()
    }

    @objc private func removeItemTapped() {
        onDeleteItemRequested?()
    }

    /// 追加・削除ボタンの有効状態を更新する
    func updateButtonStates(isReadOnly: Bool) {
        addButton.isEnabled = !isReadOnly
        removeButton.isEnabled = !isReadOnly && editor.selectedItem != nil
    }

    // MARK: - Reload

    /// エディタの状態を画面へ反映する。
    /// 選択が絞り込みで隠れた場合は先頭を選び直し、通知まで行う
    func reload() {
        tableView.reloadData()
        editor.selectFirstVisibleIfNeeded()
        syncSelectionToTableView()
        updateButtonStates(isReadOnly: editor.isReadOnly)
        onSelectionChange?(editor.selectedItem)
    }

    /// 指定アイテムの行だけ描き直す（選択やスクロール位置を保つ）。
    /// タイトルを編集して保存したあと、一覧の表示を追従させるために使う
    func refreshRow(itemID: String) {
        guard let row = editor.visibleItems.firstIndex(where: { $0.itemID == itemID }) else { return }
        tableView.reloadData(forRowIndexes: IndexSet(integer: row),
                             columnIndexes: IndexSet(integersIn: 0..<max(1, tableView.numberOfColumns)))
    }

    /// 指定アイテムへ選択を戻す（保存できず切り替えを取り消す場合に使う）。
    /// 通知を再入させないため onSelectionChange は呼ばない
    func restoreSelection(itemID: String) {
        editor.selectItem(itemID: itemID)
        syncSelectionToTableView()
        updateButtonStates(isReadOnly: editor.isReadOnly)
    }

    /// エディタの選択状態をテーブルの選択へ反映する（通知は行わない）
    private func syncSelectionToTableView() {
        if let row = editor.selectedRow {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            tableView.scrollRowToVisible(row)
        } else {
            tableView.deselectAll(nil)
        }
    }

    // MARK: - Focus

    func focusSearchField() {
        view.window?.makeFirstResponder(searchField)
    }

    /// 検索の絞り込みを解除する（新規追加したアイテムが隠れないようにする）
    func clearSearch() {
        guard !searchField.stringValue.isEmpty else { return }
        searchField.stringValue = ""
        editor.setQuery("")
    }

    func focusList() {
        view.window?.makeFirstResponder(tableView)
    }

    /// 選択行を上下に動かす（vim の j/k 相当）
    func moveSelection(by offset: Int) {
        let visible = editor.visibleItems
        guard !visible.isEmpty else { return }
        let current = editor.selectedRow ?? (offset > 0 ? -1 : visible.count)
        let next = current + offset
        guard next >= 0, next < visible.count else { return }
        editor.selectRow(next)
        syncSelectionToTableView()
        onSelectionChange?(editor.selectedItem)
    }
}

// MARK: - NSTableViewDataSource / NSTableViewDelegate

extension CPYSecureInfoListViewController: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int {
        return editor.visibleItems.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cellID = NSUserInterfaceItemIdentifier("secureInfoTitleCell")
        let cell = (tableView.makeView(withIdentifier: cellID, owner: nil) as? NSTableCellView)
                   ?? makeTitleCell(identifier: cellID)
        cell.textField?.stringValue = editor.visibleItems[row].title
        return cell
    }

    private func makeTitleCell(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = identifier
        let textField = NSTextField(labelWithString: "")
        textField.lineBreakMode = .byTruncatingTail
        textField.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(textField)
        cell.textField = textField
        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
            textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
            textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        guard row >= 0 else { return }
        editor.selectRow(row)
        updateButtonStates(isReadOnly: editor.isReadOnly)
        onSelectionChange?(editor.selectedItem)
    }
}

// MARK: - NSSearchFieldDelegate

extension CPYSecureInfoListViewController: NSSearchFieldDelegate {

    func controlTextDidChange(_ notification: Notification) {
        guard (notification.object as? NSSearchField) === searchField else { return }
        editor.setQuery(searchField.stringValue)
        reload()
    }
}
