//
//  SecureItemsTransfer.swift
//
//  Thoth
//  GitHub: https://github.com/boyaki-machine/Thoth
//

import Foundation

/// セキュア情報のファイル入出力。UI を持たないので、
/// 呼び出し元の画面に依存せず同じ処理を使える。
///
/// 入出力の単位は「ユーザー自身が設定した機微情報」（`SecureUserData`）。
/// セキュアアイテムに加えて指紋パスワードも含まれる。アプリが自動生成する
/// 環境固有の情報（DB 暗号鍵等）は対象外。
///
/// **書き出されるファイルは平文。** 呼び出し側は必ず警告を出してから使うこと。
enum SecureItemsTransfer {

    /// 保存ダイアログに出す既定のファイル名
    static let defaultFileName = "thoth-secure-items.json"

    enum TransferError: LocalizedError {
        /// キーチェーンを読み出せなかった（0 件として書き出してはいけない状態）
        case keychainUnreadable

        var errorDescription: String? {
            switch self {
            case .keychainUnreadable: return L10n.secureItemsKeychainAccessDenied
            }
        }
    }

    /// 書き出す内容を組み立てる。
    ///
    /// **読み出せたかどうかを必ずここで確かめる。** 呼び出し側の入口判定は
    /// 直近の読み込み結果を写した控えを見ているだけなので、保存パネルを開いている間に
    /// 読めなくなると 0 件のまま素通りし、ユーザーのバックアップを空で上書きしてしまう
    static func exportData(using service: SecureMenuService) throws -> Data {
        let items = service.loadAllItems()
        guard !service.isKeychainAccessDenied else { throw TransferError.keychainUnreadable }
        return try encode(items: items, cryptoPassword: service.loadCryptoPassword())
    }

    /// 書き出す JSON を作る。
    /// 差分を見やすくするため整形して並びも固定する（バックアップの比較に使える）
    static func encode(items: [SecureMenuItem], cryptoPassword: String?) throws -> Data {
        let userData = SecureUserData(items: items, cryptoPassword: cryptoPassword)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(userData)
    }

    /// 取り込みファイルを解釈する（純粋関数）。
    /// 現行形式（`SecureUserData` オブジェクト）を優先し、
    /// 旧形式（アイテムの配列のみ）もフォールバックで読み込める
    static func parseImport(_ data: Data) throws -> (items: [SecureMenuItem], cryptoPassword: String?) {
        if let userData = try? JSONDecoder().decode(SecureUserData.self, from: data) {
            let password = (userData.cryptoPassword?.isEmpty ?? true) ? nil : userData.cryptoPassword
            return (userData.items, password)
        }
        return (try JSONDecoder().decode([SecureMenuItem].self, from: data), nil)
    }

    /// 指紋パスワードの上書き確認が要るかを判定する（純粋関数）。
    ///
    /// 上書きすると、以前そのパスワードで暗号化したファイルを開けなくなることがある。
    /// **登録済みで、かつ内容が異なる場合だけ**確認する（同じ内容や未登録なら黙って進めてよい）
    static func replacesCryptoPassword(current: String?, incoming: String?) -> Bool {
        guard let incoming = incoming, !incoming.isEmpty else { return false }
        guard let current = current, !current.isEmpty else { return false }
        return current != incoming
    }

    /// 取り込みを反映する。
    ///
    /// アイテムは 1 回の書き込みでまとめて保存する
    /// （1 件ずつ保存すると件数分の Keychain 往復と変更通知が発生する）。
    /// 同じ `itemID` は上書き、それ以外は末尾に追加される
    /// **取り消し（⌘Z）が戻すのはアイテムだけで、指紋パスワードは戻らない。**
    /// 置き換えは「開けなくなる」旨の確認を通したときにしか起きないため、
    /// 取り消しが部分的になることを承知で許容している
    @discardableResult
    static func apply(items: [SecureMenuItem], cryptoPassword: String?,
                      using service: SecureMenuService) -> Bool {
        var succeeded = true
        if let cryptoPassword = cryptoPassword, !cryptoPassword.isEmpty {
            // 失敗を握りつぶすと「N 件インポートしました」と出たまま
            // 指紋パスワードだけ入っていない状態に気づけない
            succeeded = service.saveCryptoPassword(cryptoPassword)
        }
        // 0 件のファイルを取り込んだときは「何もしなかった」を成功として返す
        guard !items.isEmpty else { return succeeded }
        return service.save(items) && succeeded
    }
}
