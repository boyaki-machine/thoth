//
//  CPYClip.swift
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
import RealmSwift

/// クリップボード履歴 1 件を表す Realm モデル。
/// クリップの実データ（全ペーストボード型のアーカイブ）は Realm には持たず、
/// dataPath が指す .data ファイル（ClipDataStore が暗号化管理）に保存する。
/// Realm 側はメニュー表示に必要なメタデータのみを持つ。
final class CPYClip: Object {

    // MARK: - Properties
    /// クリップ実データ（.data ファイル）の絶対パス
    @objc dynamic var dataPath = ""
    /// メニューに表示するタイトル（文字列値の先頭部分）
    @objc dynamic var title = ""
    /// 内容のハッシュ（主キー。「同じ内容を上書き」設定時の重複判定に使用）
    @objc dynamic var dataHash = ""
    /// 代表のペーストボード型（アイコン表示の判定に使用）
    @objc dynamic var primaryType = ""
    /// コピーされた時刻（UNIX 時間。履歴の並び順・上限判定に使用）
    @objc dynamic var updateTime = 0
    /// サムネイル画像の PINCache キー（画像クリップのみ）
    @objc dynamic var thumbnailPath = ""
    /// HEX カラーコードとして解釈できる内容か（カラープレビュー表示用）
    @objc dynamic var isColorCode = false

    // MARK: Primary Key
    override static func primaryKey() -> String? {
        return "dataHash"
    }

}
