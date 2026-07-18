// 
//  AccessibilityService.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
// 
//  Created by Econa77 on 2018/10/03.
// 
//  Copyright © 2015-2018 Clipy Project.
//

import Foundation
import Cocoa

/// アクセシビリティ権限（CGEvent によるペースト・直接タイプ・vim キー変換に必須）の
/// 確認と、設定画面への誘導を行うサービス。
final class AccessibilityService {}

// MARK: - Permission
extension AccessibilityService {
    /// アクセシビリティ権限が付与されているかを返す。
    /// - Parameter isPrompt: true の場合、未付与なら OS の許可ダイアログを表示する
    @discardableResult
    func isAccessibilityEnabled(isPrompt: Bool) -> Bool {
        // Accessibility permission is required for paste command from macOS 10.14 Mojave.
        // For macOS 10.14 and later only, check accessibility permission at startup and paste
        guard #available(macOS 10.14, *) else { return true }

        let checkOptionPromptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let opts = [checkOptionPromptKey: isPrompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    /// 権限が無い場合の説明アラートを表示し、システム設定への誘導を行う
    func showAccessibilityAuthenticationAlert() {
        let alert = NSAlert()
        alert.messageText = L10n.pleaseAllowAccessibility
        alert.informativeText = L10n.toDoThisActionPleaseAllowAccessibilityInSecurityPrivacyPreferencesLocatedInSystemPreferences
        alert.addButton(withTitle: L10n.openSystemPreferences)
        NSApp.activate(ignoringOtherApps: true)

        if alert.runModal() == NSApplication.ModalResponse.alertFirstButtonReturn {
            guard !openAccessibilitySettingWindow() else { return }
            isAccessibilityEnabled(isPrompt: true)
        }
    }

    func openAccessibilitySettingWindow() -> Bool {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return false }
        return NSWorkspace.shared.open(url)
    }
}
