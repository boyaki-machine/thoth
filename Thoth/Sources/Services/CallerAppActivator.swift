//
//  CallerAppActivator.swift
//
//  Thoth
//
//  パネルで選んだ値を貼り付ける前に、貼り付け先のアプリを前面へ戻す
//

import Cocoa

/// パネル（履歴・セキュアアイテム）で選んだ値を貼り付ける前に、貼り付け先のアプリを前面へ戻す。
///
/// パネルを出すと Thoth がアクティブになるため、選択後は元のアプリへ戻してから ⌘V やキー入力を送る。
/// `activate` は非同期で、前面化が済む前に ⌘V を送ると Thoth 自身が受け取ってビープが鳴り、
/// 貼り付けられない（戻るまでの時間はアプリや負荷で変わるため、固定の待ち時間では足りないことがある）。
/// そこで、実際に前面へ来たことを確かめてから送る。
enum CallerAppActivator {

    /// 前面化を確かめる間隔
    static let pollInterval: TimeInterval = 0.02
    /// 前面化を待つ上限。過ぎたら諦めてそのまま送る（何もしないよりは貼り付けられる見込みがある）
    static let timeout: TimeInterval = 1.0
    /// 前面化を確かめてから送るまでの猶予（キーウィンドウとフォーカスの復元を待つ）
    static let settleDelay: TimeInterval = 0.05
    /// 戻す先が無いときに送るまでの待ち時間（NSMenu から選んだ場合など。従来と同じ）
    static let fallbackDelay: TimeInterval = 0.15

    /// 貼り付け先として扱うアプリか。Thoth 自身・終了済みのアプリは戻す先にしない
    static func isReturnTarget(processIdentifier: pid_t, isTerminated: Bool,
                               ownProcessIdentifier: pid_t = ProcessInfo.processInfo.processIdentifier) -> Bool {
        return !isTerminated && processIdentifier != ownProcessIdentifier
    }

    /// 戻す先のアプリが前面に来たか
    static func isFrontmost(frontmostProcessIdentifier: pid_t?, callerProcessIdentifier: pid_t) -> Bool {
        return frontmostProcessIdentifier == callerProcessIdentifier
    }

    /// 貼り付け先として覚えておくアプリを選ぶ。ホットキーを押した時点の最前面を優先し、
    /// それが使えなければ（Thoth 自身だった等）パネルを出す時点の最前面を使う。
    ///
    /// 認証（Touch ID・パスワード）のダイアログを挟むと、パネルを出す時点の最前面は
    /// 元のアプリではなくなっていることがあるため、ホットキーの時点で覚えておく
    static func returnTarget(atHotKey hotKeyApp: NSRunningApplication?,
                             atShow showApp: NSRunningApplication?) -> NSRunningApplication? {
        return [hotKeyApp, showApp].compactMap { $0 }.first {
            isReturnTarget(processIdentifier: $0.processIdentifier, isTerminated: $0.isTerminated)
        }
    }

    /// `app` を前面へ戻し、前面に来たら（または上限まで待ったら）`perform` を呼ぶ。
    /// `app` が nil・戻す先にならない場合は、少し待ってからそのまま呼ぶ
    static func activate(_ app: NSRunningApplication?, then perform: @escaping () -> Void) {
        guard let app = app,
              isReturnTarget(processIdentifier: app.processIdentifier, isTerminated: app.isTerminated) else {
            DispatchQueue.main.asyncAfter(deadline: .now() + fallbackDelay, execute: perform)
            return
        }
        // macOS 14 以降の協調型アクティベーション: 前面にいる Thoth が相手へ前面を譲ってから activate する。
        // （.activateIgnoringOtherApps は macOS 14 以降効果がないため指定しない）
        NSApp.yieldActivation(to: app)
        app.activate(options: [])
        let callerPID = app.processIdentifier
        waitUntil({ isFrontmost(frontmostProcessIdentifier: NSWorkspace.shared.frontmostApplication?.processIdentifier,
                                callerProcessIdentifier: callerPID) },
                  timeout: timeout, interval: pollInterval,
                  completion: { _ in DispatchQueue.main.asyncAfter(deadline: .now() + settleDelay, execute: perform) })
    }

    /// `condition` が真になるか `timeout` を過ぎるまで、メインスレッドで `interval` ごとに確かめる。
    /// - Parameter completion: 条件が満たされたら true、上限まで待っても満たされなければ false
    static func waitUntil(_ condition: @escaping () -> Bool, timeout: TimeInterval, interval: TimeInterval,
                          completion: @escaping (Bool) -> Void) {
        let deadline = Date().addingTimeInterval(timeout)
        func check() {
            if condition() {
                completion(true)
            } else if Date() >= deadline {
                completion(false)
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + interval, execute: check)
            }
        }
        DispatchQueue.main.async(execute: check)
    }
}
