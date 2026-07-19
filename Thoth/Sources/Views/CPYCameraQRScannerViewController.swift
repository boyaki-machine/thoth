//
//  CPYCameraQRScannerViewController.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Copyright © 2015-2018 Clipy Project.
//

import Cocoa
import AVFoundation

/// Mac のカメラで指紋パスワードの QR コード（`thoth-cpw:` ペイロード）を読み取るシート。
///
/// スマートフォンに表示した QR 写真をカメラにかざすと、フレームを Vision でデコードし、
/// `CryptoPasswordQRCodec` の接頭辞検証を通過したパスワードを `onScan` で返して閉じる。
/// 無関係な QR（TOTP の otpauth 等）は取り込まずエラー表示のまま読み取りを続ける。
///
/// カメラ権限（TCC）が未決定の場合はここで要求し、拒否されている場合は
/// システム設定への誘導ボタンを表示する。macOS では `AVCaptureMetadataOutput` の
/// QR 検出が使えないため、`AVCaptureVideoDataOutput` のフレームを Vision で解析する。
final class CPYCameraQRScannerViewController: NSViewController {

    /// 読み取り成功時にパスワード（接頭辞除去済み）を返す（メインスレッドで呼ばれる）
    var onScan: ((String) -> Void)?

    private let session = AVCaptureSession()
    /// セッション構成・フレーム解析用の直列キュー（メインスレッドを塞がない）
    private let sessionQueue = DispatchQueue(label: "io.github.boyaki-machine.Thoth.camera-qr", qos: .userInitiated)
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private let previewContainer = NSView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let openSettingsButton = NSButton()
    private let cancelButton = NSButton()
    /// 直近のデコード実行時刻（フレームごとの解析を 0.3 秒間隔に間引く）
    private var lastDecodeTime: CFTimeInterval = 0
    /// 読み取り成功後の二重コールバック・二重 dismiss を防ぐ（sessionQueue 上でのみ触る）
    private var didScan = false

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 420))
        setupUI()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        startAccordingToPermission()
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        // キャンセル・Esc・読み取り成功のいずれで閉じてもここを通り、カメラを確実に停止する
        sessionQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        previewLayer?.frame = previewContainer.bounds
        previewLayer?.contentsScale = view.window?.backingScaleFactor ?? 2
    }

    override func cancelOperation(_ sender: Any?) {
        closeSelf()
    }

    private func closeSelf() {
        if presentingViewController != nil {
            presentingViewController?.dismiss(self)
        } else {
            view.window?.performClose(self)
        }
    }

    // MARK: - Permission

    /// カメラ権限の状態に応じて、セッション開始・権限要求・設定誘導を行う
    private func startAccordingToPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndStartSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.configureAndStartSession()
                    } else {
                        self?.showPermissionDenied()
                    }
                }
            }
        default:
            showPermissionDenied()
        }
    }

    private func showPermissionDenied() {
        statusLabel.stringValue = L10n.cameraQRPermissionDenied
        statusLabel.textColor = .systemRed
        openSettingsButton.isHidden = false
    }

    /// システム設定の「プライバシーとセキュリティ > カメラ」を開く
    @objc private func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func cancelAction() {
        closeSelf()
    }

    // MARK: - Capture Session

    /// カメラ入力とフレーム出力を構成してセッションを開始する
    private func configureAndStartSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device),
                  self.session.canAddInput(input) else {
                DispatchQueue.main.async { [weak self] in
                    self?.statusLabel.stringValue = L10n.cameraQRNoCamera
                    self?.statusLabel.textColor = .systemRed
                }
                return
            }
            self.session.beginConfiguration()
            self.session.sessionPreset = .high
            self.session.addInput(input)

            let output = AVCaptureVideoDataOutput()
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: self.sessionQueue)
            if self.session.canAddOutput(output) {
                self.session.addOutput(output)
            }
            self.session.commitConfiguration()
            self.session.startRunning()

            DispatchQueue.main.async { [weak self] in
                self?.attachPreviewLayer()
                self?.statusLabel.stringValue = L10n.cameraQRGuide
                self?.statusLabel.textColor = .secondaryLabelColor
            }
        }
    }

    private func attachPreviewLayer() {
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = previewContainer.bounds
        layer.contentsScale = view.window?.backingScaleFactor ?? 2
        previewContainer.layer?.addSublayer(layer)
        previewLayer = layer
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CPYCameraQRScannerViewController: AVCaptureVideoDataOutputSampleBufferDelegate {

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // sessionQueue 上で呼ばれる。0.3 秒間隔に間引いて Vision デコードを行う
        let now = CACurrentMediaTime()
        guard !didScan, now - lastDecodeTime > 0.3 else { return }
        lastDecodeTime = now

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let payload = QRDecodeService.decodeQRPayload(from: pixelBuffer) else { return }

        guard let password = CryptoPasswordQRCodec.decode(payload) else {
            // QR は写っているが指紋パスワード QR ではない（otpauth 等）→ 読み取りは継続
            DispatchQueue.main.async { [weak self] in
                self?.statusLabel.stringValue = L10n.cameraQRWrongPayload
                self?.statusLabel.textColor = .systemRed
            }
            return
        }
        didScan = true
        DispatchQueue.main.async { [weak self] in
            self?.onScan?(password)
            self?.closeSelf()
        }
    }
}

// MARK: - UI Setup

fileprivate extension CPYCameraQRScannerViewController {

    func setupUI() {
        let titleLabel = NSTextField(labelWithString: L10n.cameraQRTitle)
        titleLabel.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        previewContainer.wantsLayer = true
        previewContainer.layer?.backgroundColor = NSColor.black.cgColor
        previewContainer.layer?.cornerRadius = 6
        previewContainer.layer?.masksToBounds = true
        previewContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(previewContainer)

        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.maximumNumberOfLines = 2
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)

        // 権限拒否時のみ表示するシステム設定誘導ボタン
        openSettingsButton.title = L10n.cameraQROpenSettings
        openSettingsButton.bezelStyle = .rounded
        openSettingsButton.target = self
        openSettingsButton.action = #selector(openSystemSettings)
        openSettingsButton.isHidden = true
        openSettingsButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(openSettingsButton)

        cancelButton.title = L10n.cancel
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1B}"
        cancelButton.target = self
        cancelButton.action = #selector(cancelAction)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cancelButton)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20),

            previewContainer.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            previewContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            previewContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            previewContainer.heightAnchor.constraint(equalToConstant: 300),

            statusLabel.topAnchor.constraint(equalTo: previewContainer.bottomAnchor, constant: 10),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            openSettingsButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            openSettingsButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),

            cancelButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            cancelButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16)
        ])
    }
}
