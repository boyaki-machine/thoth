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

// MARK: - View Controller

/// 現在の指紋パスワード（暗号化・復号化の固定パスワード）の表示と登録・更新を行うダイアログ。
/// 表示時に Touch ID 認証を行い、成功した場合のみ現在のパスワードを表示・編集できる。
///
/// 呼び出し元（ファイル暗号化ウィンドウ）が明確なため、独立ウィンドウではなく
/// `presentAsSheet` によるシート（モーダル）として表示する。
/// シートの間は親ウィンドウが操作不能になり、閉じると自動的に親へフォーカスが戻る。
final class CPYCryptoPasswordManagerViewController: NSViewController {

    private let passwordField = NSTextField()
    private let statusLabel   = NSTextField(labelWithString: "")
    private let saveButton    = NSButton()
    private let closeButton   = NSButton()
    private let generateButton = NSButton()
    /// パスワード欄の内容を QR コードで表示するビュー（スマートフォンでの持ち出し用）
    private let qrImageView = NSImageView()
    private let qrCaptionLabel = NSTextField(labelWithString: L10n.cryptoQRCaption)
    /// カメラで QR を読み取るシートを開くボタン
    private let scanButton = NSButton()
    /// Touch ID 認証が完了したか（未認証では保存できない）
    private var isAuthenticated = false

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 470, height: 380))
        setupUI()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        authenticateAndLoad()
    }

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

    /// Touch ID 認証を行い、成功したら現在のパスワードを表示する
    private func authenticateAndLoad() {
        isAuthenticated = false
        passwordField.stringValue = ""
        passwordField.isEnabled = false
        saveButton.isEnabled = false
        scanButton.isEnabled = false
        updateQRCode()
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
            self.scanButton.isEnabled = true
            self.statusLabel.stringValue = ""
            self.updateQRCode()
            self.view.window?.makeFirstResponder(self.passwordField)
        }
    }

    /// パスワード欄の内容から QR コード表示を更新する。
    /// 空欄・生成失敗（容量超過）時は QR を非表示にする。
    /// 認証前は欄が常に空のため、QR も Touch ID 認証成功後にのみ表示される
    private func updateQRCode() {
        let password = passwordField.stringValue
        let image = password.isEmpty ? nil : CryptoPasswordQRCodec.generateQRImage(for: password)
        qrImageView.image = image
        qrImageView.isHidden = (image == nil)
        qrCaptionLabel.isHidden = (image == nil)
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
        // 登録処理を行い、成功したらシートを閉じる
        if AppEnvironment.current.secureMenuService.saveCryptoPassword(password) {
            closeSelf()
        } else {
            statusLabel.stringValue = L10n.cryptoErrorFailed
            statusLabel.textColor = .systemRed
        }
    }

    @objc private func closeWindow() {
        closeSelf()
    }

    /// パスワード生成ダイアログをシートとして表示する（呼び出し元が明確なためモーダル）
    @objc private func openPasswordGenerator() {
        presentAsSheet(CPYPasswordGeneratorViewController())
    }

    /// カメラで QR を読み取り、パスワード欄に反映する（保存は「登録・更新」で利用者が確定する）
    @objc private func openCameraScanner() {
        guard isAuthenticated else { return }
        let scanner = CPYCameraQRScannerViewController()
        scanner.onScan = { [weak self] password in
            guard let self = self else { return }
            self.passwordField.stringValue = password
            self.updateQRCode()
            self.statusLabel.textColor = .secondaryLabelColor
            self.statusLabel.stringValue = L10n.cryptoQRScanned
        }
        presentAsSheet(scanner)
    }
}

// MARK: - NSTextFieldDelegate

extension CPYCryptoPasswordManagerViewController: NSTextFieldDelegate {

    /// パスワード欄の編集に追従して QR 表示をライブ更新する
    func controlTextDidChange(_ obj: Notification) {
        updateQRCode()
    }
}

// MARK: - UI Setup

fileprivate extension CPYCryptoPasswordManagerViewController {

    func setupUI() {
        let passwordLabel = NSTextField(labelWithString: L10n.cryptoKey)
        passwordLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(passwordLabel)

        // 登録済みパスワードの確認・更新を行うため、あえて可視のテキストフィールドにする。
        // 改行を含まない長いパスワードでも、表示幅を超えた分は次の行へ折り返される。
        // 折り返しを表示できるよう欄は常に3行分の高さを確保する
        passwordField.placeholderString = L10n.cryptoKeyPlaceholder
        passwordField.delegate = self
        passwordField.usesSingleLineMode = false
        passwordField.maximumNumberOfLines = 3
        passwordField.cell?.wraps = true
        passwordField.cell?.isScrollable = false
        passwordField.lineBreakMode = .byCharWrapping
        passwordField.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(passwordField)

        // パスワードの QR 表示（欄の内容に追従。ドット境界が滲まないよう最近傍補間で拡大する）
        qrImageView.imageScaling = .scaleProportionallyUpOrDown
        qrImageView.wantsLayer = true
        qrImageView.layer?.magnificationFilter = .nearest
        qrImageView.isHidden = true
        qrImageView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(qrImageView)

        qrCaptionLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        qrCaptionLabel.textColor = .secondaryLabelColor
        qrCaptionLabel.isHidden = true
        qrCaptionLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(qrCaptionLabel)

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

        // カメラで QR を読み取るボタン（パスワード生成の右隣。認証成功まで無効）
        scanButton.title = L10n.cryptoReadQRCamera
        scanButton.bezelStyle = .rounded
        scanButton.target = self
        scanButton.action = #selector(openCameraScanner)
        // 幅が足りない場合は右隣のボタンに重ねず、自身のタイトルを切り詰める
        scanButton.setContentCompressionResistancePriority(.init(490), for: .horizontal)
        scanButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scanButton)

        // パスワード欄の下端〜下部ボタン上端の領域。QR ブロックをこの中で上下センタリングし、
        // 余白が上下で均等になるようにする
        let contentAreaGuide = NSLayoutGuide()
        view.addLayoutGuide(contentAreaGuide)
        // QR 画像・説明・ステータスをひとまとまりとして扱うガイド
        let qrBlockGuide = NSLayoutGuide()
        view.addLayoutGuide(qrBlockGuide)

        NSLayoutConstraint.activate([
            passwordField.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),
            passwordField.leadingAnchor.constraint(equalTo: passwordLabel.trailingAnchor, constant: 8),
            passwordField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            // 3行分の固定高さ（1行 ≈ 17pt × 3 + 枠余白）
            passwordField.heightAnchor.constraint(equalToConstant: 56),
            // 複数行になっても 1 行目とラベルの高さが揃うようベースラインで合わせる
            passwordLabel.firstBaselineAnchor.constraint(equalTo: passwordField.firstBaselineAnchor),
            passwordLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),

            contentAreaGuide.topAnchor.constraint(equalTo: passwordField.bottomAnchor),
            contentAreaGuide.bottomAnchor.constraint(equalTo: closeButton.topAnchor),
            contentAreaGuide.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentAreaGuide.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            qrBlockGuide.topAnchor.constraint(equalTo: qrImageView.topAnchor),
            qrBlockGuide.bottomAnchor.constraint(equalTo: statusLabel.bottomAnchor),

            qrImageView.topAnchor.constraint(greaterThanOrEqualTo: contentAreaGuide.topAnchor, constant: 8),
            qrImageView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            qrImageView.widthAnchor.constraint(equalToConstant: 160),
            qrImageView.heightAnchor.constraint(equalToConstant: 160),

            qrCaptionLabel.topAnchor.constraint(equalTo: qrImageView.bottomAnchor, constant: 6),
            qrCaptionLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            statusLabel.topAnchor.constraint(equalTo: qrCaptionLabel.bottomAnchor, constant: 12),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            closeButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
            saveButton.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -8),
            saveButton.bottomAnchor.constraint(equalTo: closeButton.bottomAnchor),

            generateButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            generateButton.bottomAnchor.constraint(equalTo: closeButton.bottomAnchor),
            scanButton.leadingAnchor.constraint(equalTo: generateButton.trailingAnchor, constant: 8),
            scanButton.bottomAnchor.constraint(equalTo: closeButton.bottomAnchor),
            // ボタン同士の重なり防止（幅が不足する場合は scanButton 側が切り詰められる）
            scanButton.trailingAnchor.constraint(lessThanOrEqualTo: saveButton.leadingAnchor, constant: -8)
        ])

        // 上下センタリング。パスワード欄が3行に伸びて領域が不足した場合は
        // 最小余白（上端 8pt）の制約を優先させるため、必須より低い優先度にする
        let centerConstraint = qrBlockGuide.centerYAnchor.constraint(equalTo: contentAreaGuide.centerYAnchor)
        centerConstraint.priority = .defaultHigh
        centerConstraint.isActive = true
    }
}
