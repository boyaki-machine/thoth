//
//  SecureInfoFieldTemplate.swift
//
//  Thoth
//  GitHub: https://github.com/boyaki-machine/Thoth
//

import Foundation

/// セキュア情報確認ウィンドウの「フィールドを追加」メニューに並ぶ雛形。
///
/// TOTP は otpauth URI / QR コードの取り込みが必要で、空のフィールドを作っても
/// 意味を成さないためここには含めない（専用の取り込みシートから追加する）。
enum SecureInfoFieldTemplate: String, CaseIterable {
    case text
    case password
    case url
    case note

    /// 追加されるフィールドの種別
    var kind: SecureMenuItem.Field.Kind {
        switch self {
        case .text, .password: return .plain
        case .url:  return .url
        case .note: return .note
        }
    }

    /// 追加直後からマスク表示にするか
    var isPassword: Bool {
        switch self {
        case .password: return true
        case .text, .url, .note: return false
        }
    }

    /// 追加されるフィールドの初期ラベル。
    /// 空ラベルのままだと「ラベルも値も空のフィールドは保存しない」規則で
    /// 保存時に消えてしまうため、必ず既定値を入れる
    var defaultLabel: String {
        switch self {
        case .text:     return L10n.secureFieldDefaultLabelText
        case .password: return L10n.secureFieldDefaultLabelPassword
        case .url:      return L10n.secureFieldDefaultLabelURL
        case .note:     return L10n.secureFieldDefaultLabelNote
        }
    }

    /// メニューに表示する名前（初期ラベルと同じ文言を使う）
    var menuTitle: String {
        return defaultLabel
    }
}
