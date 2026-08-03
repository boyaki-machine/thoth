//
//  SecureItemsTransfer.swift
//
//  Thoth
//  GitHub: https://github.com/boyaki-machine/Thoth
//

import Foundation

/// セキュア情報のファイル入出力。UI を持たないので、
/// セキュアアイテム管理ウィンドウと確認ウィンドウの両方から同じ処理を呼べる。
///
/// 入出力の単位は「ユーザー自身が設定した機微情報」（`SecureUserData`）。
/// セキュアアイテムに加えて指紋パスワードも含まれる。アプリが自動生成する
/// 環境固有の情報（DB 暗号鍵等）は対象外。
///
/// **書き出されるファイルは平文。** 呼び出し側は必ず警告を出してから使うこと。
enum SecureItemsTransfer {

    /// 保存ダイアログに出す既定のファイル名
    static let defaultFileName = "thoth-secure-items.json"

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
    @discardableResult
    static func apply(items: [SecureMenuItem], cryptoPassword: String?,
                      using service: SecureMenuService) -> Bool {
        if let cryptoPassword = cryptoPassword, !cryptoPassword.isEmpty {
            _ = service.saveCryptoPassword(cryptoPassword)
        }
        // 0 件のファイルを取り込んだときは「何もしなかった」を成功として返す
        guard !items.isEmpty else { return true }
        return service.save(items)
    }
}
