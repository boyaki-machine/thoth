//
//  SecureFieldRowView.swift
//
//  Thoth
//  GitHub: https://github.com/boyaki-machine/Thoth
//

import Cocoa

/// セキュア情報確認ウィンドウの右ペインに並ぶ、フィールド 1 件分の行ビュー。
///
/// ```
/// [ ラベル ] [ 値 ..................... ] [👁] [↗] [⧉]
/// ```
///
/// 種別ごとに値エリアとボタンの構成が変わる:
///
/// | 種別 | 値エリア | ボタン |
/// |---|---|---|
/// | plain | 単一行 | コピー |
/// | plain + マスク | 単一行（•••） | 表示切替 / コピー |
/// | totp | 単一行（毎秒更新） | コピー（コードのみ） |
/// | url | 単一行 | 開く / コピー |
/// | note | 複数行 | コピー |
///
/// **行ビューは使い捨て**にしている（NSTableView のようなセル再利用をしない）。
/// 再利用すると「表示中（👁 ON）の状態が別のフィールドの行に残る」事故が起きうるため。
final class SecureFieldRowView: NSView {

    private enum Layout {
        static let labelWidth: CGFloat    = 110
        static let spacing: CGFloat       = 8
        static let buttonSize: CGFloat    = 22
        static let singleLineHeight: CGFloat = 24
        static let noteHeight: CGFloat    = 84
    }

    /// マスク表示に使う伏せ字
    static let maskedPlaceholder = "••••••••"

    /// 平文表示を自動で伏せ字へ戻すまでの秒数。
    /// 表示したまま離席すると画面に残り続けるため、時間で必ず閉じる
    static let revealTimeout: TimeInterval = 30

    let field: SecureMenuItem.Field
    /// パスワード等を一時的に平文表示しているか
    private(set) var isRevealed = false
    /// 平文表示を始めた時刻（自動解除の判定に使う）
    private(set) var revealedAt: Date?

    /// 読み取り専用モード（Keychain を読み出せない場合など）
    let isReadOnly: Bool

    /// コピー要求（TOTP はその時点のコードをコピーする）
    var onCopy: ((SecureFieldRowView) -> Void)?
    /// URL を開く要求
    var onOpenURL: ((SecureFieldRowView) -> Void)?
    /// ラベルが変更された（入力のたびに呼ばれる）
    var onLabelEdited: ((SecureFieldRowView, String) -> Void)?
    /// 値が変更された（入力のたびに呼ばれる）
    var onValueEdited: ((SecureFieldRowView, String) -> Void)?
    /// 編集が終わった（フォーカスが外れた）。保存のきっかけに使う
    var onEditingEnded: ((SecureFieldRowView) -> Void)?
    /// マスク指定（🔒）が切り替えられた
    var onMaskToggled: ((SecureFieldRowView, Bool) -> Void)?
    /// このフィールドの削除が要求された
    var onDelete: ((SecureFieldRowView) -> Void)?
    /// 平文表示が切り替えられた（自動解除タイマーの起動に使う）
    var onRevealToggled: ((SecureFieldRowView) -> Void)?

    // 表示内容をユニットテストから検証できるよう internal にしている
    let labelField = NSTextField(labelWithString: "")
    let valueField = NSTextField(labelWithString: "")
    let noteTextView = NSTextView()
    let maskButton   = NSButton()
    let revealButton = NSButton()
    let openButton   = NSButton()
    let copyButton   = NSButton()
    let deleteButton = NSButton()

    private let noteScrollView = NSScrollView()

    // MARK: - Init

    init(field: SecureMenuItem.Field, isReadOnly: Bool = false) {
        self.field = field
        self.isReadOnly = isReadOnly
        super.init(frame: .zero)
        setupUI()
        updateValueDisplay()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Display

    /// 値エリアに出す文字列を決める（純粋関数のためユニットテスト可能）。
    ///
    /// - TOTP は secret を決して画面に出さない。表示はその時点のコードだけなので
    ///   ここでは空を返し、`updateTOTPDisplay(code:remainingSeconds:)` が別に埋める
    /// - マスク指定のフィールドは、表示切替が ON のときだけ平文にする
    static func displayedValue(for field: SecureMenuItem.Field, isRevealed: Bool) -> String {
        guard field.kind.displaysRawValue else { return "" }
        // マスクを持たない種別では isPassword を無視する。旧データでメモに
        // マスク指定が残っていても、解除できない伏せ字にならないようにする
        guard field.kind.allowsPasswordToggle, field.isPassword, !isRevealed else { return field.value }
        return maskedPlaceholder
    }

    /// 表示切替を反転する。マスクを持たない種別では何もしない。
    /// - Parameter date: 平文表示を始めた時刻（自動解除の判定用。テストから注入する）
    func toggleReveal(at date: Date = Date()) {
        guard field.isPassword, field.kind.allowsPasswordToggle else { return }
        isRevealed.toggle()
        revealedAt = isRevealed ? date : nil
        updateValueDisplay()
        onRevealToggled?(self)
    }

    /// 平文表示を解除する（アイテムの切り替え・ウィンドウ非アクティブ化などで呼ぶ）
    func hideRevealedValue() {
        guard isRevealed else { return }
        isRevealed = false
        revealedAt = nil
        updateValueDisplay()
    }

    /// 平文表示の期限が切れていれば伏せ字へ戻す。
    /// 表示したまま離席された場合に、画面に残り続けないようにするための保険
    /// - Returns: 実際に伏せ字へ戻した場合 true
    @discardableResult
    func hideRevealedValueIfExpired(now: Date = Date()) -> Bool {
        guard isRevealed, let revealedAt = revealedAt,
              now.timeIntervalSince(revealedAt) >= Self.revealTimeout else { return false }
        hideRevealedValue()
        return true
    }

    /// 値エリアを編集できるかを判定する（純粋関数のためユニットテスト可能）。
    ///
    /// - 読み取り専用モードでは編集不可
    /// - TOTP は secret を表示しないため編集不可（取り込み直しで置き換える）
    /// - **マスク中は編集不可**。伏せ字を表示したまま編集させると、
    ///   画面に見えている「••••••••」がそのまま値として保存されてしまう。
    ///   編集したい場合は 👁 で平文に切り替えてから行う
    static func isValueEditable(field: SecureMenuItem.Field, isRevealed: Bool, isReadOnly: Bool) -> Bool {
        guard !isReadOnly, field.kind.displaysRawValue else { return false }
        guard field.kind.allowsPasswordToggle, field.isPassword else { return true }
        return isRevealed
    }

    /// ラベルを編集できるか（読み取り専用でなければ種別を問わず編集できる）
    static func isLabelEditable(isReadOnly: Bool) -> Bool {
        return !isReadOnly
    }

    private func updateValueDisplay() {
        let displayed = Self.displayedValue(for: field, isRevealed: isRevealed)
        let editable = Self.isValueEditable(field: field, isRevealed: isRevealed, isReadOnly: isReadOnly)
        if field.kind.isMultiline {
            noteTextView.string = displayed
            noteTextView.isEditable = editable
        } else {
            valueField.stringValue = displayed
            valueField.isEditable = editable
            valueField.isBordered = editable
            valueField.drawsBackground = editable
        }
        revealButton.image = NSImage(systemSymbolName: isRevealed ? "eye.slash" : "eye",
                                     accessibilityDescription: nil)
    }

    /// TOTP 行の表示を更新する（1 秒ごとに呼ばれる）。
    /// コードを生成できない場合は `code` に nil を渡す
    func updateTOTPDisplay(code: String?, remainingSeconds: Int) {
        guard field.isTOTP else { return }
        valueField.stringValue = Self.totpDisplayString(code: code, remainingSeconds: remainingSeconds)
    }

    /// TOTP 行の表示文字列（純粋関数）。`123 456 · 18s`
    static func totpDisplayString(code: String?, remainingSeconds: Int) -> String {
        guard let code = code else { return "------" }
        return "\(TOTPService.groupedCode(code)) · \(remainingSeconds)s"
    }

    // MARK: - UI

    private func setupUI() {
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

        NSLayoutConstraint.activate([
            labelField.leadingAnchor.constraint(equalTo: leadingAnchor),
            labelField.topAnchor.constraint(equalTo: topAnchor),
            labelField.widthAnchor.constraint(equalToConstant: Layout.labelWidth),

            valueContainer.leadingAnchor.constraint(equalTo: labelField.trailingAnchor, constant: Layout.spacing),
            valueContainer.topAnchor.constraint(equalTo: topAnchor),
            valueContainer.bottomAnchor.constraint(equalTo: bottomAnchor),
            valueContainer.trailingAnchor.constraint(equalTo: buttonStack.leadingAnchor, constant: -Layout.spacing),

            buttonStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            buttonStack.topAnchor.constraint(equalTo: topAnchor),
            buttonStack.heightAnchor.constraint(equalToConstant: Layout.buttonSize)
        ])
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

        // 種別ごとに使えないボタンは並べない（押せないボタンを見せない）
        var buttons: [NSView] = []
        if field.kind.allowsPasswordToggle && !isReadOnly { buttons.append(maskButton) }
        if field.isPassword && field.kind.allowsPasswordToggle { buttons.append(revealButton) }
        if field.kind == .url { buttons.append(openButton) }
        buttons.append(copyButton)
        if !isReadOnly { buttons.append(deleteButton) }

        let stack = NSStackView(views: buttons)
        stack.orientation = .horizontal
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        return stack
    }

    // MARK: - Actions

    @objc private func revealTapped() {
        toggleReveal()
    }

    @objc private func openTapped() {
        onOpenURL?(self)
    }

    @objc private func copyTapped() {
        onCopy?(self)
    }

    @objc private func maskTapped() {
        onMaskToggled?(self, !field.isPassword)
    }

    @objc private func deleteTapped() {
        onDelete?(self)
    }
}

// MARK: - NSTextFieldDelegate / NSTextViewDelegate

extension SecureFieldRowView: NSTextFieldDelegate, NSTextViewDelegate {

    func controlTextDidChange(_ notification: Notification) {
        guard let control = notification.object as? NSTextField else { return }
        if control === labelField {
            onLabelEdited?(self, labelField.stringValue)
        } else if control === valueField {
            // マスク中は編集不可なので、ここへ来る値は必ず平文
            onValueEdited?(self, valueField.stringValue)
        }
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        onEditingEnded?(self)
    }

    func textDidChange(_ notification: Notification) {
        guard (notification.object as? NSTextView) === noteTextView else { return }
        onValueEdited?(self, noteTextView.string)
    }

    func textDidEndEditing(_ notification: Notification) {
        guard (notification.object as? NSTextView) === noteTextView else { return }
        onEditingEnded?(self)
    }
}
