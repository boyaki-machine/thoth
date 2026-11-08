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
import RxCocoa
import RxSwift

/// メニュー（スニペット）と各パネル（履歴・セキュアアイテム）の表示を統括するマネージャ。
///
/// ## 遅延再構築の設計
/// メニューは NSMenu インスタンスを固定し、内容だけを表示直前に再構築する。
/// 履歴・スニペット・設定の変更は世代カウンター（menuGeneration）を進めるのみで、
/// 実際の構築コスト（履歴数に比例）はメニューを開く瞬間まで支払わない。
///
/// ## 構成ファイル
/// - MenuManager.swift: 状態・バインディング・共通ヘルパー
/// - MenuManager+MenuBuilding.swift: メニュー項目の構築・vim キー CGEvent tap
/// - MenuManager+Popup.swift: ポップアップ表示・セキュアメニュー・セキュア出力
final class MenuManager: NSObject {

    // MARK: - Properties
    // Menus
    // インスタンスは固定し、内容だけを表示直前に再構築する（遅延構築）
    // 拡張ファイル (MenuManager+MenuBuilding / MenuManager+Popup) から参照するため internal
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
    fileprivate let shortenSymbol = "..."
    // 保存層（履歴・スニペット）の変更通知のオブザーバー
    fileprivate var libraryObserver: NSObjectProtocol?
    // Vim key navigation
    var vimKeyEventTap: CFMachPort?
    var vimKeyRunLoopSource: CFRunLoopSource?
    // メニューが開いている間だけ true にする（CGEvent tap コールバックから参照）
    static var menuIsOpen = false
    // ネストしたメニュー（サブメニューなど）の開閉を正確に追跡するカウンター
    var openMenuCount = 0
    // 認証〜パネル表示の間の再入を防ぐフラグ
    var isSecureMenuActive = false
    // 認証の結果を待っている間 true。パネルがまだ無いこの間を「フラグの取り残し」と誤判定しないために持つ
    var isSecureAuthenticationInProgress = false
    // セキュアアイテム選択パネル
    var securePickerPanel: CPYSecurePickerPanel?
    // willCloseNotification オブザーバートークン（解放するまで通知を受け取るために保持が必須）
    var secureCloseObserver: NSObjectProtocol?
    // 履歴検索パネル（履歴メニューの「検索...」/ "/" キーから開く）
    var historyPickerPanel: CPYHistoryPickerPanel?
    var historyPickerCloseObserver: NSObjectProtocol?

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

    /// ステータスアイコンの表示と設定の監視を開始する（保存層には触れない軽量処理）。
    /// 起動直後に呼んでメニューバーへのアイコン表示を最速にする
    func setup() {
        snippetMenu.delegate = self
        bind()
        setupVimKeyEventTap()
    }

    /// 保存層の変更通知（履歴・スニペット）の監視を開始する。
    /// 保存層の準備（LibraryProvider.prepare）完了後に呼ぶこと
    func bindLibraryNotifications() {
        // 変更のたびに再構築すると履歴数に比例したメインスレッド負荷がコピーごとに発生するため、
        // ここでは世代カウンターを進めるだけにして、構築はメニュー表示直前まで遅延する
        libraryObserver = notificationCenter.addObserver(forName: .thothLibraryDidChange, object: nil, queue: .main) { [weak self] _ in
            self?.setNeedsMenuRebuild()
        }
        // 準備完了前に開いたメニューは構築を見送っているため、ここで一度古い扱いにする
        setNeedsMenuRebuild()
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
        // メニューの再構築が必要になる設定キーを型別の配列で管理し、
        // 同型の Observable 生成コードの繰り返しを避ける
        let defaults = AppEnvironment.current.defaults
        let menuChangedBoolKeys = [Constants.UserDefaults.addClearHistoryMenuItem,
                                   Constants.UserDefaults.showIconInTheMenu,
                                   Constants.UserDefaults.menuItemsTitleStartWithZero,
                                   Constants.UserDefaults.menuItemsAreMarkedWithNumbers,
                                   Constants.UserDefaults.showToolTipOnMenuItem,
                                   Constants.UserDefaults.showImageInTheMenu,
                                   Constants.UserDefaults.addNumericKeyEquivalents,
                                   Constants.UserDefaults.showColorPreviewInTheMenu]
        let menuChangedIntKeys = [Constants.UserDefaults.maxHistorySize,
                                  Constants.UserDefaults.numberOfItemsPlaceInline,
                                  Constants.UserDefaults.numberOfItemsPlaceInsideFolder,
                                  Constants.UserDefaults.maxMenuItemTitleLength,
                                  Constants.UserDefaults.maxLengthOfToolTip]
        let boolObservables = menuChangedBoolKeys.map { key in
            defaults.rx.observe(Bool.self, key, options: [.new], retainSelf: false)
                .compactMap { $0 }.distinctUntilChanged().map { _ in }
        }
        let intObservables = menuChangedIntKeys.map { key in
            defaults.rx.observe(Int.self, key, options: [.new], retainSelf: false)
                .compactMap { $0 }.distinctUntilChanged().map { _ in }
        }
        Observable.merge(boolObservables + intObservables)
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
        // 保存層の準備前（起動直後の暗号化移行中など）は構築しない。
        // 準備完了時に bindLibraryNotifications が世代を進めるため、次回表示時に構築される
        guard LibraryProvider.isReady else { return }
        guard builtGenerations[type] != menuGeneration else { return }
        builtGenerations[type] = menuGeneration
        // メイン・履歴・セキュアは NSMenu ではなくパネルで表示するので、構築するものは無い
        guard type == .snippet else { return }
        snippetMenu.removeAllItems()
        addSnippetItems(snippetMenu, separateMenu: false)
    }

    func menuItemTitle(_ title: String, listNumber: NSInteger, isMarkWithNumber: Bool) -> String {
        return (isMarkWithNumber) ? "\(listNumber). \(title)" : title
    }

    func makeSubmenuItem(_ title: String) -> NSMenuItem {
        let subMenu = NSMenu(title: "")
        let subMenuItem = NSMenuItem(title: title, action: nil)
        subMenuItem.submenu = subMenu
        subMenuItem.image = (AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.showIconInTheMenu)) ? folderIcon : nil
        return subMenuItem
    }

    func trimTitle(_ title: String?) -> String {
        if title == nil { return "" }
        let theString = title!.trimmingCharacters(in: .whitespacesAndNewlines) as NSString

        let aRange = NSRange(location: 0, length: 0)
        var lineStart = 0, lineEnd = 0, contentsEnd = 0
        theString.getLineStart(&lineStart, end: &lineEnd, contentsEnd: &contentsEnd, for: aRange)

        var titleString = (lineEnd == theString.length) ? theString as String : theString.substring(to: contentsEnd)

        var maxMenuItemTitleLength = AppEnvironment.current.defaults.integer(forKey: Constants.UserDefaults.maxMenuItemTitleLength)
        // NSString の位置で切るので、長さはすべて UTF-16 単位でそろえる
        if maxMenuItemTitleLength < shortenSymbol.utf16.count {
            maxMenuItemTitleLength = shortenSymbol.utf16.count
        }

        if titleString.utf16.count > maxMenuItemTitleLength {
            let nsTitle = titleString as NSString
            // 絵文字などの途中で切らないよう、文字の境界まで戻す
            let cut = nsTitle.rangeOfComposedCharacterSequence(at: maxMenuItemTitleLength - shortenSymbol.utf16.count).location
            titleString = nsTitle.substring(to: cut) + shortenSymbol
        }

        return titleString as String
    }
}
