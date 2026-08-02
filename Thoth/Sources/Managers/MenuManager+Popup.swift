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
        // セキュアメニュー・履歴検索パネルとは排他表示: 表示中のパネルを閉じる
        dismissSecurePicker()
        dismissHistoryPicker()
        let menu: NSMenu?
        switch type {
        case .main:
            // メインはセキュアアイテムと同じ「検索ボックス + リスト一体型」パネルで表示する
            // （NSMenu にはインクリメンタルサーチを組み込めないため）。
            // スニペット・ツール類はパネル下部の固定行から利用する
            popUpHistorySearchPanel(showsFixedSections: true)
            return
        case .history:
            // 履歴ホットキーは「コピー履歴 + 検索」だけのウィンドウとして表示する
            popUpHistorySearchPanel(showsFixedSections: false)
            return
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

    /// 環境設定ウィンドウが表示中なら、フォーカスを設定ウィンドウへ戻す。
    /// 設定ウィンドウを開いたままショートカットでパネルを表示 → 選択せずに閉じた場合に、
    /// フォーカスが他アプリへ移ってしまわないようにする
    func restorePreferencesFocusIfNeeded() {
        guard let window = CPYPreferencesWindowController.sharedController.window,
              window.isVisible else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// 表示中の履歴検索パネルを閉じて状態をリセットする。
    /// コピー選択メニュー・セキュアメニューとの排他表示に使用する。
    func dismissHistoryPicker() {
        guard historyPickerPanel != nil else { return }
        // willClose オブザーバー経由の二重リセットを避けるため先に解除する
        if let observer = historyPickerCloseObserver { NotificationCenter.default.removeObserver(observer) }
        historyPickerPanel?.close()
        historyPickerPanel = nil
        historyPickerCloseObserver = nil
    }

    /// 履歴検索パネルを表示する。
    /// - Parameter showsFixedSections: true でスニペット・ツール・設定の固定セクション付き
    ///   （メインメニュー相当）、false でコピー履歴 + 検索のみ（履歴ウィンドウ相当）。
    /// 並び順は「ペースト後に履歴を並べ替える」設定に従う（旧メニューと同じ）:
    /// ON なら新しい順、OFF ならコピー順のまま（項目の位置と番号が安定し、
    /// 数字キーショートカットの筋肉記憶が保たれる）
    func popUpHistorySearchPanel(showsFixedSections: Bool = true) {
        dismissClipMenus()
        dismissSecurePicker()
        dismissHistoryPicker()
        guard RealmProvider.isReady else { return }

        let maxHistory = AppEnvironment.current.defaults.integer(forKey: Constants.UserDefaults.maxHistorySize)
        let maxTitleLength = AppEnvironment.current.defaults.integer(forKey: Constants.UserDefaults.maxMenuItemTitleLength)
        let ascending = !AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.reorderClipsAfterPasting)
        let clipResults = realm.objects(CPYClip.self)
            .sorted(byKeyPath: #keyPath(CPYClip.updateTime), ascending: ascending)
        var clips = [CPYHistoryPickerPanel.ClipItem]()
        for clip in clipResults {
            clips.append(CPYHistoryPickerPanel.ClipItem(clip: clip, index: clips.count,
                                                        maxTitleLength: maxTitleLength))
            if clips.count >= maxHistory { break }
        }

        let panel = CPYHistoryPickerPanel(clips: clips, showsFixedSections: showsFixedSections)
        panel.onSelect = { [weak self, weak panel] dataHash in
            // NSApp.activate で Thoth がアクティブになっているため、
            // パネルを閉じる前にペースト先アプリを取得しておく
            let callerApp = panel?.callerApp
            self?.dismissHistoryPicker()
            // ペースト先アプリをアクティブ化してから貼り付ける。
            // activate は非同期で完了するため少し待ってから送出する
            callerApp?.activate(options: [.activateIgnoringOtherApps])
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                if !AppEnvironment.current.pasteService.pasteClip(withPrimaryKey: dataHash) {
                    NSSound.beep()
                }
            }
        }
        panel.onAction = { [weak self] action in
            self?.dismissHistoryPicker()
            let delegate = NSApp.delegate as? AppDelegate
            switch action {
            case .snippets:
                // パネルのクローズが落ち着いてからスニペットメニューをポップアップする
                DispatchQueue.main.async { [weak self] in
                    self?.popUpMenu(.snippet)
                }
            case .generatePassword:
                delegate?.showPasswordGeneratorWindow()
            case .crypto:
                delegate?.showCryptoWindow()
            case .secureInfo:
                delegate?.showSecureInfoWindow()
            case .clearHistory:
                delegate?.clearAllHistory()
            case .editSnippets:
                delegate?.showSnippetEditorWindow()
            case .preferences:
                delegate?.showPreferenceWindow()
            case .quit:
                delegate?.terminate()
            }
        }

        // パネルが Esc や外部クリックで閉じられた場合も状態をリセットする
        historyPickerCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            self?.historyPickerPanel = nil
            self?.historyPickerCloseObserver = nil
            // 選択なしで閉じた場合、設定ウィンドウが開いていればフォーカスを戻す
            self?.restorePreferencesFocusIfNeeded()
        }

        historyPickerPanel = panel
        panel.show(near: NSEvent.mouseLocation)
    }

    func popUpSecureMenu() {
        // コピー選択メニュー・履歴検索パネルとは排他表示: 表示中のものを閉じる
        dismissClipMenus()
        dismissHistoryPicker()
        // セキュアアイテムを編集中のウィンドウ（管理ウィンドウ・確認ウィンドウ）が
        // 表示中の場合は、選択パネルを出さずにそちらをアクティブにする。
        // 選択パネルは .screenSaver レベルで表示されるため、編集中の画面に被ってしまう
        let editingWindows = [CPYSecureItemsWindowController.shared.window,
                              CPYSecureInfoWindowController.shared.window]
        if let visibleWindow = editingWindows.compactMap({ $0 }).first(where: { $0.isVisible }) {
            #if DEBUG
            NSLog("[MenuManager] popUpSecureMenu: editing window visible, activating it instead")
            #endif
            NSApp.activate(ignoringOtherApps: true)
            visibleWindow.makeKeyAndOrderFront(nil)
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
                // 選択なしで閉じた場合、設定ウィンドウが開いていればフォーカスを戻す
                self?.restorePreferencesFocusIfNeeded()
            }

            self.securePickerPanel = panel
            panel.show(near: NSEvent.mouseLocation)
        }
    }

    /// セキュア選択の出力を行う唯一の共通経路（パネル選択・メニュー選択の両方から呼ばれる）。
    /// 継続ペーストモード用の選択記録もここで行う。
    ///
    /// - TOTP: クリップボードを経由せず、その時点のコードを CGEvent で直接タイプする
    ///   （OS のコピー履歴にも Clipy 履歴にも残らない）
    /// - それ以外: 秘匿マーカー付きでクリップボードに書き込んでペーストし、
    ///   一定時間後（その間に別のコピーが無ければ）クリアする。
    ///   マーカーにより ClipService の履歴保存はスキップされる。
    ///
    /// ※ context.clear() はここでは呼ばない。複数回選択した場合に古いタイマーが
    ///   新しい選択後の context を消してしまうため。isWithinWindow がタイムスタンプで
    ///   自動的に期限切れを判定するので明示的なクリアは不要。
    func outputSecureSelection(_ selection: SecureFieldSelection) {
        let context = AppEnvironment.current.secureSelectionContext
        context.record(parentItemID: selection.parentItemID, fieldIndex: selection.fieldIndex)
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
            AppEnvironment.current.pasteService.copyConcealedToPasteboard(with: selection.fieldValue)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                AppEnvironment.current.pasteService.paste()
            }
            AppEnvironment.current.pasteService.scheduleConcealedClear()
        }
    }

    func popUpSnippetFolder(_ folder: CPYFolder) {
        // セキュアメニュー・履歴検索パネルとは排他表示: 表示中のパネルを閉じる
        dismissSecurePicker()
        dismissHistoryPicker()
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
