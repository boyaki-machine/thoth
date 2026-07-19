import Quick
import Nimble
@testable import Thoth

/// 指紋パスワードの QR コーデック（エンコード・デコード・QR 画像生成）のテスト。
/// QR 画像の生成→デコードのラウンドトリップは Vision を用いるがヘッドレスで動作する
class CryptoPasswordQRCodecSpec: QuickSpec {

    override func spec() {
        encodeDecodeSpecs()
        rejectionSpecs()
        qrImageSpecs()
    }

    // MARK: - Encode / Decode

    private func encodeDecodeSpecs() {
        describe("エンコードとデコード") {
            it("エンコードは接頭辞 thoth-cpw:v1: を付与する") {
                expect(CryptoPasswordQRCodec.encode("abc")) == "thoth-cpw:v1:abc"
            }

            it("エンコードした文字列をデコードすると元のパスワードに戻る") {
                let passwords = [
                    "simplePassword123",
                    "with symbols !@#$%^&*()_+-=[]{}|;'\",.<>/?`~",
                    "colon:inside:password",           // パスワード内の : を許容すること
                    "日本語パスワード🔐絵文字",
                    String(repeating: "Ab1:", count: 32)  // 128 文字
                ]
                for password in passwords {
                    expect(CryptoPasswordQRCodec.decode(CryptoPasswordQRCodec.encode(password))) == password
                }
            }
        }
    }

    // MARK: - Rejection

    private func rejectionSpecs() {
        describe("不正ペイロードの拒否") {
            it("otpauth URI（TOTP の QR）は拒否する") {
                expect(CryptoPasswordQRCodec.decode("otpauth://totp/Example:user?secret=ABCDEF")).to(beNil())
            }

            it("接頭辞のない生の文字列は拒否する") {
                expect(CryptoPasswordQRCodec.decode("plainPassword")).to(beNil())
            }

            it("バージョンの異なる接頭辞は拒否する") {
                expect(CryptoPasswordQRCodec.decode("thoth-cpw:v2:abc")).to(beNil())
            }

            it("接頭辞は大文字小文字を区別する") {
                expect(CryptoPasswordQRCodec.decode("THOTH-CPW:V1:abc")).to(beNil())
            }

            it("接頭辞のみで空パスワードの場合は拒否する") {
                expect(CryptoPasswordQRCodec.decode("thoth-cpw:v1:")).to(beNil())
            }
        }
    }

    // MARK: - QR Image Round-trip

    private func qrImageSpecs() {
        describe("QR 画像の生成とラウンドトリップ") {
            it("生成した QR 画像をデコードすると元のパスワードに戻る") {
                let password = "Th0th-P@ssw0rd:2026!"
                guard let image = CryptoPasswordQRCodec.generateQRImage(for: password) else {
                    fail("QR 画像の生成に失敗")
                    return
                }
                let payload = QRDecodeService.decodeQRPayload(from: image)
                expect(payload) == CryptoPasswordQRCodec.encode(password)
                expect(payload.flatMap { CryptoPasswordQRCodec.decode($0) }) == password
            }

            it("長いパスワード（200 文字）でもラウンドトリップできる") {
                let password = String(repeating: "aB3#", count: 50)
                guard let image = CryptoPasswordQRCodec.generateQRImage(for: password) else {
                    fail("QR 画像の生成に失敗")
                    return
                }
                let payload = QRDecodeService.decodeQRPayload(from: image)
                expect(payload.flatMap { CryptoPasswordQRCodec.decode($0) }) == password
            }

            it("生成画像は指定した最小ピクセルサイズ以上になる") {
                guard let image = CryptoPasswordQRCodec.generateQRImage(for: "abc", minimumPixelSize: 320),
                      let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                    fail("QR 画像の生成に失敗")
                    return
                }
                expect(cgImage.width) >= 320
            }

            it("空パスワードでは QR を生成しない") {
                expect(CryptoPasswordQRCodec.generateQRImage(for: "")).to(beNil())
            }

            it("QR の容量を超えるペイロードでは nil を返す") {
                let oversized = String(repeating: "x", count: 3000)
                expect(CryptoPasswordQRCodec.generateQRImage(for: oversized)).to(beNil())
            }
        }
    }
}
