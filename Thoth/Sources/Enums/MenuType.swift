//
//  MenuType.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Econa77 on 2016/06/26.
//
//  Copyright © 2015-2018 Clipy Project.
//

import Foundation

enum MenuType: String {
    case main       = "ClipMenu"
    case history    = "HistoryMenu"
    case snippet    = "SnippetMenu"
    case secure     = "SecureMenu"

    var userDefaultsKey: String {
        switch self {
        case .main:
            return Constants.HotKey.mainKeyCombo
        case .history:
            return Constants.HotKey.historyKeyCombo
        case .snippet:
            return Constants.HotKey.snippetKeyCombo
        case .secure:
            return Constants.HotKey.secureKeyCombo
        }
    }

    var hotKeySelector: Selector {
        switch self {
        case .main:
            return #selector(HotKeyService.popupMainMenu)
        case .history:
            return #selector(HotKeyService.popupHistoryMenu)
        case .snippet:
            return #selector(HotKeyService.popUpSnippetMenu)
        case .secure:
            return #selector(HotKeyService.popUpSecureMenu)
        }
    }

}
