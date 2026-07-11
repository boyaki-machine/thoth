//
//  AppDelegate.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Econa77 on 2015/06/21.
//
//  Copyright © 2015-2018 Clipy Project.
//

import Cocoa
import Sparkle
import RxCocoa
import RxSwift
import LoginServiceKit
import Magnet
import Screeen
import RxScreeen
import RealmSwift
import LetsMove

@NSApplicationMain
class AppDelegate: NSObject, NSMenuItemValidation {

    // MARK: - Properties
    let screenshotObserver = ScreenShotObserver()
    let disposeBag = DisposeBag()
    // 再署名による再起動が予約されている間 true（起動処理をスキップするためのフラグ）
    fileprivate var isRelaunchPendingForResign = false

    // MARK: - Init
    override func awakeFromNib() {
        super.awakeFromNib()
        // Migrate Realm
        Realm.migration()
    }

    // MARK: - NSMenuItem Validation
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(AppDelegate.clearAllHistory) {
            let realm = try! Realm()
            return !realm.objects(CPYClip.self).isEmpty
        }
        return true
    }

    // MARK: - Class Methods
    static func storeTypesDictinary() -> [String: NSNumber] {
        var storeTypes = [String: NSNumber]()
        CPYClipData.availableTypesString.forEach { storeTypes[$0] = NSNumber(value: true) }
        return storeTypes
    }

    // MARK: - Menu Actions
    @objc func showPreferenceWindow() {
        NSApp.activate(ignoringOtherApps: true)
        CPYPreferencesWindowController.sharedController.showWindow(self)
    }

    @objc func showSnippetEditorWindow() {
        NSApp.activate(ignoringOtherApps: true)
        CPYSnippetsEditorWindowController.sharedController.showWindow(self)
    }

    @objc func showSecureItemsWindow() {
        NSApp.activate(ignoringOtherApps: true)
        CPYSecureItemsWindowController.shared.showWindow(self)
    }

    @objc func showPasswordGeneratorWindow() {
        NSApp.activate(ignoringOtherApps: true)
        CPYPasswordGeneratorWindowController.shared.showWindow(self)
    }

    @objc func showCryptoWindow() {
        NSApp.activate(ignoringOtherApps: true)
        CPYCryptoWindowController.shared.showWindow(self)
    }

    @objc func terminate() {
        terminateApplication()
    }

    @objc func clearAllHistory() {
        let isShowAlert = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.showAlertBeforeClearHistory)
        if isShowAlert {
            let alert = NSAlert()
            alert.messageText = L10n.clearHistory
            alert.informativeText = L10n.areYouSureYouWantToClearYourClipboardHistory
            alert.addButton(withTitle: L10n.clearHistory)
            alert.addButton(withTitle: L10n.cancel)
            alert.showsSuppressionButton = true

            NSApp.activate(ignoringOtherApps: true)

            let result = alert.runModal()
            if result != NSApplication.ModalResponse.alertFirstButtonReturn { return }

            if alert.suppressionButton?.state == NSControl.StateValue.on {
                AppEnvironment.current.defaults.set(false, forKey: Constants.UserDefaults.showAlertBeforeClearHistory)
            }
        }

        AppEnvironment.current.clipService.clearAll()
    }

    @objc func selectClipMenuItem(_ sender: NSMenuItem) {
        CPYUtilities.sendCustomLog(with: "selectClipMenuItem")
        guard let primaryKey = sender.representedObject as? String else {
            CPYUtilities.sendCustomLog(with: "Cannot fetch clip primary key")
            NSSound.beep()
            return
        }
        let realm = try! Realm()
        guard let clip = realm.object(ofType: CPYClip.self, forPrimaryKey: primaryKey) else {
            CPYUtilities.sendCustomLog(with: "Cannot fetch clip data")
            NSSound.beep()
            return
        }

        AppEnvironment.current.pasteService.paste(with: clip)
    }

    @objc func selectSnippetMenuItem(_ sender: AnyObject) {
        CPYUtilities.sendCustomLog(with: "selectSnippetMenuItem")
        guard let primaryKey = sender.representedObject as? String else {
            CPYUtilities.sendCustomLog(with: "Cannot fetch snippet primary key")
            NSSound.beep()
            return
        }
        let realm = try! Realm()
        guard let snippet = realm.object(ofType: CPYSnippet.self, forPrimaryKey: primaryKey) else {
            CPYUtilities.sendCustomLog(with: "Cannot fetch snippet data")
            NSSound.beep()
            return
        }
        AppEnvironment.current.pasteService.copyToPasteboard(with: snippet.content)
        AppEnvironment.current.pasteService.paste()
    }

    @objc func selectSecureMenuItem(_ sender: NSMenuItem) {
        guard let selection = sender.representedObject as? SecureFieldSelection else {
            NSSound.beep()
            return
        }
        // 出力処理（TOTP 直接タイプ / 秘匿コピー+ペースト+遅延クリア）は
        // MenuManager.outputSecureSelection に一本化されている
        AppEnvironment.current.menuManager.outputSecureSelection(selection)
    }

    func terminateApplication() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Login Item Methods
    private func promptToAddLoginItems() {
        let alert = NSAlert()
        alert.messageText = L10n.launchClipyOnSystemStartup
        alert.informativeText = L10n.youCanChangeThisSettingInThePreferencesIfYouWant
        alert.addButton(withTitle: L10n.launchOnSystemStartup)
        alert.addButton(withTitle: L10n.donTLaunch)
        alert.showsSuppressionButton = true
        NSApp.activate(ignoringOtherApps: true)

        //  Launch on system startup
        if alert.runModal() == NSApplication.ModalResponse.alertFirstButtonReturn {
            AppEnvironment.current.defaults.set(true, forKey: Constants.UserDefaults.loginItem)
            reflectLoginItemState()
        }
        // Do not show this message again
        if alert.suppressionButton?.state == NSControl.StateValue.on {
            AppEnvironment.current.defaults.set(true, forKey: Constants.UserDefaults.suppressAlertForLoginItem)
        }
    }

    private func toggleAddingToLoginItems(_ isEnable: Bool) {
        let appPath = Bundle.main.bundlePath
        LoginServiceKit.removeLoginItems(at: appPath)
        guard isEnable else { return }
        LoginServiceKit.addLoginItems(at: appPath)
    }

    private func reflectLoginItemState() {
        let isInLoginItems = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.loginItem)
        toggleAddingToLoginItems(isInLoginItems)
    }
}

// MARK: - NSApplication Delegate
extension AppDelegate: NSApplicationDelegate {

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // 再署名による再起動が予約されている場合は起動処理を行わない。
        // 再署名前（ad-hoc 署名）のバイナリがアクセシビリティ確認等で TCC に登録されると、
        // アクセシビリティ設定に重複エントリが増えてしまうため
        guard !isRelaunchPendingForResign else { return }
        // Environments
        AppEnvironment.replaceCurrent(environment: AppEnvironment.fromStorage())
        // UserDefaults
        CPYUtilities.registerUserDefaultKeys()
        // SDKs
        CPYUtilities.initSDKs()
        // Check Accessibility Permission
        AppEnvironment.current.accessibilityService.isAccessibilityEnabled(isPrompt: true)

        // Show Login Item
        if !AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.loginItem) && !AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.suppressAlertForLoginItem) {
            promptToAddLoginItems()
        }

        // Sparkle
        let updater = SUUpdater.shared()
        updater?.feedURL = Constants.Application.appcastURL
        updater?.automaticallyChecksForUpdates = AppEnvironment.current.defaults.bool(forKey: Constants.Update.enableAutomaticCheck)
        updater?.updateCheckInterval = TimeInterval(AppEnvironment.current.defaults.integer(forKey: Constants.Update.checkInterval))

        // Binding Events
        bind()

        // Services
        AppEnvironment.current.clipService.startMonitoring()
        AppEnvironment.current.dataCleanService.startMonitoring()
        AppEnvironment.current.excludeAppService.startMonitoring()
        AppEnvironment.current.hotKeyService.setupDefaultHotKeys()

        // Managers
        AppEnvironment.current.menuManager.setup()
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        // ユニットテスト実行時（テストホスト起動時）はスキップする
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        // 2重起動を禁止する。既に同じアプリが起動している場合は
        // 先行インスタンスをアクティブ化して自分は終了する
        terminateIfAlreadyRunning()
        // 署名をデバイス固有の証明書で安定化する（バージョンをまたいだ
        // セキュアアイテムの読み出しに必要。再署名した場合は再起動する）
        isRelaunchPendingForResign = CodeSignService().ensureStableSignatureAtLaunch()
        guard !isRelaunchPendingForResign else { return }
        #if RELEASE
            PFMoveToApplicationsFolderIfNecessary()
        #endif
    }

    private func terminateIfAlreadyRunning() {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }
        let currentProcessIdentifier = NSRunningApplication.current.processIdentifier
        let existingApp = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .first { $0.processIdentifier != currentProcessIdentifier && !$0.isTerminated }
        guard let runningApp = existingApp else { return }
        runningApp.activate(options: [.activateIgnoringOtherApps])
        NSApp.terminate(nil)
    }

}

// MARK: - Bind
private extension AppDelegate {
    func bind() {
        // Login Item
        AppEnvironment.current.defaults.rx.observe(Bool.self, Constants.UserDefaults.loginItem, retainSelf: false)
            .compactMap { $0 }
            .subscribe(onNext: { [weak self] _ in
                self?.reflectLoginItemState()
            })
            .disposed(by: disposeBag)
        // Observe Screenshot
        let observerScreenshot = AppEnvironment.current.defaults.rx.observe(Bool.self, Constants.Beta.observerScreenshot, retainSelf: false)
            .compactMap { $0 }
            .share(replay: 1)
        observerScreenshot
            .subscribe(onNext: { [weak self] enabled in
                self?.screenshotObserver.isEnabled = enabled
            })
            .disposed(by: disposeBag)
        observerScreenshot
            .filter { $0 }
            .take(1)
            .subscribe(onNext: { [weak self] _ in
                self?.screenshotObserver.start()
            })
            .disposed(by: disposeBag)
        // Observe Screenshot image
        screenshotObserver.rx.addedImage
            .subscribe(onNext: { image in
                AppEnvironment.current.clipService.create(with: image)
            })
            .disposed(by: disposeBag)
    }
}
