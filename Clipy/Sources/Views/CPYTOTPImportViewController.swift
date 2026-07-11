import Cocoa

final class CPYTOTPImportViewController: NSViewController {
    var onImport: ((String) -> Void)?
    private let inputField = NSTextField()
    private let statusLabel = NSTextField(labelWithString: "")

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 470, height: 210))
        setupUI()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(inputField)
        if inputField.stringValue.isEmpty, let value = QRDecodeService.otpAuthFromClipboard() {
            inputField.stringValue = value
            showStatus("クリップボードから取り込みました", isError: false)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        dismiss(self)
    }

    @objc private func pasteFromClipboard() {
        if let value = QRDecodeService.otpAuthFromClipboard() {
            inputField.stringValue = value
            showStatus("クリップボードから取り込みました", isError: false)
        } else {
            showStatus("クリップボードに有効な TOTP / QR が見つかりません", isError: true)
        }
    }

    @objc private func captureQR() {
        QRDecodeService.captureAndDecode { [weak self] payload in
            guard let self = self else { return }
            NSApp.activate(ignoringOtherApps: true)
            self.view.window?.makeKeyAndOrderFront(nil)
            if let payload = payload {
                self.inputField.stringValue = payload
                self.showStatus("QR コードを読み取りました", isError: false)
            } else {
                self.showStatus("QR コードを読み取れませんでした", isError: true)
            }
        }
    }

    @objc private func addAction() {
        let input = inputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard TOTPService.isValid(input) else {
            showStatus("有効な otpauth:// URI または secret を入力してください", isError: true)
            return
        }
        onImport?(input)
        dismiss(self)
    }

    @objc private func cancelAction() {
        dismiss(self)
    }

    private func showStatus(_ text: String, isError: Bool) {
        statusLabel.stringValue = text
        statusLabel.textColor = isError ? .systemRed : .secondaryLabelColor
    }
}

fileprivate extension CPYTOTPImportViewController {
    func setupUI() {
        let titleLabel = NSTextField(labelWithString: "ワンタイムパスワード（TOTP）を追加")
        titleLabel.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        let descLabel = NSTextField(wrappingLabelWithString:
            "otpauth:// URI または secret を入力するか、クリップボード・画面の QR コードから読み取ってください。")
        descLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        descLabel.textColor = .secondaryLabelColor
        descLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(descLabel)

        inputField.placeholderString = "otpauth://totp/... または Base32 secret"
        inputField.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(inputField)

        let pasteButton = NSButton(title: "クリップボードから", target: self, action: #selector(pasteFromClipboard))
        let captureButton = NSButton(title: "画面の QR を読み取る", target: self, action: #selector(captureQR))
        let cancelButton = NSButton(title: "キャンセル", target: self, action: #selector(cancelAction))
        let addButton = NSButton(title: "追加", target: self, action: #selector(addAction))
        addButton.keyEquivalent = "\r"
        cancelButton.keyEquivalent = "\u{1B}"
        [pasteButton, captureButton, cancelButton, addButton].forEach {
            $0.bezelStyle = .rounded
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }

        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            descLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            descLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            descLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            inputField.topAnchor.constraint(equalTo: descLabel.bottomAnchor, constant: 12),
            inputField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            inputField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            pasteButton.topAnchor.constraint(equalTo: inputField.bottomAnchor, constant: 10),
            pasteButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            captureButton.centerYAnchor.constraint(equalTo: pasteButton.centerYAnchor),
            captureButton.leadingAnchor.constraint(equalTo: pasteButton.trailingAnchor, constant: 8),
            statusLabel.topAnchor.constraint(equalTo: pasteButton.bottomAnchor, constant: 12),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            addButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
            addButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            cancelButton.bottomAnchor.constraint(equalTo: addButton.bottomAnchor),
            cancelButton.trailingAnchor.constraint(equalTo: addButton.leadingAnchor, constant: -8)
        ])
    }
}
