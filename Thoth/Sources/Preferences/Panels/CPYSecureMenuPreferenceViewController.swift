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
    static let clipySecureItemRow = NSPasteboard.PasteboardType("io.github.boyaki-machine.thoth.secureItemRow")
}

// MARK: - Window Controller

/// セキュアアイテム管理ウィンドウのコントローラ。
/// アプリ起動中に一度だけ生成されるシングルトン。
/// 表示のたびに `reloadItems()` でデータを最新化する。
final class CPYSecureItemsWindowController: NSWindowController {

    static let shared: CPYSecureItemsWindowController = {
        let secureItemsViewController = CPYSecureItemsViewController()
        let window = NSWindow(contentViewController: secureItemsViewController)
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
    // Tab キーによるフォーカス切替対象のボタン群（TabCapturingButton でフォーカスを受け取る）
    private let addButton    = TabCapturingButton()
    private let removeButton = TabCapturingButton()
    private let importButton = TabCapturingButton()
    private let exportButton = TabCapturingButton()
    private let closeButton  = TabCapturingButton()
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

        let dragHandleColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("dragHandle"))
        dragHandleColumn.title = ""
        dragHandleColumn.width = 20
        dragHandleColumn.minWidth = 20
        dragHandleColumn.maxWidth = 20

        let titleColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("title"))
        titleColumn.title = "Title"
        titleColumn.width = 280

        let fieldsColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("fields"))
        fieldsColumn.title = "Fields"
        fieldsColumn.width = 100

        tableView.addTableColumn(dragHandleColumn)
        tableView.addTableColumn(titleColumn)
        tableView.addTableColumn(fieldsColumn)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.doubleAction = #selector(editItemAction)
        tableView.target = self
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = true
        tableView.registerForDraggedTypes([.clipySecureItemRow])
        tableView.setDraggingSourceOperationMask(.move, forLocal: true)
        scrollView.documentView = tableView

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(separator)

        addButton.image = NSImage(named: NSImage.addTemplateName)
        addButton.bezelStyle = .smallSquare
        addButton.translatesAutoresizingMaskIntoConstraints = false
        addButton.target = self
        addButton.action = #selector(addItemAction)
        view.addSubview(addButton)

        removeButton.image = NSImage(named: NSImage.removeTemplateName)
        removeButton.bezelStyle = .smallSquare
        removeButton.translatesAutoresizingMaskIntoConstraints = false
        removeButton.target = self
        removeButton.action = #selector(deleteItemAction)
        view.addSubview(removeButton)

        importButton.title = L10n.importSecureItems
        importButton.bezelStyle = .rounded
        importButton.translatesAutoresizingMaskIntoConstraints = false
        importButton.target = self
        importButton.action = #selector(importItemsAction)
        view.addSubview(importButton)

        exportButton.title = L10n.exportSecureItems
        exportButton.bezelStyle = .rounded
        exportButton.translatesAutoresizingMaskIntoConstraints = false
        exportButton.target = self
        exportButton.action = #selector(exportItemsAction)
        view.addSubview(exportButton)

        closeButton.title = L10n.close
        closeButton.bezelStyle = .rounded
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.target = self
        closeButton.action = #selector(closeWindow)
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

            importButton.leadingAnchor.constraint(equalTo: removeButton.trailingAnchor, constant: 16),
            importButton.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),

            exportButton.leadingAnchor.constraint(equalTo: importButton.trailingAnchor, constant: 4),
            exportButton.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),

            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            closeButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8)
        ])
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.view.window else { return event }
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            switch event.keyCode {
            case 48: // Tab / Shift+Tab → アイテムリストと各ボタンのフォーカスを循環
                guard mods.isEmpty || mods == .shift else { return event }
                self.cycleFocus(backward: mods == .shift)
            case 38: // j
                if mods == .control { self.moveSelectedItem(by: 1) } else if mods.isEmpty { self.selectRow(offset: 1) } else { return event }
            case 40: // k
                if mods == .control { self.moveSelectedItem(by: -1) } else if mods.isEmpty { self.selectRow(offset: -1) } else { return event }
            case 49, 36, 76: // Space / Return / Numpad Enter
                guard mods.isEmpty else { return event }
                // ボタンにフォーカスがある場合はそのボタンを押下する
                if let button = self.view.window?.firstResponder as? TabCapturingButton {
                    button.performClick(nil)
                } else {
                    self.editItemAction()
                }
            case 37: // l
                guard mods.isEmpty, !(self.view.window?.firstResponder is TabCapturingButton) else { return event }
                self.editItemAction()
            default:
                return event
            }
            return nil
        }
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        if let monitor = keyMonitor { NSEvent.removeMonitor(monitor); keyMonitor = nil }
    }

    func reloadItems() {
        items = AppEnvironment.current.secureMenuService.loadAllItems()
        tableView.reloadData()
        // アクセス拒否（バイナリ更新による Keychain ACL 不一致など）を検出したら警告を表示する
        if AppEnvironment.current.secureMenuService.isKeychainAccessDenied {
            showKeychainAccessDeniedAlert()
        }
    }

    private func showKeychainAccessDeniedAlert() {
        NSAlert.showNotice(message: L10n.secureItems,
                           informative: L10n.secureItemsKeychainAccessDenied,
                           for: view.window)
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
        NSAlert.showNotice(message: "Save failed",
                           informative: "Failed to save the item to Keychain. Check Console.app for details (filter: SecureMenuService).")
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
        // 複数選択に対応: 選択中のすべてのアイテムをまとめて削除する
        let selectedItems = tableView.selectedRowIndexes.compactMap { items[safe: $0] }
        guard !selectedItems.isEmpty else {
            NSSound.beep()
            return
        }
        var message = L10n.areYouSureWantToDeleteThisSecureItem
        if selectedItems.count > 1 {
            message += " (\(selectedItems.count))"
        }
        guard let window = view.window else { return }
        NSAlert.showConfirmation(message: L10n.deleteSecureItem, informative: message,
                                 confirmTitle: L10n.deleteSecureItem, cancelTitle: L10n.cancel,
                                 for: window) { [weak self] in
            _ = AppEnvironment.current.secureMenuService.delete(itemIDs: selectedItems.map { $0.itemID })
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
        case "dragHandle": return "≡"
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
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(String(row), forType: .clipySecureItemRow)
        return pasteboardItem
    }

    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo,
                   proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        if dropOperation == .on { tableView.setDropRow(row, dropOperation: .above) }
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

// MARK: - Tab Focus Navigation

fileprivate extension CPYSecureItemsViewController {
    /// Tab キーでアイテムリスト → + → - → Import → Export → 閉じる → アイテムリスト の順に
    /// フォーカスを循環させる（Shift+Tab は逆順）。
    func cycleFocus(backward: Bool) {
        guard let window = view.window else { return }
        let focusOrder: [NSResponder] = [tableView, addButton, removeButton, importButton, exportButton, closeButton]
        let currentIndex = focusOrder.firstIndex { $0 === window.firstResponder } ?? 0
        let offset = backward ? focusOrder.count - 1 : 1
        let nextResponder = focusOrder[(currentIndex + offset) % focusOrder.count]
        window.makeFirstResponder(nextResponder)
    }
}

// MARK: - Import / Export

extension CPYSecureItemsViewController {

    /// エクスポート: 平文で出力される旨を警告してから保存先を選択させる
    @objc fileprivate func exportItemsAction() {
        guard let window = view.window else { return }
        NSAlert.showConfirmation(message: L10n.exportSecureItems,
                                 informative: L10n.secureItemsExportWarning,
                                 confirmTitle: L10n.exportSecureItems, cancelTitle: L10n.cancel,
                                 for: window) { [weak self] in
            self?.showExportPanel()
        }
    }

    private func showExportPanel() {
        guard let window = view.window else { return }
        let panel = NSSavePanel()
        panel.allowedFileTypes = ["json"]
        panel.nameFieldStringValue = "clipy-secure-items.json"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.exportItems(to: url)
        }
    }

    /// エクスポートの単位は「ユーザー自身が設定した機微情報」（SecureUserData）。
    /// セキュアアイテムに加えて指紋パスワードも含まれる。
    /// アプリが自動生成する環境固有の情報（DB 暗号鍵等）は対象外
    private func exportItems(to url: URL) {
        do {
            let service = AppEnvironment.current.secureMenuService
            let userData = SecureUserData(items: service.loadAllItems(),
                                          cryptoPassword: service.loadCryptoPassword())
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(userData)
            try data.write(to: url, options: .atomic)
        } catch {
            showImportExportError(error)
        }
    }

    /// インポート: JSON を読み込み、同じ ID のアイテムは上書き・それ以外は末尾に追加する
    @objc fileprivate func importItemsAction() {
        guard let window = view.window else { return }
        let panel = NSOpenPanel()
        panel.allowedFileTypes = ["json"]
        panel.allowsMultipleSelection = false
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.importItems(from: url)
        }
    }

    private func importItems(from url: URL) {
        do {
            let data = try Data(contentsOf: url)
            let service = AppEnvironment.current.secureMenuService
            // 現行形式（SecureUserData オブジェクト）を優先し、
            // 旧形式（アイテムの配列のみ）もフォールバックで読み込める
            let importedItems: [SecureMenuItem]
            if let userData = try? JSONDecoder().decode(SecureUserData.self, from: data) {
                importedItems = userData.items
                // 指紋パスワードが含まれていれば取り込む（既存の登録は上書きされる）
                if let password = userData.cryptoPassword, !password.isEmpty {
                    _ = service.saveCryptoPassword(password)
                }
            } else {
                importedItems = try JSONDecoder().decode([SecureMenuItem].self, from: data)
            }
            var savedCount = 0
            for item in importedItems where service.save(item) {
                savedCount += 1
            }
            reloadItems()
            NSAlert.showNotice(message: L10n.importSecureItems,
                               informative: L10n.importedSecureItemsFormat(savedCount),
                               style: .informational, for: view.window)
        } catch {
            showImportExportError(error)
        }
    }

    private func showImportExportError(_ error: Error) {
        NSAlert.showNotice(message: L10n.secureItems,
                           informative: error.localizedDescription,
                           for: view.window)
    }
}
