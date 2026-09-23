//
//  DebugLog.swift
//
//  Thoth
//
//  利用者が有効にしたときだけ、不具合の調査用に操作の段階をファイルへ残す
//

import Foundation

/// 調査用に記録できる出来事。**記録できるのはここに挙げた種類と、真偽値・数値だけ。**
///
/// 文字列を受け取るケースを作らないこと。コピーした内容・セキュアアイテムの値や項目名・
/// 使っていたアプリの名前やバンドル ID・ファイル名が紛れ込む経路を、型で塞いでいる
/// （`DebugLogSpec` が、どのケースも文字列を持たないことを確かめる）。
enum DebugEvent: Equatable {
    /// キーボードフォーカスの持ち主が、貼り付け先か
    enum KeyboardFocus: String, Equatable {
        case target, other, unknown
    }

    // MARK: 貼り付け（前面化と ⌘V・キー入力の送出）
    case pasteNoReturnTarget(delay: Double)
    case pasteActivationRequested(requested: Bool, accessibilityTrusted: Bool)
    case pasteReady(ready: Bool, elapsed: Double, frontmostIsTarget: Bool, keyboardFocus: KeyboardFocus)
    case pasteCommandDisabled
    case pasteAccessibilityMissing
    case pastePosted(keyCode: Int, thothActive: Bool)

    // MARK: セキュアメニュー（ホットキー → 認証 → パネル）
    case secureHotKeyReceived(secureInput: Bool)
    case secureInfoWindowVisible
    case securePickerAlreadyVisible
    case secureStaleFlagReset
    case secureIgnoredWhileAuthenticating
    case secureAuthenticationSkipped
    case secureAuthenticationUnavailable(code: Int)
    case secureAuthenticationRequested
    case secureAuthenticationError(isLocalAuthenticationError: Bool, code: Int)
    case secureAuthenticationFinished(success: Bool)
    case securePickerShowRequested
    case securePickerShown(visible: Bool, key: Bool, thothActive: Bool)
    case securePickerState(onScreen: Bool, level: Int, hasReturnTarget: Bool)

    var category: String {
        switch self {
        case .pasteNoReturnTarget, .pasteActivationRequested, .pasteReady, .pasteCommandDisabled,
             .pasteAccessibilityMissing, .pastePosted:
            return "Paste"
        default:
            return "SecureMenu"
        }
    }

    var message: String {
        switch self {
        case .pasteNoReturnTarget(let delay):
            return "no return target; sending after \(Self.seconds(delay))"
        case let .pasteActivationRequested(requested, trusted):
            return "activate return target: requested=\(requested) accessibilityTrusted=\(trusted)"
        case let .pasteReady(ready, elapsed, frontmostIsTarget, focus):
            return "ready=\(ready) after \(Self.seconds(elapsed)) frontmostIsTarget=\(frontmostIsTarget) keyboardFocus=\(focus.rawValue)"
        case .pasteCommandDisabled:
            return "paste: ⌘V input is turned off in Preferences"
        case .pasteAccessibilityMissing:
            return "paste: accessibility permission is missing"
        case let .pastePosted(keyCode, thothActive):
            return "paste: posted ⌘V (keyCode \(keyCode)) thothActive=\(thothActive)"
        case .secureHotKeyReceived(let secureInput):
            return "hotkey received (secureInput=\(secureInput))"
        case .secureInfoWindowVisible:
            return "secure info window is visible; activating it instead of the picker"
        case .securePickerAlreadyVisible:
            return "picker already visible; re-activating it"
        case .secureStaleFlagReset:
            return "stale active flag (picker not visible); resetting"
        case .secureIgnoredWhileAuthenticating:
            return "ignored: authentication is in progress"
        case .secureAuthenticationSkipped:
            return "authentication skipped (within the grace period)"
        case .secureAuthenticationUnavailable(let code):
            return "authentication unavailable: \(code)"
        case .secureAuthenticationRequested:
            return "authentication requested"
        case let .secureAuthenticationError(isLAError, code):
            return "authentication error: localAuthentication=\(isLAError) code=\(code)"
        case .secureAuthenticationFinished(let success):
            return "authentication finished: success=\(success)"
        case .securePickerShowRequested:
            return "picker show requested"
        case let .securePickerShown(visible, key, thothActive):
            return "picker shown: visible=\(visible) key=\(key) thothActive=\(thothActive)"
        case let .securePickerState(onScreen, level, hasReturnTarget):
            return "picker state: onScreen=\(onScreen) level=\(level) hasReturnTarget=\(hasReturnTarget)"
        }
    }

    private static func seconds(_ value: Double) -> String {
        return String(format: "%.3fs", value)
    }
}

/// 利用者が環境設定（ベータ機能 >「デバッグ情報を保存する」）で有効にしたときだけ、
/// 調査用の出来事を `~/Library/Logs/Thoth/debug.log` に追記する。
///
/// セキュアな情報を扱うアプリなので、利用者が知らないうちに行動を記録しない:
/// - **既定はオフ。オフの間は何も書かない**（ファイルにも、macOS の統合ログにも）
/// - 書けるのは `DebugEvent`（真偽値・数値だけ）と時刻。内容・項目名・アプリ名は型の上で書けない
/// - ファイルは本人だけが読める権限（フォルダ 0700・ファイル 0600）。大きさは既定で 512KB までで、
///   超えたら 1 世代だけ `debug.1.log` に残して新しく始める
/// - オフにすると、保存済みのファイルを消す（`deleteAll()`。AppDelegate が設定の変化を見て呼ぶ）
final class DebugLog {

    static let shared = DebugLog()

    /// 1 ファイルの上限の既定値（超えたら 1 世代だけ残して新しく始める）
    static let defaultMaxFileSize = 512 * 1024

    let directory: URL
    let maxFileSize: Int
    private let isEnabled: () -> Bool
    private let queue = DispatchQueue(label: "io.github.boyaki-machine.Thoth.DebugLog", qos: .utility)
    private let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    var fileURL: URL { directory.appendingPathComponent("debug.log") }
    var rotatedFileURL: URL { directory.appendingPathComponent("debug.1.log") }

    init(directory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Thoth", isDirectory: true),
         maxFileSize: Int = DebugLog.defaultMaxFileSize,
         isEnabled: @escaping () -> Bool = { AppEnvironment.current.defaults.bool(forKey: Constants.Beta.saveDebugLog) }) {
        self.directory = directory
        self.maxFileSize = maxFileSize
        self.isEnabled = isEnabled
    }

    /// 有効なときだけ記録する（どのスレッドから呼んでもよい）
    func record(_ event: DebugEvent) {
        guard isEnabled() else { return }
        let line = "\(formatter.string(from: Date())) [\(event.category)] \(event.message)\n"
        queue.async { [self] in append(line) }
    }

    /// 保存済みのデバッグ情報を消す
    func deleteAll() {
        queue.async { [self] in
            try? FileManager.default.removeItem(at: fileURL)
            try? FileManager.default.removeItem(at: rotatedFileURL)
        }
    }

    /// 書き込みの完了を待つ（テスト用）
    func waitUntilIdle() {
        queue.sync {}
    }

    private func append(_ line: String) {
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true,
                                            attributes: [.posixPermissions: 0o700])
            if let size = (try? fileManager.attributesOfItem(atPath: fileURL.path))?[.size] as? Int,
               size >= maxFileSize {
                try? fileManager.removeItem(at: rotatedFileURL)
                try fileManager.moveItem(at: fileURL, to: rotatedFileURL)
            }
            if !fileManager.fileExists(atPath: fileURL.path) {
                fileManager.createFile(atPath: fileURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
            }
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(line.utf8))
        } catch {
            // 調査用の記録なので、書けなくても本来の動作は止めない
        }
    }
}
