//
//  CPYSecureInfoSplitViewController+Observers.swift
//
//  Thoth
//  GitHub: https://github.com/boyaki-machine/Thoth
//

import Cocoa

// MARK: - Observers
//
// 「保存を取りこぼさない」「平文を見せたまま放置しない」ための通知の受け口。
// 登録は viewDidAppear、解除は viewWillDisappear（どちらも本体側）。
//
// 監視トークンは登録したセンターごとに分けて持つ。まとめて持つと、
// 解除時にどのセンターへ返せばよいか分からなくなる。
extension CPYSecureInfoSplitViewController {

    /// ウィンドウが非アクティブになったとき・アプリ終了時にも取りこぼさず保存する。
    /// あわせて画面ロック・スリープでウィンドウを閉じ、平文が残らないようにする
    func installCommitObservers() {
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
        // 他の経路（インポートなど）で起きた変更に追従する
        windowObservers.append(center.addObserver(forName: .secureItemsDidChange,
                                                  object: nil, queue: .main) { [weak self] _ in
            self?.applyExternalChangeIfNeeded()
        })
    }

    /// 監視の解除。NotificationCenter / NSWorkspace / DistributedNotificationCenter は
    /// それぞれ別のセンターなので、登録元へ返す
    func removeCommitObservers() {
        windowObservers.forEach { NotificationCenter.default.removeObserver($0) }
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        distributedObservers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
        windowObservers = []
        workspaceObservers = []
        distributedObservers = []
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
            // 読み直さない経路なので、ここで取り消しの世代を捨てておく。
            // 残したままにすると控えてある状態が他の画面の変更を含まず、
            // 取り消した瞬間に相手の変更ごと巻き戻してしまう
            clearUndoHistory()
            detailViewController.showExternalChangeBanner { [weak self] in
                self?.reloadItems()
            }
            return
        }
        reloadItems()
    }

    /// 画面ロック・スリープを機に、編集内容を保存してからウィンドウを閉じる
    func closeForSecurity() {
        view.window?.makeFirstResponder(nil)
        commitIfNeeded()
        detailViewController.hideAllRevealedValues()
        view.window?.performClose(nil)
    }
}
