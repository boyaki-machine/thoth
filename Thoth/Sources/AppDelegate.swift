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
import RxCocoa
import RxSwift
import Magnet
import LetsMove

/// アプリのエントリポイント。起動シーケンスの統括・メニュー項目のアクション受け口・
/// ログイン項目の管理を担う。
/// ビジネスロジックは持たず、AppEnvironment のサービス層へ委譲する方針
/// （起動シーケンスの詳細は下部 NSApplicationDelegate 拡張のコメントを参照）。
@NSApplicationMain
class AppDelegate: NSObject, NSMenuItemValidation {

    // MARK: - Properties
    let screenshotWatcher = ScreenshotWatcher()
    let disposeBag = DisposeBag()
    // 再署名による再起動が予約されている間 true（起動処理をスキップするためのフラグ）
    fileprivate var isRelaunchPendingForResign = false
    // startApplication() の二重実行防止フラグ
    fileprivate var hasStartedApplication = false

    // MARK: - Init
    // 注意: 保存層の準備はここ（awakeFromNib）では行わない。
    // 暗号鍵の作成は安定署名を前提とするため、applicationDidFinishLaunching で
    // 再署名判定（isRelaunchPendingForResign）を通過した後に LibraryProvider.prepare() を呼ぶ。

    // MARK: - NSMenuItem Validation
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(AppDelegate.clearAllHistory) {
            // 保存層の準備前（起動直後の移行中など）は無効にしておく
            guard LibraryProvider.isReady else { return false }
            return !AppEnvironment.current.historyStore.isEmpty
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

    /// ウィンドウをアクティブ化して前面に出す共通処理。
    /// メニュー項目から呼ばれた直後は、メニュー閉鎖に伴う「元のアプリへの
    /// アクティベーション返却」と競合してフォーカスを奪われることがあるため、
    /// 次のランループまで遅延してから activate → makeKey する
    private func presentWindow(of controller: NSWindowController) {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            controller.showWindow(self)
            controller.window?.makeKeyAndOrderFront(nil)
        }
    }

    @objc func showPreferenceWindow() {
        presentWindow(of: CPYPreferencesWindowController.sharedController)
    }

    @objc func showSnippetEditorWindow() {
        presentWindow(of: CPYSnippetsEditorWindowController.sharedController)
    }

    /// セキュア情報確認ウィンドウを開く。
    /// このウィンドウは値を平文で表示するため、表示前に必ず Touch ID / パスワード認証を通す
    /// （認証成功から 30 秒以内は SecureMenuService 側で再認証が省略される）。
    /// completion は常にメインスレッドで呼ばれる
    @objc func showSecureInfoWindow() {
        AppEnvironment.current.secureMenuService.authenticate(reason: L10n.secureInfoAuthenticationReason) { [weak self] success in
            guard success, let self = self else { return }
            self.presentWindow(of: CPYSecureInfoWindowController.shared)
        }
    }

    @objc func showPasswordGeneratorWindow() {
        presentWindow(of: CPYPasswordGeneratorWindowController.shared)
    }

    @objc func showCryptoWindow() {
        presentWindow(of: CPYCryptoWindowController.shared)
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

    /// 履歴検索パネルを開く（履歴メニューの「検索...」項目 / メニュー表示中の "/" キー）。
    /// メニュー項目のアクションはメニュー閉鎖後に発火するが、閉鎖に伴う
    /// 元アプリへのアクティベーション返却と競合しないよう次のランループへ遅延する
    /// （presentWindow と同じ理由）
    @objc func showHistorySearchPanel() {
        DispatchQueue.main.async {
            AppEnvironment.current.menuManager.popUpHistorySearchPanel()
        }
    }

    @objc func selectClipMenuItem(_ sender: NSMenuItem) {
        guard let primaryKey = sender.representedObject as? String,
              AppEnvironment.current.pasteService.pasteClip(withPrimaryKey: primaryKey) else {
            NSSound.beep()
            return
        }
    }

    @objc func selectSnippetMenuItem(_ sender: AnyObject) {
        guard let primaryKey = sender.representedObject as? String,
              AppEnvironment.current.pasteService.pasteSnippet(withPrimaryKey: primaryKey) else {
            NSSound.beep()
            return
        }
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
        alert.messageText = L10n.launchThothOnSystemStartup
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

    private func reflectLoginItemState() {
        let isInLoginItems = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.loginItem)
        LoginItemService.sync(enabled: isInLoginItems)
    }
}

// MARK: - NSApplication Delegate
extension AppDelegate: NSApplicationDelegate {

    // 起動シーケンス（フェーズ分割によりメニューバーアイコン表示までを最短化する）:
    //
    //   willFinishLaunching [main]
    //    ├─ terminateIfAlreadyRunning()              … 軽量・同期
    //    ├─ 署名確認（SecCode API・軽量・同期）
    //    │   └─ 未署名時のみ [bg] identity 生成 → codesign --deep → relaunch
    //    │        └─ 失敗時は [main] で startApplication() を続行
    //    └─ (RELEASE) PFMoveToApplicationsFolder
    //   didFinishLaunching [main] → startApplication()
    //    ├─ DI・UserDefaults・メニューバーアイコン表示・アクセシビリティ確認
    //    └─ [bg] LibraryProvider.prepare()           … 鍵取得 + ストアを開く（初回は Realm から移行）
    //         └─ [main] 保存層の差し替え → startServices():
    //              変更通知・各サービス開始・ログイン項目アラート・.data スイープ
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // 再署名による再起動が予約されている場合は起動処理を行わない。
        // 再署名前（ad-hoc 署名）のバイナリがアクセシビリティ確認等で TCC に登録されると、
        // アクセシビリティ設定に重複エントリが増えてしまうため
        guard !isRelaunchPendingForResign else { return }
        startApplication()
    }

    /// 通常の起動処理。二重呼び出しは無視する
    /// （再署名失敗時のフォールバックと didFinishLaunching の両方から呼ばれ得るため）
    private func startApplication() {
        guard !hasStartedApplication else { return }
        hasStartedApplication = true

        // --- 軽量な同期処理: メニューバーアイコン表示までを最短にする ---
        // Environments
        AppEnvironment.replaceCurrent(environment: AppEnvironment.fromStorage())
        // UserDefaults
        CPYUtilities.registerUserDefaultKeys()
        // ステータスバーアイコンの表示（保存層には触れない）
        AppEnvironment.current.menuManager.setup()
        // Check Accessibility Permission
        AppEnvironment.current.accessibilityService.isAccessibilityEnabled(isPrompt: true)

        // ユニットテスト実行時はここまで。サービス起動（ポーリング・ホットキー・
        // modal ダイアログ等）はテストの実行を妨げるため行わない
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }

        // --- 重い初期化（ストアを開く・初回は Realm から移行）はバックグラウンドで ---
        LibraryProvider.prepare { [weak self] prepared in
            AppEnvironment.replaceLibrary(historyStore: prepared.historyStore, snippetStore: prepared.snippetStore,
                                          isUsable: prepared.availability == .ready)
            self?.startServices()
            self?.finishLibraryMigration(prepared)
            self?.notifyIfLibraryUnavailable(prepared)
        }
    }

    /// 保存層の準備完了後に呼ばれる。保存層に依存するサービスの起動と残りの初期化を行う
    private func startServices() {
        // 履歴・スニペットの変更監視（メニュー再構築のトリガー）
        AppEnvironment.current.menuManager.bindLibraryNotifications()

        // Binding Events（スクリーンショット監視は clipService 経由で保存層に触れる）
        bind()

        // Services
        AppEnvironment.current.clipService.startMonitoring()
        AppEnvironment.current.dataCleanService.startMonitoring()
        AppEnvironment.current.excludeAppService.startMonitoring()
        AppEnvironment.current.hotKeyService.setupDefaultHotKeys()

        // 旧バージョンが平文で保存したクリップ .data ファイルを
        // バックグラウンドで暗号化形式へ変換する（冪等・失敗分は次回再試行）
        DispatchQueue.global(qos: .utility).async {
            ClipDataStore.shared.encryptPlaintextFiles(inDirectory: CPYUtilities.applicationSupportFolder())
        }

        // Show Login Item（modal ダイアログのため、起動処理がすべて終わった後に表示する）
        let defaults = AppEnvironment.current.defaults
        if !defaults.bool(forKey: Constants.UserDefaults.loginItem) && !defaults.bool(forKey: Constants.UserDefaults.suppressAlertForLoginItem) {
            DispatchQueue.main.async { [weak self] in
                self?.promptToAddLoginItems()
            }
        }
    }

    /// 移行の後処理をバックグラウンドで行う。
    /// サムネイルは旧キャッシュ（平文・元の解像度）から移さず .data から作り直し、旧キャッシュは消す
    private func finishLibraryMigration(_ prepared: LibraryProvider.Prepared) {
        let clipIDs = prepared.migrationReport?.clipIDsNeedingThumbnail ?? []
        let historyStore = prepared.historyStore
        DispatchQueue.global(qos: .utility).async {
            if !clipIDs.isEmpty {
                let count = ClipThumbnail.regenerate(clipIDs: clipIDs, in: historyStore)
                NSLog("[AppDelegate] regenerated \(count) of \(clipIDs.count) thumbnails after migration")
            }
            ClipThumbnail.removeLegacyCache()
        }
    }

    /// 暗号鍵が使えないときに、その起動中の制限を一度だけ知らせる。
    /// 履歴はメモリ上だけになり、スニペットは表示も編集もできない（データは消していない）
    private func notifyIfLibraryUnavailable(_ prepared: LibraryProvider.Prepared) {
        guard prepared.availability != .ready else { return }
        NSLog("[AppDelegate] library unavailable: \(prepared.availability)")
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            NSAlert.showNotice(message: L10n.libraryUnavailableTitle, informative: L10n.libraryUnavailableMessage)
        }
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        // ユニットテスト実行時（テストホスト起動時）はスキップする
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        // Clipy 時代の識別子で保存されたデータ（UserDefaults・データフォルダ）を
        // 他のあらゆる処理より先に移行する
        LegacyMigration.migrateIfNeeded()
        // 2重起動を禁止する。既に同じアプリが起動している場合は
        // 先行インスタンスをアクティブ化して自分は終了する
        terminateIfAlreadyRunning()
        // 署名をデバイス固有の証明書で安定化する（バージョンをまたいだ
        // セキュアアイテムの読み出しに必要。再署名した場合は再起動する）。
        // 重い処理（identity 生成・codesign --deep）はバックグラウンドで実行され、
        // 失敗した場合のみコールバックで通常起動にフォールバックする
        isRelaunchPendingForResign = CodeSignService().ensureStableSignatureAtLaunch { [weak self] in
            guard let self = self, self.isRelaunchPendingForResign else { return }
            self.isRelaunchPendingForResign = false
            self.startApplication()
        }
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
        runningApp.activate(options: [])
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
        // デバッグ情報（ベータ機能）。オフの間は記録せず、オフになったら保存済みのものを消す。
        // 起動時にオフなら、前回の残り（オフにする前に終了した等）も消す
        AppEnvironment.current.defaults.rx.observe(Bool.self, Constants.Beta.saveDebugLog, retainSelf: false)
            .compactMap { $0 }
            .distinctUntilChanged()
            .filter { !$0 }
            .subscribe(onNext: { _ in
                DebugLog.shared.deleteAll()
            })
            .disposed(by: disposeBag)
        // Observe Screenshot（ベータ機能。オンの間だけ保存先フォルダを見張る）
        screenshotWatcher.onCapture = { image in
            AppEnvironment.current.clipService.create(with: image)
        }
        AppEnvironment.current.defaults.rx.observe(Bool.self, Constants.Beta.observerScreenshot, retainSelf: false)
            .compactMap { $0 }
            .distinctUntilChanged()
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] enabled in
                if enabled {
                    self?.screenshotWatcher.start()
                } else {
                    self?.screenshotWatcher.stop()
                }
            })
            .disposed(by: disposeBag)
    }
}
