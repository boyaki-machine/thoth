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

    /// レイアウト定数（組み立ては +Layout.swift）
    enum Layout {
        static let labelWidth: CGFloat    = 110
        static let spacing: CGFloat       = 8
        static let buttonSize: CGFloat    = 22
        static let singleLineHeight: CGFloat = 24
        static let noteHeight: CGFloat    = 84
        /// コピー ⧉ と削除 🗑 のあいだに空ける幅。
        /// 他のボタンと同じ 2pt 間隔で並べると、コピーのつもりで削除を押してしまう
        static let deleteGap: CGFloat = 10
        /// 並べ替えの掴み手 ≡ の幅
        static let handleWidth: CGFloat = 16
        /// 掴み手とラベルの間隔
        static let handleGap: CGFloat = 4
        /// ドラッグとみなす移動量。これ未満はクリックとして扱う
        static let dragThreshold: CGFloat = 3
        /// ドラッグ中に出す絵の余白
        static let dragImagePadding: CGFloat = 6
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
    /// 行を上下に動かす要求（右クリックメニュー。引数は移動量）
    var onMove: ((SecureFieldRowView, Int) -> Void)?

    /// マウスがこの行に乗っているか（削除ボタンの表示条件）
    private(set) var isHovered = false
    /// この行のラベルまたは値を編集中か（削除ボタンの表示条件）。
    /// マウスを使わない操作でも削除ボタンへ到達できるようにするために見る
    private(set) var hasEditingFocus = false
    private var hoverTrackingArea: NSTrackingArea?

    // 表示内容をユニットテストから検証できるよう internal にしている
    /// 並べ替えの掴み手 ≡。**ここからしかドラッグを始めない**。
    /// 行全体を掴めるようにすると、値欄のテキスト選択ドラッグと衝突する
    let dragHandle = NSImageView()
    let labelField = NSTextField(labelWithString: "")
    let valueField = NSTextField(labelWithString: "")
    let noteTextView = NSTextView()
    let maskButton   = NSButton()
    let revealButton = NSButton()
    let openButton   = NSButton()
    let copyButton   = NSButton()
    let deleteButton = NSButton()

    /// メモ用のスクロールビュー（組み立ては +Layout.swift）
    let noteScrollView = NSScrollView()

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

    // MARK: - Dragging

    /// 掴み手を押した位置。ドラッグ開始の判定に使う
    private var dragOrigin: NSPoint?

    /// 掴み手の上にあるクリックは自分で受け取る。
    /// `NSImageView` は `NSControl` の一員なので、素のままだと mouseDown を
    /// 自分で握ってしまい、ドラッグが始まらない
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isReadOnly, dragHandle.superview != nil else { return super.hitTest(point) }
        let local = convert(point, from: superview)
        return dragHandle.frame.contains(local) ? self : super.hitTest(point)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        // 掴み手以外から始まったクリックには関与しない（テキスト選択などを邪魔しない）
        guard !isReadOnly, dragHandle.superview != nil, dragHandle.frame.contains(point) else {
            super.mouseDown(with: event)
            return
        }
        dragOrigin = point
    }

    override func mouseDragged(with event: NSEvent) {
        guard let origin = dragOrigin else {
            super.mouseDragged(with: event)
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        // わずかな手ぶれで並べ替えが始まらないよう、少し動かしてから開始する
        guard hypot(point.x - origin.x, point.y - origin.y) >= Layout.dragThreshold else { return }
        dragOrigin = nil
        beginFieldDrag(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        dragOrigin = nil
        super.mouseUp(with: event)
    }

    private func beginFieldDrag(with event: NSEvent) {
        beginDraggingSession(with: [makeDraggingItem()], event: event, source: self)
    }

    /// ドラッグ 1 件分を組み立てる。**外へ出す情報はここだけで決まる**ので、
    /// 中身をユニットテストから確認できるよう internal にしている。
    ///
    /// - ペイストボードに載せるのは **fieldID だけ**。値を載せると、
    ///   ドラッグ中のペイストボードを読める他のアプリへ機微情報が漏れる
    /// - 絵は行の写しではなく**ラベルだけ**（理由は `dragImage(label:)` を参照）
    func makeDraggingItem() -> NSDraggingItem {
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(field.fieldID, forType: .thothSecureFieldRow)
        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
        let image = Self.dragImage(label: field.label)
        draggingItem.setDraggingFrame(NSRect(origin: .zero, size: image.size), contents: image)
        return draggingItem
    }

    /// ドラッグ中に出す絵。**行そのものの写しは使わない。**
    ///
    /// ドラッグの絵は行を離れてシステム側のウィンドウに描かれるため、
    /// このウィンドウに掛けた `NSWindow.sharingType = .none`（画面共有・収録からの除外）が
    /// 効かない。行を丸ごと写すと、👁 で表示中のパスワードやメモの本文が
    /// 画面収録に入りうる。**ラベルだけ**なら検索対象にも選択パネルにも出ている情報で、
    /// どのフィールドを掴んでいるかも分かる
    static func dragImage(label: String) -> NSImage {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
            .foregroundColor: NSColor.labelColor
        ]
        let text = label.isEmpty ? L10n.secureInfoMoveField : label
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributed.size()
        let size = NSSize(width: max(textSize.width, 1) + Layout.dragImagePadding * 2,
                          height: max(textSize.height, 1) + Layout.dragImagePadding)
        let image = NSImage(size: size)
        image.lockFocus()
        attributed.draw(at: NSPoint(x: Layout.dragImagePadding, y: Layout.dragImagePadding / 2))
        image.unlockFocus()
        return image
    }

    // MARK: - Delete button

    /// 削除ボタンを見せるか（純粋関数のためユニットテスト可能）。
    ///
    /// 既定では隠しておき、**マウスが行に乗っているとき**か
    /// **その行を編集中のとき**だけ出す。コピー ⧉ の隣に常時置くと、
    /// 狙いを外して不可逆な削除を押してしまう。
    /// 編集中にも出すのは、マウスを使わない操作でも到達できるようにするため
    /// （右クリックメニューからも削除できる）
    static func showsDeleteButton(isReadOnly: Bool, isHovered: Bool, hasFocus: Bool) -> Bool {
        guard !isReadOnly else { return false }
        return isHovered || hasFocus
    }

    func updateDeleteButtonVisibility() {
        deleteButton.isHidden = !Self.showsDeleteButton(isReadOnly: isReadOnly,
                                                        isHovered: isHovered,
                                                        hasFocus: hasEditingFocus)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea = hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
        guard !isReadOnly else { return }
        // .inVisibleRect にしておくと、スクロールや行の作り直しで矩形がずれない
        let area = NSTrackingArea(rect: .zero,
                                  options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateDeleteButtonVisibility()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateDeleteButtonVisibility()
    }

    /// テストから hover 状態を再現するための入口（実イベントを合成せずに済ませる）
    func setHovered(_ hovered: Bool) {
        isHovered = hovered
        updateDeleteButtonVisibility()
    }

    // MARK: - Context menu

    /// 右クリックメニュー。ホバーでしか出ない削除の導線を補い、
    /// 並べ替え（Ctrl+j / Ctrl+k）にもマウスから届くようにする
    override func menu(for event: NSEvent) -> NSMenu? {
        guard !isReadOnly else { return nil }
        let menu = NSMenu()

        let moveUp = NSMenuItem(title: L10n.secureInfoMoveUp, action: #selector(moveUpSelected), keyEquivalent: "")
        moveUp.target = self
        menu.addItem(moveUp)

        let moveDown = NSMenuItem(title: L10n.secureInfoMoveDown, action: #selector(moveDownSelected), keyEquivalent: "")
        moveDown.target = self
        menu.addItem(moveDown)

        menu.addItem(NSMenuItem.separator())

        let delete = NSMenuItem(title: L10n.secureInfoRemoveField, action: #selector(deleteTapped), keyEquivalent: "")
        delete.target = self
        menu.addItem(delete)
        return menu
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

    @objc func moveUpSelected() {
        onMove?(self, -1)
    }

    @objc func moveDownSelected() {
        onMove?(self, 1)
    }
}

// MARK: - NSDraggingSource

extension SecureFieldRowView: NSDraggingSource {

    /// **アプリ内の並べ替えだけを許す。** 行を他のアプリへ引き出せると、
    /// ペイストボード経由で機微情報が渡る余地を作ってしまう
    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        return context == .withinApplication ? .move : []
    }
}

// MARK: - NSTextFieldDelegate / NSTextViewDelegate

extension SecureFieldRowView: NSTextFieldDelegate, NSTextViewDelegate {

    // 編集の開始・終了で削除ボタンの表示を切り替える。
    // 行の中に first responder があるかを外から見張るより、
    // フィールドエディタの出入りを直接受け取るほうが取りこぼしが無い
    func controlTextDidBeginEditing(_ notification: Notification) {
        hasEditingFocus = true
        updateDeleteButtonVisibility()
    }

    func textDidBeginEditing(_ notification: Notification) {
        guard (notification.object as? NSTextView) === noteTextView else { return }
        hasEditingFocus = true
        updateDeleteButtonVisibility()
    }

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
        hasEditingFocus = false
        updateDeleteButtonVisibility()
        onEditingEnded?(self)
    }

    func textDidChange(_ notification: Notification) {
        guard (notification.object as? NSTextView) === noteTextView else { return }
        onValueEdited?(self, noteTextView.string)
    }

    func textDidEndEditing(_ notification: Notification) {
        guard (notification.object as? NSTextView) === noteTextView else { return }
        hasEditingFocus = false
        updateDeleteButtonVisibility()
        onEditingEnded?(self)
    }
}
