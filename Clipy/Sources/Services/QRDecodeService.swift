//
//  QRDecodeService.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Copyright © 2015-2018 Clipy Project.
//

import Foundation
import AppKit
import Vision

/// QR コードから TOTP の `otpauth://` URI / secret を取り込むためのユーティリティ。
/// デコードは Vision（macOS 10.13+）で行い、追加の権限を必要としない。
enum QRDecodeService {

    // MARK: - Image Decoding

    /// CGImage から最初に見つかった QR コードのペイロード文字列を返す。
    /// `otpauth://` を優先し、無ければ最初の QR の内容を返す。
    static func decodeQRPayload(from cgImage: CGImage) -> String? {
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        let observations = (request.results as [VNBarcodeObservation]?) ?? []
        let payloads = observations.compactMap { $0.payloadStringValue }
        if let otpauth = payloads.first(where: { $0.lowercased().hasPrefix("otpauth://") }) {
            return otpauth
        }
        return payloads.first
    }

    /// NSImage から QR ペイロードを取り出す。
    static func decodeQRPayload(from image: NSImage) -> String? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return decodeQRPayload(from: cgImage)
    }

    // MARK: - Clipboard

    /// クリップボードから TOTP として使える文字列を取り出す。
    /// テキスト（otpauth URI / secret）を優先し、無ければ画像から QR をデコードする。
    static func otpAuthFromClipboard() -> String? {
        let pasteboard = NSPasteboard.general
        // 1. テキスト
        if let text = pasteboard.string(forType: .string), TOTPService.isValid(text) {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // 2. 画像から QR
        if let image = NSImage(pasteboard: pasteboard),
           let payload = decodeQRPayload(from: image) {
            return payload
        }
        return nil
    }

    // MARK: - Interactive Screen Capture

    /// `screencapture -i` で範囲選択キャプチャを行い、その画像から QR をデコードする。
    /// OS 標準の範囲選択 UI を用いるため、アプリ自身に画面収録権限を要求しない。
    /// ユーザーがキャンセルした場合やデコード失敗時は nil を返す（completion はメインスレッド）。
    static func captureAndDecode(completion: @escaping (String?) -> Void) {
        let tmpPath = NSTemporaryDirectory() + "clipy-totp-qr-\(UUID().uuidString).png"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-x", tmpPath]  // -i: 範囲選択, -x: シャッター音なし
        process.terminationHandler = { _ in
            DispatchQueue.main.async {
                defer { try? FileManager.default.removeItem(atPath: tmpPath) }
                // ユーザーがキャンセルするとファイルは生成されない
                guard FileManager.default.fileExists(atPath: tmpPath),
                      let image = NSImage(contentsOfFile: tmpPath) else {
                    completion(nil)
                    return
                }
                completion(decodeQRPayload(from: image))
            }
        }
        do {
            try process.run()
        } catch {
            DispatchQueue.main.async { completion(nil) }
        }
    }
}
