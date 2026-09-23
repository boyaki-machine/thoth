//
//  CPYBetaPreferenceViewController.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Econa77 on 2016/06/28.
//
//  Copyright © 2015-2018 Clipy Project.
//

import Cocoa

final class CPYBetaPreferenceViewController: NSViewController {

    // MARK: - Joke Language

    /// ジョーク言語の選択肢。rawValue はポップアップの項目インデックスに対応する
    private enum JokeLanguage: Int, CaseIterable {
        case systemDefault = 0
        case latin
        case hieroglyphs

        /// AppleLanguages に書き込む言語コード（nil = システム標準 = 上書きなし）
        var code: String? {
            switch self {
            case .systemDefault: return nil
            case .latin: return "la"
            case .hieroglyphs: return "egy"
            }
        }

        var title: String {
            switch self {
            case .systemDefault: return L10n.betaLanguageSystemDefault
            case .latin: return L10n.betaLanguageLatin
            case .hieroglyphs: return L10n.betaLanguageHieroglyphs
            }
        }
    }

    private let languagePopUp = NSPopUpButton()

    /// テストから部品を探すための識別子
    enum ViewID {
        static let debugLogCheckbox = NSUserInterfaceItemIdentifier("beta.debugLogCheckbox")
        static let debugLogNote = NSUserInterfaceItemIdentifier("beta.debugLogNote")
        static let debugLogShowButton = NSUserInterfaceItemIdentifier("beta.debugLogShowButton")
    }

    /// 最下段の「デバッグ情報を保存する」のために、タブを下へ広げる高さ
    static let debugLogSectionHeight: CGFloat = 88
    /// 説明文の枠（どの言語でも 4 行まで収まる大きさ。DebugLogSpec が確かめる）
    static let debugLogNoteSize = NSSize(width: 347, height: 58)

    // MARK: - View Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        makeRoomForDebugLogSection()
        setupLanguageSwitcher()
        setupDebugLogSection()
    }

    // MARK: - Language Switcher

    /// ジョーク言語（ラテン語・ヒエログリフ）切替 UI をタブ下部に追加する。
    /// これらの言語は macOS のシステム言語リストから選べないため、
    /// アプリドメインの AppleLanguages を直接上書きして切り替える
    private func setupLanguageSwitcher() {
        let label = NSTextField(labelWithString: L10n.betaLanguage)
        label.frame = NSRect(x: 59, y: 30 + Self.debugLogSectionHeight, width: 160, height: 17)
        label.autoresizingMask = [.maxXMargin, .minYMargin]
        view.addSubview(label)

        languagePopUp.frame = NSRect(x: 226, y: 25 + Self.debugLogSectionHeight, width: 198, height: 26)
        languagePopUp.autoresizingMask = [.maxXMargin, .minYMargin]
        JokeLanguage.allCases.forEach { languagePopUp.addItem(withTitle: $0.title) }
        languagePopUp.target = self
        languagePopUp.action = #selector(languageChanged(_:))
        languagePopUp.selectItem(at: currentJokeLanguage().rawValue)
        view.addSubview(languagePopUp)
    }

    // MARK: - Debug Log

    /// Xib で組んだ部品を上へずらし、タブを下へ広げて最下段の場所を作る
    private func makeRoomForDebugLogSection() {
        let extra = Self.debugLogSectionHeight
        view.subviews.forEach { $0.frame.origin.y += extra }
        view.setFrameSize(NSSize(width: view.frame.width, height: view.frame.height + extra))
    }

    /// 「デバッグ情報を保存する」。利用者が知らないうちに行動を記録しないよう、既定はオフで、
    /// 何を保存して何を保存しないかをその場に書く。「表示」で保存中の中身をいつでも確かめられる
    private func setupDebugLogSection() {
        let checkbox = NSButton(checkboxWithTitle: L10n.betaDebugLog, target: nil, action: nil)
        checkbox.identifier = ViewID.debugLogCheckbox
        checkbox.frame = NSRect(x: 59, y: 66, width: 290, height: 18)
        checkbox.autoresizingMask = [.maxXMargin, .minYMargin]
        checkbox.bind(.value, to: NSUserDefaultsController.shared,
                      withKeyPath: "values.\(Constants.Beta.saveDebugLog)", options: nil)
        view.addSubview(checkbox)

        let showButton = NSButton(title: L10n.betaDebugLogShow, target: self, action: #selector(showDebugLog))
        showButton.identifier = ViewID.debugLogShowButton
        showButton.bezelStyle = .rounded
        showButton.controlSize = .small
        showButton.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        showButton.sizeToFit()
        showButton.frame.origin = NSPoint(x: 424 - showButton.frame.width, y: 63)
        showButton.autoresizingMask = [.maxXMargin, .minYMargin]
        view.addSubview(showButton)

        let note = NSTextField(wrappingLabelWithString: L10n.betaDebugLogNote)
        note.identifier = ViewID.debugLogNote
        note.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        note.textColor = .secondaryLabelColor
        note.frame = NSRect(origin: NSPoint(x: 77, y: 4), size: Self.debugLogNoteSize)
        note.autoresizingMask = [.maxXMargin, .minYMargin]
        view.addSubview(note)
    }

    /// 保存中のデバッグ情報を Finder で示す（まだ無ければフォルダを開く）
    @objc private func showDebugLog() {
        let log = DebugLog.shared
        if FileManager.default.fileExists(atPath: log.fileURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([log.fileURL])
        } else {
            let alert = NSAlert()
            alert.messageText = L10n.betaDebugLogEmpty
            alert.addButton(withTitle: L10n.close)
            if let window = view.window { alert.beginSheetModal(for: window) }
        }
    }

    /// 現在アプリドメインに設定されているジョーク言語を返す。
    /// UserDefaults.standard.array(forKey:) はグローバルドメイン（システム言語）も
    /// 返してしまうため、アプリドメインの永続値だけを見る
    private func currentJokeLanguage() -> JokeLanguage {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier,
              let domain = UserDefaults.standard.persistentDomain(forName: bundleIdentifier),
              let first = (domain["AppleLanguages"] as? [String])?.first else { return .systemDefault }
        switch first {
        case "la": return .latin
        case "egy": return .hieroglyphs
        default: return .systemDefault
        }
    }

    @objc private func languageChanged(_ sender: NSPopUpButton) {
        let selected = JokeLanguage(rawValue: sender.indexOfSelectedItem) ?? .systemDefault
        let defaults = UserDefaults.standard
        if let code = selected.code {
            // ジョーク言語に無いキーや OS 標準ダイアログのために、
            // システムの優先言語をフォールバックとして後ろに残す
            let fallback = Locale.preferredLanguages.filter { language in
                language != "la" && language != "egy"
                    && !language.hasPrefix("la-") && !language.hasPrefix("egy-")
            }
            defaults.set([code] + fallback, forKey: "AppleLanguages")
        } else {
            defaults.removeObject(forKey: "AppleLanguages")
        }
        promptRestart()
    }

    /// 言語は起動時に確定するため、再起動を促す
    private func promptRestart() {
        guard let window = view.window else { return }
        let alert = NSAlert()
        alert.messageText = L10n.betaLanguageRestartMessage
        alert.addButton(withTitle: L10n.betaLanguageRestartNow)
        alert.addButton(withTitle: L10n.close)
        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            UserDefaults.standard.synchronize()
            CodeSignService.relaunch()
        }
    }
}
