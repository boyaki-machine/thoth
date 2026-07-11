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
        // 表示のたびに条件に基づいた新しいパスワードを生成する
        (contentViewController as? CPYPasswordGeneratorViewController)?.generateAction()
    }
}

// MARK: - View Controller

/// パスワード生成ダイアログ。
///
/// ## レイアウト
/// ```
/// [ 生成されたパスワード（選択・コピー可能） ]
/// 文字数: [ 16 ] --------o------ (スライダー)
/// 文字種: [x] 半角英字  [x] 数字
///         [ ] 記号      [x] 大文字小文字を区別
///         [ ] 入力しやすいパスワード
///        [パスワード生成] [コピー] [閉じる]
/// ```
final class CPYPasswordGeneratorViewController: NSViewController {

    private let service = PasswordGenerateService()

    private let passwordField  = NSTextField(labelWithString: "")
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

    private static let defaultLength = 16

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 440, height: 250))
        setupUI()
    }

    /// Esc キーでウィンドウを閉じる
    override func cancelOperation(_ sender: Any?) {
        view.window?.performClose(sender)
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
        }
    }

    /// 現在表示中のパスワードをクリップボードにコピーする
    @objc private func copyAction() {
        let password = passwordField.stringValue
        guard !password.isEmpty else {
            NSSound.beep()
            return
        }
        AppEnvironment.current.pasteService.copyToPasteboard(with: password)
    }

    @objc private func closeWindow() {
        view.window?.performClose(self)
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

        [generateButton, copyButton, closeButton].forEach { button in
            button.bezelStyle = .rounded
            button.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(button)
        }

        NSLayoutConstraint.activate([
            passwordField.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            passwordField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            passwordField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            lengthLabel.topAnchor.constraint(equalTo: passwordField.bottomAnchor, constant: 20),
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
    }
}
