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
        DebugLog.shared.record(.preferencesFocusRestored)
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
        guard LibraryProvider.isReady else { return }

        let maxHistory = AppEnvironment.current.defaults.integer(forKey: Constants.UserDefaults.maxHistorySize)
        let maxTitleLength = AppEnvironment.current.defaults.integer(forKey: Constants.UserDefaults.maxMenuItemTitleLength)
        let ascending = !AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.reorderClipsAfterPasting)
        let clipRecords = AppEnvironment.current.historyStore.clips(ascending: ascending)
        var clips = [CPYHistoryPickerPanel.ClipItem]()
        for clip in clipRecords {
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
            // ペースト先アプリを前面へ戻し、前面に来たのを確かめてから貼り付ける
            CallerAppActivator.activate(callerApp) {
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
        // セキュア情報確認ウィンドウが表示中の場合は、選択パネルを出さずに
        // そちらをアクティブにする。選択パネルは .screenSaver レベルで表示されるため、
        // 編集中の画面に被ってしまう。
        //
        // ここで `CPYSecureInfoWindowController.shared` を参照するとシングルトンが
        // 生成され、一度も開いていないウィンドウまで組み立ててしまう。
        // 表示中のウィンドウを実際に走査して、生成せずに判定する
        if let visibleWindow = NSApp.windows.first(where: { window in
            guard window.isVisible else { return false }
            return window.contentViewController is CPYSecureInfoSplitViewController
        }) {
            DebugLog.shared.record(.secureInfoWindowVisible)
            NSApp.activate(ignoringOtherApps: true)
            visibleWindow.makeKeyAndOrderFront(nil)
            return
        }
        // 認証中・表示中の場合は既存パネルを前面に戻す（または強制リセット）
        if isSecureMenuActive {
            if let existing = securePickerPanel, existing.isVisible {
                // パネルが既に表示中 → 前面に出して再アクティブ化して終了
                DebugLog.shared.record(.securePickerAlreadyVisible)
                NSApp.activate(ignoringOtherApps: true)
                existing.makeKeyAndOrderFront(nil)
                return
            } else {
                // パネルが消えているのにフラグが残っている → 強制リセット
                DebugLog.shared.record(.secureStaleFlagReset)
                if let observer = secureCloseObserver { NotificationCenter.default.removeObserver(observer) }
                isSecureMenuActive  = false
                securePickerPanel   = nil
                secureCloseObserver = nil
            }
        }
        guard !isSecureMenuActive else {
            DebugLog.shared.record(.secureIgnoredWhileAuthenticating)
            return
        }
        isSecureMenuActive = true
        // 貼り付け先はホットキーを押した時点で覚えておく。認証ダイアログを挟むと、
        // パネルを出す時点の最前面は元のアプリではなくなっていることがある
        let hotKeyApp = NSWorkspace.shared.frontmostApplication
        let reason = L10n.secureMenuAuthenticationReason
        AppEnvironment.current.secureMenuService.authenticate(reason: reason) { [weak self] success in
            guard let self = self else { return }
            DebugLog.shared.record(.secureAuthenticationFinished(success: success))
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
                // 閉じる前に willClose の監視を外す（dismissSecurePicker）。外さないと
                // 「選択なしで閉じた」扱いで設定ウィンドウへフォーカスを戻してしまい
                // （restorePreferencesFocusIfNeeded）、設定ウィンドウを開いたままだと ⌘V が Thoth に届く
                self?.dismissSecurePicker()
                // ペースト先アプリを前面へ戻し、前面に来たのを確かめてから出力する
                self?.outputSecureSelection(selection, returningFocusTo: callerApp)
            }
            // 選択パネルからもメインメニューと同じセキュア情報確認ウィンドウを開く。
            // showSecureInfoWindow() は認証を通すが、選択パネルを開いた時点で
            // 認証済みなので SecureMenuService の猶予（30 秒）に入り再要求されない
            panel.onManage = { [weak self] in
                self?.dismissSecurePicker()
                (NSApp.delegate as? AppDelegate)?.showSecureInfoWindow()
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
            panel.show(near: NSEvent.mouseLocation, callerApp: hotKeyApp)
        }
    }

    /// セキュア選択の出力を行う唯一の共通経路（パネル選択・メニュー選択の両方から呼ばれる）。
    /// 継続ペーストモード用の選択記録もここで行う。
    ///
    /// - TOTP: クリップボードを経由せず、その時点のコードを CGEvent で直接タイプする
    ///   （OS のコピー履歴にも Clipy 履歴にも残らない）
    /// - それ以外: 秘匿マーカー付きでクリップボードに書き込んでペーストし、
    ///   少し後（その間に別のコピーが無ければ）書き込む前の内容へ戻す。
    ///   マーカーにより ClipService の履歴保存はスキップされる。
    ///   ペーストを送れなかった場合（設定で無効・権限なし）は、利用者が自分で貼り付けられるよう
    ///   従来どおり一定時間後にクリアする
    ///
    /// - Parameter callerApp: 出力の前に前面へ戻すアプリ（パネルから選んだ場合）。
    ///   nil なら戻さない（NSMenu から選んだ場合は元のアプリが前面のまま）
    ///
    /// ※ context.clear() はここでは呼ばない。複数回選択した場合に古いタイマーが
    ///   新しい選択後の context を消してしまうため。isWithinWindow がタイムスタンプで
    ///   自動的に期限切れを判定するので明示的なクリアは不要。
    func outputSecureSelection(_ selection: SecureFieldSelection, returningFocusTo callerApp: NSRunningApplication? = nil) {
        let context = AppEnvironment.current.secureSelectionContext
        context.record(parentItemID: selection.parentItemID, fieldIndex: selection.fieldIndex)
        let pasteService = AppEnvironment.current.pasteService
        if selection.isTOTP {
            guard let params = TOTPService.parse(selection.fieldValue) else {
                NSSound.beep()
                return
            }
            CallerAppActivator.activate(callerApp) {
                // コードは送る直前に作る（前面化を待つ間に周期をまたいでも古いコードを打たない）
                guard let code = TOTPService().code(for: params) else {
                    NSSound.beep()
                    return
                }
                pasteService.typeString(code)
            }
        } else {
            let pasteboard = NSPasteboard.general
            let snapshot = PasteboardSnapshot(pasteboard: pasteboard)
            pasteService.copyConcealedToPasteboard(with: selection.fieldValue)
            let writtenChangeCount = pasteboard.changeCount
            CallerAppActivator.activate(callerApp) {
                if pasteService.paste() {
                    pasteService.restorePasteboard(snapshot, ifUnchangedSince: writtenChangeCount)
                } else {
                    pasteService.scheduleConcealedClear()
                }
            }
        }
    }

    func popUpSnippetFolder(_ folder: SnippetFolderRecord) {
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
