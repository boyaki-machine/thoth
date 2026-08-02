//
//  CPYSecureInfoSplitViewController.swift
//
//  Thoth
//  GitHub: https://github.com/boyaki-machine/Thoth
//

import Cocoa

/// セキュア情報確認ウィンドウの 2 ペイン構成（左＝一覧 / 右＝詳細）。
///
/// 左ペインは `NSSplitViewItem(sidebarWithViewController:)` で作る。
/// macOS 11 以降ではサイドバー用の vibrancy と選択色が自動で付き、
/// ライト/ダークの切り替えにも追従するため、固定色を持たずに済む。
///
/// キーボード操作用のローカルイベントモニターは **このコントローラが 1 つだけ**持つ。
/// 左右のペインそれぞれに登録すると、アプリ全体を監視するモニターが増えて
/// 他ウィンドウ（セキュアアイテム管理・編集シート）と干渉するため。
final class CPYSecureInfoSplitViewController: NSSplitViewController {

    let editor = SecureInfoEditor()

    private lazy var listViewController = CPYSecureInfoListViewController(editor: editor)
    private lazy var detailViewController = CPYSecureInfoDetailViewController()

    /// ユニットテストから右ペインの表示状態を確認するための入口
    var detailViewControllerForTesting: CPYSecureInfoDetailViewController { detailViewController }

    private var keyMonitor: Any?
    private var fallbackCommitTimer: Timer?
    private var windowObservers: [NSObjectProtocol] = []
    /// 保存失敗の警告を 1 セッションで繰り返さないためのフラグ
    private var hasShownCommitFailure = false

    /// 最後の入力から保険として保存するまでの秒数
    private static let fallbackCommitInterval: TimeInterval = 20

    private enum Layout {
        static let sidebarMinWidth: CGFloat = 180
        static let sidebarMaxWidth: CGFloat = 320
    }

    deinit {
        fallbackCommitTimer?.invalidate()
        windowObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let sidebarItem = NSSplitViewItem(sidebarWithViewController: listViewController)
        sidebarItem.minimumThickness = Layout.sidebarMinWidth
        sidebarItem.maximumThickness = Layout.sidebarMaxWidth
        // 折りたためると右ペインだけの状態になり、アイテムを選び直せなくなる
        sidebarItem.canCollapse = false
        addSplitViewItem(sidebarItem)

        addSplitViewItem(NSSplitViewItem(viewController: detailViewController))

        listViewController.onSelectionChange = { [weak self] item in
            guard let self = self else { return }
            // 別のアイテムへ移る前に、直前の編集内容を確定させる。
            // draft は自分の itemID を持っているので、選択が変わったあとでも正しい相手に保存される
            self.commitIfNeeded()
            self.editor.beginEditing(itemID: item?.itemID)
            self.detailViewController.show(item: self.editor.draft)
        }
        detailViewController.onTitleEdited = { [weak self] title in
            self?.editor.updateTitle(title)
            self?.scheduleFallbackCommit()
        }
        detailViewController.onFieldEdited = { [weak self] field, label, value in
            self?.editor.updateField(fieldID: field.fieldID, label: label, value: value)
            self?.scheduleFallbackCommit()
        }
        detailViewController.onEditingEnded = { [weak self] in
            self?.commitIfNeeded()
        }
    }

    // MARK: - Data

    /// Keychain からアイテムを読み直して画面へ反映する
    func reloadItems() {
        let service = AppEnvironment.current.secureMenuService
        editor.setItems(service.loadAllItems())
        // 読み出せていない状態では編集させない。編集できても保存が拒否されるだけで、
        // 入力した内容が失われるだけになる
        editor.isReadOnly = service.isKeychainAccessDenied
        detailViewController.isReadOnly = editor.isReadOnly
        listViewController.reload()
        // 警告はシートとして出す。ウィンドウがまだ無い状態で NSAlert に nil を渡すと
        // runModal() になり、画面に出ないまま操作をブロックしてしまう
        if service.isKeychainAccessDenied, let window = view.window {
            NSAlert.showNotice(message: L10n.secureItems,
                               informative: L10n.secureItemsKeychainAccessDenied,
                               for: window)
        }
    }

    // MARK: - Commit

    /// 未保存の変更があれば Keychain へ保存する。
    ///
    /// キー入力ごとの遅延保存（debounce）は**行わない**。`SecureMenuService.save(_:)` は
    /// 値が変わるたびに変更履歴を 1 件積む（上限 10 件）ため、打鍵の途中経過が履歴を
    /// 食い潰して本当の旧値が押し出されてしまう。確定は編集の区切りでのみ行う。
    @discardableResult
    func commitIfNeeded() -> Bool {
        cancelFallbackCommit()
        switch editor.commitOutcome() {
        case .notNeeded:
            return true
        case .titleRequired:
            // 編集内容は破棄せず保持したまま知らせる（タイトルを入れれば保存できる）
            showCommitFailure(informative: L10n.secureInfoTitleRequired)
            return false
        case .ready(let item):
            return save(item)
        }
    }

    private func save(_ item: SecureMenuItem) -> Bool {
        let service = AppEnvironment.current.secureMenuService
        guard service.save(item) else {
            showCommitFailure(informative: L10n.secureInfoSaveFailed)
            return false
        }
        // 保存後の内容（変更履歴が追記された状態）で作業コピーを更新する
        let saved = service.loadAllItems().first { $0.itemID == item.itemID } ?? item
        editor.markCommitted(saved)
        listViewController.refreshRow(itemID: saved.itemID)
        return true
    }

    /// 保存できなかったことを知らせる。編集内容は保持したままなので、
    /// 原因を直して ⌘S で再試行できる。同じセッションで警告を連打しない
    private func showCommitFailure(informative: String) {
        guard !hasShownCommitFailure, let window = view.window else { return }
        hasShownCommitFailure = true
        NSAlert.showNotice(message: L10n.secureInfo, informative: informative, for: window)
    }

    // MARK: - Fallback commit

    /// NSTextView は編集終了の通知が来ないままウィンドウが閉じられることがあるため、
    /// 最後の入力からしばらく経ったら保険として保存する
    private func scheduleFallbackCommit() {
        cancelFallbackCommit()
        let timer = Timer(timeInterval: Self.fallbackCommitInterval, repeats: false) { [weak self] _ in
            self?.commitIfNeeded()
        }
        RunLoop.main.add(timer, forMode: .common)
        fallbackCommitTimer = timer
    }

    private func cancelFallbackCommit() {
        fallbackCommitTimer?.invalidate()
        fallbackCommitTimer = nil
    }

    // MARK: - Keyboard

    override func viewDidAppear() {
        super.viewDidAppear()
        installKeyMonitor()
        installCommitObservers()
        hasShownCommitFailure = false
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        if let keyMonitor = keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        // 編集中のテキストを確定させてから保存する（フィールドエディタを切り離す）
        view.window?.makeFirstResponder(nil)
        commitIfNeeded()
        windowObservers.forEach { NotificationCenter.default.removeObserver($0) }
        windowObservers = []
    }

    /// ウィンドウが非アクティブになったとき・アプリ終了時にも取りこぼさず保存する
    private func installCommitObservers() {
        guard windowObservers.isEmpty, let window = view.window else { return }
        let center = NotificationCenter.default
        windowObservers.append(center.addObserver(forName: NSWindow.didResignKeyNotification,
                                                  object: window, queue: .main) { [weak self] _ in
            self?.view.window?.makeFirstResponder(nil)
            self?.commitIfNeeded()
        })
        windowObservers.append(center.addObserver(forName: NSApplication.willTerminateNotification,
                                                  object: nil, queue: .main) { [weak self] _ in
            self?.view.window?.makeFirstResponder(nil)
            self?.commitIfNeeded()
        })
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, event.window === self.view.window else { return event }
            return self.handleKeyDown(event) ? nil : event
        }
    }

    /// - Returns: イベントを消費した場合 true
    private func handleKeyDown(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        // テキスト入力中（検索欄など）は文字入力を優先し、素通しする
        let isEditingText = view.window?.firstResponder is NSTextView

        if modifiers == .command, event.charactersIgnoringModifiers == "f" {
            listViewController.focusSearchField()
            return true
        }
        // ⌘S: 明示保存。編集中のテキストを確定させてから保存する
        if modifiers == .command, event.charactersIgnoringModifiers == "s" {
            view.window?.makeFirstResponder(nil)
            hasShownCommitFailure = false
            commitIfNeeded()
            return true
        }

        guard !isEditingText, modifiers.isEmpty else { return false }

        switch event.keyCode {
        case 38: // j
            listViewController.moveSelection(by: 1)
            return true
        case 40: // k
            listViewController.moveSelection(by: -1)
            return true
        case 44: // /
            listViewController.focusSearchField()
            return true
        default:
            return false
        }
    }

    /// Esc でウィンドウを閉じる
    override func cancelOperation(_ sender: Any?) {
        view.window?.performClose(sender)
    }
}
