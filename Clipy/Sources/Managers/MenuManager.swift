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
    // 拡張ファイル (MenuManager+MenuBuilding / MenuManager+Popup) から参照するため internal
    let clipMenu = NSMenu(title: Constants.Application.name)
    let historyMenu = NSMenu(title: Constants.Menu.history)
    let snippetMenu = NSMenu(title: Constants.Menu.snippet)
    // 履歴・スニペット・設定が変わるたびにインクリメントされる世代カウンター。
    // メニュー表示直前に各メニューの構築済み世代と比較し、古い場合のみ再構築する。
    // これによりコピーのたびに発生していたメインスレッドでの全メニュー再構築を排除する。
    fileprivate var menuGeneration = 1
    fileprivate var builtGenerations = [MenuType: Int]()
    // StatusMenu
    var statusItem: NSStatusItem?
    // Icon Cache
    fileprivate let folderIcon = Asset.iconFolder.image
    let snippetIcon = Asset.iconText.image
    // Other
    fileprivate let disposeBag = DisposeBag()
    fileprivate let notificationCenter = NotificationCenter.default
    let kMaxKeyEquivalents = 10
    fileprivate let shortenSymbol = "..."
    // Realm
    // 遅延プロパティにすることで、Realm の構成・移行が完了する前
    // （MenuManager 生成時点）にファイルを開いてしまわないようにする。
    // 初回アクセスは bindRealmNotifications()（RealmProvider.warmUp 完了後）
    lazy var realm: Realm = try! Realm()
    fileprivate var clipToken: NotificationToken?
    fileprivate var snippetToken: NotificationToken?
    // Vim key navigation
    var vimKeyEventTap: CFMachPort?
    var vimKeyRunLoopSource: CFRunLoopSource?
    // メニューが開いている間だけ true にする（CGEvent tap コールバックから参照）
    static var menuIsOpen = false
    // ネストしたメニュー（サブメニューなど）の開閉を正確に追跡するカウンター
    var openMenuCount = 0
    // 認証〜パネル表示の間の再入を防ぐフラグ
    var isSecureMenuActive = false
    // セキュアアイテム選択パネル
    var securePickerPanel: CPYSecurePickerPanel?
    // willCloseNotification オブザーバートークン（解放するまで通知を受け取るために保持が必須）
    var secureCloseObserver: NSObjectProtocol?

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

    /// ステータスアイコンの表示と設定の監視を開始する（Realm には触れない軽量処理）。
    /// 起動直後に呼んでメニューバーへのアイコン表示を最速にする
    func setup() {
        clipMenu.delegate = self
        historyMenu.delegate = self
        snippetMenu.delegate = self
        bind()
        setupVimKeyEventTap()
    }

    /// Realm の変更通知（履歴・スニペット）の監視を開始する。
    /// Realm 初期化（RealmProvider.warmUp）完了後に呼ぶこと
    func bindRealmNotifications() {
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
    }

}

// MARK: - Binding
private extension MenuManager {
    func bind() {
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
// 拡張ファイル (MenuManager+MenuBuilding / MenuManager+Popup) から呼び出すため internal
extension MenuManager {
    /// メニューの内容が古くなったことを記録する。実際の構築は表示直前まで行わない。
    fileprivate func setNeedsMenuRebuild() {
        menuGeneration += 1
    }

    /// 表示対象のメニューが古い世代の場合のみ、その 1 つだけを再構築する
    func rebuildMenuIfNeeded(_ type: MenuType) {
        // Realm の準備前（起動直後の暗号化移行中など）は構築しない。
        // 準備完了時に Realm 通知が世代を進めるため、次回表示時に構築される
        guard RealmProvider.isReady else { return }
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

    fileprivate func rebuildClipMenu() {
        clipMenu.removeAllItems()

        addHistoryItems(clipMenu)
        addSnippetItems(clipMenu, separateMenu: true)

        // ツールセクション（スニペットセクションの直後）
        clipMenu.addItem(NSMenuItem.separator())
        let toolsLabelItem = NSMenuItem(title: L10n.tools, action: nil)
        toolsLabelItem.isEnabled = false
        clipMenu.addItem(toolsLabelItem)
        let generatePasswordItem = NSMenuItem(title: "\(L10n.generateNewPassword) (&p)", action: #selector(AppDelegate.showPasswordGeneratorWindow))
        // メニュー表示中に p キーで起動できるようにする
        generatePasswordItem.keyEquivalent = "p"
        generatePasswordItem.keyEquivalentModifierMask = []
        clipMenu.addItem(generatePasswordItem)

        let cryptoItem = NSMenuItem(title: "\(L10n.encryptDecrypt) (&E)", action: #selector(AppDelegate.showCryptoWindow))
        // メニュー表示中に e キーで起動できるようにする
        cryptoItem.keyEquivalent = "e"
        cryptoItem.keyEquivalentModifierMask = []
        clipMenu.addItem(cryptoItem)

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
