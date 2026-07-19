//
//  CryptoPasswordQRService.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Copyright © 2015-2018 Clipy Project.
//

import Foundation
import AppKit
import CoreImage

/// 指紋パスワード（ファイル暗号化の固定パスワード）を QR コードで持ち運ぶための
/// エンコード・デコード・画像生成ユーティリティ。
///
/// ## ペイロード形式
/// `thoth-cpw:v1:<パスワード>` という接頭辞付き文字列を QR に埋め込む。
/// 読み取り側は接頭辞を検証することで、無関係な QR（TOTP の otpauth URI 等）の
/// 誤取り込みを防ぐ。接頭辞にバージョンを含めるため、将来形式を変えても判別できる。
///
/// ## 利用の流れ
/// 1. 指紋パスワード管理シートが `generateQRImage` で QR を表示
/// 2. 利用者がスマートフォンで撮影して持ち運ぶ
/// 3. 別端末で `CPYCameraQRScannerViewController` がカメラから読み取り、
///    `decode` で検証してパスワード欄に反映する
enum CryptoPasswordQRCodec {

    /// QR ペイロードの接頭辞（バージョン付き・大文字小文字を区別する）
    static let prefix = "thoth-cpw:v1:"

    // MARK: - Payload

    /// パスワードを QR ペイロード文字列にエンコードする
    static func encode(_ password: String) -> String {
        return prefix + password
    }

    /// ペイロードを検証し、接頭辞が一致すればパスワードを返す。
    /// 接頭辞不一致（otpauth 等）・空パスワードは nil。
    /// パスワード自体に `:` が含まれても正しく扱えるよう、分割ではなく接頭辞除去で取り出す
    static func decode(_ payload: String) -> String? {
        guard payload.hasPrefix(prefix) else { return nil }
        let password = String(payload.dropFirst(prefix.count))
        guard !password.isEmpty else { return nil }
        return password
    }

    // MARK: - QR Image Generation

    /// パスワードから QR コード画像を生成する（訂正レベル "M"）。
    /// スマートフォンのカメラで確実に読めるよう、最近傍補間の整数倍スケールで
    /// 拡大しモジュール境界のシャープさを保つ。
    /// - Parameter minimumPixelSize: 出力画像の最小ピクセル幅（既定 320）
    /// - Returns: 生成失敗時（QR 容量超過など）は nil
    static func generateQRImage(for password: String, minimumPixelSize: CGFloat = 320) -> NSImage? {
        guard !password.isEmpty else { return nil }
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(encode(password).utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage, output.extent.width > 0 else { return nil }

        let scale = max(1, ceil(minimumPixelSize / output.extent.width))
        let scaled = output.samplingNearest()
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cgImage = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: scaled.extent.width, height: scaled.extent.height))
    }
}
