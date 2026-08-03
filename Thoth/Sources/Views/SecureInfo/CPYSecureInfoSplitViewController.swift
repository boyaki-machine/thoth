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
/// 他ウィンドウ（セキュアアイテム選択パネルなど）と干渉するため。
final class CPYSecureInfoSplitViewController: NSSplitViewController {

    let editor = SecureInfoEditor()

    /// 取り消し／やり直しの世代（⌘Z / ⌘⇧Z）。
    /// **平文を保持する**ため、`clearUndoHistory()` を呼ぶ 3 箇所を必ず維持すること
    let undoStack = SecureInfoUndoStack()
    /// 取り消し／やり直しの実行中か。
    /// `performUndo()` は先頭で `commitIfNeeded()` を呼ぶため、この目印が無いと
    /// 取り消しの最中に新しい世代が積まれて 1 回で戻りきらなくなる。
    /// 実際の読み書きは +Undo.swift 側なので internal
    var isPerformingUndo = false

    // キー操作の拡張（+Keyboard.swift）から参照するため internal
    lazy var listViewController = CPYSecureInfoListViewController(editor: editor)
    lazy var detailViewController = CPYSecureInfoDetailViewController()

    /// ユニットテストから右ペインの表示状態を確認するための入口
    var detailViewControllerForTesting: CPYSecureInfoDetailViewController { detailViewController }

    var keyMonitor: Any?
    private var fallbackCommitTimer: Timer?
    // 監視トークンは登録したセンターごとに分けて持つ。
    // まとめて持つと解除時にどのセンターへ返せばよいか分からなくなる
    // （登録・解除の中身は +Observers.swift）
    var windowObservers: [NSObjectProtocol] = []
    var workspaceObservers: [NSObjectProtocol] = []
    var distributedObservers: [NSObjectProtocol] = []
    /// 保存失敗の警告を 1 セッションで繰り返さないためのフラグ
    var hasShownCommitFailure = false
    /// 画面へ反映済みの変更番号。自分が起こした変更で再読込しないための目印
    var appliedChangeToken = 0
    /// 自分がデータを変更している最中か。
    /// 変更通知は NotificationCenter の仕様上、メインスレッドからの post だと
    /// **保存処理の途中で同期的に**届く。その時点では通し番号の更新も
    /// 保存完了の記録も済んでいないため、通し番号だけでは自分の変更を見分けられない
    var isApplyingLocalChange = false

    /// 自分の変更として実行する。実行中に届いた変更通知は無視し、
    /// 終了時に反映済みの通し番号を更新する。
    /// 取り消し・入出力の拡張（+Undo.swift / +Transfer.swift）からも使うため internal
    @discardableResult
    func performLocalChange<T>(_ body: () -> T) -> T {
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
        detailViewController.onFieldMoveRequested = { [weak self] fieldID, toIndex in
            self?.moveField(fieldID: fieldID, toIndex: toIndex)
        }
        detailViewController.onAddFieldRequested = { [weak self] template in
            self?.addField(template)
        }
        detailViewController.onAddTOTPRequested = { [weak self] in
            self?.presentTOTPImport()
        }
        detailViewController.onGeneratePasswordRequested = { [weak self] in
            self?.presentPasswordGenerator()
        }
        listViewController.onAddItemRequested = { [weak self] in
            self?.addItem()
        }
        listViewController.onDeleteItemRequested = { [weak self] in
            self?.confirmDeleteSelectedItem()
        }
        listViewController.onReorderRequested = { [weak self] itemID, toIndex in
            self?.reorderItem(itemID: itemID, toIndex: toIndex)
        }
        listViewController.undoState = { [weak self] in
            guard let self = self else { return (undo: nil, redo: nil) }
            return (undo: self.undoStack.undoAction, redo: self.undoStack.redoAction)
        }
        listViewController.onUndoRequested = { [weak self] in self?.performUndo() }
        listViewController.onRedoRequested = { [weak self] in self?.performRedo() }
        listViewController.onImportRequested = { [weak self] in self?.presentImport() }
        listViewController.onExportRequested = { [weak self] in self?.presentExport() }
    }

    // MARK: - Fields

    private func addField(_ template: SecureInfoFieldTemplate) {
        guard editor.draft != nil else { NSSound.beep(); return }
        guard editor.addField(kind: template.kind, label: template.defaultLabel,
                              isPassword: template.isPassword) != nil else { return }
        detailViewController.show(item: editor.draft)
        commitIfNeeded()
    }

    /// フィールドを削除する。
    ///
    /// **確認ダイアログは出さない。** 毎回出しても惰性で通してしまい、通したあとに
    /// 取り返す手段が無い方が問題だった。代わりに 🗑 をホバー中だけ見せて誤爆を減らし、
    /// 消してしまっても ⌘Z で戻せるようにしてある（控えは直後の `commitIfNeeded()` が積む）。
    /// アイテムの削除は影響が大きく、消えたものが画面から見えなくなるため確認を残している
    private func removeField(_ field: SecureMenuItem.Field) {
        guard editor.removeField(fieldID: field.fieldID) else { return }
        detailViewController.show(item: editor.draft)
        commitIfNeeded()
    }

    /// フォーカスのあるフィールド行を上下に動かす（Ctrl+j / Ctrl+k）
    func moveFocusedField(by offset: Int) {
        guard let row = detailViewController.focusedRow else { NSSound.beep(); return }
        guard let index = detailViewController.fieldRows.firstIndex(where: { $0 === row }) else { return }
        moveField(fieldID: row.field.fieldID, toIndex: index + offset)
    }

    /// フィールドを指定位置へ動かす（右クリックメニュー・ドラッグ&ドロップ・Ctrl+j / Ctrl+k）
    func moveField(fieldID: String, toIndex: Int) {
        guard editor.moveField(fieldID: fieldID, toIndex: toIndex) else { NSSound.beep(); return }
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
        pushUndoSnapshot(action: .addItem)
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

    /// 確認を経ずに削除する。確認は `confirmDeleteSelectedItem()` が行う
    /// （ウィンドウ無しでは確認シートを出せないため、ユニットテストはこちらを直接呼ぶ）
    func deleteItem(_ item: SecureMenuItem) {
        let service = AppEnvironment.current.secureMenuService
        // 取り消し用の控えは beginEditing より前に取る（下で作業コピーを捨てるため）
        pushUndoSnapshot(action: .deleteItem)
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
        guard let item = editor.selectedItem,
              let index = editor.items.firstIndex(where: { $0.itemID == item.itemID }) else {
            NSSound.beep()
            return
        }
        reorderItem(itemID: item.itemID, toIndex: index + offset)
    }

    /// アイテムを保存順の指定位置へ動かす（ドラッグ&ドロップ・Ctrl+j / Ctrl+k）
    func reorderItem(itemID: String, toIndex: Int) {
        guard SecureInfoEditor.canReorderItems(query: editor.query, isReadOnly: editor.isReadOnly) else {
            NSSound.beep()
            return
        }
        // reorderItems は渡した配列の内容をそのまま書き戻すため、**必ず先にコミットしてから**
        // 並びを組み立てること。順序を逆にすると、直前の編集を保存前の内容で上書きしてしまう
        commitIfNeeded()
        guard let reordered = SecureInfoEditor.reordered(editor.items, movingItemID: itemID, toIndex: toIndex) else {
            NSSound.beep()
            return
        }
        pushUndoSnapshot(action: .reorderItems)
        let service = AppEnvironment.current.secureMenuService
        performLocalChange {
            guard service.reorderItems(reordered) else {
                showCommitFailure(informative: L10n.secureInfoSaveFailed)
                return
            }
            editor.setItems(service.loadAllItems())
            // 動かしたアイテムを選んだままにする（ドロップ後に選択が飛ばない）
            editor.selectItem(itemID: itemID)
            listViewController.reload()
        }
    }

    // MARK: - Data

    /// Keychain からアイテムを読み直して画面へ反映する。
    ///
    /// - Parameter clearsUndoHistory: 取り消しの世代を捨てるか。
    ///   読み直すと控えてある状態が現在のデータと食い違うため既定は true。
    ///   自分で書き込んだ直後（インポート）だけ false にして、取り消しを効かせる
    func reloadItems(clearsUndoHistory: Bool = true) {
        let service = AppEnvironment.current.secureMenuService
        appliedChangeToken = service.itemsChangeToken
        if clearsUndoHistory { clearUndoHistory() }
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
        // 編集系の取り消しはここ 1 箇所で積む。値・ラベル・タイトルの変更も、
        // フィールドの追加・削除・並べ替えも、確定は必ずこの経路を通るため
        pushUndoSnapshot(action: .edit)
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
    /// 原因を直して ⌘S で再試行できる。同じセッションで警告を連打しない。
    /// 取り消し（+Undo.swift）からも使うため internal
    func showCommitFailure(informative: String) {
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
        // 次に開くときは showWindow が reloadItems で読み直す。
        // 取り消しの世代も削除・編集前の平文を抱えているので同時に捨てる
        editor.clearSensitiveData()
        clearUndoHistory()
        // OS 側の認証状態も持ち越さない。常駐したまま残り続けると、
        // 次に開くときの認証ゲートを迂回できる余地が生まれる
        AppEnvironment.current.secureMenuService.invalidateAuthentication()
        listViewController.clearSearch()
        listViewController.reload()
        detailViewController.show(item: nil)
    }

    /// Esc でウィンドウを閉じる
    override func cancelOperation(_ sender: Any?) {
        view.window?.performClose(sender)
    }
}
