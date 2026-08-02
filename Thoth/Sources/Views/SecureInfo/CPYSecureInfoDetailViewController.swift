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

    private enum Layout {
        static let padding: CGFloat    = 20
        static let rowSpacing: CGFloat = 10
    }

    /// TOTP 行の表示更新間隔（秒）
    private static let totpRefreshInterval: TimeInterval = 1.0

    // 表示内容をユニットテストから検証できるよう internal にしている
    let titleLabel = NSTextField(labelWithString: "")
    let placeholderLabel = NSTextField(labelWithString: "")
    let rowStackView = NSStackView()

    private let scrollView = NSScrollView()
    private let totpService = TOTPService()
    private var totpTimer: Timer?

    private(set) var displayedItem: SecureMenuItem?

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
        startTOTPTimerIfNeeded()
    }

    private func setupUI() {
        titleLabel.font = .systemFont(ofSize: NSFont.systemFontSize + 4, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        rowStackView.orientation = .vertical
        rowStackView.alignment = .leading
        rowStackView.spacing = Layout.rowSpacing
        rowStackView.translatesAutoresizingMaskIntoConstraints = false

        let documentView = NSView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(rowStackView)

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

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: Layout.padding),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Layout.padding),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Layout.padding),

            scrollView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: Layout.padding),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Layout.padding),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Layout.padding),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -Layout.padding),

            // 横方向はスクロールさせず、内容の幅を可視領域に合わせる。
            // scrollView 自体の幅に合わせると、縦スクローラーが出たときに
            // その分だけ内容がはみ出して横スクロールが発生する
            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            rowStackView.topAnchor.constraint(equalTo: documentView.topAnchor),
            rowStackView.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            rowStackView.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            rowStackView.bottomAnchor.constraint(equalTo: documentView.bottomAnchor),

            placeholderLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            placeholderLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    // MARK: - Content

    /// 表示するアイテムを差し替える。nil で「選択なし」表示にする
    func show(item: SecureMenuItem?) {
        displayedItem = item
        rebuildRows(for: item)

        guard let item = item else {
            titleLabel.stringValue = ""
            titleLabel.isHidden = true
            scrollView.isHidden = true
            placeholderLabel.stringValue = L10n.secureInfoNoSelection
            placeholderLabel.isHidden = false
            return
        }
        titleLabel.stringValue = item.title
        titleLabel.isHidden = false
        scrollView.isHidden = false
        placeholderLabel.isHidden = true
    }

    private func rebuildRows(for item: SecureMenuItem?) {
        stopTOTPTimer()
        // 行ビューは使い捨て。前のアイテムの表示状態を持ち越さないよう毎回作り直す
        rowStackView.arrangedSubviews.forEach {
            rowStackView.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        for field in item?.fields ?? [] {
            let row = SecureFieldRowView(field: field)
            row.onCopy = { [weak self] row in self?.copyValue(of: row.field) }
            row.onOpenURL = { [weak self] row in self?.openURL(of: row.field) }
            rowStackView.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: rowStackView.widthAnchor).isActive = true
        }

        refreshTOTPRows()
        startTOTPTimerIfNeeded()
    }

    /// 表示中の平文をすべて伏せ字へ戻す
    func hideAllRevealedValues() {
        fieldRows.forEach { $0.hideRevealedValue() }
    }

    // MARK: - TOTP live update

    private func startTOTPTimerIfNeeded() {
        stopTOTPTimer()
        guard fieldRows.contains(where: { $0.field.isTOTP }) else { return }
        // NSWindow は通常の RunLoop で動くため .common モードに追加すれば安定して発火する
        let timer = Timer(timeInterval: Self.totpRefreshInterval, repeats: true) { [weak self] _ in
            self?.refreshTOTPRows()
        }
        RunLoop.main.add(timer, forMode: .common)
        totpTimer = timer
    }

    private func stopTOTPTimer() {
        totpTimer?.invalidate()
        totpTimer = nil
    }

    /// TOTP 行のコードと残り秒数を現在時刻で描き直す
    func refreshTOTPRows() {
        for row in fieldRows where row.field.isTOTP {
            guard let params = TOTPService.parse(row.field.value) else {
                row.updateTOTPDisplay(code: nil, remainingSeconds: 0)
                continue
            }
            row.updateTOTPDisplay(code: totpService.code(for: params),
                                  remainingSeconds: totpService.remainingSeconds(for: params))
        }
    }

    // MARK: - Actions

    /// 値をコピーする。履歴に残さないよう必ず秘匿マーカー付きで書き込み、
    /// 一定時間後（その間に別のコピーが無ければ）自動でクリアする
    private func copyValue(of field: SecureMenuItem.Field) {
        guard let value = copyableValue(of: field) else {
            NSSound.beep()
            return
        }
        AppEnvironment.current.pasteService.copyConcealedToPasteboard(with: value)
        AppEnvironment.current.pasteService.scheduleConcealedClear()
    }

    /// コピー対象の文字列。TOTP は secret ではなくその時点のコードを返す
    func copyableValue(of field: SecureMenuItem.Field) -> String? {
        guard field.isTOTP else { return field.value }
        guard let params = TOTPService.parse(field.value) else { return nil }
        return totpService.code(for: params)
    }

    private func openURL(of field: SecureMenuItem.Field) {
        guard let url = Self.openableURL(from: field.value) else {
            NSSound.beep()
            return
        }
        NSWorkspace.shared.open(url)
    }

    /// ブラウザで開いてよい URL かを判定する（純粋関数のためユニットテスト可能）。
    ///
    /// **http / https だけを許可する。** インポートしたデータや打ち間違いに
    /// `file://` や独自スキームが入っていると、ボタン 1 つで意図しないファイルや
    /// アプリを開いてしまうため。ホスト名の無い URL も弾く
    static func openableURL(from value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty else { return nil }
        return url
    }
}
