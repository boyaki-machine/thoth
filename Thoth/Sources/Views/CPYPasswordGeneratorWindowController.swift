//
//  CPYPasswordGeneratorWindowController.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Copyright © 2015-2018 Clipy Project.
//

import Cocoa

// MARK: - Window Controller

/// パスワード生成ダイアログウィンドウのコントローラ。
/// アプリ起動中に一度だけ生成されるシングルトン。表示のたびに新しいパスワードを生成する。
final class CPYPasswordGeneratorWindowController: NSWindowController {

    static let shared: CPYPasswordGeneratorWindowController = {
        let viewController = CPYPasswordGeneratorViewController()
        let window = NSWindow(contentViewController: viewController)
        window.title = L10n.passwordGenerator
        window.styleMask = [.titled, .closable]
        window.center()
        return CPYPasswordGeneratorWindowController(window: window)
    }()

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(self)
        // 新規パスワードの生成は VC の viewDidAppear で行われる
        // （シート表示と独立ウィンドウ表示の両方で同じ挙動にするため）
    }
}

// MARK: - View Controller

/// パスワード生成ダイアログ。
///
/// ## レイアウト
/// ```
/// [ 生成されたパスワード（選択・コピー可能） ]
///              [ QR コード ]
/// 文字数: [ 16 ] --------o------ (スライダー)
/// 文字種: [x] 半角英字  [x] 数字
///         [ ] 記号      [x] 大文字小文字を区別
///         [ ] 入力しやすいパスワード
/// 入力先: [ パスワード ▾ ] [この項目に入力]   [生成] [コピー] [閉じる]
/// ```
/// 「入力先」と「この項目に入力」は `fillDestinations` を渡した呼び出し元にだけ出る。
final class CPYPasswordGeneratorViewController: NSViewController {

    /// 生成値の入力先候補（画面に出す順に渡す）
    struct FillDestination: Equatable {
        let fieldID: String
        /// ポップアップに出す名前（フィールドのラベル）
        let title: String
    }

    /// 入力先の候補。空なら入力の導線を出さない（コピー専用）。
    ///
    /// 独立ウィンドウ（`CPYPasswordGeneratorWindowController.shared`）や
    /// 指紋パスワード管理からの呼び出しでは渡さないため、それらの挙動は
    /// 従来どおり変わらない
    var fillDestinations: [FillDestination] = []

    /// 最初に選んでおく入力先。呼び出し元が「直前に編集していた欄」を知っている
    /// 場合に渡す。該当が無ければ先頭を選ぶ
    var preferredDestinationID: String?

    /// 生成したパスワードと、選ばれた入力先の `fieldID` を呼び出し元へ渡す。
    ///
    /// **どこへ入れるかは画面上で選ばせる。** 呼び出し元がフォーカス等から
    /// 推測すると、利用者から見て「どの欄に入ったのか分からない」状態になる。
    /// マスク中の欄は空でも `••••••••` と表示され、入ったかどうかを目視で
    /// 確かめられないため、なおさら推測に頼れない
    var onUse: ((_ password: String, _ fieldID: String) -> Void)?

    private let service = PasswordGenerateService()

    private let passwordField = NSTextField(labelWithString: "")
    /// 生成したパスワードの QR 表示（指紋パスワード管理と同じ thoth-cpw 形式。
    /// スマートフォンでの持ち出しや、別端末のカメラ読み取りによる取り込みに使える）
    private let qrImageView    = NSImageView()
    private let lengthField    = NSTextField()
    private let lengthSlider   = NSSlider()
    private lazy var lettersCheckbox = NSButton(checkboxWithTitle: L10n.passwordLetters, target: self, action: #selector(lettersCheckboxChanged))
    private lazy var digitsCheckbox  = NSButton(checkboxWithTitle: L10n.passwordDigits, target: nil, action: nil)
    private lazy var symbolsCheckbox = NSButton(checkboxWithTitle: L10n.passwordSymbols, target: nil, action: nil)
    private lazy var caseCheckbox    = NSButton(checkboxWithTitle: L10n.passwordDistinguishCase, target: nil, action: nil)
    private lazy var easyToTypeCheckbox = NSButton(checkboxWithTitle: L10n.easyToTypePassword, target: nil, action: nil)
    private let generateButton = NSButton()
    private let copyButton     = NSButton()
    private let closeButton    = NSButton()
    /// 生成値を選んだフィールドへ入れるボタン。
    /// 出し入れをユニットテストから検証できるよう internal にしている
    let useButton = NSButton()
    /// 入力先を選ぶポップアップ
    let destinationPopUp = NSPopUpButton()
    private let destinationLabel = NSTextField(labelWithString: "")
    /// 「入力先」の一行をまとめた入れ物。候補が無い呼び出し元では高さ 0 に畳んで、
    /// 独立ウィンドウの見た目を従来どおりに保つ
    private let destinationRow = NSStackView()
    private var destinationRowHeight: NSLayoutConstraint?

    private static let defaultLength = 16
    /// 「入力先」の行の高さ（候補が無いときは 0 に畳む）
    private static let destinationRowHeightValue: CGFloat = 25

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 440, height: 425))
        setupUI()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        // 候補が loadView() より後に設定されていても取りこぼさない
        reloadFillDestinations()
        // 表示のたびに条件に基づいた新しいパスワードを生成する
        generateAction()
    }

    /// 入力先ポップアップを組み立て直す。候補が無ければ入力の導線ごと隠す
    func reloadFillDestinations() {
        let hasDestinations = !fillDestinations.isEmpty && onUse != nil
        destinationRow.isHidden = !hasDestinations
        destinationRowHeight?.constant = hasDestinations ? Self.destinationRowHeightValue : 0
        destinationLabel.isHidden = !hasDestinations
        destinationPopUp.isHidden = !hasDestinations
        useButton.isHidden = !hasDestinations
        guard hasDestinations else { return }

        // **`addItem(withTitle:)` は使わない。** NSPopUpButton のそれは同名の項目を
        // 先に取り除く仕様で、「Password」が 2 つある持ち物では候補が 1 つに潰れる。
        // メニューを直接組めば同名でも並び、選択は添字で解決できる
        let menu = NSMenu()
        for destination in fillDestinations {
            menu.addItem(NSMenuItem(title: destination.title, action: nil, keyEquivalent: ""))
        }
        destinationPopUp.menu = menu
        let index = fillDestinations.firstIndex { $0.fieldID == preferredDestinationID } ?? 0
        destinationPopUp.selectItem(at: index)
    }

    /// いま選ばれている入力先（候補が無ければ nil）
    var selectedDestination: FillDestination? {
        let index = destinationPopUp.indexOfSelectedItem
        guard index >= 0, index < fillDestinations.count else { return nil }
        return fillDestinations[index]
    }

    /// Esc キーで閉じる
    override func cancelOperation(_ sender: Any?) {
        closeSelf()
    }

    /// シート（presentAsSheet）の場合は dismiss、独立ウィンドウの場合は close する
    private func closeSelf() {
        if presentingViewController != nil {
            presentingViewController?.dismiss(self)
        } else {
            view.window?.performClose(self)
        }
    }

    // MARK: - Actions

    /// 指定条件に基づいて新規パスワードを生成して表示する
    @objc func generateAction() {
        let conditions = currentConditions()
        guard conditions.hasAnyCharacterType else {
            NSSound.beep()
            return
        }
        generateButton.isEnabled = false
        service.generate(conditions: conditions) { [weak self] password in
            guard let self = self else { return }
            self.generateButton.isEnabled = true
            guard let password = password else {
                NSSound.beep()
                return
            }
            self.passwordField.stringValue = password
            self.updateQRCode()
        }
    }

    /// 表示中のパスワードから QR 表示を更新する（空・生成失敗時は非表示）
    private func updateQRCode() {
        let password = passwordField.stringValue
        let image = password.isEmpty ? nil : CryptoPasswordQRCodec.generateQRImage(for: password)
        qrImageView.image = image
        qrImageView.isHidden = (image == nil)
    }

    /// 現在表示中のパスワードをクリップボードにコピーする。
    /// 生成物はパスワードなので秘匿マーカー付きでコピーし（履歴に残さない）、
    /// 一定時間後に自動クリアする
    @objc private func copyAction() {
        let password = passwordField.stringValue
        guard !password.isEmpty else {
            NSSound.beep()
            return
        }
        AppEnvironment.current.pasteService.copyConcealedToPasteboard(with: password)
        AppEnvironment.current.pasteService.scheduleConcealedClear()
    }

    /// 表示中のパスワードを呼び出し元のフィールドへ渡して閉じる。
    /// クリップボードは経由しない（貼り付け先を取り違える事故と、
    /// 秘匿マーカー付きコピーの自動クリア待ちを避ける）
    @objc private func useAction() {
        let password = passwordField.stringValue
        guard !password.isEmpty, let destination = selectedDestination else {
            NSSound.beep()
            return
        }
        onUse?(password, destination.fieldID)
        closeSelf()
    }

    @objc private func closeWindow() {
        closeSelf()
    }

    @objc private func lettersCheckboxChanged() {
        // 大文字小文字の区別は英字が有効なときのみ意味を持つ
        caseCheckbox.isEnabled = lettersCheckbox.state == .on
    }

    @objc private func lengthSliderChanged() {
        lengthField.integerValue = lengthSlider.integerValue
    }

    @objc private func lengthFieldChanged() {
        let clamped = min(max(lengthField.integerValue, PasswordGenerateService.minimumLength),
                          PasswordGenerateService.maximumLength)
        lengthField.integerValue = clamped
        lengthSlider.integerValue = clamped
    }

    private func currentConditions() -> PasswordGenerateService.Conditions {
        lengthFieldChanged()
        return PasswordGenerateService.Conditions(length: lengthField.integerValue,
                                                  useLetters: lettersCheckbox.state == .on,
                                                  useDigits: digitsCheckbox.state == .on,
                                                  useSymbols: symbolsCheckbox.state == .on,
                                                  distinguishCase: caseCheckbox.state == .on,
                                                  easyToType: easyToTypeCheckbox.state == .on)
    }
}

// MARK: - UI Setup

fileprivate extension CPYPasswordGeneratorViewController {

    func setupUI() {
        // 生成されたパスワード（1行目・大きめの文字・選択コピー可能）
        passwordField.font = NSFont(name: "Menlo", size: 18) ?? NSFont.systemFont(ofSize: 18)
        passwordField.alignment = .center
        passwordField.isSelectable = true
        passwordField.lineBreakMode = .byTruncatingMiddle
        passwordField.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(passwordField)

        // パスワードの QR 表示（ドット境界が滲まないよう最近傍補間で拡大する）
        qrImageView.imageScaling = .scaleProportionallyUpOrDown
        qrImageView.wantsLayer = true
        qrImageView.layer?.magnificationFilter = .nearest
        qrImageView.isHidden = true
        qrImageView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(qrImageView)

        // 文字数
        let lengthLabel = NSTextField(labelWithString: L10n.passwordLength)
        lengthLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(lengthLabel)

        lengthField.integerValue = Self.defaultLength
        lengthField.alignment = .right
        lengthField.target = self
        lengthField.action = #selector(lengthFieldChanged)
        lengthField.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(lengthField)

        // 最小〜最大文字数までシームレスに変更できるスライダー
        lengthSlider.minValue = Double(PasswordGenerateService.minimumLength)
        lengthSlider.maxValue = Double(PasswordGenerateService.maximumLength)
        lengthSlider.integerValue = Self.defaultLength
        lengthSlider.allowsTickMarkValuesOnly = false
        lengthSlider.isContinuous = true
        lengthSlider.target = self
        lengthSlider.action = #selector(lengthSliderChanged)
        lengthSlider.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(lengthSlider)

        // 文字種（チェックボックス 2x2）
        let typesLabel = NSTextField(labelWithString: L10n.characterTypes)
        typesLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(typesLabel)

        lettersCheckbox.state = .on
        digitsCheckbox.state = .on
        symbolsCheckbox.state = .off
        caseCheckbox.state = .on
        easyToTypeCheckbox.state = .off
        [lettersCheckbox, digitsCheckbox, symbolsCheckbox, caseCheckbox, easyToTypeCheckbox].forEach { checkbox in
            checkbox.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(checkbox)
        }

        // ボタン（パスワード生成・コピー・閉じる）
        generateButton.title = L10n.generatePassword
        generateButton.keyEquivalent = "\r"
        generateButton.target = self
        generateButton.action = #selector(generateAction)

        copyButton.title = L10n.copyPassword
        copyButton.target = self
        copyButton.action = #selector(copyAction)

        closeButton.title = L10n.close
        closeButton.target = self
        closeButton.action = #selector(closeWindow)

        // 呼び出し元へ返す操作なので、生成・コピー・閉じるの並びとは離して左端に置く
        useButton.title = L10n.passwordGeneratorFillField
        useButton.target = self
        useButton.action = #selector(useAction)

        [generateButton, copyButton, closeButton, useButton].forEach { button in
            button.bezelStyle = .rounded
            button.translatesAutoresizingMaskIntoConstraints = false
        }
        [generateButton, copyButton, closeButton].forEach { view.addSubview($0) }

        NSLayoutConstraint.activate([
            passwordField.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            passwordField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            passwordField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            qrImageView.topAnchor.constraint(equalTo: passwordField.bottomAnchor, constant: 12),
            qrImageView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            qrImageView.widthAnchor.constraint(equalToConstant: 160),
            qrImageView.heightAnchor.constraint(equalToConstant: 160),

            lengthLabel.topAnchor.constraint(equalTo: qrImageView.bottomAnchor, constant: 16),
            lengthLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            lengthField.centerYAnchor.constraint(equalTo: lengthLabel.centerYAnchor),
            lengthField.leadingAnchor.constraint(equalTo: lengthLabel.trailingAnchor, constant: 8),
            lengthField.widthAnchor.constraint(equalToConstant: 56),
            lengthSlider.centerYAnchor.constraint(equalTo: lengthLabel.centerYAnchor),
            lengthSlider.leadingAnchor.constraint(equalTo: lengthField.trailingAnchor, constant: 12),
            lengthSlider.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            typesLabel.topAnchor.constraint(equalTo: lengthLabel.bottomAnchor, constant: 16),
            typesLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            lettersCheckbox.centerYAnchor.constraint(equalTo: typesLabel.centerYAnchor),
            lettersCheckbox.leadingAnchor.constraint(equalTo: typesLabel.trailingAnchor, constant: 8),
            digitsCheckbox.centerYAnchor.constraint(equalTo: typesLabel.centerYAnchor),
            digitsCheckbox.leadingAnchor.constraint(equalTo: lettersCheckbox.trailingAnchor, constant: 16),
            symbolsCheckbox.topAnchor.constraint(equalTo: lettersCheckbox.bottomAnchor, constant: 8),
            symbolsCheckbox.leadingAnchor.constraint(equalTo: lettersCheckbox.leadingAnchor),
            caseCheckbox.centerYAnchor.constraint(equalTo: symbolsCheckbox.centerYAnchor),
            caseCheckbox.leadingAnchor.constraint(equalTo: digitsCheckbox.leadingAnchor),
            easyToTypeCheckbox.topAnchor.constraint(equalTo: symbolsCheckbox.bottomAnchor, constant: 8),
            easyToTypeCheckbox.leadingAnchor.constraint(equalTo: lettersCheckbox.leadingAnchor),

            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            closeButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
            copyButton.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -8),
            copyButton.bottomAnchor.constraint(equalTo: closeButton.bottomAnchor),
            generateButton.trailingAnchor.constraint(equalTo: copyButton.leadingAnchor, constant: -8),
            generateButton.bottomAnchor.constraint(equalTo: closeButton.bottomAnchor)
        ])

        setupDestinationRow()
    }

    /// 「入力先」の一行を組み立てる。
    /// ボタン列の 1 段上に置く（同じ行に並べると 440pt の幅に収まらない）。
    /// 候補を渡されない呼び出し元では高さ 0 に畳んで、見た目を従来どおりに保つ
    func setupDestinationRow() {
        destinationLabel.stringValue = L10n.passwordGeneratorDestination
        destinationRow.orientation = .horizontal
        destinationRow.spacing = 8
        destinationRow.translatesAutoresizingMaskIntoConstraints = false
        [destinationLabel, destinationPopUp, useButton].forEach {
            destinationRow.addArrangedSubview($0)
        }
        view.addSubview(destinationRow)

        let heightConstraint = destinationRow.heightAnchor.constraint(
            equalToConstant: Self.destinationRowHeightValue)
        NSLayoutConstraint.activate([
            destinationRow.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            destinationRow.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20),
            destinationRow.topAnchor.constraint(greaterThanOrEqualTo: easyToTypeCheckbox.bottomAnchor,
                                                constant: 8),
            destinationRow.bottomAnchor.constraint(equalTo: closeButton.topAnchor, constant: -10),
            destinationPopUp.widthAnchor.constraint(greaterThanOrEqualToConstant: 130),
            heightConstraint
        ])
        destinationRowHeight = heightConstraint
        reloadFillDestinations()
    }
}
