//
//  CPYSecureInfoWindowController.swift
//
//  Thoth
//  GitHub: https://github.com/boyaki-machine/Thoth
//

import Cocoa

/// セキュア情報確認ウィンドウのコントローラ。
/// アプリ起動中に一度だけ生成されるシングルトンで、表示のたびに内容を読み直す。
///
/// このウィンドウは値を平文で画面に表示するため、**表示前に必ず認証を通すこと**
/// （導線は `AppDelegate.showSecureInfoWindow()`）。
/// セキュアアイテム管理ウィンドウとは異なり、メインメニューから直接開けるため
/// 認証ゲートが無いと未認証で機密情報を閲覧できてしまう。
final class CPYSecureInfoWindowController: NSWindowController {

    private enum Layout {
        static let width: CGFloat     = 760
        static let height: CGFloat    = 520
        static let minWidth: CGFloat  = 620
        static let minHeight: CGFloat = 420
    }

    static let shared: CPYSecureInfoWindowController = {
        let splitViewController = CPYSecureInfoSplitViewController()
        let window = NSWindow(contentViewController: splitViewController)
        window.title = L10n.secureInfo
        window.setContentSize(NSSize(width: Layout.width, height: Layout.height))
        window.contentMinSize = NSSize(width: Layout.minWidth, height: Layout.minHeight)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        // NSWindow にキービューループの自動再計算を委ねる（Tab キーナビゲーション）
        window.autorecalculatesKeyViewLoop = true
        window.center()
        return CPYSecureInfoWindowController(window: window)
    }()

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        (contentViewController as? CPYSecureInfoSplitViewController)?.reloadItems()
        window?.makeKeyAndOrderFront(self)
    }
}
