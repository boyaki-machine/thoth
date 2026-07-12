//
//  CPYCryptoWindowController.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Copyright © 2015-2018 Clipy Project.
//

import Cocoa

// MARK: - Window Controller

/// ファイル・フォルダの暗号化／復号化ダイアログウィンドウのコントローラ。
/// アプリ起動中に一度だけ生成されるシングルトン。
final class CPYCryptoWindowController: NSWindowController {

    static let shared: CPYCryptoWindowController = {
        let viewController = CPYCryptoViewController()
        let window = NSWindow(contentViewController: viewController)
        window.title = L10n.encryptDecrypt
        window.styleMask = [.titled, .closable]
        // 別のデスクトップスペースへ移動していても、表示時は現在のスペースに出す
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.center()
        return CPYCryptoWindowController(window: window)
    }()

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        // 現在のスペースの最前面に出す
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(self)
        // 開くたびに前回の入力内容をクリアして初期状態にする
        (contentViewController as? CPYCryptoViewController)?.resetForm()
    }
}

// MARK: - View Controller

/// 暗号化／復号化ダイアログ。
///
/// ## レイアウト
/// ```
/// 対象: [ /path/to/file      ] [選択...]
/// 出力ファイル名: [ file.enc          ]
/// パスワード:     [ ••••••••          ]
///                        [暗号化] [復号化] [閉じる]
/// ```
///
/// 暗号化は AES-256-CBC + PBKDF2（10 万回）で openssl をバックグラウンド実行する。
final class CPYCryptoViewController: NSViewController {

    private let service = CryptoService()

    private let inputPathField    = NSTextField()
    // Tab でフォーカスを受け取れるよう、ボタンは TabCapturingButton を使う
    private let chooseButton      = TabCapturingButton()
    private let outputNameField   = NSTextField()
    private let passwordField     = NSSecureTextField()
    private let fingerprintButton = TabCapturingButton()
    private let statusLabel       = NSTextField(labelWithString: "")
    /// 暗号化成功後に表示する openssl 復号コマンド例（選択・コピー可能）
    private let recoveryCommandField = NSTextField(wrappingLabelWithString: "")
    private let copyCommandButton = TabCapturingButton()
    private let manageButton      = TabCapturingButton()
    private let encryptButton     = TabCapturingButton()
    private let decryptButton     = TabCapturingButton()
    private let closeButton       = TabCapturingButton()

    /// 選択中の入力パス
    private var inputURL: URL?

    /// Tab キーによるフォーカス循環の順序。テキストフィールドとボタンを含む。
    private lazy var focusOrder: [NSResponder] = [chooseButton, outputNameField, passwordField,
                                                  fingerprintButton, manageButton,
                                                  encryptButton, decryptButton, closeButton]
    /// `viewDidAppear` で登録し `viewWillDisappear` で解除するローカルイベントモニター
    private var keyEventMonitor: Any?

    /// ファイル選択パネルは初回生成時に別プロセス（openAndSavePanelService）との
    /// 接続確立で遅延するため、事前に生成・再利用してクリック時の表示を高速化する。
    private lazy var openPanel: NSOpenPanel = {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        return panel
    }()

    override func loadView() {
        // 高さは復号コマンド例（3 行程度）の表示領域を含む
        view = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 320))
        setupUI()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(chooseButton)
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, event.window === self.view.window else { return event }
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if event.keyCode == 48 { // Tab / Shift+Tab → フォーカスを循環
                guard mods.isEmpty || mods == .shift else { return event }
                self.moveFocus(backward: mods == .shift)
                return nil
            }
            // Return / Enter: ボタンにフォーカスがあればそのボタンを押下する
            if event.keyCode == 36 || event.keyCode == 76, mods.isEmpty,
               let focusedButton = self.view.window?.firstResponder as? TabCapturingButton {
                focusedButton.performClick(nil)
                return nil
            }
            return event
        }
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        if let monitor = keyEventMonitor {
            NSEvent.removeMonitor(monitor)
            keyEventMonitor = nil
        }
    }

    /// Tab / Shift+Tab でフォーカスを次（前）の要素へ循環させる
    private func moveFocus(backward: Bool) {
        guard let window = view.window else { return }
        let currentResponder = window.firstResponder
        // テキストフィールド編集中は field editor が firstResponder になるため currentEditor でも判定する
        let currentIndex = focusOrder.firstIndex { responder in
            responder === currentResponder || (responder as? NSTextField)?.currentEditor() != nil
        } ?? 0
        let offset = backward ? focusOrder.count - 1 : 1
        let nextResponder = focusOrder[(currentIndex + offset) % focusOrder.count]
        window.makeFirstResponder(nextResponder)
    }

    /// Esc キーでウィンドウを閉じる
    override func cancelOperation(_ sender: Any?) {
        view.window?.performClose(sender)
    }

    /// フォームを初期状態に戻す
    func resetForm() {
        inputURL = nil
        inputPathField.stringValue = ""
        outputNameField.stringValue = ""
        passwordField.stringValue = ""
        statusLabel.stringValue = ""
        showRecoveryCommand(nil)
        setControlsEnabled(true)
        // ファイル選択パネルを事前生成してウォームアップし、初回表示の遅延を抑える
        _ = openPanel
        // 初期フォーカスをファイル選択ボタンに置く
        view.window?.makeFirstResponder(chooseButton)
    }

    // MARK: - Actions

    @objc private func chooseInput() {
        guard let window = view.window else { return }
        // NSOpenPanel はフォルダをハイライトして Return を押すと中にナビゲートしてしまい、
        // 選択が確定しない。Return をローカルで捕捉し、選択があればその場で確定する。
        var keyMonitor: Any?
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, event.window === self.openPanel,
                  event.keyCode == 36 || event.keyCode == 76 else { return event } // Return / Enter
            guard let url = self.openPanel.urls.first else { return event }
            self.openPanel.cancel(nil)
            self.updateInput(url: url)
            return nil
        }
        openPanel.beginSheetModal(for: window) { [weak self] response in
            if let monitor = keyMonitor { NSEvent.removeMonitor(monitor); keyMonitor = nil }
            guard response == .OK, let url = self?.openPanel.url else { return }
            self?.updateInput(url: url)
        }
    }

    private func updateInput(url: URL) {
        inputURL = url
        inputPathField.stringValue = url.path
        // 出力ファイル名のデフォルトを設定する
        if url.pathExtension == CryptoService.encryptedExtension {
            // 暗号化ファイルが選ばれた場合は復号時の既定名（.enc を除いた名前）
            outputNameField.stringValue = url.deletingPathExtension().lastPathComponent
        } else {
            outputNameField.stringValue = "\(url.lastPathComponent).\(CryptoService.encryptedExtension)"
        }
    }

    @objc private func encryptAction() {
        performCrypto(isEncrypt: true)
    }

    @objc private func decryptAction() {
        performCrypto(isEncrypt: false)
    }

    private func performCrypto(isEncrypt: Bool) {
        guard let inputURL = inputURL else {
            showStatus(L10n.cryptoErrorInputNotFound, isError: true)
            return
        }
        let password = passwordField.stringValue
        guard !password.isEmpty else {
            showStatus(L10n.cryptoErrorEmptyPassword, isError: true)
            return
        }
        let outputName = outputNameField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !outputName.isEmpty else {
            showStatus(L10n.cryptoErrorEmptyOutputName, isError: true)
            return
        }
        let outputURL = inputURL.deletingLastPathComponent().appendingPathComponent(outputName)

        // フォルダ暗号化かどうか（復号コマンド例に tar 展開を含めるかの判定）
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: inputURL.path, isDirectory: &isDirectory)
        let isFolder = isDirectory.boolValue

        setControlsEnabled(false)
        showRecoveryCommand(nil)
        showStatus(isEncrypt ? L10n.cryptoEncrypting : L10n.cryptoDecrypting, isError: false)
        let completion: (Result<URL, Error>) -> Void = { [weak self] result in
            guard let self = self else { return }
            self.setControlsEnabled(true)
            switch result {
            case .success(let url):
                if isEncrypt {
                    // ウィンドウは閉じず、openssl での復号コマンド例を表示する
                    // （アプリが無い環境での復旧手順をその場で確認・コピーできるように）
                    self.showStatus(L10n.cryptoEncryptedWithCommand, isError: false)
                    self.showRecoveryCommand(CryptoService.opensslDecryptCommand(
                        encryptedPath: url.path,
                        outputName: inputURL.lastPathComponent,
                        isFolder: isFolder))
                } else {
                    // 復号はウィンドウを閉じ、生成物を Finder で選択表示する
                    self.view.window?.performClose(self)
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            case .failure(let error):
                self.showStatus(error.localizedDescription, isError: true)
            }
        }
        if isEncrypt {
            service.encrypt(inputURL: inputURL, outputURL: outputURL, password: password, completion: completion)
        } else {
            service.decrypt(inputURL: inputURL, outputURL: outputURL, password: password, completion: completion)
        }
    }

    @objc private func closeWindow() {
        view.window?.performClose(self)
    }

    /// 指紋アイコン押下: Touch ID 認証後、登録済みの固定パスワードをパスワード欄に入力する
    @objc private func fingerprintAuthenticate() {
        let service = AppEnvironment.current.secureMenuService
        guard service.hasCryptoPassword() else {
            showStatus(L10n.cryptoNoFingerprintPassword, isError: true)
            return
        }
        service.authenticate(reason: L10n.cryptoFingerprintReason) { [weak self] success in
            guard let self = self else { return }
            // 認証ダイアログにフォーカスが移るため、自分のウィンドウを前面に戻す
            self.activateWindow()
            guard success, let password = service.loadCryptoPassword() else {
                self.showStatus(L10n.cryptoFingerprintFailed, isError: true)
                return
            }
            self.passwordField.stringValue = password
            self.showStatus(L10n.cryptoFingerprintApplied, isError: false)
        }
    }

    /// 認証ダイアログ等でフォーカスが外れた後、このウィンドウを前面に戻す。
    /// Touch ID の認証 UI が完全に閉じる前に前面化すると失敗するため、少し遅延させる。
    private func activateWindow() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            NSApp.activate(ignoringOtherApps: true)
            self?.view.window?.makeKeyAndOrderFront(nil)
        }
    }

    /// 指紋パスワード管理をシートとして表示する（呼び出し元が明確なためモーダル。
    /// シートの間はこのウィンドウは操作不能になり、閉じるとフォーカスが戻る）
    @objc private func openFingerprintPasswordManager() {
        presentAsSheet(CPYCryptoPasswordManagerViewController())
    }

    private func setControlsEnabled(_ enabled: Bool) {
        [chooseButton, encryptButton, decryptButton, fingerprintButton, manageButton].forEach { $0.isEnabled = enabled }
    }

    private func showStatus(_ message: String, isError: Bool) {
        statusLabel.stringValue = message
        statusLabel.textColor = isError ? .systemRed : .secondaryLabelColor
    }

    /// openssl 復号コマンド例の表示／非表示を切り替える（nil で非表示）
    private func showRecoveryCommand(_ command: String?) {
        recoveryCommandField.stringValue = command ?? ""
        recoveryCommandField.isHidden = (command == nil)
        copyCommandButton.isHidden = (command == nil)
    }

    /// 復号コマンド例をクリップボードにコピーする
    /// （パスワードはプレースホルダーのため秘匿情報は含まれず、通常コピーでよい）
    @objc private func copyRecoveryCommand() {
        AppEnvironment.current.pasteService.copyToPasteboard(with: recoveryCommandField.stringValue)
        showStatus(L10n.copied, isError: false)
    }
}

// MARK: - UI Setup

fileprivate extension CPYCryptoViewController {

    func setupUI() {
        let inputLabel = NSTextField(labelWithString: L10n.cryptoTarget)
        inputLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(inputLabel)

        inputPathField.placeholderString = L10n.cryptoTargetPlaceholder
        inputPathField.isEditable = false
        inputPathField.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(inputPathField)

        chooseButton.title = L10n.cryptoChoose
        chooseButton.bezelStyle = .rounded
        chooseButton.setCommandKey("f")
        chooseButton.toolTip = "⌘F"
        chooseButton.target = self
        chooseButton.action = #selector(chooseInput)
        chooseButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(chooseButton)

        let outputLabel = NSTextField(labelWithString: L10n.cryptoOutputName)
        outputLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(outputLabel)

        outputNameField.placeholderString = "output.\(CryptoService.encryptedExtension)"
        outputNameField.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(outputNameField)

        let passwordLabel = NSTextField(labelWithString: L10n.cryptoKey)
        passwordLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(passwordLabel)

        passwordField.placeholderString = L10n.cryptoKeyPlaceholder
        passwordField.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(passwordField)

        // 指紋認証で固定パスワードを入力するボタン
        if #available(macOS 11.0, *) {
            fingerprintButton.image = NSImage(systemSymbolName: "touchid", accessibilityDescription: L10n.cryptoFingerprint)
        } else {
            fingerprintButton.title = "🔑"
        }
        fingerprintButton.bezelStyle = .rounded
        fingerprintButton.toolTip = L10n.cryptoFingerprint
        fingerprintButton.target = self
        fingerprintButton.action = #selector(fingerprintAuthenticate)
        fingerprintButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(fingerprintButton)

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.lineBreakMode = .byTruncatingMiddle
        statusLabel.textColor = .secondaryLabelColor
        view.addSubview(statusLabel)

        // openssl 復号コマンド例（暗号化成功後のみ表示。選択してコピー可能）
        recoveryCommandField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        recoveryCommandField.textColor = .secondaryLabelColor
        recoveryCommandField.isSelectable = true
        recoveryCommandField.isHidden = true
        recoveryCommandField.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(recoveryCommandField)

        copyCommandButton.title = L10n.cryptoCopyCommand
        copyCommandButton.bezelStyle = .rounded
        copyCommandButton.controlSize = .small
        copyCommandButton.isHidden = true
        copyCommandButton.target = self
        copyCommandButton.action = #selector(copyRecoveryCommand)
        copyCommandButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(copyCommandButton)

        // 左下: 指紋パスワード管理
        manageButton.title = L10n.cryptoManageFingerprintPassword
        manageButton.bezelStyle = .rounded
        manageButton.target = self
        manageButton.action = #selector(openFingerprintPasswordManager)
        manageButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(manageButton)

        // どのボタンも既定（Enter）にはせず、Cmd+E / Cmd+D をショートカットに割り当てる
        encryptButton.title = L10n.cryptoEncrypt
        encryptButton.bezelStyle = .rounded
        encryptButton.setCommandKey("e")
        encryptButton.toolTip = "⌘E"
        encryptButton.target = self
        encryptButton.action = #selector(encryptAction)

        decryptButton.title = L10n.cryptoDecrypt
        decryptButton.bezelStyle = .rounded
        decryptButton.setCommandKey("d")
        decryptButton.toolTip = "⌘D"
        decryptButton.target = self
        decryptButton.action = #selector(decryptAction)

        closeButton.title = L10n.close
        closeButton.bezelStyle = .rounded
        closeButton.target = self
        closeButton.action = #selector(closeWindow)

        [encryptButton, decryptButton, closeButton].forEach { button in
            button.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(button)
        }

        activateConstraints(inputLabel: inputLabel, outputLabel: outputLabel, passwordLabel: passwordLabel)
    }

    private func activateConstraints(inputLabel: NSTextField, outputLabel: NSTextField, passwordLabel: NSTextField) {
        let labelWidth: CGFloat = 96
        NSLayoutConstraint.activate([
            inputLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            inputLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            inputLabel.widthAnchor.constraint(equalToConstant: labelWidth),
            inputPathField.centerYAnchor.constraint(equalTo: inputLabel.centerYAnchor),
            inputPathField.leadingAnchor.constraint(equalTo: inputLabel.trailingAnchor, constant: 8),
            chooseButton.centerYAnchor.constraint(equalTo: inputLabel.centerYAnchor),
            chooseButton.leadingAnchor.constraint(equalTo: inputPathField.trailingAnchor, constant: 8),
            chooseButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            outputLabel.topAnchor.constraint(equalTo: inputLabel.bottomAnchor, constant: 16),
            outputLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            outputLabel.widthAnchor.constraint(equalToConstant: labelWidth),
            outputNameField.centerYAnchor.constraint(equalTo: outputLabel.centerYAnchor),
            outputNameField.leadingAnchor.constraint(equalTo: outputLabel.trailingAnchor, constant: 8),
            outputNameField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            passwordLabel.topAnchor.constraint(equalTo: outputLabel.bottomAnchor, constant: 16),
            passwordLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            passwordLabel.widthAnchor.constraint(equalToConstant: labelWidth),
            passwordField.centerYAnchor.constraint(equalTo: passwordLabel.centerYAnchor),
            passwordField.leadingAnchor.constraint(equalTo: passwordLabel.trailingAnchor, constant: 8),
            fingerprintButton.centerYAnchor.constraint(equalTo: passwordLabel.centerYAnchor),
            fingerprintButton.leadingAnchor.constraint(equalTo: passwordField.trailingAnchor, constant: 8),
            fingerprintButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            fingerprintButton.widthAnchor.constraint(equalToConstant: 44),

            statusLabel.topAnchor.constraint(equalTo: passwordLabel.bottomAnchor, constant: 16),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            recoveryCommandField.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 8),
            recoveryCommandField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            recoveryCommandField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            copyCommandButton.topAnchor.constraint(equalTo: recoveryCommandField.bottomAnchor, constant: 6),
            copyCommandButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),

            manageButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            manageButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),

            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            closeButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
            decryptButton.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -8),
            decryptButton.bottomAnchor.constraint(equalTo: closeButton.bottomAnchor),
            encryptButton.trailingAnchor.constraint(equalTo: decryptButton.leadingAnchor, constant: -8),
            encryptButton.bottomAnchor.constraint(equalTo: closeButton.bottomAnchor)
        ])
    }
}

// MARK: - Command Key Shortcut

fileprivate extension NSButton {
    /// Command + 指定文字 でボタンを押せるショートカットを設定する。
    /// Enter（既定ボタン）を占有せず、テキスト入力中でも文字入力と衝突しない。
    func setCommandKey(_ character: String) {
        keyEquivalent = character
        keyEquivalentModifierMask = [.command]
    }
}
