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

    // キー操作の拡張（+Keyboard.swift）から参照するため internal
    lazy var listViewController = CPYSecureInfoListViewController(editor: editor)
    lazy var detailViewController = CPYSecureInfoDetailViewController()

    /// ユニットテストから右ペインの表示状態を確認するための入口
    var detailViewControllerForTesting: CPYSecureInfoDetailViewController { detailViewController }

    var keyMonitor: Any?
    private var fallbackCommitTimer: Timer?
    // 監視トークンは登録したセンターごとに分けて持つ。
    // まとめて持つと解除時にどのセンターへ返せばよいか分からなくなる
    private var windowObservers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var distributedObservers: [NSObjectProtocol] = []
    /// 保存失敗の警告を 1 セッションで繰り返さないためのフラグ
    var hasShownCommitFailure = false
    /// 画面へ反映済みの変更番号。自分が起こした変更で再読込しないための目印
    private var appliedChangeToken = 0
    /// 自分がデータを変更している最中か。
    /// 変更通知は NotificationCenter の仕様上、メインスレッドからの post だと
    /// **保存処理の途中で同期的に**届く。その時点では通し番号の更新も
    /// 保存完了の記録も済んでいないため、通し番号だけでは自分の変更を見分けられない
    private var isApplyingLocalChange = false

    /// 自分の変更として実行する。実行中に届いた変更通知は無視し、
    /// 終了時に反映済みの通し番号を更新する
    private func performLocalChange<T>(_ body: () -> T) -> T {
        isApplyingLocalChange = true
        defer {
            isApplyingLocalChange = false
            appliedChangeToken = AppEnvironment.current.secureMenuService.itemsChangeToken
        }
        return body()
    }

    /// 最後の入力から保険として保存するまでの秒数
    private static let fallbackCommitInterval: TimeInterval = 20

    /// 画面ロックの分散通知。AppKit / NSWorkspace には対応する通知が無い
    static let screenIsLockedNotification = Notification.Name("com.apple.screenIsLocked")

    private enum Layout {
        static let sidebarMinWidth: CGFloat = 180
        static let sidebarMaxWidth: CGFloat = 320
    }

    deinit {
        fallbackCommitTimer?.invalidate()
        windowObservers.forEach { NotificationCenter.default.removeObserver($0) }
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        distributedObservers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
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
            let editingItemID = self.editor.draft?.itemID
            guard self.commitIfNeeded() else {
                // 保存できなかった（タイトル未入力など）場合は編集内容を捨てずに戻す。
                // ここで切り替えると「編集内容は保持されています」という案内と食い違う
                if let editingItemID = editingItemID, editingItemID != item?.itemID {
                    self.listViewController.restoreSelection(itemID: editingItemID)
                }
                return
            }
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
        detailViewController.onFieldMaskToggled = { [weak self] field, isPassword in
            guard let self = self else { return }
            self.editor.updateField(fieldID: field.fieldID, isPassword: isPassword)
            // マスクの有無で行に並ぶボタンが変わるため作り直す
            self.detailViewController.show(item: self.editor.draft)
            self.commitIfNeeded()
        }
        detailViewController.onFieldDeleteRequested = { [weak self] field in
            self?.removeField(field)
        }
        detailViewController.onAddFieldRequested = { [weak self] template in
            self?.addField(template)
        }
        detailViewController.onAddTOTPRequested = { [weak self] in
            self?.presentTOTPImport()
        }
        listViewController.onAddItemRequested = { [weak self] in
            self?.addItem()
        }
        listViewController.onDeleteItemRequested = { [weak self] in
            self?.confirmDeleteSelectedItem()
        }
    }

    // MARK: - Fields

    private func addField(_ template: SecureInfoFieldTemplate) {
        guard editor.draft != nil else { NSSound.beep(); return }
        guard editor.addField(kind: template.kind, label: template.defaultLabel,
                              isPassword: template.isPassword) != nil else { return }
        detailViewController.show(item: editor.draft)
        commitIfNeeded()
    }

    private func removeField(_ field: SecureMenuItem.Field) {
        guard let window = view.window else { return }
        NSAlert.showConfirmation(message: L10n.secureInfoRemoveField,
                                 informative: L10n.secureInfoRemoveFieldConfirmation,
                                 confirmTitle: L10n.secureInfoRemoveField, cancelTitle: L10n.cancel,
                                 for: window) { [weak self] in
            guard let self = self, self.editor.removeField(fieldID: field.fieldID) else { return }
            self.detailViewController.show(item: self.editor.draft)
            self.commitIfNeeded()
        }
    }

    /// TOTP の取り込みシートを開く（既存の取り込み画面を再利用する）
    private func presentTOTPImport() {
        guard editor.draft != nil else { NSSound.beep(); return }
        let importViewController = CPYTOTPImportViewController()
        importViewController.onImport = { [weak self] secret in
            guard let self = self else { return }
            self.editor.addField(kind: .totp, label: L10n.totpDefaultFieldLabel, value: secret)
            self.detailViewController.show(item: self.editor.draft)
            self.commitIfNeeded()
        }
        presentAsSheet(importViewController)
    }

    /// フォーカスのあるフィールド行を上下に動かす（Ctrl+j / Ctrl+k）
    func moveFocusedField(by offset: Int) {
        guard let row = detailViewController.focusedRow else { NSSound.beep(); return }
        let fieldID = row.field.fieldID
        guard editor.moveField(fieldID: fieldID, by: offset) else { NSSound.beep(); return }
        detailViewController.show(item: editor.draft)
        // 行を作り直したのでフォーカスが失われている。動かした行へ戻さないと、
        // 続けて Ctrl+j を押したときに一覧のアイテム側が動いてしまう
        detailViewController.focusRow(fieldID: fieldID)
        commitIfNeeded()
    }

    // MARK: - Items

    /// アイテムを新規作成して選択する。
    /// タイトルが空だと保存できないため、既定のタイトルを入れた状態で作る
    func addItem() {
        guard !editor.isReadOnly else { NSSound.beep(); return }
        // 直前の編集を保存できない状態で追加すると、その編集が失われる
        guard commitIfNeeded() else { return }
        let service = AppEnvironment.current.secureMenuService
        let newItem = SecureMenuItem(title: L10n.newSecureItemTitle)
        let added: Bool = performLocalChange {
            guard service.save(newItem) else {
                showCommitFailure(informative: L10n.secureInfoSaveFailed)
                return false
            }
            // 検索で絞り込んだままだと新しいアイテムが見えないので解除する
            listViewController.clearSearch()
            editor.setItems(service.loadAllItems())
            editor.selectItem(itemID: newItem.itemID)
            listViewController.reload()
            return true
        }
        guard added else { return }
        detailViewController.focusTitleField()
    }

    func confirmDeleteSelectedItem() {
        guard !editor.isReadOnly, let item = editor.selectedItem, let window = view.window else {
            NSSound.beep()
            return
        }
        NSAlert.showConfirmation(message: L10n.deleteSecureItem,
                                 informative: L10n.areYouSureWantToDeleteThisSecureItem,
                                 confirmTitle: L10n.deleteSecureItem, cancelTitle: L10n.cancel,
                                 for: window) { [weak self] in
            self?.deleteItem(item)
        }
    }

    private func deleteItem(_ item: SecureMenuItem) {
        let service = AppEnvironment.current.secureMenuService
        // 削除するアイテムの未保存編集は捨てる（保存すると復活してしまう）
        editor.beginEditing(itemID: nil)
        performLocalChange {
            guard service.delete(itemID: item.itemID) else {
                showCommitFailure(informative: L10n.secureInfoSaveFailed)
                return
            }
            editor.setItems(service.loadAllItems())
            editor.selectItem(itemID: nil)
            listViewController.reload()
        }
    }

    /// 選択中アイテムを一覧内で上下に動かす（Ctrl+j / Ctrl+k）。
    /// 絞り込み中は見えている順と保存順が一致しないため行わない
    func moveSelectedItem(by offset: Int) {
        guard !editor.isReadOnly, editor.query.isEmpty, let item = editor.selectedItem else {
            NSSound.beep()
            return
        }
        // reorderItems は渡した配列の内容をそのまま書き戻すため、**必ず先にコミットしてから**
        // 並びを組み立てること。順序を逆にすると、直前の編集を保存前の内容で上書きしてしまう
        commitIfNeeded()
        guard let reordered = SecureInfoEditor.reordered(editor.items, movingItemID: item.itemID, by: offset) else {
            NSSound.beep()
            return
        }
        let service = AppEnvironment.current.secureMenuService
        performLocalChange {
            guard service.reorderItems(reordered) else {
                showCommitFailure(informative: L10n.secureInfoSaveFailed)
                return
            }
            editor.setItems(service.loadAllItems())
            listViewController.reload()
        }
    }

    // MARK: - Data

    /// Keychain からアイテムを読み直して画面へ反映する
    func reloadItems() {
        let service = AppEnvironment.current.secureMenuService
        appliedChangeToken = service.itemsChangeToken
        detailViewController.hideExternalChangeBanner()
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
        return performLocalChange {
            guard service.save(item) else {
                showCommitFailure(informative: L10n.secureInfoSaveFailed)
                return false
            }
            // 保存後の内容（変更履歴が追記された状態）で作業コピーを更新する
            let saved = service.loadAllItems().first { $0.itemID == item.itemID } ?? item
            editor.markCommitted(saved)
            listViewController.refreshRow(itemID: saved.itemID)
            // 自分の保存で案内バーが残っていたら消す
            detailViewController.hideExternalChangeBanner()
            return true
        }
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
        removeCommitObservers()
        // 閉じたあともメモリに平文が残り続けないよう、保持しているデータを破棄する。
        // 次に開くときは showWindow が reloadItems で読み直す
        editor.clearSensitiveData()
        // OS 側の認証状態も持ち越さない。常駐したまま残り続けると、
        // 次に開くときの認証ゲートを迂回できる余地が生まれる
        AppEnvironment.current.secureMenuService.invalidateAuthentication()
        listViewController.clearSearch()
        listViewController.reload()
        detailViewController.show(item: nil)
    }

    /// 監視の解除。NotificationCenter / NSWorkspace / DistributedNotificationCenter は
    /// それぞれ別のセンターなので、登録元へ返す
    private func removeCommitObservers() {
        windowObservers.forEach { NotificationCenter.default.removeObserver($0) }
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        distributedObservers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
        windowObservers = []
        workspaceObservers = []
        distributedObservers = []
    }

    /// ウィンドウが非アクティブになったとき・アプリ終了時にも取りこぼさず保存する。
    /// あわせて画面ロック・スリープでウィンドウを閉じ、平文が残らないようにする
    private func installCommitObservers() {
        guard windowObservers.isEmpty, workspaceObservers.isEmpty,
              distributedObservers.isEmpty, let window = view.window else { return }
        let center = NotificationCenter.default
        windowObservers.append(center.addObserver(forName: NSWindow.didResignKeyNotification,
                                                  object: window, queue: .main) { [weak self] _ in
            self?.view.window?.makeFirstResponder(nil)
            self?.commitIfNeeded()
            // 他のアプリへ移った隙に平文が見えたままにならないよう伏せ字へ戻す
            self?.detailViewController.hideAllRevealedValues()
        })
        windowObservers.append(center.addObserver(forName: NSApplication.willTerminateNotification,
                                                  object: nil, queue: .main) { [weak self] _ in
            self?.view.window?.makeFirstResponder(nil)
            self?.commitIfNeeded()
        })
        // スリープ復帰後にロック画面の背後で開いたままにならないよう閉じる
        workspaceObservers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.closeForSecurity()
        })
        // 画面ロックは AppKit ではなく分散通知で届く
        distributedObservers.append(DistributedNotificationCenter.default().addObserver(
            forName: Self.screenIsLockedNotification, object: nil, queue: .main) { [weak self] _ in
            self?.closeForSecurity()
        })
        // 別のウィンドウ（セキュアアイテム管理）での変更に追従する
        windowObservers.append(center.addObserver(forName: .secureItemsDidChange,
                                                  object: nil, queue: .main) { [weak self] _ in
            self?.applyExternalChangeIfNeeded()
        })
    }

    /// 他の画面での変更を取り込む。
    ///
    /// 未保存の編集がある場合は勝手に読み直さず、案内バーを出して選択を委ねる。
    /// ここで読み直すと、打ちかけの内容が黙って消えてしまう
    func applyExternalChangeIfNeeded() {
        let service = AppEnvironment.current.secureMenuService
        // 自分が起こした変更なら何もしない（再読込で入力中のフォーカスが飛ぶ）。
        // 保存の途中で同期的に届く通知もここで弾く
        guard !isApplyingLocalChange else { return }
        guard service.itemsChangeToken != appliedChangeToken else { return }
        guard !editor.isDirty else {
            detailViewController.showExternalChangeBanner { [weak self] in
                self?.reloadItems()
            }
            return
        }
        reloadItems()
    }

    /// 画面ロック・スリープを機に、編集内容を保存してからウィンドウを閉じる
    private func closeForSecurity() {
        view.window?.makeFirstResponder(nil)
        commitIfNeeded()
        detailViewController.hideAllRevealedValues()
        view.window?.performClose(nil)
    }

    /// Esc でウィンドウを閉じる
    override func cancelOperation(_ sender: Any?) {
        view.window?.performClose(sender)
    }
}
