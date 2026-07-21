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
/// バージョン文字列は Info.plist（CFBundleShortVersionString）から取得する。
/// リリース年月日は Info.plist の ThothReleaseDate から取得する。この値は
/// リリースビルド（scripts/make_dmg.sh）が git のバージョンタグ日付を
/// ビルド設定 THOTH_RELEASE_DATE として注入する。タグの無い開発ビルドでは
/// 空になり、リリース日ラベルは表示されない
class CPYVersionPreferenceViewController: NSViewController {

    /// 生成する各ビューの識別子（レイアウト検証テストから対象を特定するために付与する）
    enum ViewID {
        static let icon        = NSUserInterfaceItemIdentifier("versionAppIcon")
        static let version     = NSUserInterfaceItemIdentifier("versionText")
        static let releaseDate = NSUserInterfaceItemIdentifier("versionReleaseDate")
    }

    override func loadView() {
        // 他のタブ（XIB 定義）と同じコンテンツサイズに合わせる
        view = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 374))
        setupUI()
    }
}

// MARK: - Layout
fileprivate extension CPYVersionPreferenceViewController {
    func setupUI() {
        // アプリアイコン（バージョン文字列の上に表示）。
        // NSApp.applicationIconImage は OS が付ける角丸スクエアの下地込みで返るため、
        // 透過背景のクリップボード画像アセット（AppIconArtwork）を直接表示する
        let iconSize: CGFloat = 96
        let iconView = NSImageView(frame: NSRect(x: (480 - iconSize) / 2, y: 182,
                                                 width: iconSize, height: iconSize))
        iconView.identifier = ViewID.icon
        iconView.image = NSImage(named: "AppIconArtwork")
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin]
        view.addSubview(iconView)

        // バージョン表記（例: Thoth ver.1.0.0）
        let versionLabel = NSTextField(labelWithString: "\(Constants.Application.name) ver.\(Bundle.main.appVersion ?? "")")
        versionLabel.identifier = ViewID.version
        versionLabel.alignment = .center
        versionLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        versionLabel.frame = NSRect(x: 40, y: 123, width: 400, height: 30)
        versionLabel.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin]
        view.addSubview(versionLabel)

        // リリース年月日（バージョンタグ日付。開発ビルド等で未設定なら表示しない）
        let releaseDate = (Bundle.main.object(forInfoDictionaryKey: "ThothReleaseDate") as? String)?
            .trimmingCharacters(in: .whitespaces)
        if let releaseDate = releaseDate, !releaseDate.isEmpty {
            let releaseDateLabel = NSTextField(labelWithString: L10n.versionReleaseDate(releaseDate))
            releaseDateLabel.identifier = ViewID.releaseDate
            releaseDateLabel.alignment = .center
            releaseDateLabel.font = .systemFont(ofSize: NSFont.systemFontSize)
            releaseDateLabel.textColor = .secondaryLabelColor
            releaseDateLabel.frame = NSRect(x: 40, y: 96, width: 400, height: 20)
            releaseDateLabel.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin]
            view.addSubview(releaseDateLabel)
        }
    }
}
