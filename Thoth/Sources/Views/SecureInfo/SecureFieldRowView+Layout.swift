//
//  SecureFieldRowView+Layout.swift
//
//  Thoth
//  GitHub: https://github.com/boyaki-machine/Thoth
//

import Cocoa

// MARK: - Layout
//
// 行ビューの組み立て。左から
// `[≡] [ラベル] [値 ...] [🔒][👁][↗][⧉]  [🗑]` の順に並ぶ。
//
// 掴み手 ≡ と削除 🗑 は行の両端に置き、中央のボタン列とは別に配置している
// （それぞれの理由は本体側のコメントを参照）。
extension SecureFieldRowView {

    // MARK: - UI

    func setupUI() {
        translatesAutoresizingMaskIntoConstraints = false

        labelField.stringValue = field.label
        labelField.textColor = .secondaryLabelColor
        labelField.alignment = .right
        labelField.lineBreakMode = .byTruncatingTail
        labelField.isEditable = Self.isLabelEditable(isReadOnly: isReadOnly)
        labelField.isBordered = false
        labelField.drawsBackground = false
        labelField.delegate = self
        labelField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(labelField)

        let valueContainer = makeValueContainer()
        let buttonStack = makeButtonStack()
        let labelLeading = setupDragHandle()
        // 掴み手を置いたときだけ、ラベルとの間に隙間を空ける
        let labelLeadingGap = isReadOnly ? 0 : Layout.handleGap

        // 削除ボタンはスタックの外に置き、位置を固定する。
        // スタックの一員のまま isHidden にすると幅が畳まれ、マウスを乗せるたびに
        // 他のボタンが横へ動いてしまう（狙って押せなくなる）
        let buttonStackTrailing = isReadOnly
            ? buttonStack.trailingAnchor.constraint(equalTo: trailingAnchor)
            : buttonStack.trailingAnchor.constraint(equalTo: deleteButton.leadingAnchor,
                                                    constant: -Layout.deleteGap)

        // 履歴パネルは値エリアの真下へ差し込むので、基準として控えておく
        valueContainerForHistory = valueContainer
        // 行の高さの基準。折りたたみ時は値エリアの下端が行の下端になる。
        // 展開すると無効化され、履歴パネルの下端が基準に変わる（+History.swift）
        collapsedBottomConstraint = valueContainer.bottomAnchor.constraint(equalTo: bottomAnchor)

        NSLayoutConstraint.activate([
            labelField.leadingAnchor.constraint(equalTo: labelLeading, constant: labelLeadingGap),
            labelField.topAnchor.constraint(equalTo: topAnchor),
            labelField.widthAnchor.constraint(equalToConstant: Layout.labelWidth),

            valueContainer.leadingAnchor.constraint(equalTo: labelField.trailingAnchor, constant: Layout.spacing),
            valueContainer.topAnchor.constraint(equalTo: topAnchor),
            collapsedBottomConstraint!,
            valueContainer.trailingAnchor.constraint(equalTo: buttonStack.leadingAnchor, constant: -Layout.spacing),

            buttonStackTrailing,
            buttonStack.topAnchor.constraint(equalTo: topAnchor),
            buttonStack.heightAnchor.constraint(equalToConstant: Layout.buttonSize)
        ])

        updateHistoryButtonVisibility()

        guard !isReadOnly else { return }
        NSLayoutConstraint.activate([
            deleteButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            deleteButton.topAnchor.constraint(equalTo: topAnchor)
        ])
        updateDeleteButtonVisibility()
    }

    // MARK: - Drag handle

    /// 掴み手を組み立て、ラベルを合わせるべき左端アンカーを返す。
    /// 読み取り専用では並べ替えられないので掴み手も置かない
    private func setupDragHandle() -> NSLayoutXAxisAnchor {
        guard !isReadOnly else { return leadingAnchor }
        dragHandle.image = NSImage(systemSymbolName: "line.3.horizontal", accessibilityDescription: nil)
        dragHandle.contentTintColor = .tertiaryLabelColor
        dragHandle.toolTip = L10n.secureInfoMoveField
        dragHandle.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dragHandle)
        NSLayoutConstraint.activate([
            dragHandle.leadingAnchor.constraint(equalTo: leadingAnchor),
            dragHandle.topAnchor.constraint(equalTo: topAnchor),
            dragHandle.widthAnchor.constraint(equalToConstant: Layout.handleWidth),
            dragHandle.heightAnchor.constraint(equalToConstant: Layout.buttonSize)
        ])
        return dragHandle.trailingAnchor
    }

    /// 値エリアを組み立てる。複数行の種別だけスクロール付きの NSTextView にする
    private func makeValueContainer() -> NSView {
        guard field.kind.isMultiline else {
            // 編集できない状態でも選択・コピーはできるようにする
            valueField.isSelectable = true
            valueField.lineBreakMode = .byTruncatingTail
            valueField.delegate = self
            valueField.translatesAutoresizingMaskIntoConstraints = false
            addSubview(valueField)
            valueField.heightAnchor.constraint(equalToConstant: Layout.singleLineHeight).isActive = true
            return valueField
        }

        noteTextView.isSelectable = true
        noteTextView.isRichText = false
        // 打鍵単位の取り消しは AppKit に任せる（既定は false で ⌘Z が効かない）。
        // 単一行のフィールドはウィンドウ共有のフィールドエディタが同じ役目を持つ。
        // 行ビューは使い捨てなので、行を作り直せば打鍵の履歴も一緒に消える
        noteTextView.allowsUndo = true
        noteTextView.delegate = self
        // メモは URL 等を自動リンク化せずそのまま見せる（誤操作で外部アプリが開くのを避ける）
        noteTextView.isAutomaticLinkDetectionEnabled = false
        noteTextView.enabledTextCheckingTypes = 0
        noteTextView.drawsBackground = false
        noteTextView.textColor = .labelColor

        // コードから生成した NSTextView は、Interface Builder の「Text View」と違い
        // スクロールビューへの載せ方が自動設定されない。この 5 行が無いと
        // 本文が折り返されず、行数に応じたスクロールもできない
        noteTextView.minSize = NSSize(width: 0, height: 0)
        noteTextView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                      height: CGFloat.greatestFiniteMagnitude)
        noteTextView.isVerticallyResizable = true
        noteTextView.isHorizontallyResizable = false
        noteTextView.autoresizingMask = .width
        noteTextView.textContainer?.widthTracksTextView = true
        noteTextView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)

        noteScrollView.documentView = noteTextView
        noteScrollView.hasVerticalScroller = true
        noteScrollView.borderType = .bezelBorder
        noteScrollView.drawsBackground = false
        noteScrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(noteScrollView)
        noteScrollView.heightAnchor.constraint(equalToConstant: Layout.noteHeight).isActive = true
        return noteScrollView
    }

    /// 種別に応じたボタン列を組み立てる
    private func makeButtonStack() -> NSStackView {
        for button in [maskButton, revealButton, openButton, copyButton, deleteButton] {
            button.bezelStyle = .smallSquare
            button.isBordered = false
            button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(equalToConstant: Layout.buttonSize).isActive = true
            button.heightAnchor.constraint(equalToConstant: Layout.buttonSize).isActive = true
        }

        maskButton.image = NSImage(systemSymbolName: field.isPassword ? "lock.fill" : "lock.open",
                                   accessibilityDescription: nil)
        maskButton.toolTip = L10n.secureInfoToggleMask
        maskButton.target = self
        maskButton.action = #selector(maskTapped)

        deleteButton.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
        deleteButton.toolTip = L10n.secureInfoRemoveField
        deleteButton.target = self
        deleteButton.action = #selector(deleteTapped)

        revealButton.image = NSImage(systemSymbolName: "eye", accessibilityDescription: nil)
        revealButton.toolTip = L10n.secureInfoRevealValue
        revealButton.target = self
        revealButton.action = #selector(revealTapped)

        openButton.image = NSImage(systemSymbolName: "arrow.up.right.square", accessibilityDescription: nil)
        openButton.toolTip = L10n.secureInfoOpenURL
        openButton.target = self
        openButton.action = #selector(openTapped)

        copyButton.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
        copyButton.toolTip = L10n.secureInfoCopyValue
        copyButton.target = self
        copyButton.action = #selector(copyTapped)

        historyButton.image = NSImage(systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: nil)
        historyButton.toolTip = L10n.valueHistory
        historyButton.target = self
        historyButton.action = #selector(historyTapped)
        historyButton.widthAnchor.constraint(equalToConstant: Layout.buttonSize).isActive = true
        historyButton.heightAnchor.constraint(equalToConstant: Layout.buttonSize).isActive = true
        historyButton.bezelStyle = .smallSquare
        historyButton.isBordered = false
        historyButton.translatesAutoresizingMaskIntoConstraints = false

        // 種別ごとに使えないボタンは並べない（押せないボタンを見せない）。
        // 削除ボタンだけはスタックに入れず、setupUI が余白を空けて別に配置する
        var buttons: [NSView] = []
        if field.kind.allowsPasswordToggle && !isReadOnly { buttons.append(maskButton) }
        if field.isPassword && field.kind.allowsPasswordToggle { buttons.append(revealButton) }
        if field.kind == .url { buttons.append(openButton) }
        // 🕘 は履歴のある行にだけ並べる。削除ボタンと違いスタックの中ほどに入るため、
        // ホバーでの出し入れは isHidden ではなく alphaValue で行う（幅を確保したままにして、
        // 現れた瞬間にコピー ⧉ が横へ動かないようにする）
        if hasValueHistory { buttons.append(historyButton) }
        buttons.append(copyButton)
        if !isReadOnly { addSubview(deleteButton) }

        let stack = NSStackView(views: buttons)
        stack.orientation = .horizontal
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        return stack
    }

    // MARK: - Actions

    @objc func revealTapped() {
        toggleReveal()
    }

    @objc func openTapped() {
        onOpenURL?(self)
    }

    @objc func copyTapped() {
        onCopy?(self)
    }

    @objc func maskTapped() {
        onMaskToggled?(self, !field.isPassword)
    }

    @objc func deleteTapped() {
        onDelete?(self)
    }

    @objc func historyTapped() {
        toggleHistory()
    }

    @objc func moveUpSelected() {
        onMove?(self, -1)
    }

    @objc func moveDownSelected() {
        onMove?(self, 1)
    }
}
