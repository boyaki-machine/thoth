//
//  Diagnostics.swift
//
//  Thoth
//
//  不具合の調査用に、貼り付けやパネル表示の各段階を統合ログへ残す
//

import os

/// 不具合の調査用ログ（統合ログ。Console.app か `log show` で読める）。
///
/// 貼り付け先への前面化・⌘V の送出・セキュアメニューの表示（ホットキー → 認証 → パネル）のように、
/// 利用者の環境でしか再現しない流れの各段階を残す。**貼り付ける値・項目名などの内容は決して書かない**
/// （書くのはアプリのバンドル ID・経過時間・真偽値・ウィンドウの状態だけ）。
///
/// レベルは notice（ディスクに残る）にする。info だと macOS がメモリ上にしか持たず、
/// 利用者が再現してから読むまでの間に消えてしまう（v1.6.0 の動作確認で実際に消えた）。
///
/// 読み方:
/// ```
/// log show --last 10m --style compact --predicate 'subsystem == "io.github.boyaki-machine.Thoth"'
/// ```
enum Diagnostics {
    static let subsystem = "io.github.boyaki-machine.Thoth"
    /// 貼り付け先への前面化と ⌘V・キー入力の送出
    static let paste = Logger(subsystem: subsystem, category: "Paste")
    /// セキュアメニューの表示（ホットキー → 認証 → パネル）
    static let secureMenu = Logger(subsystem: subsystem, category: "SecureMenu")
}
