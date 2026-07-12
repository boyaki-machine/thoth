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

    // MARK: - View Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupLanguageSwitcher()
    }

    // MARK: - Language Switcher

    /// ジョーク言語（ラテン語・ヒエログリフ）切替 UI をタブ下部に追加する。
    /// これらの言語は macOS のシステム言語リストから選べないため、
    /// アプリドメインの AppleLanguages を直接上書きして切り替える
    private func setupLanguageSwitcher() {
        let label = NSTextField(labelWithString: L10n.betaLanguage)
        label.frame = NSRect(x: 59, y: 30, width: 160, height: 17)
        label.autoresizingMask = [.maxXMargin, .minYMargin]
        view.addSubview(label)

        languagePopUp.frame = NSRect(x: 226, y: 25, width: 198, height: 26)
        languagePopUp.autoresizingMask = [.maxXMargin, .minYMargin]
        JokeLanguage.allCases.forEach { languagePopUp.addItem(withTitle: $0.title) }
        languagePopUp.target = self
        languagePopUp.action = #selector(languageChanged(_:))
        languagePopUp.selectItem(at: currentJokeLanguage().rawValue)
        view.addSubview(languagePopUp)
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
