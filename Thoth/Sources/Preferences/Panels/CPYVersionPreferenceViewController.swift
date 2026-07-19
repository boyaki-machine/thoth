//
//  CPYVersionPreferenceViewController.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Copyright © 2015-2018 Clipy Project.
//

import Cocoa

/// アプリのバージョン情報を表示するタブ。
/// バージョン文字列は Info.plist（CFBundleShortVersionString）から、
/// リリース年月日は Constants.Application.releaseDate から取得する
class CPYVersionPreferenceViewController: NSViewController {

    override func loadView() {
        // 他のタブ（XIB 定義）と同じコンテンツサイズに合わせる
        view = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 374))
        setupUI()
    }
}

// MARK: - Layout
fileprivate extension CPYVersionPreferenceViewController {
    func setupUI() {
        // バージョン表記（例: Thoth ver.1.0.0）
        let versionLabel = NSTextField(labelWithString: "\(Constants.Application.name) ver.\(Bundle.main.appVersion ?? "")")
        versionLabel.alignment = .center
        versionLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        versionLabel.frame = NSRect(x: 40, y: 205, width: 400, height: 30)
        versionLabel.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin]
        view.addSubview(versionLabel)

        // リリース年月日
        let releaseDateLabel = NSTextField(labelWithString: L10n.versionReleaseDate(Constants.Application.releaseDate))
        releaseDateLabel.alignment = .center
        releaseDateLabel.font = .systemFont(ofSize: NSFont.systemFontSize)
        releaseDateLabel.textColor = .secondaryLabelColor
        releaseDateLabel.frame = NSRect(x: 40, y: 178, width: 400, height: 20)
        releaseDateLabel.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin]
        view.addSubview(releaseDateLabel)
    }
}
