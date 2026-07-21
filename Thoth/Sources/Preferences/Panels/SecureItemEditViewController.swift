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

    // titleField〜saveBtnRef はキーボード操作拡張（+Keyboard.swift）から参照するため internal
    let titleField        = NSTextField()
    // NSTableViewDataSource 拡張（別ファイル）から参照するため internal
    let fieldsTable               = NSTableView()
    private let fieldsScroll      = NSScrollView()
    let addFieldBtnRef    = TabCapturingButton()
    let removeFieldBtnRef = TabCapturingButton()
    let passwordGeneratorBtnRef = TabCapturingButton()
    let totpImportBtnRef = TabCapturingButton()
    let cancelBtnRef      = TabCapturingButton()
    let saveBtnRef        = TabCapturingButton()
    /// `viewDidAppear` で登録し、`viewWillDisappear` で解除するローカルイベントモニター。
    private var tabEventMonitor: Any?

    // NSTableViewDataSource 拡張（別ファイル）から参照するため internal
    enum ColID {
        static let dragHandle = NSUserInterfaceItemIdentifier("fDragHandle")
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
        // 履歴列（🕘）まで初期状態で見えるよう、列幅合計に余裕を持たせた幅にする
        view = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 360))
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
            totpImportBtnRef.leadingAnchor.constraint(equalTo: passwordGeneratorBtnRef.trailingAnchor, constant: 8),
            totpImportBtnRef.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),
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
        let dragHandleCol = NSTableColumn(identifier: ColID.dragHandle)
        dragHandleCol.title = ""; dragHandleCol.width = 20; dragHandleCol.minWidth = 20; dragHandleCol.maxWidth = 20

        let labelCol = NSTableColumn(identifier: ColID.label)
        labelCol.title = "Label"; labelCol.width = 130; labelCol.minWidth = 60

        let valueCol = NSTableColumn(identifier: ColID.value)
        valueCol.title = "Value"; valueCol.width = 168; valueCol.minWidth = 60

        let passCol = NSTableColumn(identifier: ColID.pass)
        passCol.title = "🔒"; passCol.width = 36; passCol.minWidth = 36; passCol.maxWidth = 36

        // Val の変更履歴列（クリックで過去の値をポップアップ表示）
        let historyCol = NSTableColumn(identifier: ColID.history)
        historyCol.title = "🕘"; historyCol.width = 36; historyCol.minWidth = 36; historyCol.maxWidth = 36

        fieldsTable.addTableColumn(dragHandleCol)
        fieldsTable.addTableColumn(labelCol)
        fieldsTable.addTableColumn(valueCol)
        fieldsTable.addTableColumn(passCol)
        fieldsTable.addTableColumn(historyCol)
        fieldsTable.columnAutoresizingStyle = .noColumnAutoresizing
        fieldsTable.dataSource = self
        fieldsTable.delegate = self
        fieldsTable.usesAlternatingRowBackgroundColors = true
        fieldsTable.rowHeight = 24
        fieldsTable.registerForDraggedTypes([NSPasteboard.PasteboardType("io.github.boyaki-machine.thoth.secure-field-row")])
        fieldsTable.setDraggingSourceOperationMask(.move, forLocal: true)
        // ラベル/値列はシングルクリックで即編集に入る（行選択→再クリックの
        // 2 段階を無くし、セル幅全体をクリック対象にする）
        fieldsTable.target = self
        fieldsTable.action = #selector(fieldsTableClicked)

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

        totpImportBtnRef.title = L10n.addTOTP
        totpImportBtnRef.bezelStyle = .rounded
        totpImportBtnRef.target = self
        totpImportBtnRef.action = #selector(addTOTP)
        totpImportBtnRef.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(totpImportBtnRef)

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

    /// パスワード生成ダイアログを開く（生成したパスワードはコピーして Value 欄に貼り付ける）。
    /// 呼び出し元（この編集シート）が明確なため、シートとして表示する
    @objc private func openPasswordGenerator() {
        presentAsSheet(CPYPasswordGeneratorViewController())
    }

    /// TOTP 取り込みシートを開く
    @objc private func addTOTP() {
        let vc = CPYTOTPImportViewController()
        vc.onImport = { [weak self] (secret: String) in
            guard let self = self else { return }
            let field = SecureMenuItem.Field(label: L10n.totpDefaultFieldLabel, value: secret,
                                             isPassword: false, kind: .totp)
            self.fields.append(field)
            self.fieldsTable.insertRows(at: IndexSet(integer: self.fields.count - 1), withAnimation: .slideDown)
        }
        presentAsSheet(vc)
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
            let label = (fieldsTable.view(atColumn: 1, row: row, makeIfNecessary: false)
                            as? NSTableCellView)?.textField?.stringValue ?? fields[row].label
            // TOTP の Value（otpauth URI / secret）はセルに表示しない設計で、
            // セルの入力値は常に空文字になる。セルから読むと保存のたびに
            // 秘密鍵を空文字で消してしまうため、必ずモデルの値を使う
            let value: String
            if fields[row].isTOTP {
                value = fields[row].value
            } else {
                value = (fieldsTable.view(atColumn: 2, row: row, makeIfNecessary: false)
                            as? FieldValueCell)?.currentValue ?? fields[row].value
            }
            guard !label.trimmingCharacters(in: .whitespaces).isEmpty
                    || !value.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            currentFields.append(SecureMenuItem.Field(fieldID: fields[row].fieldID,
                                                      label: label, value: value,
                                                      isPassword: fields[row].isPassword,
                                                      kind: fields[row].kind,
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
                                           kind: fields[row].kind,
                                           history: fields[row].history)
    }

    @objc func valueFieldChanged(_ sender: NSTextField) {
        let row = fieldsTable.row(for: sender)
        guard row >= 0, row < fields.count else { return }
        fields[row] = SecureMenuItem.Field(fieldID: fields[row].fieldID,
                                           label: fields[row].label,
                                           value: sender.stringValue,
                                           isPassword: fields[row].isPassword,
                                           kind: fields[row].kind,
                                           history: fields[row].history)
    }

    /// クリックされた列がシングルクリックで即編集に入れる列かを判定する（純粋関数）。
    /// ラベル列は常に編集可、値列は TOTP 行以外で編集可、それ以外
    /// （ドラッグハンドル・🔒・履歴の各列）は編集対象外。
    /// UI に依存しないためユニットテスト可能
    static func isEditableColumn(_ columnID: NSUserInterfaceItemIdentifier, isTOTP: Bool) -> Bool {
        switch columnID {
        case ColID.label: return true
        case ColID.value: return !isTOTP
        default: return false
        }
    }

    /// 指定列からの行ドラッグ（並べ替え）を許可するかを判定する（純粋関数）。
    /// ドラッグハンドル列（≡）のみ許可し、ラベル/値/ボタン列上のドラッグは
    /// 編集・選択のために使えるようにする。UI に依存しないためユニットテスト可能
    static func allowsRowDrag(from columnID: NSUserInterfaceItemIdentifier) -> Bool {
        return columnID == ColID.dragHandle
    }

    /// テーブルのシングルクリックで、ラベル列・値列を即編集に切り替える。
    /// ボタン列（🔒・履歴）・ドラッグハンドル列は対象外。TOTP 行の値は編集不可
    @objc func fieldsTableClicked() {
        let row = fieldsTable.clickedRow
        let column = fieldsTable.clickedColumn
        guard row >= 0, row < fields.count, column >= 0, column < fieldsTable.numberOfColumns else { return }
        let columnID = fieldsTable.tableColumns[column].identifier
        guard Self.isEditableColumn(columnID, isTOTP: fields[row].isTOTP) else { return }
        fieldsTable.editColumn(column, row: row, with: nil, select: false)
    }

    @objc func passwordCheckboxChanged(_ sender: NSButton) {
        let row = fieldsTable.row(for: sender)
        guard row >= 0, row < fields.count else { return }
        // Value 列の既存セルを取得（ドラッグハンドル列があるため列番号は直書きせず
        // 識別子から解決する）
        let valueColumn = fieldsTable.column(withIdentifier: ColID.value)
        guard valueColumn >= 0 else { return }
        let valueCell = fieldsTable.view(atColumn: valueColumn, row: row, makeIfNecessary: false) as? FieldValueCell
        // 画面上のセルから最新の value を取得してモデルを更新する
        let currentValue = valueCell?.currentValue ?? fields[row].value
        // 値欄を編集中だった場合は、フィールドの差し替え前に編集を確定して
        // フィールドエディタ（NSText）を切り離す
        if let editing = valueCell?.textField, view.window?.firstResponder != nil {
            view.window?.endEditing(for: editing)
        }
        let isPassword = sender.state == .on
        fields[row] = SecureMenuItem.Field(fieldID: fields[row].fieldID,
                                           label: fields[row].label,
                                           value: currentValue,
                                           isPassword: isPassword,
                                           kind: fields[row].kind,
                                           history: fields[row].history)
        // reload では field editor の状態次第で表示が更新されないことがあるため、
        // 既存セルを直接再構成してプレーン／セキュアフィールドの表示を即時に切り替える
        valueCell?.configure(value: currentValue, isPassword: isPassword, isTOTP: fields[row].isTOTP,
                             createdAt: fields[row].createdAt,
                             target: self, action: #selector(valueFieldChanged(_:)))
    }

}

// Tab ナビゲーション・キーボード操作は SecureItemEditViewController+Keyboard.swift を参照

// MARK: - Drag & Drop (Row Reordering)

extension SecureItemEditViewController: NSDraggingSource, NSDraggingDestination {

    /// ドラッグソースのペーストボード情報を提供する
    /// NSTableView が自動的にドラッグを開始するために必須
    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (NSPasteboardWriting)? {
        // ドラッグ開始位置がドラッグハンドル列（≡）のときだけ並べ替えを許可する。
        // nil を返すとその行のドラッグ自体が始まらないため、ラベル/値のテキスト
        // フィールド上でのクリックやドラッグが行の並べ替えに奪われず、編集・選択に
        // 使える（willBeginAt はドラッグ開始後の通知で中止できないため、ここで制御する）。
        let mouseInWindow = tableView.window?.mouseLocationOutsideOfEventStream ?? .zero
        let pointInTable = tableView.convert(mouseInWindow, from: nil)
        let column = tableView.column(at: pointInTable)
        guard column >= 0, column < tableView.numberOfColumns,
              Self.allowsRowDrag(from: tableView.tableColumns[column].identifier) else { return nil }

        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(String(row), forType: NSPasteboard.PasteboardType("io.github.boyaki-machine.thoth.secure-field-row"))
        return pasteboardItem
    }

    /// ドラッグ中のホバー時に、ドロップが許可されるか判定する
    /// dropOperation を .above に変更して行間に挿入線を表示する
    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo,
                   proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        guard let pboard = info.draggingPasteboard.string(forType: NSPasteboard.PasteboardType("io.github.boyaki-machine.thoth.secure-field-row")) else {
            return []
        }
        let pboardStr = String(pboard)
        guard let sourceRow = Int(pboardStr) else { return [] }

        // 同じ行へのドロップは拒否
        if row == sourceRow || row == sourceRow + 1 { return [] }

        // .on を .above に変更（行間の挿入線を表示）
        if dropOperation == .on {
            tableView.setDropRow(row, dropOperation: .above)
        } else {
            tableView.setDropRow(row, dropOperation: dropOperation)
        }

        return .move
    }

    /// ドロップを受け入れて行の順序を変更する
    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo,
                   row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        guard let pboard = info.draggingPasteboard.string(forType: NSPasteboard.PasteboardType("io.github.boyaki-machine.thoth.secure-field-row")) else {
            return false
        }
        let pboardStr = String(pboard)
        guard let sourceRow = Int(pboardStr) else { return false }

        // 境界値チェック（.above では row は 0～count）
        guard sourceRow >= 0, sourceRow < fields.count, row >= 0, row <= fields.count else { return false }

        // 同じ行へのドロップは無視
        if dropOperation == .above && (row == sourceRow || row == sourceRow + 1) { return false }

        // 行を移動
        let field = fields.remove(at: sourceRow)
        let targetRow = row > sourceRow ? row - 1 : row
        fields.insert(field, at: targetRow)

        // テーブル再描画
        let minRow = min(sourceRow, targetRow)
        let maxRow = max(sourceRow, targetRow)
        fieldsTable.reloadData(forRowIndexes: IndexSet(integersIn: minRow...maxRow), columnIndexes: IndexSet(0..<5))
        fieldsTable.selectRowIndexes(IndexSet(integer: targetRow), byExtendingSelection: false)

        return true
    }

    // NSDraggingSource の必須メソッド
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        return .move
    }
}
