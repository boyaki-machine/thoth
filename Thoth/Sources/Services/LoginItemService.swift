//
//  LoginItemService.swift
//
//  Thoth
//  GitHub: https://github.com/boyaki-machine/Thoth
//

import Foundation
import ServiceManagement

/// ログイン時の自動起動（ログイン項目）への登録・解除。
///
/// macOS 13 で導入された `SMAppService` でアプリ本体を登録する。
/// 以前は LoginServiceKit（Pod）を手元で `SMAppService` 対応に直して使っていたが、
/// その修正は git 管理外の `Pods/` にしか無く、`pod install` のたびに失われていた
/// （上流版は macOS 13 以降で機能しない `LSSharedFileList` を使う）。
/// そのため同じ処理をアプリ側へ移した。
enum LoginItemService {

    /// 設定値と現在の登録状態を揃えるために行う操作
    enum Action: Equatable {
        case none
        case register
        case unregister
    }

    /// 設定値（desired）と現在の登録状態から、行うべき操作を決める。
    ///
    /// 状態が既に揃っていれば何もしない（起動のたびに解除 → 再登録しない）。
    /// システム設定で利用者がオフにした項目（`.requiresApproval`）は、
    /// 設定値がオンでも再登録で上書きせず、利用者の判断を尊重する
    static func action(desired: Bool, status: SMAppService.Status) -> Action {
        switch (desired, status) {
        case (true, .notRegistered), (true, .notFound):
            return .register
        case (false, .enabled), (false, .requiresApproval):
            return .unregister
        default:
            return .none
        }
    }

    /// 設定値に合わせてログイン項目の登録状態を揃える（冪等）
    static func sync(enabled desired: Bool) {
        let status = SMAppService.mainApp.status
        switch action(desired: desired, status: status) {
        case .register:
            register()
        case .unregister:
            unregister()
        case .none:
            if desired && status == .requiresApproval {
                NSLog("[LoginItemService] login item is turned off in System Settings; leaving it as is")
            }
        }
    }

    @discardableResult
    static func register() -> Bool {
        do {
            try SMAppService.mainApp.register()
            return true
        } catch {
            NSLog("[LoginItemService] register failed: \(error)")
            return false
        }
    }

    @discardableResult
    static func unregister() -> Bool {
        do {
            try SMAppService.mainApp.unregister()
            return true
        } catch {
            NSLog("[LoginItemService] unregister failed: \(error)")
            return false
        }
    }
}
