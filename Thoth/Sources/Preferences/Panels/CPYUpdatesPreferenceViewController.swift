//
//  CPYUpdatesPreferenceViewController.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Econa77 on 2016/03/17.
//
//  Copyright © 2015-2018 Clipy Project.
//

import Cocoa

/// フォーク元であるオリジナル Clipy への謝辞とリポジトリリンクを表示するタブ。
/// （個人フォークのため、Sparkle による自動アップデート確認機能は撤去済み）
class CPYUpdatesPreferenceViewController: NSViewController {

    // MARK: - View Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    // MARK: - Actions
    @objc private func openOriginalRepository() {
        NSWorkspace.shared.open(Constants.Application.originalRepositoryURL)
    }
}

// MARK: - Layout
fileprivate extension CPYUpdatesPreferenceViewController {
    func setupUI() {
        // オリジナル Clipy へのリスペクト文章
        let messageLabel = NSTextField(wrappingLabelWithString: L10n.updatesRespectMessage)
        messageLabel.alignment = .center
        messageLabel.frame = NSRect(x: 40, y: 78, width: 400, height: 100)
        messageLabel.autoresizingMask = [.maxXMargin, .minYMargin]
        view.addSubview(messageLabel)

        // リンクの説明ラベル
        let linkCaptionLabel = NSTextField(labelWithString: L10n.updatesOriginalRepositoryLink)
        linkCaptionLabel.alignment = .center
        linkCaptionLabel.frame = NSRect(x: 40, y: 56, width: 400, height: 17)
        linkCaptionLabel.autoresizingMask = [.maxXMargin, .minYMargin]
        view.addSubview(linkCaptionLabel)

        // オリジナルリポジトリへのリンク
        let linkButton = NSButton(title: "", target: self, action: #selector(openOriginalRepository))
        linkButton.isBordered = false
        linkButton.attributedTitle = NSAttributedString(
            string: Constants.Application.originalRepositoryURL.absoluteString,
            attributes: [
                .foregroundColor: NSColor.linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize)
            ])
        linkButton.frame = NSRect(x: 40, y: 36, width: 400, height: 20)
        linkButton.autoresizingMask = [.maxXMargin, .minYMargin]
        view.addSubview(linkButton)
        // バージョン表記は「バージョン」タブ（CPYVersionPreferenceViewController）へ移設
    }
}
