//
//  CPYPreferencesWindowController.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Econa77 on 2016/02/25.
//
//  Copyright © 2015-2018 Clipy Project.
//

import Cocoa

final class CPYPreferencesWindowController: NSWindowController {

    // MARK: - Properties
    static let sharedController = CPYPreferencesWindowController(windowNibName: "CPYPreferencesWindowController")
    @IBOutlet private weak var toolBar: NSView!
    // ImageViews
    @IBOutlet private weak var generalImageView: NSImageView!
    @IBOutlet private weak var menuImageView: NSImageView!
    @IBOutlet private weak var typeImageView: NSImageView!
    @IBOutlet private weak var excludeImageView: NSImageView!
    @IBOutlet private weak var shortcutsImageView: NSImageView!
    @IBOutlet private weak var updatesImageView: NSImageView!
    @IBOutlet private weak var betaImageView: NSImageView!
    // Labels
    @IBOutlet private weak var generalTextField: NSTextField!
    @IBOutlet private weak var menuTextField: NSTextField!
    @IBOutlet private weak var typeTextField: NSTextField!
    @IBOutlet private weak var excludeTextField: NSTextField!
    @IBOutlet private weak var shortcutsTextField: NSTextField!
    @IBOutlet private weak var updatesTextField: NSTextField!
    @IBOutlet private weak var betaTextField: NSTextField!
    // Buttons
    @IBOutlet private weak var generalButton: NSButton!
    @IBOutlet private weak var menuButton: NSButton!
    @IBOutlet private weak var typeButton: NSButton!
    @IBOutlet private weak var excludeButton: NSButton!
    @IBOutlet private weak var shortcutsButton: NSButton!
    @IBOutlet private weak var updatesButton: NSButton!
    @IBOutlet private weak var betaButton: NSButton!
    // ViewController
    private let viewController = [NSViewController(nibName: "CPYGeneralPreferenceViewController", bundle: nil),
                                  NSViewController(nibName: "CPYMenuPreferenceViewController", bundle: nil),
                                  CPYTypePreferenceViewController(nibName: "CPYTypePreferenceViewController", bundle: nil),
                                  CPYExcludeAppPreferenceViewController(nibName: "CPYExcludeAppPreferenceViewController", bundle: nil),
                                  CPYShortcutsPreferenceViewController(nibName: "CPYShortcutsPreferenceViewController", bundle: nil),
                                  CPYUpdatesPreferenceViewController(nibName: "CPYUpdatesPreferenceViewController", bundle: nil),
                                  CPYBetaPreferenceViewController(nibName: "CPYBetaPreferenceViewController", bundle: nil),
                                  CPYVersionPreferenceViewController()]
    // バージョンタブ（XIB を変更せずコードで追加するため参照を保持する）
    private let versionImageView = NSImageView()
    private let versionTextField = NSTextField(labelWithString: L10n.preferenceVersionTab)
    private let versionButton = NSButton()

    // MARK: - Window Life Cycle
    override func windowDidLoad() {
        super.windowDidLoad()
        self.window?.collectionBehavior = .canJoinAllSpaces
        self.window?.backgroundColor = NSColor(white: 0.99, alpha: 1)
        if #available(OSX 10.10, *) {
            self.window?.titlebarAppearsTransparent = true
        }
        setupVersionTab()
        toolBarItemTapped(generalButton)
        generalButton.sendAction(on: .leftMouseDown)
        menuButton.sendAction(on: .leftMouseDown)
        typeButton.sendAction(on: .leftMouseDown)
        excludeButton.sendAction(on: .leftMouseDown)
        shortcutsButton.sendAction(on: .leftMouseDown)
        updatesButton.sendAction(on: .leftMouseDown)
        betaButton.sendAction(on: .leftMouseDown)
        versionButton.sendAction(on: .leftMouseDown)
    }

    /// 「バージョン」タブを XIB を変更せずコードでタブバー末尾へ追加する。
    /// 既存タブの最終項目（ベータ: x=309..359）のラベルがコンテナ幅を超えて
    /// はみ出すため、2.5 文字分（約 25pt）の余白を空けて配置する
    private func setupVersionTab() {
        let container = NSView(frame: NSRect(x: 390, y: 0, width: 50, height: 56))
        container.autoresizingMask = [.maxXMargin, .minYMargin]

        versionImageView.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 18, weight: .regular))
        versionImageView.contentTintColor = ColorName.tabTitle.color
        versionImageView.frame = NSRect(x: 13, y: 24, width: 24, height: 24)
        container.addSubview(versionImageView)

        versionTextField.alignment = .center
        versionTextField.font = .systemFont(ofSize: 10)
        versionTextField.textColor = ColorName.tabTitle.color
        versionTextField.lineBreakMode = .byClipping
        versionTextField.frame = NSRect(x: 1, y: 8, width: 48, height: 12)
        container.addSubview(versionTextField)

        versionButton.title = ""
        versionButton.isBordered = false
        versionButton.isTransparent = true
        versionButton.tag = 7
        versionButton.target = self
        versionButton.action = #selector(toolBarItemTapped(_:))
        versionButton.frame = NSRect(x: 0, y: 0, width: 50, height: 56)
        container.addSubview(versionButton)

        toolBar.addSubview(container)
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(self)
    }
}

// MARK: - IBActions
extension CPYPreferencesWindowController {
    @IBAction private func toolBarItemTapped(_ sender: NSButton) {
        selectedTab(sender.tag)
        switchView(sender.tag)
    }
}

// MARK: - NSWindow Delegate
extension CPYPreferencesWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        if let viewController = viewController[2] as? CPYTypePreferenceViewController {
            AppEnvironment.current.defaults.set(viewController.storeTypes, forKey: Constants.UserDefaults.storeTypes)
        }
        if let window = window, !window.makeFirstResponder(window) {
            window.endEditing(for: nil)
        }
        NSApp.deactivate()
    }
}

// MARK: - Layout
private extension CPYPreferencesWindowController {
    func resetImages() {
        generalImageView.image = Asset.prefGeneral.image
        menuImageView.image = Asset.prefMenu.image
        typeImageView.image = Asset.prefType.image
        excludeImageView.image = Asset.prefExcluded.image
        shortcutsImageView.image = Asset.prefShortcut.image
        updatesImageView.image = Asset.prefUpdate.image
        betaImageView.image = Asset.prefBeta.image
        versionImageView.contentTintColor = ColorName.tabTitle.color

        generalTextField.textColor = ColorName.tabTitle.color
        menuTextField.textColor = ColorName.tabTitle.color
        typeTextField.textColor = ColorName.tabTitle.color
        excludeTextField.textColor = ColorName.tabTitle.color
        shortcutsTextField.textColor = ColorName.tabTitle.color
        updatesTextField.textColor = ColorName.tabTitle.color
        betaTextField.textColor = ColorName.tabTitle.color
        versionTextField.textColor = ColorName.tabTitle.color
    }

    func selectedTab(_ index: Int) {
        resetImages()

        switch index {
        case 0:
            generalImageView.image = Asset.prefGeneralOn.image
            generalTextField.textColor = ColorName.clipy.color
        case 1:
            menuImageView.image = Asset.prefMenuOn.image
            menuTextField.textColor = ColorName.clipy.color
        case 2:
            typeImageView.image = Asset.prefTypeOn.image
            typeTextField.textColor = ColorName.clipy.color
        case 3:
            excludeImageView.image = Asset.prefExcludedOn.image
            excludeTextField.textColor = ColorName.clipy.color
        case 4:
            shortcutsImageView.image = Asset.prefShortcutOn.image
            shortcutsTextField.textColor = ColorName.clipy.color
        case 5:
            updatesImageView.image = Asset.prefUpdateOn.image
            updatesTextField.textColor = ColorName.clipy.color
        case 6:
            betaImageView.image = Asset.prefBetaOn.image
            betaTextField.textColor = ColorName.clipy.color
        case 7:
            versionImageView.contentTintColor = ColorName.clipy.color
            versionTextField.textColor = ColorName.clipy.color
        default: break
        }
    }

    func switchView(_ index: Int) {
        let newView = viewController[index].view
        // Remove current views without toolbar
        window?.contentView?.subviews.forEach { view in
            if view != toolBar {
                view.removeFromSuperview()
            }
        }
        // Resize view
        let frame = window!.frame
        var newFrame = window!.frameRect(forContentRect: newView.frame)
        newFrame.origin = frame.origin
        newFrame.origin.y += frame.height - newFrame.height - toolBar.frame.height
        newFrame.size.height += toolBar.frame.height
        window?.setFrame(newFrame, display: true)
        window?.contentView?.addSubview(newView)
    }
}
