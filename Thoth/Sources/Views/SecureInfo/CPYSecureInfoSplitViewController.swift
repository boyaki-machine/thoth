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

    private var keyMonitor: Any?

    private enum Layout {
        static let sidebarMinWidth: CGFloat = 180
        static let sidebarMaxWidth: CGFloat = 320
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
            self?.detailViewController.show(item: item)
        }
    }

    // MARK: - Data

    /// Keychain からアイテムを読み直して画面へ反映する
    func reloadItems() {
        let service = AppEnvironment.current.secureMenuService
        editor.setItems(service.loadAllItems())
        listViewController.reload()
        if service.isKeychainAccessDenied {
            NSAlert.showNotice(message: L10n.secureItems,
                               informative: L10n.secureItemsKeychainAccessDenied,
                               for: view.window)
        }
    }

    // MARK: - Keyboard

    override func viewDidAppear() {
        super.viewDidAppear()
        installKeyMonitor()
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        if let keyMonitor = keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
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
