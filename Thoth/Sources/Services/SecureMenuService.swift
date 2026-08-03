//
//  SecureMenuService.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Copyright © 2015-2018 Clipy Project.
//

import Foundation
import LocalAuthentication
import Security

/// 「ユーザー自身が設定する機微情報」の集合。Keychain の 1 エントリ（account: user-data）に
/// JSON で集約して保存する。エクスポート／インポートの対象はこの単位。
///
/// 対になる概念として「アプリが動作のために自動生成する情報」（DB 暗号鍵等）があり、
/// そちらは環境固有のため RealmProvider の app-keys エントリで別管理される
/// （エクスポート対象外・インストールごとに生成）。
struct SecureUserData: Codable {
    /// スキーマバージョン（将来の形式変更用）
    var version: Int
    /// セキュアアイテム全件
    var items: [SecureMenuItem]
    /// ファイル暗号化の指紋パスワード（未登録なら nil）
    var cryptoPassword: String?

    init(version: Int = SecureUserData.currentVersion, items: [SecureMenuItem] = [], cryptoPassword: String? = nil) {
        self.version = version
        self.items = items
        self.cryptoPassword = cryptoPassword
    }

    /// 現在のスキーマバージョン
    static let currentVersion = 2

    // キーが欠けていても読めるように寛容にデコードする（前方互換）
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? SecureUserData.currentVersion
        items = try container.decodeIfPresent([SecureMenuItem].self, forKey: .items) ?? []
        cryptoPassword = try container.decodeIfPresent(String.self, forKey: .cryptoPassword)
    }
}

/// セキュアメニューのアイテム（パスワード等の機微情報）と指紋パスワードを
/// macOS Keychain で管理し、Touch ID / パスワード認証を提供するサービス。
///
/// ## 認証と Keychain 保護の設計（トレードオフ）
/// - 認証（LAContext.evaluatePolicy）に成功したコンテキストは保持され、
///   以降の Keychain 読み出しに `kSecUseAuthenticationContext` で紐付けられる。
/// - エントリの新規作成時は `.userPresence` ACL 付き（data protection keychain）での
///   保存をプローブする。成功した環境では **OS が読み出しごとに在席確認を強制** し、
///   アプリコードの改変では迂回できない保護になる。
/// - ただし data protection keychain は application-identifier エンタイトルメントを要求し、
///   本アプリの ad-hoc / 自己署名（CodeSignService による署名安定化）では
///   `errSecMissingEntitlement` で失敗するため、従来のファイルベース Keychain に
///   自動フォールバックする。この場合の実効的な保護は
///   「CodeSignService による署名の安定化 + アプリ内の LAContext 認証ゲート」となる。
///   Developer ID 署名へ移行すれば ACL 保護が自動的に有効になる。
final class SecureMenuService {

    // MARK: - Constants

    private static let defaultKeychainService = "io.github.boyaki-machine.Thoth.SecureMenu"
    /// Clipy 時代のサービス名（改名移行用）。移行後もバックアップとしてエントリを残す
    private static let legacyKeychainService = "com.clipy-app.Clipy.SecureMenu"
    /// ユーザー由来の機微情報（セキュアアイテム + 指紋パスワード）を
    /// SecureUserData としてひとつにまとめた Keychain エントリのキー。
    /// 1エントリ = 1回の "Allow" ダイアログで済む。
    private static let userDataKey = "user-data"
    /// 旧形式（〜v1）: セキュアアイテムのみを保存していたエントリのキー。移行元として参照する
    private static let legacyItemsKey = "all-items"
    /// 旧形式（〜v1）: 指紋パスワードを保存していたエントリのキー。移行元として参照する
    private static let legacyCryptoPasswordKey = "crypto-password"

    /// Keychain エントリの service 名。テストでは専用の名前を注入して本番データと分離する。
    private let keychainService: String

    /// 直近の `loadAllItems()` がアクセス拒否等で失敗した場合 true（「アイテム 0 件」との区別に使う）。
    /// ad-hoc 署名ビルドではバイナリが変わるたびに Keychain の ACL 上は「別アプリ」と
    /// 判定されるため、既存エントリの読み出しが拒否されることがある。
    /// この状態のまま保存すると既存データを上書き消去してしまうため、`saveAllItems` はガードする。
    /// （テストから拒否状態を再現できるよう setter は internal にしている）
    var isKeychainAccessDenied = false

    /// 直近に成功した認証のコンテキスト。Keychain クエリに `kSecUseAuthenticationContext` で
    /// 引き渡し、認証結果と Keychain 読み出しを OS レベルで紐付ける。
    /// ACL 付きエントリ（後述のプローブが成功した環境）では、このコンテキストが無いと
    /// 読み出し時に OS が再認証を要求する＝アプリのロジックを迂回しても値を取れない。
    private var authenticatedContext: LAContext?

    /// 認証成功からこの秒数以内の再認証は省略する（猶予期間）。
    /// ID → パスワード → TOTP のように短時間に連続してセキュアアイテムを
    /// 選択するユースケースで、選択のたびに Touch ID を要求しないための UX 措置。
    /// 猶予は「実際に認証が成功した時刻」から固定で、省略のたびに延長はしない
    /// （延長型にすると使い続ける限り無期限に認証が省略されてしまうため）。
    static let authenticationGracePeriod: TimeInterval = 30

    /// 直近で認証が成功した時刻（テストから注入できるよう internal）
    var lastAuthenticatedDate: Date?

    /// セキュアアイテムが変更されるたびに増える通し番号。
    /// 複数のウィンドウが同じサービスを共有するため、「自分が起こした変更か」を
    /// この番号で判定する（自分の保存で再読込が走ると入力中のフォーカスが飛ぶ）
    private(set) var itemsChangeToken: Int = 0

    /// セキュアアイテムが変更されたことを知らせる。
    /// 変更経路は `saveAllItems`（保存・削除・並べ替え）と `deleteAllItems` の 2 つ。
    /// 新しい変更経路を足す場合は必ず `postItemsDidChange()` を呼ぶこと
    private func postItemsDidChange() {
        itemsChangeToken += 1
        NotificationCenter.default.post(name: .secureItemsDidChange, object: self)
    }

    // MARK: - Initialize

    init(keychainService: String = SecureMenuService.defaultKeychainService) {
        self.keychainService = keychainService
    }

    // MARK: - Authentication

    func authenticate(reason: String, completion: @escaping (Bool) -> Void) {
        // 猶予期間内は再認証を省略する（completion は他の経路と同様に非同期で呼ぶ）
        if let lastAuthenticated = lastAuthenticatedDate,
           Date().timeIntervalSince(lastAuthenticated) < Self.authenticationGracePeriod {
            DispatchQueue.main.async { completion(true) }
            return
        }

        let context = LAContext()
        var error: NSError?
        let policy = LAPolicy.deviceOwnerAuthentication

        guard context.canEvaluatePolicy(policy, error: &error) else {
            #if DEBUG
            NSLog("[SecureMenuService] authenticate: canEvaluatePolicy failed: \(String(describing: error))")
            #endif
            DispatchQueue.main.async { completion(false) }
            return
        }
        #if DEBUG
        NSLog("[SecureMenuService] authenticate: starting evaluatePolicy")
        #endif

        context.evaluatePolicy(policy, localizedReason: reason) { success, authError in
            #if DEBUG
            if let authError = authError {
                NSLog("[SecureMenuService] authenticate: evaluatePolicy error: \(authError)")
            }
            #endif
            DispatchQueue.main.async {
                // 評価済みコンテキストを保持し、以降の Keychain 読み出しに紐付ける
                self.authenticatedContext = success ? context : nil
                // 猶予期間の起点を記録する（失敗時はクリア）
                self.lastAuthenticatedDate = success ? Date() : nil
                completion(success)
            }
        }
    }

    // MARK: - Keychain Primitives

    /// Keychain クエリの共通部分を組み立てる。
    /// - Parameter dataProtection: true の場合 data protection keychain
    ///   （ACL 付きエントリの保存先）を対象にする
    private func keychainQuery(account: String, dataProtection: Bool = false, service: String? = nil) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service ?? keychainService,
            kSecAttrAccount as String: account
        ]
        if dataProtection {
            query[kSecUseDataProtectionKeychain as String] = true
        }
        return query
    }

    /// エントリを読み出す。従来のファイルベース Keychain → data protection keychain
    /// （ACL 付き）の順に検索し、評価済み LAContext があれば認証コンテキストとして引き渡す
    private func readEntry(account: String, service: String? = nil) -> (status: OSStatus, data: Data?) {
        var fileBasedStatus: OSStatus = errSecItemNotFound
        for dataProtection in [false, true] {
            var query = keychainQuery(account: account, dataProtection: dataProtection, service: service)
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            query[kSecReturnData as String] = true
            if let context = authenticatedContext {
                query[kSecUseAuthenticationContext as String] = context
            }
            var result: AnyObject?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            if status == errSecSuccess {
                return (status, result as? Data)
            }
            if !dataProtection {
                fileBasedStatus = status
                // ファイルベース側でアクセス拒否等が起きた場合はそのまま返す
                // （data protection 側の探索で notFound に化けさせない）
                if status != errSecItemNotFound { return (status, nil) }
            }
        }
        // data protection 側の失敗（errSecMissingEntitlement 等）は「存在しない」と同義に扱う
        return (fileBasedStatus, nil)
    }

    /// エントリを保存する（既存があれば更新、無ければ新規作成）。
    ///
    /// 新規作成時はまず `.userPresence` ACL 付きで data protection keychain への保存を試みる
    /// （プローブ）。成功すれば以降の読み出しに OS レベルの認証が要求される。
    /// ad-hoc / 自己署名ビルドは application-identifier エンタイトルメントを持たないため
    /// `errSecMissingEntitlement` で失敗する——その場合は従来のファイルベース Keychain に
    /// 自動フォールバックする（Developer ID 署名へ移行すれば ACL が自動的に有効になる）
    private func writeEntry(account: String, label: String, data: Data) -> Bool {
        // 既存エントリの更新（保存先はエントリ作成時の場所を維持する）
        for dataProtection in [false, true] {
            var existsQuery = keychainQuery(account: account, dataProtection: dataProtection)
            existsQuery[kSecMatchLimit as String] = kSecMatchLimitOne
            guard SecItemCopyMatching(existsQuery as CFDictionary, nil) == errSecSuccess else { continue }

            var query = keychainQuery(account: account, dataProtection: dataProtection)
            if dataProtection, let context = authenticatedContext {
                query[kSecUseAuthenticationContext as String] = context
            }
            let attributes: [String: Any] = [
                kSecValueData as String: data,
                kSecAttrLabel as String: label
            ]
            return SecItemUpdate(query as CFDictionary, attributes as CFDictionary) == errSecSuccess
        }
        // 新規作成: ACL 付き保存をプローブし、失敗したら従来方式にフォールバック
        if addProtectedEntry(account: account, label: label, data: data) { return true }
        var addQuery = keychainQuery(account: account)
        addQuery[kSecAttrLabel as String] = label
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        addQuery[kSecValueData as String] = data
        return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
    }

    /// `.userPresence` ACL 付きエントリの作成を試みる。
    /// 成功すると、読み出し時に OS が Touch ID / パスワードによる在席確認を強制する
    /// （アプリのコードが改変されても Keychain 側で認証が要求される）
    private func addProtectedEntry(account: String, label: String, data: Data) -> Bool {
        // テスト実行時はプローブしない（成功する環境だと読み出しで認証プロンプトが出て
        // テストが停止してしまうため、常にファイルベース側を使う）
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return false }
        guard let accessControl = SecAccessControlCreateWithFlags(nil,
                                                                  kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                                                                  .userPresence, nil) else { return false }
        var addQuery = keychainQuery(account: account, dataProtection: true)
        addQuery[kSecAttrLabel as String] = label
        addQuery[kSecAttrAccessControl as String] = accessControl
        addQuery[kSecValueData as String] = data
        if let context = authenticatedContext {
            addQuery[kSecUseAuthenticationContext as String] = context
        }
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        #if DEBUG
        if status != errSecSuccess {
            NSLog("[SecureMenuService] protected add failed (status \(status)); falling back to file-based keychain")
        }
        #endif
        return status == errSecSuccess
    }

    /// エントリを削除する（ファイルベース・data protection の両方から）
    private func removeEntry(account: String) -> Bool {
        var success = true
        for dataProtection in [false, true] {
            let status = SecItemDelete(keychainQuery(account: account, dataProtection: dataProtection) as CFDictionary)
            if !dataProtection {
                success = (status == errSecSuccess || status == errSecItemNotFound)
            }
        }
        return success
    }

    // MARK: - User Data (user-data エントリの読み書き)

    /// user-data エントリを読み込む。存在しない場合は旧 2 エントリ
    /// （all-items / crypto-password）からの移行を試みる。
    ///
    /// 「読み出しには成功したが内容を解釈できない」場合は `errSecDecode` を返す。
    /// ここで `errSecSuccess` + nil を返すと、呼び出し側のガード
    /// （`status == errSecSuccess || status == errSecItemNotFound`）を素通りして
    /// 「アイテム 0 件」として扱われ、直後の保存で読めなかったデータを
    /// 空で上書きしてしまう。破損は「読めなかった」と同義に扱い、書き込みを禁止する
    private func loadUserData() -> (status: OSStatus, userData: SecureUserData?) {
        let (status, raw) = readEntry(account: Self.userDataKey)
        if status == errSecSuccess {
            guard let raw = raw else {
                NSLog("[SecureMenuService] loadUserData: entry found but returned no data")
                return (errSecDecode, nil)
            }
            guard let decoded = try? JSONDecoder().decode(SecureUserData.self, from: raw) else {
                NSLog("[SecureMenuService] loadUserData: decode failed (\(raw.count) bytes), treating as unreadable")
                return (errSecDecode, nil)
            }
            return (status, decoded)
        }
        guard status == errSecItemNotFound else { return (status, nil) }
        return migrateLegacyUserData()
    }

    /// 旧形式（all-items / crypto-password の 2 エントリ）から user-data へ移行する。
    /// 新エントリの読み戻し検証に成功した場合のみ旧エントリを削除する
    /// （検証前に消すと、書き込み失敗時にデータを失うため）
    private func migrateLegacyUserData() -> (status: OSStatus, userData: SecureUserData?) {
        let (itemsStatus, itemsData) = readEntry(account: Self.legacyItemsKey)
        let (passwordStatus, passwordData) = readEntry(account: Self.legacyCryptoPasswordKey)
        // どちらかがアクセス拒否なら移行しない（読めないデータを上書き・削除しないため）
        if itemsStatus != errSecSuccess && itemsStatus != errSecItemNotFound { return (itemsStatus, nil) }
        if passwordStatus != errSecSuccess && passwordStatus != errSecItemNotFound { return (passwordStatus, nil) }
        // 旧エントリも無い場合は、Clipy 時代の旧サービス名からの移行を試みる
        if itemsStatus == errSecItemNotFound && passwordStatus == errSecItemNotFound {
            return migrateFromLegacyService()
        }

        var userData = SecureUserData()
        if let itemsData = itemsData {
            // 旧エントリを解釈できない場合は移行を中止する。空の items で user-data を
            // 作ってしまうと、読み戻し検証（空データでも成功する）を通過して
            // 旧エントリが削除され、アイテムが完全に失われる
            guard let decodedItems = try? JSONDecoder().decode([SecureMenuItem].self, from: itemsData) else {
                NSLog("[SecureMenuService] migrateLegacyUserData: failed to decode legacy all-items, migration aborted")
                return (errSecDecode, nil)
            }
            userData.items = decodedItems
        }
        if let passwordData = passwordData {
            userData.cryptoPassword = String(data: passwordData, encoding: .utf8)
        }

        // 新エントリへ書き込み → 読み戻し検証 → 成功時のみ旧エントリを削除。
        // 書き込みに失敗しても、読めた内容はそのまま返す（旧エントリは残っており次回再試行される）
        if writeUserData(userData) {
            let (verifyStatus, verifyRaw) = readEntry(account: Self.userDataKey)
            if verifyStatus == errSecSuccess, let verifyRaw = verifyRaw,
               (try? JSONDecoder().decode(SecureUserData.self, from: verifyRaw)) != nil {
                _ = removeEntry(account: Self.legacyItemsKey)
                _ = removeEntry(account: Self.legacyCryptoPasswordKey)
                NSLog("[SecureMenuService] migrated legacy keychain entries to user-data")
            }
        }
        return (errSecSuccess, userData)
    }

    /// Clipy 時代の旧サービス名のエントリから移行する（Thoth への改名対応）。
    /// user-data → 旧 2 エントリの順に探し、見つかれば新サービス名へ書き込む。
    /// 旧サービスのエントリはロールバックに備えてバックアップとして残す
    private func migrateFromLegacyService() -> (status: OSStatus, userData: SecureUserData?) {
        // テスト用などカスタムサービス名のインスタンスでは移行しない
        // （実環境の Clipy データがテスト用サービスへ流れ込むのを防ぐ）
        guard keychainService == Self.defaultKeychainService else { return (errSecItemNotFound, nil) }
        let (status, raw) = readEntry(account: Self.userDataKey, service: Self.legacyKeychainService)
        if status == errSecSuccess {
            // 旧サービスのエントリが読めたのに解釈できない場合は移行を中止する。
            // ここで素通りさせると旧 2 エントリ経由の探索に落ちて「新規インストール」
            // と誤判定され、移行できていないデータの上に空の状態が作られる
            guard let raw = raw,
                  let decoded = try? JSONDecoder().decode(SecureUserData.self, from: raw) else {
                NSLog("[SecureMenuService] migrateFromLegacyService: failed to decode legacy user-data, migration aborted")
                return (errSecDecode, nil)
            }
            if writeUserData(decoded) {
                NSLog("[SecureMenuService] migrated user-data from legacy Clipy service")
            }
            return (errSecSuccess, decoded)
        }
        // アクセス拒否は移行せずそのまま返す（読めないデータの上書き防止）
        if status != errSecItemNotFound { return (status, nil) }

        let (itemsStatus, itemsData) = readEntry(account: Self.legacyItemsKey, service: Self.legacyKeychainService)
        let (passwordStatus, passwordData) = readEntry(account: Self.legacyCryptoPasswordKey, service: Self.legacyKeychainService)
        if itemsStatus != errSecSuccess && itemsStatus != errSecItemNotFound { return (itemsStatus, nil) }
        if passwordStatus != errSecSuccess && passwordStatus != errSecItemNotFound { return (passwordStatus, nil) }
        // 旧サービスにも無い = 新規インストール
        if itemsStatus == errSecItemNotFound && passwordStatus == errSecItemNotFound {
            return (errSecItemNotFound, nil)
        }

        var userData = SecureUserData()
        if let itemsData = itemsData {
            // 解釈できない旧データを空で置き換えないよう、移行を中止する（上記と同じ理由）
            guard let decodedItems = try? JSONDecoder().decode([SecureMenuItem].self, from: itemsData) else {
                NSLog("[SecureMenuService] migrateFromLegacyService: failed to decode legacy all-items, migration aborted")
                return (errSecDecode, nil)
            }
            userData.items = decodedItems
        }
        if let passwordData = passwordData {
            userData.cryptoPassword = String(data: passwordData, encoding: .utf8)
        }
        if writeUserData(userData) {
            NSLog("[SecureMenuService] migrated legacy entries from legacy Clipy service")
        }
        return (errSecSuccess, userData)
    }

    private func writeUserData(_ userData: SecureUserData) -> Bool {
        guard let data = try? JSONEncoder().encode(userData) else { return false }
        return writeEntry(account: Self.userDataKey, label: "Thoth Secure User Data", data: data)
    }

    // MARK: - Keychain CRUD

    func loadAllItems() -> [SecureMenuItem] {
        let (status, userData) = loadUserData()
        #if DEBUG
        NSLog("[SecureMenuService] loadAllItems: status=\(status)")
        #endif
        // 「エントリが存在しない」以外の失敗は読み出し不能として記録する。
        // - アクセス拒否（バイナリ更新により Keychain ACL の照合に失敗した場合など）
        // - errSecDecode: 読めたが解釈できない（破損、または未知の形式で保存された
        //   データを古いバイナリで読んだ場合）
        // どちらも「既存データを空で上書きしてはいけない」状態なので同じ扱いにする
        isKeychainAccessDenied = (status != errSecSuccess && status != errSecItemNotFound)

        guard let userData = userData else {
            if isKeychainAccessDenied {
                NSLog("[SecureMenuService] loadAllItems: keychain access failed with status \(status)")
            }
            return []
        }
        return userData.items.sorted { $0.displayOrder < $1.displayOrder }
    }

    func save(_ item: SecureMenuItem) -> Bool {
        return save([item])
    }

    /// 複数アイテムをまとめて保存する（Keychain への読み書きと変更通知は 1 回）。
    ///
    /// 1 件ずつ `save(_:)` を呼ぶと件数分の読み書きが走り、そのたびに変更通知が飛んで
    /// 各ウィンドウが再読込するため、インポートのような一括処理では極端に遅くなる
    @discardableResult
    func save(_ newItems: [SecureMenuItem]) -> Bool {
        guard !newItems.isEmpty else { return true }
        var items = loadAllItems()
        // 新規追加の displayOrder は末尾に積む
        var maxOrder = items.map { $0.displayOrder }.max() ?? -1
        for item in newItems {
            if let index = items.firstIndex(where: { $0.itemID == item.itemID }) {
                // 上書き時は各フィールドの Val 変更履歴を引き継ぎ・追記する
                items[index] = mergeFieldHistories(oldItem: items[index], newItem: item)
            } else {
                maxOrder += 1
                items.append(SecureMenuItem(itemID: item.itemID,
                                            title: item.title,
                                            fields: item.fields,
                                            displayOrder: maxOrder))
            }
        }
        return saveAllItems(items)
    }

    func delete(itemID: String) -> Bool {
        return delete(itemIDs: [itemID])
    }

    /// 複数アイテムをまとめて削除する（Keychain への書き込みは 1 回で行う）
    func delete(itemIDs: [String]) -> Bool {
        var items = loadAllItems()
        items.removeAll { itemIDs.contains($0.itemID) }
        return saveAllItems(items)
    }

    func reorderItems(_ orderedItems: [SecureMenuItem]) -> Bool {
        let reordered = orderedItems.enumerated().map { index, item in
            SecureMenuItem(itemID: item.itemID, title: item.title, fields: item.fields, displayOrder: index)
        }
        return saveAllItems(reordered)
    }

    /// 全アイテムを削除する（テストのクリーンアップ用）。
    /// 指紋パスワードも未登録ならエントリごと削除し、旧形式のエントリ残骸も掃除する
    @discardableResult
    func deleteAllItems() -> Bool {
        _ = removeEntry(account: Self.legacyItemsKey)
        let (status, existing) = loadUserData()
        if status == errSecItemNotFound { return true }
        guard status == errSecSuccess else { return false }
        var userData = existing ?? SecureUserData()
        let hadItems = !(existing?.items.isEmpty ?? true)
        userData.items = []
        let removed = (userData.cryptoPassword ?? "").isEmpty
            ? removeEntry(account: Self.userDataKey)
            : writeUserData(userData)
        // 消すものが無かった場合は「変更なし」として通知しない
        if removed && hadItems { postItemsDidChange() }
        return removed
    }

    // MARK: - Crypto Password (指紋パスワード)

    /// 暗号化・復号化の指紋パスワード（固定パスワード）を保存する。
    /// user-data エントリ（セキュアアイテムと同一）の cryptoPassword に格納される
    @discardableResult
    func saveCryptoPassword(_ password: String) -> Bool {
        let (status, existing) = loadUserData()
        guard status == errSecSuccess || status == errSecItemNotFound else { return false }
        var userData = existing ?? SecureUserData()
        userData.cryptoPassword = password
        return writeUserData(userData)
    }

    /// 保存済みの指紋パスワードを読み出す。未登録の場合は nil を返す。
    /// ACL 付きエントリの場合、authenticate() 済みのコンテキストが紐付いていないと
    /// OS が追加の認証を要求する
    func loadCryptoPassword() -> String? {
        return loadUserData().userData?.cryptoPassword
    }

    /// 指紋パスワードが登録済みか
    func hasCryptoPassword() -> Bool {
        let password = loadCryptoPassword() ?? ""
        return !password.isEmpty
    }

    /// 指紋パスワードを削除する（テストのクリーンアップ用）。
    /// アイテムも無ければエントリごと削除し、旧形式のエントリ残骸も掃除する
    @discardableResult
    func deleteCryptoPassword() -> Bool {
        _ = removeEntry(account: Self.legacyCryptoPasswordKey)
        let (status, existing) = loadUserData()
        if status == errSecItemNotFound { return true }
        guard status == errSecSuccess, var userData = existing else { return false }
        userData.cryptoPassword = nil
        if userData.items.isEmpty {
            return removeEntry(account: Self.userDataKey)
        }
        return writeUserData(userData)
    }

    // MARK: - Private Helpers

    /// フィールドごとの Val 変更履歴の最大保持件数（超過分は古いものから自動削除する）
    static let maxFieldHistoryCount = 10

    /// 同じ itemID の既存アイテムを上書きする際、各フィールドの Val が変更されていた場合に、
    /// 旧値を「置き換えられた日時」つきで変更履歴に追記する。
    /// フィールドの対応付けは fieldID（安定 ID）で行うため、Label を変更しても履歴は追従する。
    /// fieldID を持たない旧形式データから移行する場合のみ label で対応付ける。
    /// 履歴は渡されたフィールドのものを正とする（ポップアップからの削除を反映するため）。
    private func mergeFieldHistories(oldItem: SecureMenuItem, newItem: SecureMenuItem) -> SecureMenuItem {
        var merged = newItem
        merged.fields = newItem.fields.map { field in
            let oldField = oldItem.fields.first { $0.fieldID == field.fieldID }
                ?? oldItem.fields.first { $0.label == field.label }
            guard let old = oldField else { return field }
            var history = field.history
            // 履歴を残す種別（plain / url）のみ旧値を追記する。
            // TOTP は secret が極めて機微なため、メモは長文が履歴表示を壊すため残さない
            if field.kind.retainsValueHistory, old.value != field.value && !old.value.isEmpty {
                history.append(SecureMenuItem.FieldHistoryEntry(value: old.value, replacedAt: Date()))
            }
            // 上限を超えた分は古いものから削除する
            history = Array(history.suffix(Self.maxFieldHistoryCount))
            return field.updating(history: history)
        }
        return merged
    }

    private func saveAllItems(_ items: [SecureMenuItem]) -> Bool {
        // 既存エントリを読み出せていない状態で保存すると、読めなかったデータを
        // 上書きして消去してしまうため保存を拒否する
        guard !isKeychainAccessDenied else {
            NSLog("[SecureMenuService] saveAllItems: rejected to prevent overwriting unreadable keychain data")
            return false
        }
        // cryptoPassword を保持したまま items だけ差し替える（read-modify-write）
        let (status, existing) = loadUserData()
        guard status == errSecSuccess || status == errSecItemNotFound else { return false }
        var userData = existing ?? SecureUserData()
        userData.items = items
        guard writeUserData(userData) else { return false }
        postItemsDidChange()
        return true
    }
}

// MARK: - Notifications

extension Notification.Name {
    /// セキュアアイテムが変更された（保存・削除・並べ替え）。
    /// 同じサービスを共有する複数のウィンドウが表示を同期するために使う。
    /// object は変更を行った `SecureMenuService`
    static let secureItemsDidChange = Notification.Name("io.github.boyaki-machine.Thoth.secureItemsDidChange")
}
