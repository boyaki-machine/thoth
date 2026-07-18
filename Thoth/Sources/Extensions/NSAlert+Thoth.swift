//
//  NSAlert+Clipy.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Copyright © 2015-2018 Clipy Project.
//

import AppKit

/// アラート表示の定型コード（生成 → ボタン設定 → シート/モーダルの自動切替）を集約する。
/// 各画面で `NSAlert()` を組み立てる重複を減らし、表示方法を統一する目的。
extension NSAlert {

    /// 通知アラート（ボタンは OK のみ）を表示する。
    /// ウィンドウが渡されればシートとして、無ければモーダルで表示する
    static func showNotice(message: String, informative: String,
                           style: NSAlert.Style = .warning, for window: NSWindow? = nil) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = informative
        alert.alertStyle = style
        if let window = window {
            alert.beginSheetModal(for: window, completionHandler: nil)
        } else {
            alert.runModal()
        }
    }

    /// 確認アラート（実行 / キャンセルの 2 ボタン）を表示する。
    /// 実行ボタンが押された場合のみ handler が呼ばれる。
    /// ウィンドウが渡されればシートとして、無ければモーダルで表示する
    static func showConfirmation(message: String, informative: String,
                                 confirmTitle: String, cancelTitle: String,
                                 style: NSAlert.Style = .warning, for window: NSWindow? = nil,
                                 onConfirm handler: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = informative
        alert.addButton(withTitle: confirmTitle)
        alert.addButton(withTitle: cancelTitle)
        alert.alertStyle = style
        if let window = window {
            alert.beginSheetModal(for: window) { response in
                guard response == .alertFirstButtonReturn else { return }
                handler()
            }
        } else {
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            handler()
        }
    }
}
