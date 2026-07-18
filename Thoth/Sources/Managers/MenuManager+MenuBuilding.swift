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
import PINCache
import RealmSwift
import RxCocoa
import RxSwift

// MARK: - Clips
extension MenuManager {
    /// メニューアイテム描画に必要な設定値をまとめた構造体。
    /// ループ外で一度だけ UserDefaults を読み込み、N アイテム分の繰り返しアクセスを排除する。
    fileprivate struct ClipMenuItemSettings {
        let isMarkWithNumber: Bool
        let isShowToolTip: Bool
        let isShowImage: Bool
        let isShowColorCode: Bool
        let addNumericKeyEquivalents: Bool
        let isStartFromZero: Bool
        let maxLengthOfToolTip: Int

        init(_ defaults: UserDefaults) {
            isMarkWithNumber       = defaults.bool(forKey: Constants.UserDefaults.menuItemsAreMarkedWithNumbers)
            isShowToolTip          = defaults.bool(forKey: Constants.UserDefaults.showToolTipOnMenuItem)
            isShowImage            = defaults.bool(forKey: Constants.UserDefaults.showImageInTheMenu)
            isShowColorCode        = defaults.bool(forKey: Constants.UserDefaults.showColorPreviewInTheMenu)
            addNumericKeyEquivalents = defaults.bool(forKey: Constants.UserDefaults.addNumericKeyEquivalents)
            isStartFromZero        = defaults.bool(forKey: Constants.UserDefaults.menuItemsTitleStartWithZero)
            maxLengthOfToolTip     = defaults.integer(forKey: Constants.UserDefaults.maxLengthOfToolTip)
        }
    }

    func addHistoryItems(_ menu: NSMenu) {
        let defaults = AppEnvironment.current.defaults
        let placeInLine = defaults.integer(forKey: Constants.UserDefaults.numberOfItemsPlaceInline)
        let placeInsideFolder = defaults.integer(forKey: Constants.UserDefaults.numberOfItemsPlaceInsideFolder)
        let maxHistory = defaults.integer(forKey: Constants.UserDefaults.maxHistorySize)

        // History title
        let labelItem = NSMenuItem(title: L10n.history, action: nil)
        labelItem.isEnabled = false
        menu.addItem(labelItem)

        // History
        let firstIndex = firstIndexOfMenuItems()
        var listNumber = firstIndex
        var subMenuCount = placeInLine
        var subMenuIndex = 1 + placeInLine

        let ascending = !defaults.bool(forKey: Constants.UserDefaults.reorderClipsAfterPasting)
        let clipResults = realm.objects(CPYClip.self).sorted(byKeyPath: #keyPath(CPYClip.updateTime), ascending: ascending)
        let currentSize = Int(clipResults.count)
        // 表示設定をループ外で一括取得（N アイテム × 6 回の UserDefaults アクセスを 6 回に削減）
        let settings = ClipMenuItemSettings(defaults)
        var i = 0
        for clip in clipResults {
            if placeInLine < 1 || placeInLine - 1 < i {
                // Folder
                if i == subMenuCount {
                    let subMenuItem = makeSubmenuItem(subMenuCount, start: firstIndex, end: currentSize, numberOfItems: placeInsideFolder)
                    menu.addItem(subMenuItem)
                    listNumber = firstIndex
                }

                // Clip
                if let subMenu = menu.item(at: subMenuIndex)?.submenu {
                    let menuItem = makeClipMenuItem(clip, index: i, listNumber: listNumber, settings: settings)
                    subMenu.addItem(menuItem)
                    listNumber = incrementListNumber(listNumber, max: placeInsideFolder, start: firstIndex)
                }
            } else {
                // Clip
                let menuItem = makeClipMenuItem(clip, index: i, listNumber: listNumber, settings: settings)
                menu.addItem(menuItem)
                listNumber = incrementListNumber(listNumber, max: placeInLine, start: firstIndex)
            }

            i += 1
            if i == subMenuCount + placeInsideFolder {
                subMenuCount += placeInsideFolder
                subMenuIndex += 1
            }

            if maxHistory <= i { break }
        }
    }

    fileprivate func makeClipMenuItem(_ clip: CPYClip, index: Int, listNumber: Int, settings: ClipMenuItemSettings) -> NSMenuItem {
        var keyEquivalent = ""

        if settings.addNumericKeyEquivalents && (index <= kMaxKeyEquivalents) {
            var shortCutNumber = settings.isStartFromZero ? index : index + 1
            if shortCutNumber == kMaxKeyEquivalents {
                shortCutNumber = 0
            }
            keyEquivalent = "\(shortCutNumber)"
        }

        let primaryPboardType = NSPasteboard.PasteboardType(rawValue: clip.primaryType)
        let clipString = clip.title
        let title = trimTitle(clipString)
        let titleWithMark = menuItemTitle(title, listNumber: listNumber, isMarkWithNumber: settings.isMarkWithNumber)

        let menuItem = NSMenuItem(title: titleWithMark, action: #selector(AppDelegate.selectClipMenuItem(_:)), keyEquivalent: keyEquivalent)
        menuItem.representedObject = clip.dataHash

        if settings.isShowToolTip {
            let toIndex = min(clipString.count, settings.maxLengthOfToolTip)
            menuItem.toolTip = (clipString as NSString).substring(to: toIndex)
        }

        if primaryPboardType == .deprecatedTIFF {
            menuItem.title = menuItemTitle("(Image)", listNumber: listNumber, isMarkWithNumber: settings.isMarkWithNumber)
        } else if primaryPboardType == .deprecatedPDF {
            menuItem.title = menuItemTitle("(PDF)", listNumber: listNumber, isMarkWithNumber: settings.isMarkWithNumber)
        } else if primaryPboardType == .deprecatedFilenames && title.isEmpty {
            menuItem.title = menuItemTitle("(Filenames)", listNumber: listNumber, isMarkWithNumber: settings.isMarkWithNumber)
        }

        if !clip.thumbnailPath.isEmpty && !clip.isColorCode && settings.isShowImage {
            PINCache.shared.object(forKeyAsync: clip.thumbnailPath) { [weak menuItem] _, _, object in
                DispatchQueue.main.async {
                    menuItem?.image = object as? NSImage
                }
            }
        }
        if !clip.thumbnailPath.isEmpty && clip.isColorCode && settings.isShowColorCode {
            PINCache.shared.object(forKeyAsync: clip.thumbnailPath) { [weak menuItem] _, _, object in
                DispatchQueue.main.async {
                    menuItem?.image = object as? NSImage
                }
            }
        }

        return menuItem
    }
}

// MARK: - Snippets
extension MenuManager {
    func addSnippetItems(_ menu: NSMenu, separateMenu: Bool) {
        let folderResults = realm.objects(CPYFolder.self).sorted(byKeyPath: #keyPath(CPYFolder.index), ascending: true)
        guard !folderResults.isEmpty else { return }
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

        folderResults
            .filter { $0.enable }
            .forEach { folder in
                let folderTitle = folder.title
                let subMenuItem = makeSubmenuItem(folderTitle)
                menu.addItem(subMenuItem)
                subMenuIndex += 1

                var i = firstIndex
                folder.snippets
                    .sorted(byKeyPath: #keyPath(CPYSnippet.index), ascending: true)
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

    func makeSnippetMenuItem(_ snippet: CPYSnippet, listNumber: Int, isMarkWithNumber: Bool, isShowIcon: Bool) -> NSMenuItem {
        let title = trimTitle(snippet.title)
        let titleWithMark = menuItemTitle(title, listNumber: listNumber, isMarkWithNumber: isMarkWithNumber)

        let menuItem = NSMenuItem(title: titleWithMark, action: #selector(AppDelegate.selectSnippetMenuItem(_:)), keyEquivalent: "")
        menuItem.representedObject = snippet.identifier
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
        statusItem?.image = image
        statusItem?.highlightMode = true
        statusItem?.toolTip = "\(Constants.Application.name) v\(Bundle.main.appVersion ?? "")"
        statusItem?.menu = clipMenu
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
        // ステータスバークリックなど popUpMenu() を経由しない表示経路でも
        // 表示直前に最新の内容へ再構築する
        switch menu {
        case clipMenu:
            rebuildMenuIfNeeded(.main)
        case historyMenu:
            rebuildMenuIfNeeded(.history)
        case snippetMenu:
            rebuildMenuIfNeeded(.snippet)
        default:
            break
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
                guard type == .keyDown else { return Unmanaged.passRetained(event) }
                guard MenuManager.menuIsOpen else { return Unmanaged.passRetained(event) }
                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                let flags = event.flags
                // Cmd / Alt / Ctrl が押されている場合は hjkl リマッピング不要。
                // Shift は HJKL をサポートするため修飾キーとして扱わない。
                let hasModifiers = !flags.isDisjoint(with: [.maskCommand, .maskAlternate, .maskControl])
                guard !hasModifiers else { return Unmanaged.passRetained(event) }
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
                default: return Unmanaged.passRetained(event)
                }
                event.setIntegerValueField(.keyboardEventKeycode, value: arrowKeyCode)
                // Shift フラグを除去して純粋な矢印キーとして送出する
                event.flags = flags.subtracting(.maskShift)
                var chars: [UniChar] = [arrowCharacter]
                event.keyboardSetUnicodeString(stringLength: 1, unicodeString: &chars)
                return Unmanaged.passRetained(event)
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
