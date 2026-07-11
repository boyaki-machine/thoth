//
//  SecureItemEditViewController.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Copyright © 2015-2018 Clipy Project.
//

import Cocoa

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
/// [+][-] [パスワード生成...]   [Cancel][Save]
/// ```
///
/// ## Tab キーナビゲーション
/// NSWindow が Tab イベントを横取りするため `insertTab` オーバーライドでは対応不可。
/// ローカルイベントモニター（`tabEventMonitor`）でキーダウンを先に捕捉し、
/// `handleTabKey(shift:)` で手動ルーティングする。
///
/// Tab 順序（正方向）:
///   titleField → Label[0] → Value[0] → Checkbox[0] → Label[1] → ... → +ボタン → -ボタン → パスワード生成 → Cancel → Save → titleField
///
/// ## フォーカス検出
/// `NSControl.currentEditor()` が nil 以外を返す場合に「そのフィールドが編集中」と判定する。
/// `window.firstResponder` を直接比較する方法は、テキストフィールドが編集中に
/// first responder がフィールドエディタ (NSTextView) に切り替わるため不安定。
final class SecureItemEditViewController: NSViewController {

    var onSave: ((SecureMenuItem) -> Void)?

    private var editingItem: SecureMenuItem
    // NSTableViewDataSource 拡張（別ファイル）から参照するため internal
    var fields: [SecureMenuItem.Field]

    private let titleField        = NSTextField()
    // NSTableViewDataSource 拡張（別ファイル）から参照するため internal
    let fieldsTable               = NSTableView()
    private let fieldsScroll      = NSScrollView()
    private let addFieldBtnRef    = TabCapturingButton()
    private let removeFieldBtnRef = TabCapturingButton()
    private let passwordGeneratorBtnRef = TabCapturingButton()
    private let cancelBtnRef      = TabCapturingButton()
    private let saveBtnRef        = TabCapturingButton()
    /// `viewDidAppear` で登録し、`viewWillDisappear` で解除するローカルイベントモニター。
    private var tabEventMonitor: Any?

    // NSTableViewDataSource 拡張（別ファイル）から参照するため internal
    enum ColID {
        static let label   = NSUserInterfaceItemIdentifier("fLabel")
        static let value   = NSUserInterfaceItemIdentifier("fValue")
        static let pass    = NSUserInterfaceItemIdentifier("fPass")
        static let history = NSUserInterfaceItemIdentifier("fHistory")
    }

    init(item: SecureMenuItem?) {
        let editTargetItem = item ?? SecureMenuItem(itemID: UUID().uuidString, title: "", fields: [], displayOrder: 0)
        editingItem = editTargetItem
        fields = editTargetItem.fields
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
            // Return / Numpad Enter: ボタンにフォーカスがある場合はそのボタンを押下する
            // （Save ボタンの keyEquivalent "\r" より先に処理して誤発動を防ぐ）
            if event.keyCode == 36 || event.keyCode == 76, mods.isEmpty,
               let focusedButton = self.view.window?.firstResponder as? TabCapturingButton {
                focusedButton.performClick(nil)
                return nil
            }
            if event.keyCode == 0 && mods == .control {       // Ctrl+A → フィールド追加
                self.addFieldRow()
                return nil
            }
            if event.keyCode == 2 && mods == .control {       // Ctrl+D → フィールド削除
                self.removeFieldRow()
                return nil
            }
            if event.keyCode == 35 && (mods == .command || mods == .option) { // Cmd+P / Opt+P → パスワード生成
                self.openPasswordGenerator()
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
            passwordGeneratorBtnRef.leadingAnchor.constraint(equalTo: removeFieldBtnRef.trailingAnchor, constant: 16),
            passwordGeneratorBtnRef.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),
            saveBtnRef.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            saveBtnRef.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),
            cancelBtnRef.trailingAnchor.constraint(equalTo: saveBtnRef.leadingAnchor, constant: -8),
            cancelBtnRef.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8)
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

        // Val の変更履歴列（クリックで過去の値をポップアップ表示）
        let historyCol = NSTableColumn(identifier: ColID.history)
        historyCol.title = "🕘"; historyCol.width = 36; historyCol.minWidth = 36; historyCol.maxWidth = 36

        fieldsTable.addTableColumn(labelCol)
        fieldsTable.addTableColumn(valueCol)
        fieldsTable.addTableColumn(passCol)
        fieldsTable.addTableColumn(historyCol)
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

        passwordGeneratorBtnRef.title = "\(L10n.passwordGenerator)..."
        passwordGeneratorBtnRef.bezelStyle = .rounded
        passwordGeneratorBtnRef.toolTip = "⌘P / ⌥P"
        passwordGeneratorBtnRef.target = self
        passwordGeneratorBtnRef.action = #selector(openPasswordGenerator)
        passwordGeneratorBtnRef.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(passwordGeneratorBtnRef)

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

    /// パスワード生成ダイアログを開く（生成したパスワードはコピーして Value 欄に貼り付ける）
    @objc private func openPasswordGenerator() {
        NSApp.activate(ignoringOtherApps: true)
        CPYPasswordGeneratorWindowController.shared.showWindow(self)
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
            currentFields.append(SecureMenuItem.Field(fieldID: fields[row].fieldID,
                                                      label: label, value: value,
                                                      isPassword: fields[row].isPassword,
                                                      history: fields[row].history))
        }

        let saved = SecureMenuItem(itemID: editingItem.itemID, title: title, fields: currentFields,
                                   displayOrder: editingItem.displayOrder)
        onSave?(saved)
        presentingViewController?.dismiss(self)
    }

    // MARK: - Table Cell Change Handlers

    @objc func labelFieldChanged(_ sender: NSTextField) {
        let row = fieldsTable.row(for: sender)
        guard row >= 0, row < fields.count else { return }
        fields[row] = SecureMenuItem.Field(fieldID: fields[row].fieldID,
                                           label: sender.stringValue,
                                           value: fields[row].value,
                                           isPassword: fields[row].isPassword,
                                           history: fields[row].history)
    }

    @objc func valueFieldChanged(_ sender: NSTextField) {
        let row = fieldsTable.row(for: sender)
        guard row >= 0, row < fields.count else { return }
        fields[row] = SecureMenuItem.Field(fieldID: fields[row].fieldID,
                                           label: fields[row].label,
                                           value: sender.stringValue,
                                           isPassword: fields[row].isPassword,
                                           history: fields[row].history)
    }

    @objc func passwordCheckboxChanged(_ sender: NSButton) {
        let row = fieldsTable.row(for: sender)
        guard row >= 0, row < fields.count else { return }
        // 画面上のセルから最新の value を取得してモデルを更新する
        let currentValue = (fieldsTable.view(atColumn: 1, row: row, makeIfNecessary: false)
                                as? FieldValueCell)?.currentValue ?? fields[row].value
        fields[row] = SecureMenuItem.Field(fieldID: fields[row].fieldID,
                                           label: fields[row].label,
                                           value: currentValue,
                                           isPassword: sender.state == .on,
                                           history: fields[row].history)
        // value 列を再描画してプレーン／セキュアフィールドの表示を切り替える
        fieldsTable.reloadData(forRowIndexes: IndexSet(integer: row),
                               columnIndexes: IndexSet(integer: 1))
    }

}

// MARK: - Tab Navigation
extension SecureItemEditViewController {

    /// 指定行の Label 列テキストフィールドにフォーカスを移す。
    /// `makeIfNecessary: true` でセルビューを強制生成してからフォーカスする
    /// （`editColumn` はビューが未生成の行では動作しない場合がある）。
    private func activateLabelField(row: Int) {
        guard row < fields.count else { return }
        fieldsTable.scrollRowToVisible(row)
        if let cell = fieldsTable.view(atColumn: 0, row: row, makeIfNecessary: true) as? NSTableCellView,
           let textField = cell.textField {
            view.window?.makeFirstResponder(textField)
        }
    }

    /// 指定行の Value 列テキストフィールド（プレーンまたはセキュア）にフォーカスを移す。
    private func activateValueField(row: Int) {
        guard row < fields.count else { return }
        fieldsTable.scrollRowToVisible(row)
        if let cell = fieldsTable.view(atColumn: 1, row: row, makeIfNecessary: true) as? FieldValueCell,
           let textField = cell.textField {
            view.window?.makeFirstResponder(textField)
        }
    }

    /// 指定行のパスワードチェックボックスにフォーカスを移す。
    private func activateCheckbox(row: Int) {
        guard row < fields.count else { return }
        fieldsTable.scrollRowToVisible(row)
        if let cell = fieldsTable.view(atColumn: 2, row: row, makeIfNecessary: true),
           let button = cell.subviews.first(where: { $0 is TabCapturingButton }) as? TabCapturingButton {
            view.window?.makeFirstResponder(button)
        }
    }

    /// チェックボックスから Tab を押した際のフォーカス先を決定する。
    /// 次の行があれば Label[row+1]、なければ +ボタン へ移動する。
    private func tabFromCheckbox(row: Int) {
        if row < fields.count - 1 { activateLabelField(row: row + 1) } else { view.window?.makeFirstResponder(addFieldBtnRef) }
    }

    // MARK: - Local Event Monitor (Tab キー全体を一括処理)

    // swiftlint:disable:next cyclomatic_complexity
    fileprivate func handleTabKey(shift: Bool) -> Bool {
        guard let window = view.window else { return false }
        let currentResponder = window.firstResponder

        // ── titleField ────────────────────────────────────────────────────
        if titleField.currentEditor() != nil || currentResponder === titleField {
            if shift { window.makeFirstResponder(saveBtnRef) } else if fields.isEmpty { window.makeFirstResponder(addFieldBtnRef) } else { activateLabelField(row: 0) }
            return true
        }

        // ── テーブル内の各行 ──────────────────────────────────────────────
        for row in 0..<fields.count {
            // Label 列
            if let cell = fieldsTable.view(atColumn: 0, row: row, makeIfNecessary: false) as? NSTableCellView,
               let labelTF = cell.textField,
               labelTF.currentEditor() != nil || currentResponder === labelTF {
                if shift {
                    if row > 0 { activateCheckbox(row: row - 1) } else { window.makeFirstResponder(titleField) }
                } else { activateValueField(row: row) }
                return true
            }
            // Value 列: プレーン／セキュアの両フィールドを確認
            if let cell = fieldsTable.view(atColumn: 1, row: row, makeIfNecessary: false) as? FieldValueCell,
               cell.plainField.currentEditor() != nil || currentResponder === cell.plainField
                || cell.secureField.currentEditor() != nil || currentResponder === cell.secureField {
                if shift { activateLabelField(row: row) } else { activateCheckbox(row: row) }
                return true
            }
            // Checkbox 列
            if let cell = fieldsTable.view(atColumn: 2, row: row, makeIfNecessary: false),
               let button = cell.subviews.first(where: { $0 is TabCapturingButton }) as? TabCapturingButton,
               currentResponder === button {
                if shift { activateValueField(row: row) } else { tabFromCheckbox(row: row) }
                return true
            }
        }

        // ── ボトムバーのボタン ────────────────────────────────────────────
        switch currentResponder {
        case addFieldBtnRef:
            if shift {
                if fields.isEmpty { window.makeFirstResponder(titleField) } else { activateCheckbox(row: fields.count - 1) }
            } else { window.makeFirstResponder(removeFieldBtnRef) }
            return true
        case removeFieldBtnRef:
            if shift { window.makeFirstResponder(addFieldBtnRef) } else { window.makeFirstResponder(passwordGeneratorBtnRef) }
            return true
        case passwordGeneratorBtnRef:
            if shift { window.makeFirstResponder(removeFieldBtnRef) } else { window.makeFirstResponder(cancelBtnRef) }
            return true
        case cancelBtnRef:
            if shift { window.makeFirstResponder(passwordGeneratorBtnRef) } else { window.makeFirstResponder(saveBtnRef) }
            return true
        case saveBtnRef:
            if shift { window.makeFirstResponder(cancelBtnRef) } else { window.makeFirstResponder(titleField) }
            return true
        default:
            return false
        }
    }

    fileprivate func navigateFieldRow(offset: Int) {
        let current = fieldsTable.selectedRow
        let next = current < 0 ? (offset > 0 ? 0 : fields.count - 1) : current + offset
        guard next >= 0, next < fields.count else { return }
        fieldsTable.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        fieldsTable.scrollRowToVisible(next)
    }

    fileprivate func moveFieldRow(by delta: Int) {
        let row = fieldsTable.selectedRow
        guard row >= 0 else { return }
        let newRow = row + delta
        guard newRow >= 0, newRow < fields.count else { NSSound.beep(); return }
        fields.swapAt(row, newRow)
        fieldsTable.reloadData(forRowIndexes: IndexSet([row, newRow]), columnIndexes: IndexSet(0..<3))
        fieldsTable.selectRowIndexes(IndexSet(integer: newRow), byExtendingSelection: false)
    }
}
