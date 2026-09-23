import Quick
import Nimble
import AppKit
@testable import Thoth

/// 調査用のデバッグ情報（ベータ機能「デバッグ情報を保存する」）のスペック。
/// 利用者が有効にしたときだけ記録すること、記録に内容・項目名・アプリ名が入り込まないこと
/// （記録できる出来事が文字列を持たないこと）、本人だけが読める権限で保存し、消せることを固定する。
/// 実際の ~/Library/Logs は使わず、テストごとの一時フォルダに書く
class DebugLogSpec: QuickSpec {

    /// すべての出来事の例（ケースを足したらここにも足す）
    static let allEventSamples: [DebugEvent] = [
        .pasteNoReturnTarget(delay: 0.15),
        .pasteActivationRequested(requested: true, accessibilityTrusted: true),
        .pasteReady(ready: true, elapsed: 0.21, frontmostIsTarget: true, keyboardFocus: .unknown),
        .pasteCommandDisabled,
        .pasteAccessibilityMissing,
        .pastePosted(keyCode: 9, thothActive: false),
        .pasteSettled(thothActive: false, frontmostIsTarget: true),
        .preferencesFocusRestored,
        .secureHotKeyReceived(secureInput: true),
        .secureInfoWindowVisible,
        .securePickerAlreadyVisible,
        .secureStaleFlagReset,
        .secureIgnoredWhileAuthenticating,
        .secureAuthenticationSkipped,
        .secureAuthenticationUnavailable(code: -6),
        .secureAuthenticationRequested,
        .secureAuthenticationError(isLocalAuthenticationError: true, code: -2),
        .secureAuthenticationFinished(success: true),
        .securePickerShowRequested,
        .securePickerShown(visible: true, key: false, thothActive: false),
        .securePickerState(onScreen: true, level: 1000, hasReturnTarget: true)
    ]

    override class func spec() {
        eventSpecs()
        fileSpecs()
    }

    // MARK: - 記録できる出来事
    private static func eventSpecs() {
        describe("記録できる出来事（DebugEvent）") {
            it("どの出来事も文字列を持たない（内容・項目名・アプリ名が型の上で入り込めない）") {
                func containsString(_ value: Any) -> Bool {
                    if value is String || value is Substring || value is NSString { return true }
                    return Mirror(reflecting: value).children.contains { containsString($0.value) }
                }
                for event in allEventSamples {
                    expect(containsString(event)).to(beFalse(), description: "\(event)")
                }
            }

            it("どの出来事も、分類と 1 行の説明を持つ") {
                for event in allEventSamples {
                    expect(["Paste", "SecureMenu"]).to(contain(event.category))
                    expect(event.message.isEmpty) == false
                    expect(event.message.contains("\n")) == false
                }
            }

            it("貼り付け先の判定はアプリの識別子ではなく、真偽値とフォーカスの区分で書く") {
                let message = DebugEvent.pasteReady(ready: false, elapsed: 1.0, frontmostIsTarget: false, keyboardFocus: .other).message
                expect(message) == "ready=false after 1.000s frontmostIsTarget=false keyboardFocus=other"
            }
        }
    }

    // MARK: - ファイル
    private static func fileSpecs() {
        describe("デバッグ情報のファイル") {
            var directory: URL!
            var enabled = false
            var log: DebugLog!

            beforeEach {
                directory = FileManager.default.temporaryDirectory
                    .appendingPathComponent("ThothDebugLogSpec-\(UUID().uuidString)/Logs/Thoth", isDirectory: true)
                enabled = false
                log = DebugLog(directory: directory, maxFileSize: 400) { enabled }
            }
            afterEach {
                try? FileManager.default.removeItem(at: directory.deletingLastPathComponent().deletingLastPathComponent())
            }

            it("オフ（既定）の間は何も書かない。フォルダも作らない") {
                log.record(.secureAuthenticationRequested)
                log.waitUntilIdle()
                expect(FileManager.default.fileExists(atPath: directory.path)) == false
            }

            it("オンのときは時刻・分類・説明を 1 行ずつ追記する") {
                enabled = true
                log.record(.secureHotKeyReceived(secureInput: true))
                log.record(.secureAuthenticationFinished(success: false))
                log.waitUntilIdle()
                let lines = (try? String(contentsOf: log.fileURL, encoding: .utf8))?.split(separator: "\n") ?? []
                expect(lines.count) == 2
                expect(lines.first?.hasSuffix("[SecureMenu] hotkey received (secureInput=true)")) == true
                expect(lines.last?.hasSuffix("[SecureMenu] authentication finished: success=false")) == true
            }

            it("本人だけが読める権限で保存する（フォルダ 0700・ファイル 0600）") {
                enabled = true
                log.record(.pasteCommandDisabled)
                log.waitUntilIdle()
                let directoryPermissions = (try? FileManager.default.attributesOfItem(atPath: directory.path))?[.posixPermissions] as? Int
                let filePermissions = (try? FileManager.default.attributesOfItem(atPath: log.fileURL.path))?[.posixPermissions] as? Int
                expect(directoryPermissions) == 0o700
                expect(filePermissions) == 0o600
            }

            it("上限を超えたら 1 世代だけ残して新しく始める（際限なく大きくならない）") {
                enabled = true
                for _ in 0..<40 { log.record(.securePickerShowRequested) }
                log.waitUntilIdle()
                let size = (try? FileManager.default.attributesOfItem(atPath: log.fileURL.path))?[.size] as? Int ?? 0
                expect(size) <= 400 + 100
                expect(FileManager.default.fileExists(atPath: log.rotatedFileURL.path)) == true
                let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
                expect(Set(files)) == ["debug.log", "debug.1.log"]
            }

            it("消すと、世代を含めて保存済みのファイルが無くなる") {
                enabled = true
                for _ in 0..<40 { log.record(.securePickerShowRequested) }
                log.deleteAll()
                log.waitUntilIdle()
                expect(FileManager.default.fileExists(atPath: log.fileURL.path)) == false
                expect(FileManager.default.fileExists(atPath: log.rotatedFileURL.path)) == false
            }
        }

        describe("環境設定（ベータ機能タブ）") {
            typealias BetaVC = CPYBetaPreferenceViewController

            it("「デバッグ情報を保存する」は既定でオフ") {
                let registered = UserDefaults.standard.volatileDomain(forName: UserDefaults.registrationDomain)
                expect(registered[Constants.Beta.saveDebugLog] as? Bool) == false
            }

            it("最下段にチェックボックス・表示ボタン・説明があり、既存の項目と重ならない") {
                let viewController = BetaVC(nibName: "CPYBetaPreferenceViewController", bundle: Bundle(for: AppDelegate.self))
                let view = viewController.view
                let ids = [BetaVC.ViewID.debugLogCheckbox, BetaVC.ViewID.debugLogShowButton, BetaVC.ViewID.debugLogNote]
                let debugViews = ids.compactMap { id in view.subviews.first { $0.identifier == id } }
                expect(debugViews.count) == 3
                let sectionTop = debugViews.map { $0.frame.maxY }.max() ?? 0
                let others = view.subviews.filter { subview in !ids.contains { $0 == subview.identifier } }
                expect(others.map { $0.frame.minY }.min() ?? 0) >= sectionTop
                expect(view.frame.height) == 272 + BetaVC.debugLogSectionHeight
                // どの部品もタブの中に収まる（上へ二重にずれてツールバーに重ならない）
                for subview in view.subviews {
                    expect(subview.frame.maxY).to(beLessThanOrEqualTo(view.bounds.height), description: "\(subview)")
                    expect(subview.frame.minY) >= 0
                }
                // Xib の一番上の注意書きは、元の上端からの距離（272 - 255 = 17pt）を保つ
                expect((others.map { $0.frame.maxY }.max() ?? 0)) == view.bounds.height - 17
            }

            it("説明文はどの言語でも枠に収まる（何を保存しないかが見切れない）") {
                let bundle = Bundle(for: AppDelegate.self)
                var checked = 0
                for localization in bundle.localizations {
                    guard let path = bundle.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: localization),
                          let table = NSDictionary(contentsOfFile: path) as? [String: String],
                          let note = table["Beta Debug Log Note"] else { continue }
                    let field = NSTextField(wrappingLabelWithString: note)
                    field.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
                    let size = BetaVC.debugLogNoteSize
                    let height = field.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: size.width, height: 1000)).height ?? .infinity
                    expect(height).to(beLessThanOrEqualTo(size.height), description: "\(localization)")
                    checked += 1
                }
                expect(checked) >= 6
            }
        }
    }
}
