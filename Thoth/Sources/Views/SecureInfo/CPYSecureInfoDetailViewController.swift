//
//  CPYSecureInfoDetailViewController.swift
//
//  Thoth
//  GitHub: https://github.com/boyaki-machine/Thoth
//

import Cocoa

/// セキュア情報確認ウィンドウの右ペイン。
/// 選択中アイテムのタイトルと各フィールドを縦に並べて表示する。
///
/// フィールド行は `NSTableView` ではなく `NSStackView` に積む。理由は 2 つ:
/// - メモの `NSTextView` は行高が可変で、テーブルの自動行高とは相性が悪い
/// - セル再利用があると「表示中（👁 ON）の状態が別の行に残る」事故が起きうる。
///   行ビューを使い捨てにすればその危険が構造的に無くなる
///
/// 編集機能は後続ステップで追加する。現時点では表示・コピー・URL を開くまで。
final class CPYSecureInfoDetailViewController: NSViewController {

    /// +BottomBar.swift からも参照するので internal
    enum Layout {
        static let padding: CGFloat    = 20
        static let rowSpacing: CGFloat = 10
    }

    /// 表示更新の間隔（秒）。TOTP のコード更新と、平文表示の期限切れ確認を兼ねる
    static let refreshInterval: TimeInterval = 1.0

    // 表示内容をユニットテストから検証できるよう internal にしている
    let titleField = NSTextField(string: "")
    let placeholderLabel = NSTextField(labelWithString: "")
    let rowStackView = NSStackView()

    /// 読み取り専用モード（Keychain を読み出せない場合など）。
    /// 反映するには show(item:) を呼び直す
    var isReadOnly = false

    /// タイトルが変更された（入力のたびに呼ばれる）
    var onTitleEdited: ((String) -> Void)?
    /// 値・ラベルが変更された
    var onFieldEdited: ((SecureMenuItem.Field, _ label: String?, _ value: String?) -> Void)?
    /// 編集が終わった。保存のきっかけに使う
    var onEditingEnded: (() -> Void)?
    /// マスク指定（🔒）が切り替えられた
    var onFieldMaskToggled: ((SecureMenuItem.Field, Bool) -> Void)?
    /// フィールドの削除が要求された
    var onFieldDeleteRequested: ((SecureMenuItem.Field) -> Void)?
    /// フィールドの移動が要求された（右クリックメニュー・ドラッグ&ドロップ）。
    /// 移動先は現在の並びに対する添字
    var onFieldMoveRequested: ((_ fieldID: String, _ toIndex: Int) -> Void)?
    /// 追加するフィールドの種別が選ばれた
    var onAddFieldRequested: ((SecureInfoFieldTemplate) -> Void)?
    /// TOTP の取り込みが要求された
    var onAddTOTPRequested: (() -> Void)?
    /// パスワード生成が要求された
    var onGeneratePasswordRequested: (() -> Void)?

    private let scrollView = NSScrollView()
    /// 行を並べる入れ物であり、並べ替えドラッグの受け皿
    let dropView = SecureFieldDropView()
    /// タイトル行と各フィールドを見分けやすくする区切り線
    let titleSeparator = NSBox()
    /// 他の画面で変更が起きたことを知らせるバー（未保存の編集がある間だけ出す）
    let externalChangeBanner = NSStackView()
    let externalChangeReloadButton = NSButton()
    private var onExternalChangeReload: (() -> Void)?
    let addFieldButton = NSPopUpButton()
    let addTOTPButton = NSButton()
    let generatePasswordButton = NSButton()
    /// ボトムバー左側（追加系）をまとめる入れ物
    let bottomBarStackView = NSStackView()
    /// ウィンドウを閉じるボタン。Esc / ⌘W と同じ操作をマウスからも行えるようにする
    let closeButton = NSButton()
    let totpService = TOTPService()
    var totpTimer: Timer?

    private(set) var displayedItem: SecureMenuItem?

    /// 最後にフォーカスが入ったパスワード生成の入力先フィールドの ID。
    ///
    /// 行ビューではなく ID で覚える。並べ替え・マスク切替・保存のたびに
    /// `show(item:)` が行を作り直すため、ビュー参照だと簿記が合わなくなる。
    /// 別のアイテムへ移ると `show(item:)` が nil に戻す。
    /// 解決は +BottomBar.swift の `fillTargetRow`
    var fillTargetFieldID: String?

    /// 現在並んでいるフィールド行
    var fieldRows: [SecureFieldRowView] {
        return rowStackView.arrangedSubviews.compactMap { $0 as? SecureFieldRowView }
    }

    deinit {
        stopTOTPTimer()
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 520))
        setupUI()
        show(item: nil)
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        // 画面から消えている間も毎秒再描画し続けないよう止める
        stopTOTPTimer()
        hideAllRevealedValues()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        startRefreshTimerIfNeeded()
    }

    private func setupUI() {
        titleField.font = .systemFont(ofSize: NSFont.systemFontSize + 4, weight: .semibold)
        titleField.lineBreakMode = .byTruncatingTail
        titleField.isBordered = false
        titleField.drawsBackground = false
        titleField.placeholderString = L10n.secureItemTitlePlaceholder
        titleField.delegate = self
        titleField.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleField)

        rowStackView.orientation = .vertical
        rowStackView.alignment = .leading
        rowStackView.spacing = Layout.rowSpacing
        rowStackView.translatesAutoresizingMaskIntoConstraints = false

        // 上詰めのための座標反転に加えて、並べ替えドラッグの受け皿も兼ねる
        let documentView = dropView
        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(rowStackView)
        setupDropView()

        scrollView.documentView = documentView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        // 「アイテムを選択してください」の案内。システムカラーを使い、
        // ライト/ダークどちらの外観にも自動で追従させる
        placeholderLabel.textColor = .secondaryLabelColor
        placeholderLabel.alignment = .center
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(placeholderLabel)

        titleSeparator.boxType = .separator
        titleSeparator.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleSeparator)

        setupBottomBar()
        setupExternalChangeBanner()

        NSLayoutConstraint.activate([
            externalChangeBanner.topAnchor.constraint(equalTo: view.topAnchor),
            externalChangeBanner.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            externalChangeBanner.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            titleField.topAnchor.constraint(equalTo: view.topAnchor, constant: Layout.padding),
            titleField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Layout.padding),
            titleField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Layout.padding),

            titleSeparator.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: Layout.rowSpacing),
            titleSeparator.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Layout.padding),
            titleSeparator.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Layout.padding),

            scrollView.topAnchor.constraint(equalTo: titleSeparator.bottomAnchor, constant: Layout.rowSpacing),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Layout.padding),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Layout.padding),
            scrollView.bottomAnchor.constraint(equalTo: bottomBarStackView.topAnchor, constant: -Layout.rowSpacing),

            // 「閉じる」は選択の有無に関わらず出すので、こちらを下端の基準にする
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Layout.padding),
            closeButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -Layout.padding),

            bottomBarStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Layout.padding),
            bottomBarStackView.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            // 幅が足りないときは「閉じる」を押しのけず、こちらが縮む
            bottomBarStackView.trailingAnchor.constraint(lessThanOrEqualTo: closeButton.leadingAnchor,
                                                         constant: -Layout.rowSpacing),

            // 横方向はスクロールさせず、内容の幅を可視領域に合わせる。
            // scrollView 自体の幅に合わせると、縦スクローラーが出たときに
            // その分だけ内容がはみ出して横スクロールが発生する
            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            rowStackView.topAnchor.constraint(equalTo: documentView.topAnchor),
            rowStackView.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            rowStackView.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            rowStackView.bottomAnchor.constraint(equalTo: documentView.bottomAnchor),
            // 内容が可視領域より短くても、ドキュメントビューを縮めて上詰めを保つ
            documentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 0),

            placeholderLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            placeholderLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    /// 並べ替えドラッグの受け皿を配線する。
    /// 行が自分の位置を知らないため、矩形の供給と添字の解決はこちらで行う
    private func setupDropView() {
        dropView.rowFrames = { [weak self] in
            guard let self = self else { return [] }
            return self.fieldRows.map { $0.convert($0.bounds, to: self.dropView) }
        }
        dropView.onFieldDropped = { [weak self] fieldID, gapIndex in
            guard let self = self,
                  let fromIndex = self.fieldRows.firstIndex(where: { $0.field.fieldID == fieldID }) else { return }
            // すき間の番号は「取り除く前の並び」に対する位置。一覧の
            // ドラッグ&ドロップと同じ関数で移動後の添字へ直す
            let destination = SecureInfoEditor.dropDestinationIndex(fromRow: fromIndex, proposedRow: gapIndex)
            self.onFieldMoveRequested?(fieldID, destination)
        }
    }

    /// 他の画面での変更を知らせるバーを組み立てる。
    /// 未保存の編集を勝手に捨てないよう、読み直すかどうかはユーザーに委ねる
    private func setupExternalChangeBanner() {
        let label = NSTextField(labelWithString: L10n.secureInfoExternalChange)
        label.lineBreakMode = .byTruncatingTail

        externalChangeReloadButton.title = L10n.secureInfoReload
        externalChangeReloadButton.bezelStyle = .rounded
        externalChangeReloadButton.target = self
        externalChangeReloadButton.action = #selector(externalChangeReloadTapped)

        externalChangeBanner.orientation = .horizontal
        externalChangeBanner.spacing = Layout.rowSpacing
        externalChangeBanner.edgeInsets = NSEdgeInsets(top: 6, left: Layout.padding, bottom: 6, right: Layout.padding)
        externalChangeBanner.addArrangedSubview(label)
        externalChangeBanner.addArrangedSubview(externalChangeReloadButton)
        externalChangeBanner.isHidden = true
        externalChangeBanner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(externalChangeBanner)
    }

    @objc private func externalChangeReloadTapped() {
        let handler = onExternalChangeReload
        hideExternalChangeBanner()
        handler?()
    }

    /// 他の画面で変更が起きたことを知らせる
    func showExternalChangeBanner(onReload: @escaping () -> Void) {
        onExternalChangeReload = onReload
        externalChangeBanner.isHidden = false
    }

    func hideExternalChangeBanner() {
        externalChangeBanner.isHidden = true
        onExternalChangeReload = nil
    }

    // MARK: - Content

    /// 表示するアイテムを差し替える。nil で「選択なし」表示にする
    func show(item: SecureMenuItem?) {
        // 別のアイテムへ移ったときだけ入力先を忘れる。フィールドの追加・削除・
        // 並べ替え・マスク切替でもここを通るが、それらは同じアイテムの中の
        // 作り直しなので覚えたままにする
        if displayedItem?.itemID != item?.itemID {
            fillTargetFieldID = nil
        }
        displayedItem = item
        rebuildRows(for: item)

        guard let item = item else {
            titleField.stringValue = ""
            titleField.isHidden = true
            titleSeparator.isHidden = true
            scrollView.isHidden = true
            setBottomBarButtonsHidden(true)
            placeholderLabel.stringValue = L10n.secureInfoNoSelection
            placeholderLabel.isHidden = false
            return
        }
        titleField.stringValue = item.title
        titleField.isEditable = !isReadOnly
        titleField.isHidden = false
        titleSeparator.isHidden = false
        scrollView.isHidden = false
        placeholderLabel.isHidden = true
        setBottomBarButtonsHidden(isReadOnly)
    }

    private func rebuildRows(for item: SecureMenuItem?) {
        stopTOTPTimer()
        // 行ビューは使い捨て。前のアイテムの表示状態を持ち越さないよう毎回作り直す
        rowStackView.arrangedSubviews.forEach {
            rowStackView.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        for field in item?.fields ?? [] {
            let row = SecureFieldRowView(field: field, isReadOnly: isReadOnly)
            row.onCopy = { [weak self] row in self?.copyValue(of: row.field) }
            row.onOpenURL = { [weak self] row in self?.openURL(of: row.field) }
            row.onLabelEdited = { [weak self] row, label in self?.onFieldEdited?(row.field, label, nil) }
            row.onValueEdited = { [weak self] row, value in self?.onFieldEdited?(row.field, nil, value) }
            row.onEditingEnded = { [weak self] _ in self?.onEditingEnded?() }
            // パスワード生成の入力先を覚える。ボタンを押した時点では編集が終わって
            // いるため、押されてから探しに行っても手遅れになる
            row.onEditingFocusGained = { [weak self] row in
                guard row.acceptsGeneratedPassword else { return }
                self?.fillTargetFieldID = row.field.fieldID
            }
            row.onMaskToggled = { [weak self] row, isPassword in
                self?.onFieldMaskToggled?(row.field, isPassword)
            }
            row.onDelete = { [weak self] row in self?.onFieldDeleteRequested?(row.field) }
            // 過去のパスワードも現在値と同じ経路でコピーする（秘匿マーカー付き + 自動クリア）
            row.onCopyHistoryValue = { [weak self] _, entry in self?.copyHistoryValue(entry) }
            // 履歴の平文表示が始まったら、期限切れを見張るためタイマーを動かす
            row.onHistoryRevealToggled = { [weak self] _ in self?.startRefreshTimerIfNeeded() }
            // 展開で行の高さが変わるため、スクロール範囲を計算し直させる
            row.onHistoryToggled = { [weak self] _ in self?.rowStackView.layoutSubtreeIfNeeded() }
            // 行は自分が何番目かを知らないので、位置の解決はここで行う
            row.onMove = { [weak self] row, offset in
                guard let self = self,
                      let index = self.fieldRows.firstIndex(where: { $0 === row }) else { return }
                self.onFieldMoveRequested?(row.field.fieldID, index + offset)
            }
            // 平文表示が始まったら、期限切れを見張るためタイマーを動かす
            row.onRevealToggled = { [weak self] _ in self?.startRefreshTimerIfNeeded() }
            rowStackView.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: rowStackView.widthAnchor).isActive = true
        }

        refreshTOTPRows()
        startRefreshTimerIfNeeded()
    }

    /// 表示中の平文をすべて伏せ字へ戻す
    func hideAllRevealedValues() {
        fieldRows.forEach { $0.hideRevealedValue() }
    }

    /// 指定フィールドの行へフォーカスを移す。
    /// 並べ替えのたびに行ビューを作り直すため、これを呼ばないとフォーカスが失われ、
    /// 続けて Ctrl+j を押したときに一覧のアイテム側が動いてしまう
    func focusRow(fieldID: String) {
        guard let row = fieldRows.first(where: { $0.field.fieldID == fieldID }) else { return }
        view.window?.makeFirstResponder(row.labelField)
    }

    /// タイトル欄へフォーカスを移す（新規作成直後にすぐ名前を付けられるようにする）
    func focusTitleField() {
        guard !titleField.isHidden else { return }
        view.window?.makeFirstResponder(titleField)
    }

    // MARK: - Row focus

    /// いま編集中（フォーカスがある）フィールド行。並べ替えの対象を決めるのに使う。
    ///
    /// テキストフィールドを編集中は first responder がフィールドエディタ（NSTextView）へ
    /// 移り、ビュー階層の親も行ビューとは限らない。`currentEditor()` による判定を
    /// 併用しないと、編集中に Ctrl+j を押したとき対象を取り違える
    var focusedRow: SecureFieldRowView? {
        guard let responder = view.window?.firstResponder else { return nil }
        if let editing = fieldRows.first(where: { row in
            row.labelField.currentEditor() != nil || row.valueField.currentEditor() != nil
        }) {
            return editing
        }
        guard let responderView = responder as? NSView else { return nil }
        return fieldRows.first { row in
            var candidate: NSView? = responderView
            while let current = candidate {
                if current === row { return true }
                candidate = current.superview
            }
            return false
        }
    }
}

// MARK: - NSTextFieldDelegate (タイトル)

extension CPYSecureInfoDetailViewController: NSTextFieldDelegate {

    func controlTextDidChange(_ notification: Notification) {
        guard (notification.object as? NSTextField) === titleField else { return }
        onTitleEdited?(titleField.stringValue)
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard (notification.object as? NSTextField) === titleField else { return }
        onEditingEnded?()
    }
}
