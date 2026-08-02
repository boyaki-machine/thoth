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

    let field: SecureMenuItem.Field
    /// パスワード等を一時的に平文表示しているか
    private(set) var isRevealed = false

    /// コピー要求（TOTP はその時点のコードをコピーする）
    var onCopy: ((SecureFieldRowView) -> Void)?
    /// URL を開く要求
    var onOpenURL: ((SecureFieldRowView) -> Void)?

    // 表示内容をユニットテストから検証できるよう internal にしている
    let labelField = NSTextField(labelWithString: "")
    let valueField = NSTextField(labelWithString: "")
    let noteTextView = NSTextView()
    let revealButton = NSButton()
    let openButton   = NSButton()
    let copyButton   = NSButton()

    private let noteScrollView = NSScrollView()

    // MARK: - Init

    init(field: SecureMenuItem.Field) {
        self.field = field
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
        if field.isPassword && !isRevealed { return maskedPlaceholder }
        return field.value
    }

    /// 表示切替を反転する。マスクを持たない種別では何もしない
    func toggleReveal() {
        guard field.isPassword, field.kind.allowsPasswordToggle else { return }
        isRevealed.toggle()
        updateValueDisplay()
    }

    /// 平文表示を解除する（アイテムの切り替え・ウィンドウ非アクティブ化などで呼ぶ）
    func hideRevealedValue() {
        guard isRevealed else { return }
        isRevealed = false
        updateValueDisplay()
    }

    private func updateValueDisplay() {
        let displayed = Self.displayedValue(for: field, isRevealed: isRevealed)
        if field.kind.isMultiline {
            noteTextView.string = displayed
        } else {
            valueField.stringValue = displayed
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
            // 読み取り専用だが選択・コピーはできるようにする
            valueField.isSelectable = true
            valueField.lineBreakMode = .byTruncatingTail
            valueField.translatesAutoresizingMaskIntoConstraints = false
            addSubview(valueField)
            valueField.heightAnchor.constraint(equalToConstant: Layout.singleLineHeight).isActive = true
            return valueField
        }

        noteTextView.isEditable = false
        noteTextView.isSelectable = true
        noteTextView.isRichText = false
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
        for button in [revealButton, openButton, copyButton] {
            button.bezelStyle = .smallSquare
            button.isBordered = false
            button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(equalToConstant: Layout.buttonSize).isActive = true
            button.heightAnchor.constraint(equalToConstant: Layout.buttonSize).isActive = true
        }

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
        if field.isPassword && field.kind.allowsPasswordToggle { buttons.append(revealButton) }
        if field.kind == .url { buttons.append(openButton) }
        buttons.append(copyButton)

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
}
