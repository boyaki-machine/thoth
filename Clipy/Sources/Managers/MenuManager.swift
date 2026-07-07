//
//  MenuManager.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Econa77 on 2016/03/08.
//
//  Copyright © 2015-2018 Clipy Project.
//

import Cocoa
import PINCache
import RealmSwift
import RxCocoa
import RxSwift

final class MenuManager: NSObject {

    // MARK: - Properties
    // Menus
    // インスタンスは固定し、内容だけを表示直前に再構築する（遅延構築）
    fileprivate let clipMenu = NSMenu(title: Constants.Application.name)
    fileprivate let historyMenu = NSMenu(title: Constants.Menu.history)
    fileprivate let snippetMenu = NSMenu(title: Constants.Menu.snippet)
    // 履歴・スニペット・設定が変わるたびにインクリメントされる世代カウンター。
    // メニュー表示直前に各メニューの構築済み世代と比較し、古い場合のみ再構築する。
    // これによりコピーのたびに発生していたメインスレッドでの全メニュー再構築を排除する。
    fileprivate var menuGeneration = 1
    fileprivate var builtGenerations = [MenuType: Int]()
    // StatusMenu
    fileprivate var statusItem: NSStatusItem?
    // Icon Cache
    fileprivate let folderIcon = Asset.iconFolder.image
    fileprivate let snippetIcon = Asset.iconText.image
    // Other
    fileprivate let disposeBag = DisposeBag()
    fileprivate let notificationCenter = NotificationCenter.default
    fileprivate let kMaxKeyEquivalents = 10
    fileprivate let shortenSymbol = "..."
    // Realm
    fileprivate let realm = try! Realm()
    fileprivate var clipToken: NotificationToken?
    fileprivate var snippetToken: NotificationToken?
    // Vim key navigation
    fileprivate var vimKeyEventTap: CFMachPort?
    fileprivate var vimKeyRunLoopSource: CFRunLoopSource?
    // メニューが開いている間だけ true にする（CGEvent tap コールバックから参照）
    fileprivate static var menuIsOpen = false
    // ネストしたメニュー（サブメニューなど）の開閉を正確に追跡するカウンター
    private var openMenuCount = 0
    // 認証〜パネル表示の間の再入を防ぐフラグ
    private var isSecureMenuActive = false
    // セキュアアイテム選択パネル
    private var securePickerPanel: CPYSecurePickerPanel?
    // willCloseNotification オブザーバートークン（解放するまで通知を受け取るために保持が必須）
    private var secureCloseObserver: NSObjectProtocol?

    // MARK: - Enum Values
    enum StatusType: Int {
        case none, black, white
    }

    // MARK: - Initialize
    override init() {
        super.init()
        folderIcon.isTemplate = true
        folderIcon.size = NSSize(width: 15, height: 13)
        snippetIcon.isTemplate = true
        snippetIcon.size = NSSize(width: 12, height: 13)
    }

    func setup() {
        clipMenu.delegate = self
        historyMenu.delegate = self
        snippetMenu.delegate = self
        bind()
        setupVimKeyEventTap()
    }

}

// MARK: - Popup Menu
extension MenuManager {
    func popUpMenu(_ type: MenuType) {
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

    func popUpSecureMenu() {
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
                if let obs = secureCloseObserver { NotificationCenter.default.removeObserver(obs) }
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
                context.record(parentItemId: selection.parentItemId, fieldIndex: selection.fieldIndex)
                AppEnvironment.current.pasteService.copyToPasteboard(with: selection.fieldValue)
                self?.isSecureMenuActive  = false
                self?.securePickerPanel   = nil
                self?.secureCloseObserver = nil
                // ペースト先アプリをアクティブ化してからペーストする。
                // activate は非同期で完了するため少し待ってから Cmd+V を送出する。
                callerApp?.activate(options: [.activateIgnoringOtherApps])
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    AppEnvironment.current.pasteService.paste()
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + SecureSelectionContext.recencyWindow) {
                    NSPasteboard.general.clearContents()
                }
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

    func popUpSnippetFolder(_ folder: CPYFolder) {
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

// MARK: - Binding
private extension MenuManager {
    func bind() {
        // Realm Notification
        // 変更のたびに再構築すると履歴数に比例したメインスレッド負荷がコピーごとに発生するため、
        // ここでは世代カウンターを進めるだけにして、構築はメニュー表示直前まで遅延する
        clipToken = realm.objects(CPYClip.self)
                        .observe { [weak self] _ in
                            self?.setNeedsMenuRebuild()
                        }
        snippetToken = realm.objects(CPYFolder.self)
                        .observe { [weak self] _ in
                            self?.setNeedsMenuRebuild()
                        }
        // Menu icon
        AppEnvironment.current.defaults.rx.observe(Int.self, Constants.UserDefaults.showStatusItem, retainSelf: false)
            .compactMap { $0 }
            .asDriver(onErrorDriveWith: .empty())
            .drive(onNext: { [weak self] key in
                self?.changeStatusItem(StatusType(rawValue: key) ?? .black)
            })
            .disposed(by: disposeBag)
        // Sort clips
        AppEnvironment.current.defaults.rx.observe(Bool.self, Constants.UserDefaults.reorderClipsAfterPasting, options: [.new], retainSelf: false)
            .compactMap { $0 }
            .asDriver(onErrorDriveWith: .empty())
            .drive(onNext: { [weak self] _ in
                self?.setNeedsMenuRebuild()
            })
            .disposed(by: disposeBag)
        // Edit snippets
        notificationCenter.rx.notification(Notification.Name(rawValue: Constants.Notification.closeSnippetEditor))
            .asDriver(onErrorDriveWith: .empty())
            .drive(onNext: { [weak self] _ in
                self?.setNeedsMenuRebuild()
            })
            .disposed(by: disposeBag)
        // Observe change preference settings
        let defaults = AppEnvironment.current.defaults
        var menuChangedObservables = [Observable<Void>]()
        menuChangedObservables.append(defaults.rx.observe(Bool.self, Constants.UserDefaults.addClearHistoryMenuItem, options: [.new], retainSelf: false)
                                        .compactMap { $0 }.distinctUntilChanged().map { _ in })
        menuChangedObservables.append(defaults.rx.observe(Int.self, Constants.UserDefaults.maxHistorySize, options: [.new], retainSelf: false)
                                        .compactMap { $0 }.distinctUntilChanged().map { _ in })
        menuChangedObservables.append(defaults.rx.observe(Bool.self, Constants.UserDefaults.showIconInTheMenu, options: [.new], retainSelf: false)
                                        .compactMap { $0 }.distinctUntilChanged().map { _ in })
        menuChangedObservables.append(defaults.rx.observe(Int.self, Constants.UserDefaults.numberOfItemsPlaceInline, options: [.new], retainSelf: false)
                                        .compactMap { $0 }.distinctUntilChanged().map { _ in })
        menuChangedObservables.append(defaults.rx.observe(Int.self, Constants.UserDefaults.numberOfItemsPlaceInsideFolder, options: [.new], retainSelf: false)
                                        .compactMap { $0 }.distinctUntilChanged().map { _ in })
        menuChangedObservables.append(defaults.rx.observe(Int.self, Constants.UserDefaults.maxMenuItemTitleLength, options: [.new], retainSelf: false)
                                        .compactMap { $0 }.distinctUntilChanged().map { _ in })
        menuChangedObservables.append(defaults.rx.observe(Bool.self, Constants.UserDefaults.menuItemsTitleStartWithZero, options: [.new], retainSelf: false)
                                        .compactMap { $0 }.distinctUntilChanged().map { _ in })
        menuChangedObservables.append(defaults.rx.observe(Bool.self, Constants.UserDefaults.menuItemsAreMarkedWithNumbers, options: [.new], retainSelf: false)
                                        .compactMap { $0 }.distinctUntilChanged().map { _ in })
        menuChangedObservables.append(defaults.rx.observe(Bool.self, Constants.UserDefaults.showToolTipOnMenuItem, options: [.new], retainSelf: false)
                                        .compactMap { $0 }.distinctUntilChanged().map { _ in })
        menuChangedObservables.append(defaults.rx.observe(Bool.self, Constants.UserDefaults.showImageInTheMenu, options: [.new], retainSelf: false)
                                        .compactMap { $0 }.distinctUntilChanged().map { _ in })
        menuChangedObservables.append(defaults.rx.observe(Bool.self, Constants.UserDefaults.addNumericKeyEquivalents, options: [.new], retainSelf: false)
                                        .compactMap { $0 }.distinctUntilChanged().map { _ in })
        menuChangedObservables.append(defaults.rx.observe(Int.self, Constants.UserDefaults.maxLengthOfToolTip, options: [.new], retainSelf: false)
                                        .compactMap { $0 }.distinctUntilChanged().map { _ in })
        menuChangedObservables.append(defaults.rx.observe(Bool.self, Constants.UserDefaults.showColorPreviewInTheMenu, options: [.new], retainSelf: false)
                                        .compactMap { $0 }.distinctUntilChanged().map { _ in })
        Observable.merge(menuChangedObservables)
            .asDriver(onErrorDriveWith: .empty())
            .drive(onNext: { [weak self] in
                self?.setNeedsMenuRebuild()
            })
            .disposed(by: disposeBag)
    }
}

// MARK: - Menus
private extension MenuManager {
    /// メニューの内容が古くなったことを記録する。実際の構築は表示直前まで行わない。
    func setNeedsMenuRebuild() {
        menuGeneration += 1
    }

    /// 表示対象のメニューが古い世代の場合のみ、その 1 つだけを再構築する
    func rebuildMenuIfNeeded(_ type: MenuType) {
        guard builtGenerations[type] != menuGeneration else { return }
        builtGenerations[type] = menuGeneration
        switch type {
        case .main:
            rebuildClipMenu()
        case .history:
            historyMenu.removeAllItems()
            addHistoryItems(historyMenu)
        case .snippet:
            snippetMenu.removeAllItems()
            addSnippetItems(snippetMenu, separateMenu: false)
        case .secure:
            break
        }
    }

    func rebuildClipMenu() {
        clipMenu.removeAllItems()

        addHistoryItems(clipMenu)
        addSnippetItems(clipMenu, separateMenu: true)

        clipMenu.addItem(NSMenuItem.separator())

        if AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.addClearHistoryMenuItem) {
            clipMenu.addItem(NSMenuItem(title: L10n.clearHistory, action: #selector(AppDelegate.clearAllHistory)))
        }

        clipMenu.addItem(NSMenuItem(title: L10n.editSnippets, action: #selector(AppDelegate.showSnippetEditorWindow)))
        clipMenu.addItem(NSMenuItem(title: L10n.preferences, action: #selector(AppDelegate.showPreferenceWindow)))
        clipMenu.addItem(NSMenuItem.separator())
        clipMenu.addItem(NSMenuItem(title: L10n.quitClipy, action: #selector(AppDelegate.terminate)))
    }

    func menuItemTitle(_ title: String, listNumber: NSInteger, isMarkWithNumber: Bool) -> String {
        return (isMarkWithNumber) ? "\(listNumber). \(title)" : title
    }

    func makeSubmenuItem(_ count: Int, start: Int, end: Int, numberOfItems: Int) -> NSMenuItem {
        var count = count
        if start == 0 {
            count -= 1
        }
        var lastNumber = count + numberOfItems
        if end < lastNumber {
            lastNumber = end
        }
        let menuItemTitle = "\(count + 1) - \(lastNumber)"
        return makeSubmenuItem(menuItemTitle)
    }

    func makeSubmenuItem(_ title: String) -> NSMenuItem {
        let subMenu = NSMenu(title: "")
        let subMenuItem = NSMenuItem(title: title, action: nil)
        subMenuItem.submenu = subMenu
        subMenuItem.image = (AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.showIconInTheMenu)) ? folderIcon : nil
        return subMenuItem
    }

    func incrementListNumber(_ listNumber: NSInteger, max: NSInteger, start: NSInteger) -> NSInteger {
        var listNumber = listNumber + 1
        if listNumber == max && max == 10 && start == 1 {
            listNumber = 0
        }
        return listNumber
    }

    func trimTitle(_ title: String?) -> String {
        if title == nil { return "" }
        let theString = title!.trimmingCharacters(in: .whitespacesAndNewlines) as NSString

        let aRange = NSRange(location: 0, length: 0)
        var lineStart = 0, lineEnd = 0, contentsEnd = 0
        theString.getLineStart(&lineStart, end: &lineEnd, contentsEnd: &contentsEnd, for: aRange)

        var titleString = (lineEnd == theString.length) ? theString as String : theString.substring(to: contentsEnd)

        var maxMenuItemTitleLength = AppEnvironment.current.defaults.integer(forKey: Constants.UserDefaults.maxMenuItemTitleLength)
        if maxMenuItemTitleLength < shortenSymbol.count {
            maxMenuItemTitleLength = shortenSymbol.count
        }

        if titleString.utf16.count > maxMenuItemTitleLength {
            titleString = (titleString as NSString).substring(to: maxMenuItemTitleLength - shortenSymbol.count) + shortenSymbol
        }

        return titleString as String
    }
}

// MARK: - Clips
private extension MenuManager {
    /// メニューアイテム描画に必要な設定値をまとめた構造体。
    /// ループ外で一度だけ UserDefaults を読み込み、N アイテム分の繰り返しアクセスを排除する。
    struct ClipMenuItemSettings {
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

    func makeClipMenuItem(_ clip: CPYClip, index: Int, listNumber: Int, settings: ClipMenuItemSettings) -> NSMenuItem {
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
private extension MenuManager {
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
private extension MenuManager {
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
        statusItem?.toolTip = "\(Constants.Application.name)\(Bundle.main.appVersion ?? "")"
        statusItem?.menu = clipMenu
    }

    func removeStatusItem() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }
}

// MARK: - Settings
private extension MenuManager {
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
private extension MenuManager {
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
                let hasModifiers = !flags.intersection([.maskCommand, .maskAlternate, .maskControl]).isEmpty
                guard !hasModifiers else { return Unmanaged.passRetained(event) }
                // h=4, j=38, k=40, l=37 / H=4+Shift, J=38+Shift, K=40+Shift, L=37+Shift
                // NSMenu は characters フィールドでナビゲーションを判断するため
                // keyCode・unicode 文字列・フラグの 3 つを矢印キーに変換する必要がある
                let arrowKeyCode: Int64
                let arrowChar: UniChar
                switch keyCode {
                case 4:  arrowKeyCode = 123; arrowChar = 0xF702  // h/H → Left
                case 38: arrowKeyCode = 125; arrowChar = 0xF701  // j/J → Down
                case 40: arrowKeyCode = 126; arrowChar = 0xF700  // k/K → Up
                case 37: arrowKeyCode = 124; arrowChar = 0xF703  // l/L → Right
                default: return Unmanaged.passRetained(event)
                }
                event.setIntegerValueField(.keyboardEventKeycode, value: arrowKeyCode)
                // Shift フラグを除去して純粋な矢印キーとして送出する
                event.flags = flags.subtracting(.maskShift)
                var chars: [UniChar] = [arrowChar]
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
