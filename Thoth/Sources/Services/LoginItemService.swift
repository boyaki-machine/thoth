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

    /// ログイン項目として有効になっているか
    static var isRegistered: Bool {
        return SMAppService.mainApp.status == .enabled
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
