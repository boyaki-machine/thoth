//
//  Diagnostics.swift
//
//  Thoth
//
//  不具合の調査用に、貼り付けやパネル表示の各段階を統合ログへ残す
//

import os

/// 不具合の調査用ログ（統合ログ）。
///
/// 貼り付け先への前面化・⌘V の送出・セキュアメニューの表示（ホットキー → 認証 → パネル）のように、
/// 利用者の環境でしか再現しない流れの各段階を残す。
///
/// **利用者の行動の足跡を残さないための約束**
/// - 貼り付ける値・項目名などの内容は書かない
/// - どのアプリで使ったか（バンドル ID・アプリ名）も書かない。「貼り付け先が前面に来たか」のような
///   真偽値・経過時間・ウィンドウの状態だけを書く
/// - レベルは info にする（macOS はメモリ上にしか持たず、ディスクに残らない）。notice 以上にすると
///   統合ログとして数日〜数週間ディスクに残り、「いつセキュアメニューを使ったか」が後から読めてしまう
///
/// 調べるときは、利用者が再現する間にリアルタイムで読む（ディスクには残らない）:
/// ```
/// log stream --info --style compact --predicate 'subsystem == "io.github.boyaki-machine.Thoth"'
/// ```
enum Diagnostics {
    static let subsystem = "io.github.boyaki-machine.Thoth"
    /// 貼り付け先への前面化と ⌘V・キー入力の送出
    static let paste = Logger(subsystem: subsystem, category: "Paste")
    /// セキュアメニューの表示（ホットキー → 認証 → パネル）
    static let secureMenu = Logger(subsystem: subsystem, category: "SecureMenu")
}
