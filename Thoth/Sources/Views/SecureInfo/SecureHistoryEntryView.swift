//
//  SecureHistoryEntryView.swift
//
//  Thoth
//  GitHub: https://github.com/boyaki-machine/Thoth
//

import Cocoa

/// 変更履歴 1 件分のビュー。行の下に展開される履歴パネルに並ぶ。
///
/// ```
/// [2026/07/20 14:30]  [••••••••]              [👁][⧉]
/// ```
///
/// **メニューではなくウィンドウの中に描く。** 過去のパスワードは平文で画面に出る情報なので、
/// ウィンドウに掛けた `NSWindow.sharingType = .none`（画面共有・収録からの除外）が
/// 効く場所に置く必要がある。NSMenu や NSPopover は別ウィンドウに描かれるため守られない。
///
/// 平文の扱いは行（`SecureFieldRowView`）とまったく同じ規律にする:
/// 既定はマスク / 👁 で平文 / `revealTimeout` 秒で自動的に伏せ字へ戻る /
/// ウィンドウ非アクティブ化で即座に伏せ字へ戻る。
final class SecureHistoryEntryView: NSView {

    private enum Layout {
        static let timestampWidth: CGFloat = 116
        static let spacing: CGFloat        = 8
        static let buttonSize: CGFloat     = 20
        static let height: CGFloat         = 22
    }

    let entry: SecureMenuItem.FieldHistoryEntry
    /// 元のフィールドがマスク指定か。履歴の見せ方は現在値の見せ方に合わせる
    let isPassword: Bool

    /// 過去の値を一時的に平文表示しているか
    private(set) var isRevealed = false
    /// 平文表示を始めた時刻（自動解除の判定に使う）
    private(set) var revealedAt: Date?

    /// この履歴の値のコピー要求
    var onCopy: ((SecureHistoryEntryView) -> Void)?
    /// 平文表示が切り替えられた（自動解除タイマーの起動に使う）
    var onRevealToggled: ((SecureHistoryEntryView) -> Void)?

    // 表示内容をユニットテストから検証できるよう internal にしている
    let timestampField = NSTextField(labelWithString: "")
    let valueField = NSTextField(labelWithString: "")
    let revealButton = NSButton()
    let copyButton = NSButton()

    // MARK: - Init

    init(entry: SecureMenuItem.FieldHistoryEntry, isPassword: Bool) {
        self.entry = entry
        self.isPassword = isPassword
        super.init(frame: .zero)
        setupUI()
        updateValueDisplay()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Display

    /// 値エリアに出す文字列を決める（純粋関数のためユニットテスト可能）。
    /// マスク指定のフィールドの履歴は、表示切替が ON のときだけ平文にする
    static func displayedValue(for entry: SecureMenuItem.FieldHistoryEntry,
                               isPassword: Bool, isRevealed: Bool) -> String {
        guard isPassword, !isRevealed else { return entry.value }
        return SecureFieldRowView.maskedPlaceholder
    }

    /// 置き換えられた日時の表示（純粋関数）。編集シートの履歴ポップアップと同じ書式にそろえる
    static func timestampText(for date: Date) -> String {
        return timestampFormatter.string(from: date)
    }

    /// 生成のたびに DateFormatter を作らない（履歴は最大 10 件 × 行数ぶん作られる）
    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd HH:mm"
        return formatter
    }()

    /// 表示切替を反転する。マスク指定でない履歴は元から平文なので何もしない。
    /// - Parameter date: 平文表示を始めた時刻（自動解除の判定用。テストから注入する）
    func toggleReveal(at date: Date = Date()) {
        guard isPassword else { return }
        isRevealed.toggle()
        revealedAt = isRevealed ? date : nil
        updateValueDisplay()
        onRevealToggled?(self)
    }

    /// 平文表示を解除する（ウィンドウ非アクティブ化・履歴を畳むときなどに呼ぶ）
    func hideRevealedValue() {
        guard isRevealed else { return }
        isRevealed = false
        revealedAt = nil
        updateValueDisplay()
    }

    /// 平文表示の期限が切れていれば伏せ字へ戻す。
    /// 失効時間は行と共有する（画面に残り続ける時間の上限を 1 箇所で決める）
    /// - Returns: 実際に伏せ字へ戻した場合 true
    @discardableResult
    func hideRevealedValueIfExpired(now: Date = Date()) -> Bool {
        guard isRevealed, let revealedAt = revealedAt,
              now.timeIntervalSince(revealedAt) >= SecureFieldRowView.revealTimeout else { return false }
        hideRevealedValue()
        return true
    }

    private func updateValueDisplay() {
        valueField.stringValue = Self.displayedValue(for: entry, isPassword: isPassword,
                                                     isRevealed: isRevealed)
        revealButton.image = NSImage(systemSymbolName: isRevealed ? "eye.slash" : "eye",
                                     accessibilityDescription: nil)
    }

    // MARK: - UI

    private func setupUI() {
        translatesAutoresizingMaskIntoConstraints = false

        timestampField.stringValue = Self.timestampText(for: entry.replacedAt)
        timestampField.textColor = .secondaryLabelColor
        timestampField.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        timestampField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(timestampField)

        // 履歴は読み取り専用。選択とコピーはできるが編集はさせない
        valueField.isSelectable = true
        valueField.isEditable = false
        valueField.lineBreakMode = .byTruncatingTail
        valueField.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        valueField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(valueField)

        let buttonStack = makeButtonStack()

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Layout.height),

            timestampField.leadingAnchor.constraint(equalTo: leadingAnchor),
            timestampField.centerYAnchor.constraint(equalTo: centerYAnchor),
            timestampField.widthAnchor.constraint(equalToConstant: Layout.timestampWidth),

            valueField.leadingAnchor.constraint(equalTo: timestampField.trailingAnchor,
                                                constant: Layout.spacing),
            valueField.centerYAnchor.constraint(equalTo: centerYAnchor),
            valueField.trailingAnchor.constraint(equalTo: buttonStack.leadingAnchor,
                                                 constant: -Layout.spacing),

            buttonStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            buttonStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            buttonStack.heightAnchor.constraint(equalToConstant: Layout.buttonSize)
        ])
    }

    private func makeButtonStack() -> NSStackView {
        for button in [revealButton, copyButton] {
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

        copyButton.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
        copyButton.toolTip = L10n.secureInfoCopyValue
        copyButton.target = self
        copyButton.action = #selector(copyTapped)

        // マスク指定でない履歴（ID や URL の旧値）は元から平文なので表示切替を出さない
        let buttons: [NSView] = isPassword ? [revealButton, copyButton] : [copyButton]
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

    @objc private func copyTapped() {
        onCopy?(self)
    }
}
