//
//  CPYSecureMenuPreferenceViewController.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Copyright © 2015-2018 Clipy Project.
//

import Cocoa

// MARK: - Pasteboard Type

private extension NSPasteboard.PasteboardType {
    static let clipySecureItemRow = NSPasteboard.PasteboardType("com.clipy-app.secureItemRow")
}

// MARK: - Window Controller

/// セキュアアイテム管理ウィンドウのコントローラ。
/// アプリ起動中に一度だけ生成されるシングルトン。
/// 表示のたびに `reloadItems()` でデータを最新化する。
final class CPYSecureItemsWindowController: NSWindowController {

    static let shared: CPYSecureItemsWindowController = {
        let vc = CPYSecureItemsViewController()
        let window = NSWindow(contentViewController: vc)
        window.title = L10n.secureItems
        window.center()
        window.setContentSize(NSSize(width: 520, height: 420))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        // NSWindow にキービューループの自動再計算を委ねる（Tab キーナビゲーション）
        window.autorecalculatesKeyViewLoop = true
        return CPYSecureItemsWindowController(window: window)
    }()

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        (contentViewController as? CPYSecureItemsViewController)?.reloadItems()
        window?.makeKeyAndOrderFront(self)
    }
}

// MARK: - Main List VC

/// セキュアアイテムの一覧を表示する ViewController。
/// テーブルにアイテムタイトルとフィールド数を表示し、ダブルクリックまたは
/// +/- ボタンで `SecureItemEditViewController` を Sheet として開く。
final class CPYSecureItemsViewController: NSViewController {

    private let tableView  = NSTableView()
    private let scrollView = NSScrollView()
    private var items: [SecureMenuItem] = []
    private var keyMonitor: Any?

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 420))
        setupUI()
    }

    private func setupUI() {
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        let titleColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("title"))
        titleColumn.title = "Title"
        titleColumn.width = 280

        let fieldsColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("fields"))
        fieldsColumn.title = "Fields"
        fieldsColumn.width = 100

        tableView.addTableColumn(titleColumn)
        tableView.addTableColumn(fieldsColumn)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.doubleAction = #selector(editItemAction)
        tableView.target = self
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.registerForDraggedTypes([.clipySecureItemRow])
        tableView.setDraggingSourceOperationMask(.move, forLocal: true)
        scrollView.documentView = tableView

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(separator)

        let addButton = NSButton()
        addButton.image = NSImage(named: NSImage.addTemplateName)
        addButton.bezelStyle = .smallSquare
        addButton.translatesAutoresizingMaskIntoConstraints = false
        addButton.target = self
        addButton.action = #selector(addItemAction)
        view.addSubview(addButton)

        let removeButton = NSButton()
        removeButton.image = NSImage(named: NSImage.removeTemplateName)
        removeButton.bezelStyle = .smallSquare
        removeButton.translatesAutoresizingMaskIntoConstraints = false
        removeButton.target = self
        removeButton.action = #selector(deleteItemAction)
        view.addSubview(removeButton)

        let closeButton = NSButton(title: L10n.close, target: self, action: #selector(closeWindow))
        closeButton.bezelStyle = .rounded
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(closeButton)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            scrollView.bottomAnchor.constraint(equalTo: separator.topAnchor),

            separator.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: closeButton.topAnchor, constant: -8),

            addButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            addButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),
            addButton.widthAnchor.constraint(equalToConstant: 24),
            addButton.heightAnchor.constraint(equalToConstant: 22),

            removeButton.leadingAnchor.constraint(equalTo: addButton.trailingAnchor, constant: 1),
            removeButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),
            removeButton.widthAnchor.constraint(equalToConstant: 24),
            removeButton.heightAnchor.constraint(equalToConstant: 22),

            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            closeButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),
        ])
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.view.window else { return event }
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            switch event.keyCode {
            case 38: // j
                if mods == .control { self.moveSelectedItem(by: 1) }
                else if mods.isEmpty { self.selectRow(offset: 1) }
                else { return event }
            case 40: // k
                if mods == .control { self.moveSelectedItem(by: -1) }
                else if mods.isEmpty { self.selectRow(offset: -1) }
                else { return event }
            case 37, 49, 36: // l / Space / Return
                guard mods.isEmpty else { return event }
                self.editItemAction()
            default:
                return event
            }
            return nil
        }
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        if let mon = keyMonitor { NSEvent.removeMonitor(mon); keyMonitor = nil }
    }

    func reloadItems() {
        items = AppEnvironment.current.secureMenuService.loadAllItems()
        tableView.reloadData()
    }

    private func selectRow(offset: Int) {
        let current = tableView.selectedRow
        let next = current < 0 ? (offset > 0 ? 0 : items.count - 1) : current + offset
        guard next >= 0, next < items.count else { return }
        tableView.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        tableView.scrollRowToVisible(next)
    }

    private func moveSelectedItem(by delta: Int) {
        let row = tableView.selectedRow
        guard row >= 0 else { NSSound.beep(); return }
        let newRow = row + delta
        guard newRow >= 0, newRow < items.count else { NSSound.beep(); return }
        var reordered = items
        reordered.swapAt(row, newRow)
        guard AppEnvironment.current.secureMenuService.reorderItems(reordered) else { return }
        items = AppEnvironment.current.secureMenuService.loadAllItems()
        tableView.reloadData()
        tableView.selectRowIndexes(IndexSet(integer: newRow), byExtendingSelection: false)
    }

    /// Esc キーでウィンドウを閉じる。
    override func cancelOperation(_ sender: Any?) {
        view.window?.performClose(sender)
    }

    @objc private func closeWindow() {
        view.window?.performClose(self)
    }

    @objc private func addItemAction() {
        let editVC = SecureItemEditViewController(item: nil)
        editVC.onSave = { [weak self] item in
            if !AppEnvironment.current.secureMenuService.save(item) {
                self?.showSaveError()
            }
            self?.reloadItems()
        }
        presentAsSheet(editVC)
    }

    private func showSaveError() {
        let alert = NSAlert()
        alert.messageText = "Save failed"
        alert.informativeText = "Failed to save the item to Keychain. Check Console.app for details (filter: SecureMenuService)."
        alert.alertStyle = .warning
        alert.runModal()
    }

    @objc private func editItemAction() {
        let row = tableView.selectedRow
        guard row >= 0, let item = items[safe: row] else {
            NSSound.beep()
            return
        }
        let editVC = SecureItemEditViewController(item: item)
        editVC.onSave = { [weak self] updated in
            if !AppEnvironment.current.secureMenuService.save(updated) {
                self?.showSaveError()
            }
            self?.reloadItems()
        }
        presentAsSheet(editVC)
    }

    @objc private func deleteItemAction() {
        let row = tableView.selectedRow
        guard row >= 0, let item = items[safe: row] else {
            NSSound.beep()
            return
        }
        let alert = NSAlert()
        alert.messageText = L10n.deleteSecureItem
        alert.informativeText = L10n.areYouSureWantToDeleteThisSecureItem
        alert.addButton(withTitle: L10n.deleteSecureItem)
        alert.addButton(withTitle: L10n.cancel)
        alert.alertStyle = .warning
        guard let window = view.window else { return }
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            _ = AppEnvironment.current.secureMenuService.delete(id: item.id)
            self?.reloadItems()
        }
    }
}

// MARK: - NSTableViewDataSource / NSTableViewDelegate

extension CPYSecureItemsViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return items.count
    }

    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        guard let item = items[safe: row] else { return nil }
        switch tableColumn?.identifier.rawValue {
        case "title":  return item.title
        case "fields": return "\(item.fields.count)"
        default:       return nil
        }
    }

    func tableView(_ tableView: NSTableView, shouldEdit tableColumn: NSTableColumn?, row: Int) -> Bool {
        return false
    }

    // MARK: Drag & Drop

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (NSPasteboardWriting)? {
        let pb = NSPasteboardItem()
        pb.setString(String(row), forType: .clipySecureItemRow)
        return pb
    }

    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo,
                   proposedRow row: Int, proposedDropOperation op: NSTableView.DropOperation) -> NSDragOperation {
        if op == .on { tableView.setDropRow(row, dropOperation: .above) }
        return .move
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo,
                   row targetRow: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        let fromRows = (info.draggingPasteboard.pasteboardItems ?? [])
            .compactMap { $0.string(forType: .clipySecureItemRow) }
            .compactMap { Int($0) }
            .sorted()
        guard !fromRows.isEmpty else { return false }

        var newItems = items
        let dragged = fromRows.map { newItems[$0] }
        var adjusted = targetRow
        for fromRow in fromRows.reversed() {
            newItems.remove(at: fromRow)
            if fromRow < adjusted { adjusted -= 1 }
        }
        for (i, item) in dragged.enumerated() { newItems.insert(item, at: adjusted + i) }

        guard AppEnvironment.current.secureMenuService.reorderItems(newItems) else { return false }
        items = AppEnvironment.current.secureMenuService.loadAllItems()
        tableView.reloadData()
        tableView.selectRowIndexes(IndexSet(adjusted..<(adjusted + fromRows.count)), byExtendingSelection: false)
        return true
    }
}

// MARK: - Edit Sheet VC

/// セキュアアイテムの新規作成・編集を行う Sheet ViewController。
///
/// ## レイアウト
/// ```
/// [ Title: _________________ ]
/// ┌──────────────────────────┐
/// │ Label │   Value   │ 🔒  │
/// │  ...  │   ...     │ [ ] │
/// └──────────────────────────┘
/// [+][-]           [Cancel][Save]
/// ```
///
/// ## Tab キーナビゲーション
/// NSWindow が Tab イベントを横取りするため `insertTab` オーバーライドでは対応不可。
/// ローカルイベントモニター（`tabEventMonitor`）でキーダウンを先に捕捉し、
/// `handleTabKey(shift:)` で手動ルーティングする。
///
/// Tab 順序（正方向）:
///   titleField → Label[0] → Value[0] → Checkbox[0] → Label[1] → ... → +ボタン → -ボタン → Cancel → Save → titleField
///
/// ## フォーカス検出
/// `NSControl.currentEditor()` が nil 以外を返す場合に「そのフィールドが編集中」と判定する。
/// `window.firstResponder` を直接比較する方法は、テキストフィールドが編集中に
/// first responder がフィールドエディタ (NSTextView) に切り替わるため不安定。
final class SecureItemEditViewController: NSViewController {

    var onSave: ((SecureMenuItem) -> Void)?

    private var editingItem: SecureMenuItem
    private var fields: [SecureMenuItem.Field]

    private let titleField        = NSTextField()
    private let fieldsTable       = NSTableView()
    private let fieldsScroll      = NSScrollView()
    private let addFieldBtnRef    = TabCapturingButton()
    private let removeFieldBtnRef = TabCapturingButton()
    private let cancelBtnRef      = TabCapturingButton()
    private let saveBtnRef        = TabCapturingButton()
    /// `viewDidAppear` で登録し、`viewWillDisappear` で解除するローカルイベントモニター。
    private var tabEventMonitor: Any?

    private enum ColID {
        static let label = NSUserInterfaceItemIdentifier("fLabel")
        static let value = NSUserInterfaceItemIdentifier("fValue")
        static let pass  = NSUserInterfaceItemIdentifier("fPass")
    }

    init(item: SecureMenuItem?) {
        let itm = item ?? SecureMenuItem(id: UUID().uuidString, title: "", fields: [], displayOrder: 0)
        editingItem = itm
        fields = itm.fields
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 360))
        setupUI()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(titleField)
        tabEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, event.window === self.view.window else { return event }
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if event.keyCode == 48 {                          // Tab / Shift+Tab
                return self.handleTabKey(shift: mods.contains(.shift)) ? nil : event
            }
            if event.keyCode == 0 && mods == .control {       // Ctrl+A → フィールド追加
                self.addFieldRow()
                return nil
            }
            if event.keyCode == 2 && mods == .control {       // Ctrl+D → フィールド削除
                self.removeFieldRow()
                return nil
            }
            // j / k / Ctrl+j / Ctrl+k（テキスト編集中は素通し）
            let isEditingText = event.window?.firstResponder is NSTextView
            if !isEditingText {
                switch (event.keyCode, mods) {
                case (38, []):       self.navigateFieldRow(offset: 1);  return nil // j
                case (40, []):       self.navigateFieldRow(offset: -1); return nil // k
                case (38, .control): self.moveFieldRow(by: 1);          return nil // Ctrl+j
                case (40, .control): self.moveFieldRow(by: -1);         return nil // Ctrl+k
                default: break
                }
            }
            return event
        }
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        if let monitor = tabEventMonitor {
            NSEvent.removeMonitor(monitor)
            tabEventMonitor = nil
        }
    }

    // MARK: - UI Setup

    private func setupUI() {
        let titleLabel = makeTitleSection()
        makeFieldsTable()
        let barSep = makeBottomBar()

        NSLayoutConstraint.activate([
            // タイトル行
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            titleLabel.widthAnchor.constraint(equalToConstant: 48),
            titleField.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            titleField.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 8),
            titleField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            // フィールドテーブル
            fieldsScroll.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 14),
            fieldsScroll.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            fieldsScroll.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            fieldsScroll.bottomAnchor.constraint(equalTo: barSep.topAnchor, constant: -4),
            // ボトムバー
            barSep.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            barSep.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            barSep.bottomAnchor.constraint(equalTo: addFieldBtnRef.topAnchor, constant: -8),
            addFieldBtnRef.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            addFieldBtnRef.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),
            addFieldBtnRef.widthAnchor.constraint(equalToConstant: 24),
            addFieldBtnRef.heightAnchor.constraint(equalToConstant: 22),
            removeFieldBtnRef.leadingAnchor.constraint(equalTo: addFieldBtnRef.trailingAnchor, constant: 1),
            removeFieldBtnRef.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),
            removeFieldBtnRef.widthAnchor.constraint(equalToConstant: 24),
            removeFieldBtnRef.heightAnchor.constraint(equalToConstant: 22),
            saveBtnRef.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            saveBtnRef.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),
            cancelBtnRef.trailingAnchor.constraint(equalTo: saveBtnRef.leadingAnchor, constant: -8),
            cancelBtnRef.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),
        ])
    }

    /// タイトル行（ラベル＋テキストフィールド）を生成してビューに追加する。
    /// - Returns: AutoLayout 制約の基点となる titleLabel
    private func makeTitleSection() -> NSTextField {
        let titleLabel = NSTextField(labelWithString: "Title:")
        titleLabel.alignment = .right
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        titleField.stringValue = editingItem.title
        titleField.placeholderString = L10n.secureItemTitlePlaceholder
        titleField.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleField)

        return titleLabel
    }

    /// フィールドテーブル（列定義＋スクロールビュー）を生成してビューに追加する。
    private func makeFieldsTable() {
        let labelCol = NSTableColumn(identifier: ColID.label)
        labelCol.title = "Label"; labelCol.width = 130; labelCol.minWidth = 60

        let valueCol = NSTableColumn(identifier: ColID.value)
        valueCol.title = "Value"; valueCol.width = 168; valueCol.minWidth = 60

        let passCol = NSTableColumn(identifier: ColID.pass)
        passCol.title = "🔒"; passCol.width = 36; passCol.minWidth = 36; passCol.maxWidth = 36

        fieldsTable.addTableColumn(labelCol)
        fieldsTable.addTableColumn(valueCol)
        fieldsTable.addTableColumn(passCol)
        fieldsTable.columnAutoresizingStyle = .noColumnAutoresizing
        fieldsTable.dataSource = self
        fieldsTable.delegate = self
        fieldsTable.usesAlternatingRowBackgroundColors = true
        fieldsTable.rowHeight = 24

        fieldsScroll.documentView = fieldsTable
        fieldsScroll.hasVerticalScroller = true
        fieldsScroll.borderType = .bezelBorder
        fieldsScroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(fieldsScroll)
    }

    /// ボトムバー（区切り線・+/-ボタン・Cancel/Save ボタン）を生成してビューに追加する。
    /// - Returns: AutoLayout 制約の基点となる区切り線 NSBox
    private func makeBottomBar() -> NSBox {
        let barSep = NSBox()
        barSep.boxType = .separator
        barSep.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(barSep)

        addFieldBtnRef.image = NSImage(named: NSImage.addTemplateName)
        addFieldBtnRef.bezelStyle = .smallSquare
        addFieldBtnRef.target = self
        addFieldBtnRef.action = #selector(addFieldRow)
        addFieldBtnRef.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(addFieldBtnRef)

        removeFieldBtnRef.image = NSImage(named: NSImage.removeTemplateName)
        removeFieldBtnRef.bezelStyle = .smallSquare
        removeFieldBtnRef.target = self
        removeFieldBtnRef.action = #selector(removeFieldRow)
        removeFieldBtnRef.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(removeFieldBtnRef)

        cancelBtnRef.title = L10n.cancel
        cancelBtnRef.bezelStyle = .rounded
        cancelBtnRef.keyEquivalent = "\u{1B}"
        cancelBtnRef.target = self
        cancelBtnRef.action = #selector(cancelSheet)
        cancelBtnRef.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cancelBtnRef)

        saveBtnRef.title = L10n.save
        saveBtnRef.bezelStyle = .rounded
        saveBtnRef.keyEquivalent = "\r"
        saveBtnRef.target = self
        saveBtnRef.action = #selector(saveSheet)
        saveBtnRef.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(saveBtnRef)

        return barSep
    }

    // MARK: - Field Actions

    @objc private func addFieldRow() {
        let newField = SecureMenuItem.Field(label: "", value: "", isPassword: false)
        fields.append(newField)
        let newRow = fields.count - 1
        fieldsTable.insertRows(at: IndexSet(integer: newRow), withAnimation: .slideDown)
        fieldsTable.selectRowIndexes(IndexSet(integer: newRow), byExtendingSelection: false)
        fieldsTable.scrollRowToVisible(newRow)
        fieldsTable.editColumn(0, row: newRow, with: nil, select: true)
    }

    @objc private func removeFieldRow() {
        let row = fieldsTable.selectedRow
        guard row >= 0, row < fields.count else { NSSound.beep(); return }
        fields.remove(at: row)
        fieldsTable.removeRows(at: IndexSet(integer: row), withAnimation: .slideUp)
    }

    @objc private func cancelSheet() {
        presentingViewController?.dismiss(self)
    }

    @objc private func saveSheet() {
        // フィールドエディタを確定させてから値を収集する
        view.window?.makeFirstResponder(nil)

        let title = titleField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else {
            let alert = NSAlert()
            alert.messageText = L10n.pleaseFillInTheContentsOfTheSnippet
            alert.runModal()
            return
        }

        // 画面上のセルが保持する最新値を優先し、未生成のセルはモデルの値にフォールバック
        var currentFields: [SecureMenuItem.Field] = []
        for row in 0..<fields.count {
            let label = (fieldsTable.view(atColumn: 0, row: row, makeIfNecessary: false)
                            as? NSTableCellView)?.textField?.stringValue ?? fields[row].label
            let value = (fieldsTable.view(atColumn: 1, row: row, makeIfNecessary: false)
                            as? FieldValueCell)?.currentValue ?? fields[row].value
            guard !label.trimmingCharacters(in: .whitespaces).isEmpty
                    || !value.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            currentFields.append(SecureMenuItem.Field(label: label, value: value,
                                                      isPassword: fields[row].isPassword))
        }

        let saved = SecureMenuItem(id: editingItem.id, title: title, fields: currentFields,
                                   displayOrder: editingItem.displayOrder)
        onSave?(saved)
        presentingViewController?.dismiss(self)
    }

    // MARK: - Table Cell Change Handlers

    @objc func labelFieldChanged(_ sender: NSTextField) {
        let row = fieldsTable.row(for: sender)
        guard row >= 0, row < fields.count else { return }
        fields[row] = SecureMenuItem.Field(label: sender.stringValue,
                                           value: fields[row].value,
                                           isPassword: fields[row].isPassword)
    }

    @objc func valueFieldChanged(_ sender: NSTextField) {
        let row = fieldsTable.row(for: sender)
        guard row >= 0, row < fields.count else { return }
        fields[row] = SecureMenuItem.Field(label: fields[row].label,
                                           value: sender.stringValue,
                                           isPassword: fields[row].isPassword)
    }

    @objc func passwordCheckboxChanged(_ sender: NSButton) {
        let row = fieldsTable.row(for: sender)
        guard row >= 0, row < fields.count else { return }
        // 画面上のセルから最新の value を取得してモデルを更新する
        let currentValue = (fieldsTable.view(atColumn: 1, row: row, makeIfNecessary: false)
                                as? FieldValueCell)?.currentValue ?? fields[row].value
        fields[row] = SecureMenuItem.Field(label: fields[row].label,
                                           value: currentValue,
                                           isPassword: sender.state == .on)
        // value 列を再描画してプレーン／セキュアフィールドの表示を切り替える
        fieldsTable.reloadData(forRowIndexes: IndexSet(integer: row),
                               columnIndexes: IndexSet(integer: 1))
    }

    // MARK: - Tab Navigation

    /// 指定行の Label 列テキストフィールドにフォーカスを移す。
    /// `makeIfNecessary: true` でセルビューを強制生成してからフォーカスする
    /// （`editColumn` はビューが未生成の行では動作しない場合がある）。
    private func activateLabelField(row: Int) {
        guard row < fields.count else { return }
        fieldsTable.scrollRowToVisible(row)
        if let cell = fieldsTable.view(atColumn: 0, row: row, makeIfNecessary: true) as? NSTableCellView,
           let tf = cell.textField {
            view.window?.makeFirstResponder(tf)
        }
    }

    /// 指定行の Value 列テキストフィールド（プレーンまたはセキュア）にフォーカスを移す。
    private func activateValueField(row: Int) {
        guard row < fields.count else { return }
        fieldsTable.scrollRowToVisible(row)
        if let cell = fieldsTable.view(atColumn: 1, row: row, makeIfNecessary: true) as? FieldValueCell,
           let tf = cell.textField {
            view.window?.makeFirstResponder(tf)
        }
    }

    /// 指定行のパスワードチェックボックスにフォーカスを移す。
    private func activateCheckbox(row: Int) {
        guard row < fields.count else { return }
        fieldsTable.scrollRowToVisible(row)
        if let cell = fieldsTable.view(atColumn: 2, row: row, makeIfNecessary: true),
           let cb = cell.subviews.first(where: { $0 is TabCapturingButton }) as? TabCapturingButton {
            view.window?.makeFirstResponder(cb)
        }
    }

    /// チェックボックスから Tab を押した際のフォーカス先を決定する。
    /// 次の行があれば Label[row+1]、なければ +ボタン へ移動する。
    private func tabFromCheckbox(row: Int) {
        if row < fields.count - 1 { activateLabelField(row: row + 1) }
        else { view.window?.makeFirstResponder(addFieldBtnRef) }
    }

    // MARK: - Local Event Monitor (Tab キー全体を一括処理)

    /// Tab / Shift+Tab キーのフォーカスルーティングを行う。
    ///
    /// NSWindow が Tab イベントを先に処理するため、`insertTab` のオーバーライドでは
    /// カスタムナビゲーションが実現できない。ローカルイベントモニターで先行捕捉し、
    /// このメソッドでフォーカス先を手動決定する。
    ///
    /// フォーカス検出には `NSControl.currentEditor()` を使用する。
    /// `window.firstResponder` を直接比較する方法は、テキストフィールドが編集中に
    /// first responder がフィールドエディタ (NSTextView) に切り替わるため不安定。
    ///
    /// - Parameter shift: Shift+Tab の場合は `true`
    /// - Returns: イベントを消費した場合は `true`（呼び出し元が `nil` を返す）
    // swiftlint:disable:next cyclomatic_complexity
    private func handleTabKey(shift: Bool) -> Bool {
        guard let window = view.window else { return false }
        let fr = window.firstResponder

        // ── titleField ────────────────────────────────────────────────────
        if titleField.currentEditor() != nil || fr === titleField {
            if shift      { window.makeFirstResponder(saveBtnRef) }
            else if fields.isEmpty { window.makeFirstResponder(addFieldBtnRef) }
            else          { activateLabelField(row: 0) }
            return true
        }

        // ── テーブル内の各行 ──────────────────────────────────────────────
        for row in 0..<fields.count {
            // Label 列
            if let cell = fieldsTable.view(atColumn: 0, row: row, makeIfNecessary: false) as? NSTableCellView,
               let labelTF = cell.textField,
               labelTF.currentEditor() != nil || fr === labelTF {
                if shift {
                    if row > 0 { activateCheckbox(row: row - 1) }
                    else { window.makeFirstResponder(titleField) }
                } else { activateValueField(row: row) }
                return true
            }
            // Value 列: プレーン／セキュアの両フィールドを確認
            if let cell = fieldsTable.view(atColumn: 1, row: row, makeIfNecessary: false) as? FieldValueCell,
               (cell.plainField.currentEditor() != nil || fr === cell.plainField
                || cell.secureField.currentEditor() != nil || fr === cell.secureField) {
                if shift { activateLabelField(row: row) }
                else     { activateCheckbox(row: row) }
                return true
            }
            // Checkbox 列
            if let cell = fieldsTable.view(atColumn: 2, row: row, makeIfNecessary: false),
               let cb = cell.subviews.first(where: { $0 is TabCapturingButton }) as? TabCapturingButton,
               fr === cb {
                if shift { activateValueField(row: row) }
                else     { tabFromCheckbox(row: row) }
                return true
            }
        }

        // ── ボトムバーのボタン ────────────────────────────────────────────
        switch fr {
        case addFieldBtnRef:
            if shift {
                if fields.isEmpty { window.makeFirstResponder(titleField) }
                else { activateCheckbox(row: fields.count - 1) }
            } else { window.makeFirstResponder(removeFieldBtnRef) }
            return true
        case removeFieldBtnRef:
            if shift { window.makeFirstResponder(addFieldBtnRef) }
            else     { window.makeFirstResponder(cancelBtnRef) }
            return true
        case cancelBtnRef:
            if shift { window.makeFirstResponder(removeFieldBtnRef) }
            else     { window.makeFirstResponder(saveBtnRef) }
            return true
        case saveBtnRef:
            if shift { window.makeFirstResponder(cancelBtnRef) }
            else     { window.makeFirstResponder(titleField) }
            return true
        default:
            return false
        }
    }

    private func navigateFieldRow(offset: Int) {
        let current = fieldsTable.selectedRow
        let next = current < 0 ? (offset > 0 ? 0 : fields.count - 1) : current + offset
        guard next >= 0, next < fields.count else { return }
        fieldsTable.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        fieldsTable.scrollRowToVisible(next)
    }

    private func moveFieldRow(by delta: Int) {
        let row = fieldsTable.selectedRow
        guard row >= 0 else { return }
        let newRow = row + delta
        guard newRow >= 0, newRow < fields.count else { NSSound.beep(); return }
        fields.swapAt(row, newRow)
        fieldsTable.reloadData(forRowIndexes: IndexSet([row, newRow]), columnIndexes: IndexSet(0..<3))
        fieldsTable.selectRowIndexes(IndexSet(integer: newRow), byExtendingSelection: false)
    }
}

// MARK: - NSTableViewDataSource / NSTableViewDelegate (Edit Sheet)

extension SecureItemEditViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int { fields.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let field = fields[row]
        switch tableColumn?.identifier {

        case ColID.label:
            let cellID = NSUserInterfaceItemIdentifier("editLabelCell")
            let cell = (tableView.makeView(withIdentifier: cellID, owner: nil) as? NSTableCellView)
                       ?? makeEditableTextCell(id: cellID, placeholder: L10n.secureFieldLabelPlaceholder)
            cell.textField?.stringValue = field.label
            cell.textField?.target = self
            cell.textField?.action = #selector(labelFieldChanged(_:))
            return cell

        case ColID.value:
            let cell = (tableView.makeView(withIdentifier: ColID.value, owner: nil) as? FieldValueCell)
                       ?? FieldValueCell()
            cell.configure(value: field.value, isPassword: field.isPassword,
                           target: self, action: #selector(valueFieldChanged(_:)))
            return cell

        case ColID.pass:
            let cellID = NSUserInterfaceItemIdentifier("editPassCell")
            let cell = (tableView.makeView(withIdentifier: cellID, owner: nil) as? NSTableCellView)
                       ?? makeCheckboxCell(id: cellID)
            if let cb = cell.subviews.first(where: { $0 is TabCapturingButton }) as? TabCapturingButton {
                cb.state = field.isPassword ? .on : .off
                cb.target = self
                cb.action = #selector(passwordCheckboxChanged(_:))
            }
            return cell

        default:
            return nil
        }
    }

    private func makeEditableTextCell(id: NSUserInterfaceItemIdentifier,
                                      placeholder: String) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = id
        let tf = NSTextField()
        tf.isBordered = false
        tf.drawsBackground = false
        tf.isEditable = true
        tf.placeholderString = placeholder
        tf.lineBreakMode = .byTruncatingTail
        tf.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(tf)
        cell.textField = tf
        NSLayoutConstraint.activate([
            tf.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            tf.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
            tf.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    private func makeCheckboxCell(id: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = id
        let cb = TabCapturingButton()
        cb.setButtonType(.switch)
        cb.title = ""
        cb.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(cb)
        NSLayoutConstraint.activate([
            cb.centerXAnchor.constraint(equalTo: cell.centerXAnchor),
            cb.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }
}

// MARK: - FieldValueCell

/// Value 列のセルビュー。
/// プレーンテキスト用 NSTextField と、パスワード用 NSSecureTextField を重ねて配置し、
/// `configure(value:isPassword:target:action:)` で一方を表示・他方を非表示に切り替える。
/// Tab ナビゲーションでは `textField`（アクティブな方）に直接フォーカスする。
private final class FieldValueCell: NSTableCellView {
    let plainField  = NSTextField()
    let secureField = NSSecureTextField()

    override init(frame: NSRect) {
        super.init(frame: frame)
        identifier = NSUserInterfaceItemIdentifier("fValue")
        for tf in [plainField, secureField] as [NSTextField] {
            tf.isBordered = false
            tf.drawsBackground = false
            tf.isEditable = true
            tf.lineBreakMode = .byTruncatingTail
            tf.placeholderString = L10n.secureFieldValuePlaceholder
            tf.translatesAutoresizingMaskIntoConstraints = false
            addSubview(tf)
            NSLayoutConstraint.activate([
                tf.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
                tf.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
                tf.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    /// フィールドの表示モードを設定する。
    /// `isPassword` が `true` の場合は secureField を、`false` の場合は plainField を表示する。
    /// `textField` プロパティにアクティブなフィールドを設定することで
    /// Tab ナビゲーションからのフォーカスを可能にする。
    func configure(value: String, isPassword: Bool, target: AnyObject, action: Selector) {
        if isPassword {
            secureField.stringValue = value
            secureField.target = target
            secureField.action = action
            plainField.isHidden  = true
            secureField.isHidden = false
        } else {
            plainField.stringValue = value
            plainField.target = target
            plainField.action = action
            secureField.isHidden = true
            plainField.isHidden  = false
        }
        textField = isPassword ? secureField : plainField
    }

    /// 現在表示中のフィールドの入力値を返す。
    var currentValue: String {
        secureField.isHidden ? plainField.stringValue : secureField.stringValue
    }
}

// MARK: - TabCapturingButton

/// `acceptsFirstResponder` を `true` にオーバーライドした NSButton。
/// `makeFirstResponder` で確実にフォーカスを受け取れるようにするため、
/// Tab ナビゲーションのフォーカス対象ボタン（+/-/Cancel/Save）に使用する。
/// Tab イベント自体は `SecureItemEditViewController` のローカルイベントモニターが処理する。
final class TabCapturingButton: NSButton {
    override var acceptsFirstResponder: Bool { true }
}
