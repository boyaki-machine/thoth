//
//  MenuManager+MenuBuilding.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Copyright © 2015-2018 Clipy Project.
//

import Cocoa
import RxCocoa
import RxSwift

// MARK: - Snippets
extension MenuManager {
    func addSnippetItems(_ menu: NSMenu, separateMenu: Bool) {
        // 暗号鍵が使えないときは一覧が空に見えてしまうため、理由を示す 1 行だけを出す
        guard AppEnvironment.current.isLibraryUsable else {
            if separateMenu { menu.addItem(NSMenuItem.separator()) }
            let item = NSMenuItem(title: L10n.snippetsUnavailable, action: nil)
            item.isEnabled = false
            menu.addItem(item)
            return
        }
        let folderRecords = AppEnvironment.current.snippetStore.folders()
        guard !folderRecords.isEmpty else { return }
        if separateMenu {
            menu.addItem(NSMenuItem.separator())
        }

        // Snippet title
        let labelItem = NSMenuItem(title: L10n.snippet, action: nil)
        labelItem.isEnabled = false
        menu.addItem(labelItem)

        var subMenuIndex = menu.numberOfItems - 1
        let firstIndex = firstIndexOfMenuItems()
        // 表示設定をループ外で一括取得
        let defaults = AppEnvironment.current.defaults
        let isMarkWithNumber = defaults.bool(forKey: Constants.UserDefaults.menuItemsAreMarkedWithNumbers)
        let isShowIcon = defaults.bool(forKey: Constants.UserDefaults.showIconInTheMenu)

        folderRecords
            .filter { $0.enable }
            .forEach { folder in
                let folderTitle = folder.title
                let subMenuItem = makeSubmenuItem(folderTitle)
                menu.addItem(subMenuItem)
                subMenuIndex += 1

                var i = firstIndex
                folder.snippets
                    .filter { $0.enable }
                    .forEach { snippet in
                        let subMenuItem = makeSnippetMenuItem(snippet, listNumber: i, isMarkWithNumber: isMarkWithNumber, isShowIcon: isShowIcon)
                        if let subMenu = menu.item(at: subMenuIndex)?.submenu {
                            subMenu.addItem(subMenuItem)
                            i += 1
                        }
                    }
            }
    }

    func makeSnippetMenuItem(_ snippet: SnippetRecord, listNumber: Int, isMarkWithNumber: Bool, isShowIcon: Bool) -> NSMenuItem {
        let title = trimTitle(snippet.title)
        let titleWithMark = menuItemTitle(title, listNumber: listNumber, isMarkWithNumber: isMarkWithNumber)

        let menuItem = NSMenuItem(title: titleWithMark, action: #selector(AppDelegate.selectSnippetMenuItem(_:)), keyEquivalent: "")
        menuItem.representedObject = snippet.id
        menuItem.toolTip = snippet.content
        menuItem.image = (isShowIcon) ? snippetIcon : nil

        return menuItem
    }
}

// MARK: - Status Item
extension MenuManager {
    func changeStatusItem(_ type: StatusType) {
        removeStatusItem()
        if type == .none { return }

        let image: NSImage?
        switch type {
        case .black:
            image = Asset.statusbarMenuBlack.image
        case .white:
            image = Asset.statusbarMenuWhite.image
        case .none: return
        }
        image?.isTemplate = true

        statusItem = NSStatusBar.system.statusItem(withLength: -1)
        statusItem?.button?.image = image
        // 旧 highlightMode = true と同じ（押下中にボタンを反転表示する）
        (statusItem?.button?.cell as? NSButtonCell)?.highlightsBy = [.pushInCellMask, .changeBackgroundCellMask]
        statusItem?.button?.toolTip = "\(Constants.Application.name) v\(Bundle.main.appVersion ?? "")"
        // クリック時も検索ボックス一体型パネルを表示する（NSMenu は割り当てない）
        statusItem?.button?.target = self
        statusItem?.button?.action = #selector(statusItemClicked)
    }

    /// ステータスバーアイコンのクリックで検索ボックス一体型パネルを表示する。
    /// 表示中の再クリックはトグルとして閉じる
    @objc func statusItemClicked() {
        if let panel = historyPickerPanel, panel.isVisible {
            dismissHistoryPicker()
            return
        }
        popUpHistorySearchPanel()
    }

    fileprivate func removeStatusItem() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }
}

// MARK: - Settings
extension MenuManager {
    func firstIndexOfMenuItems() -> NSInteger {
        return AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.menuItemsTitleStartWithZero) ? 0 : 1
    }
}

// MARK: - NSMenuDelegate (StatusBar クリックからのメニュー表示用)
extension MenuManager: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        // popUpMenu() を経由しない表示経路でも、表示直前に最新の内容へ再構築する
        if menu === snippetMenu {
            rebuildMenuIfNeeded(.snippet)
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        MenuManager.menuIsOpen = true
        openMenuCount += 1
        if openMenuCount == 1, let tap = vimKeyEventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        openMenuCount = max(0, openMenuCount - 1)
        if openMenuCount == 0 {
            MenuManager.menuIsOpen = false
            if let tap = vimKeyEventTap {
                CGEvent.tapEnable(tap: tap, enable: false)
            }
        }
    }
}

// MARK: - Vim key navigation (CGEvent tap)
extension MenuManager {
    /// アプリ起動時に一度だけ CGEvent tap を設定する。
    /// NSMenu は NSEventTrackingRunLoopMode で独自イベントループを持つため
    /// ローカルイベントモニタは機能しない。CGEvent tap は HID レベルでインターセプトし
    /// run loop mode に依存しないため確実に動作する。
    /// menuIsOpen フラグが true のときのみ h/j/k/l → 矢印キーに変換する。
    /// アクセシビリティ権限がない場合は tap の作成が失敗し、何もしない。
    func setupVimKeyEventTap() {
        guard vimKeyEventTap == nil else { return }

        let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { _, type, event, _ -> Unmanaged<CGEvent>? in
                // 受け取ったイベントをそのまま返すときは所有権を増やさない（passRetained だと毎回リークする）
                guard type == .keyDown else { return Unmanaged.passUnretained(event) }
                guard MenuManager.menuIsOpen else { return Unmanaged.passUnretained(event) }
                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                let flags = event.flags
                // Cmd / Alt / Ctrl が押されている場合は hjkl リマッピング不要。
                // Shift は HJKL をサポートするため修飾キーとして扱わない。
                let hasModifiers = !flags.isDisjoint(with: [.maskCommand, .maskAlternate, .maskControl])
                guard !hasModifiers else { return Unmanaged.passUnretained(event) }
                // h=4, j=38, k=40, l=37 / H=4+Shift, J=38+Shift, K=40+Shift, L=37+Shift
                // NSMenu は characters フィールドでナビゲーションを判断するため
                // keyCode・unicode 文字列・フラグの 3 つを矢印キーに変換する必要がある
                let arrowKeyCode: Int64
                let arrowCharacter: UniChar
                switch keyCode {
                case 4:  arrowKeyCode = 123; arrowCharacter = 0xF702  // h/H → Left
                case 38: arrowKeyCode = 125; arrowCharacter = 0xF701  // j/J → Down
                case 40: arrowKeyCode = 126; arrowCharacter = 0xF700  // k/K → Up
                case 37: arrowKeyCode = 124; arrowCharacter = 0xF703  // l/L → Right
                default: return Unmanaged.passUnretained(event)
                }
                event.setIntegerValueField(.keyboardEventKeycode, value: arrowKeyCode)
                // Shift フラグを除去して純粋な矢印キーとして送出する
                event.flags = flags.subtracting(.maskShift)
                var chars: [UniChar] = [arrowCharacter]
                event.keyboardSetUnicodeString(stringLength: 1, unicodeString: &chars)
                return Unmanaged.passUnretained(event)
            },
            userInfo: nil
        ) else {
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: false)  // メニューが開いた時だけ有効化する
        vimKeyEventTap = tap
        vimKeyRunLoopSource = source
    }
}
