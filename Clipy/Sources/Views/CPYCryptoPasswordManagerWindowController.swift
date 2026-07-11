//
//  CPYCryptoPasswordManagerWindowController.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Copyright © 2015-2018 Clipy Project.
//

import Cocoa

// MARK: - Window Controller

/// 指紋パスワード（暗号化・復号化の固定パスワード）を管理するウィンドウ。
/// 表示時に Touch ID 認証を行い、成功した場合のみ現在のパスワードを表示・編集できる。
final class CPYCryptoPasswordManagerWindowController: NSWindowController {

    static let shared: CPYCryptoPasswordManagerWindowController = {
        let viewController = CPYCryptoPasswordManagerViewController()
        let window = NSWindow(contentViewController: viewController)
        window.title = L10n.cryptoManageFingerprintPassword
        window.styleMask = [.titled, .closable]
        // 別のデスクトップスペースへ移動していても、表示時は現在のスペースに出す
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.center()
        return CPYCryptoPasswordManagerWindowController(window: window)
    }()

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(self)
        (contentViewController as? CPYCryptoPasswordManagerViewController)?.authenticateAndLoad()
    }
}

// MARK: - View Controller

/// 現在の指紋パスワードの表示と、登録・更新を行うダイアログ。
final class CPYCryptoPasswordManagerViewController: NSViewController {

    private let passwordField = NSTextField()
    private let statusLabel   = NSTextField(labelWithString: "")
    private let saveButton    = NSButton()
    private let closeButton   = NSButton()
    private let generateButton = NSButton()
    /// Touch ID 認証が完了したか（未認証では保存できない）
    private var isAuthenticated = false

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 160))
        setupUI()
    }

    override func cancelOperation(_ sender: Any?) {
        view.window?.performClose(sender)
    }

    /// Touch ID 認証を行い、成功したら現在のパスワードを表示する
    func authenticateAndLoad() {
        isAuthenticated = false
        passwordField.stringValue = ""
        passwordField.isEnabled = false
        saveButton.isEnabled = false
        statusLabel.stringValue = L10n.cryptoFingerprintReason

        let service = AppEnvironment.current.secureMenuService
        service.authenticate(reason: L10n.cryptoFingerprintReason) { [weak self] success in
            guard let self = self else { return }
            // 認証 UI が完全に閉じてから前面に戻すため少し遅延させる
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                NSApp.activate(ignoringOtherApps: true)
                self?.view.window?.makeKeyAndOrderFront(nil)
            }
            guard success else {
                self.statusLabel.stringValue = L10n.cryptoFingerprintFailed
                return
            }
            self.isAuthenticated = true
            self.passwordField.stringValue = service.loadCryptoPassword() ?? ""
            self.passwordField.isEnabled = true
            self.saveButton.isEnabled = true
            self.statusLabel.stringValue = ""
            self.view.window?.makeFirstResponder(self.passwordField)
        }
    }

    // MARK: - Actions

    @objc private func saveAction() {
        guard isAuthenticated else { return }
        let password = passwordField.stringValue
        guard !password.isEmpty else {
            statusLabel.stringValue = L10n.cryptoErrorEmptyPassword
            statusLabel.textColor = .systemRed
            return
        }
        // 登録処理を行い、成功したらウィンドウを閉じる
        if AppEnvironment.current.secureMenuService.saveCryptoPassword(password) {
            view.window?.performClose(self)
        } else {
            statusLabel.stringValue = L10n.cryptoErrorFailed
            statusLabel.textColor = .systemRed
        }
    }

    @objc private func closeWindow() {
        view.window?.performClose(self)
    }

    /// 新規パスワード生成ウィンドウを表示する
    @objc private func openPasswordGenerator() {
        CPYPasswordGeneratorWindowController.shared.showWindow(self)
    }
}

// MARK: - UI Setup

fileprivate extension CPYCryptoPasswordManagerViewController {

    func setupUI() {
        let passwordLabel = NSTextField(labelWithString: L10n.cryptoKey)
        passwordLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(passwordLabel)

        // 登録済みパスワードの確認・更新を行うため、あえて可視のテキストフィールドにする
        passwordField.placeholderString = L10n.cryptoKeyPlaceholder
        passwordField.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(passwordField)

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.textColor = .secondaryLabelColor
        view.addSubview(statusLabel)

        saveButton.title = L10n.cryptoRegisterUpdate
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"
        saveButton.target = self
        saveButton.action = #selector(saveAction)
        saveButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(saveButton)

        closeButton.title = L10n.close
        closeButton.bezelStyle = .rounded
        closeButton.target = self
        closeButton.action = #selector(closeWindow)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(closeButton)

        // 新規パスワード生成ウィンドウを開くボタン（左下に配置）
        generateButton.title = L10n.passwordGenerator
        generateButton.bezelStyle = .rounded
        generateButton.target = self
        generateButton.action = #selector(openPasswordGenerator)
        generateButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(generateButton)

        NSLayoutConstraint.activate([
            passwordLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),
            passwordLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            passwordField.centerYAnchor.constraint(equalTo: passwordLabel.centerYAnchor),
            passwordField.leadingAnchor.constraint(equalTo: passwordLabel.trailingAnchor, constant: 8),
            passwordField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            statusLabel.topAnchor.constraint(equalTo: passwordLabel.bottomAnchor, constant: 16),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            closeButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
            saveButton.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -8),
            saveButton.bottomAnchor.constraint(equalTo: closeButton.bottomAnchor),

            generateButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            generateButton.bottomAnchor.constraint(equalTo: closeButton.bottomAnchor)
        ])
    }
}
