//
//  MenuManager+Popup.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Copyright © 2015-2018 Clipy Project.
//

import Cocoa

// MARK: - Popup Menu
extension MenuManager {
    func popUpMenu(_ type: MenuType) {
        // セキュアメニューとは排他表示: 表示中のセキュアパネルを閉じる
        dismissSecurePicker()
        let menu: NSMenu?
        switch type {
        case .main:
            menu = clipMenu
        case .history:
            menu = historyMenu
        case .snippet:
            menu = snippetMenu
        case .secure:
            menu = nil
        }
        // 表示直前に必要なメニューだけ再構築する
        rebuildMenuIfNeeded(type)
        // アクセシビリティ権限が後から付与された場合に備えてリトライ
        setupVimKeyEventTap()
        // popUp() はメニューが閉じるまでブロックするため、前後でフラグを制御する
        MenuManager.menuIsOpen = true
        menu?.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        MenuManager.menuIsOpen = false
    }

    /// 表示中のセキュアアイテム選択パネルを閉じてフラグをリセットする。
    /// コピー選択メニュー（履歴・スニペット）とセキュアメニューを排他表示にするために使用する。
    func dismissSecurePicker() {
        guard isSecureMenuActive || securePickerPanel != nil else { return }
        // willClose オブザーバー経由の二重リセットを避けるため先に解除する
        if let observer = secureCloseObserver { NotificationCenter.default.removeObserver(observer) }
        securePickerPanel?.close()
        securePickerPanel   = nil
        isSecureMenuActive  = false
        secureCloseObserver = nil
    }

    /// 表示中のコピー選択メニュー（メイン・履歴・スニペット）を閉じる。
    /// セキュアメニュー表示時の排他制御に使用する。
    func dismissClipMenus() {
        [clipMenu, historyMenu, snippetMenu].forEach { $0.cancelTrackingWithoutAnimation() }
    }

    func popUpSecureMenu() {
        // コピー選択メニューとは排他表示: 表示中のメニューを閉じる
        dismissClipMenus()
        // セキュアアイテム管理ウィンドウ（編集シート含む）が表示中の場合は、
        // 選択パネルを出さずにそちらをアクティブにする
        if let managementWindow = CPYSecureItemsWindowController.shared.window, managementWindow.isVisible {
            #if DEBUG
            NSLog("[MenuManager] popUpSecureMenu: management window visible, activating it instead")
            #endif
            NSApp.activate(ignoringOtherApps: true)
            managementWindow.makeKeyAndOrderFront(nil)
            return
        }
        // 認証中・表示中の場合は既存パネルを前面に戻す（または強制リセット）
        if isSecureMenuActive {
            if let existing = securePickerPanel, existing.isVisible {
                // パネルが既に表示中 → 前面に出して再アクティブ化して終了
                #if DEBUG
                NSLog("[MenuManager] popUpSecureMenu: panel already visible, re-activating")
                #endif
                NSApp.activate(ignoringOtherApps: true)
                existing.makeKeyAndOrderFront(nil)
                return
            } else {
                // パネルが消えているのにフラグが残っている → 強制リセット
                #if DEBUG
                NSLog("[MenuManager] popUpSecureMenu: stale active flag, resetting")
                #endif
                if let observer = secureCloseObserver { NotificationCenter.default.removeObserver(observer) }
                isSecureMenuActive  = false
                securePickerPanel   = nil
                secureCloseObserver = nil
            }
        }
        guard !isSecureMenuActive else { return }
        isSecureMenuActive = true
        let reason = L10n.secureMenuAuthenticationReason
        AppEnvironment.current.secureMenuService.authenticate(reason: reason) { [weak self] success in
            guard let self = self else { return }
            guard success else {
                self.isSecureMenuActive = false
                return
            }
            let items   = AppEnvironment.current.secureMenuService.loadAllItems()
            let context = AppEnvironment.current.secureSelectionContext
            let panel   = CPYSecurePickerPanel(items: items, context: context)

            panel.onSelect = { [weak self, weak panel] selection in
                // NSApp.activate でClipyがアクティブになっているため、
                // パネルを閉じる前にペースト先アプリを取得しておく
                let callerApp = panel?.callerApp
                panel?.close()
                context.record(parentItemID: selection.parentItemID, fieldIndex: selection.fieldIndex)
                self?.isSecureMenuActive  = false
                self?.securePickerPanel   = nil
                self?.secureCloseObserver = nil
                // ペースト先アプリをアクティブ化してから出力する。
                // activate は非同期で完了するため少し待ってから送出する。
                callerApp?.activate(options: [.activateIgnoringOtherApps])
                self?.outputSecureSelection(selection)
            }
            panel.onManage = { [weak self, weak panel] in
                panel?.close()
                (NSApp.delegate as? AppDelegate)?.showSecureItemsWindow()
                self?.isSecureMenuActive  = false
                self?.securePickerPanel   = nil
                self?.secureCloseObserver = nil
            }

            // パネルが Esc や外部クリックで閉じられた場合もフラグをリセット
            // ブロックベース addObserver は戻り値（トークン）を保持しないと即時解放されるため secureCloseObserver に保存する
            self.secureCloseObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: panel,
                queue: .main
            ) { [weak self] _ in
                self?.isSecureMenuActive = false
                self?.securePickerPanel  = nil
                self?.secureCloseObserver = nil
            }

            self.securePickerPanel = panel
            panel.show(near: NSEvent.mouseLocation)
        }
    }

    /// セキュア選択の出力を行う共通処理。
    /// TOTP はクリップボードを経由せず直接タイプ（OS/Clipy 履歴に残さない）、
    /// それ以外は従来どおりクリップボード経由でペーストし、一定時間後にクリアする。
    func outputSecureSelection(_ selection: SecureFieldSelection) {
        if selection.isTOTP {
            guard let params = TOTPService.parse(selection.fieldValue),
                  let code = TOTPService().code(for: params) else {
                NSSound.beep()
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                AppEnvironment.current.pasteService.typeString(code)
            }
        } else {
            AppEnvironment.current.pasteService.copyToPasteboard(with: selection.fieldValue)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                AppEnvironment.current.pasteService.paste()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + SecureSelectionContext.recencyWindow) {
                NSPasteboard.general.clearContents()
            }
        }
    }

    func popUpSnippetFolder(_ folder: CPYFolder) {
        // セキュアメニューとは排他表示: 表示中のセキュアパネルを閉じる
        dismissSecurePicker()
        let folderMenu = NSMenu(title: folder.title)
        folderMenu.delegate = self
        // Folder title
        let labelItem = NSMenuItem(title: folder.title, action: nil)
        labelItem.isEnabled = false
        folderMenu.addItem(labelItem)
        // Snippets
        var index = firstIndexOfMenuItems()
        let defaults = AppEnvironment.current.defaults
        let isMarkWithNumber = defaults.bool(forKey: Constants.UserDefaults.menuItemsAreMarkedWithNumbers)
        let isShowIcon = defaults.bool(forKey: Constants.UserDefaults.showIconInTheMenu)
        folder.snippets
            .sorted(byKeyPath: #keyPath(CPYSnippet.index), ascending: true)
            .filter { $0.enable }
            .forEach { snippet in
                let subMenuItem = makeSnippetMenuItem(snippet, listNumber: index, isMarkWithNumber: isMarkWithNumber, isShowIcon: isShowIcon)
                folderMenu.addItem(subMenuItem)
                index += 1
            }
        // アクセシビリティ権限が後から付与された場合に備えてリトライ
        setupVimKeyEventTap()
        MenuManager.menuIsOpen = true
        folderMenu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        MenuManager.menuIsOpen = false
    }
}
