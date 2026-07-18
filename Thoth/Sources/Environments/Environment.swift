//
//  Environment.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Econa77 on 2017/08/10.
//
//  Copyright © 2015-2018 Clipy Project.
//

import Foundation

/// アプリを構成するサービス群の集合（DI コンテナの中身）。
/// 各サービスの init は軽量（Realm オープン等の重い処理は遅延化済み）のため、
/// 起動時にまとめて生成しても起動時間には影響しない。
struct Environment {

    // MARK: - Properties
    let clipService: ClipService
    let hotKeyService: HotKeyService
    let dataCleanService: DataCleanService
    let pasteService: PasteService
    let excludeAppService: ExcludeAppService
    let accessibilityService: AccessibilityService
    let menuManager: MenuManager
    let secureMenuService: SecureMenuService
    let secureSelectionContext: SecureSelectionContext

    let defaults: UserDefaults

    // MARK: - Initialize
    init(clipService: ClipService = ClipService(),
         hotKeyService: HotKeyService = HotKeyService(),
         dataCleanService: DataCleanService = DataCleanService(),
         pasteService: PasteService = PasteService(),
         excludeAppService: ExcludeAppService = ExcludeAppService(applications: []),
         accessibilityService: AccessibilityService = AccessibilityService(),
         menuManager: MenuManager = MenuManager(),
         secureMenuService: SecureMenuService = SecureMenuService(),
         secureSelectionContext: SecureSelectionContext = SecureSelectionContext(),
         defaults: UserDefaults = .standard) {

        self.clipService = clipService
        self.hotKeyService = hotKeyService
        self.dataCleanService = dataCleanService
        self.pasteService = pasteService
        self.excludeAppService = excludeAppService
        self.accessibilityService = accessibilityService
        self.menuManager = menuManager
        self.secureMenuService = secureMenuService
        self.secureSelectionContext = secureSelectionContext
        self.defaults = defaults
    }

}
