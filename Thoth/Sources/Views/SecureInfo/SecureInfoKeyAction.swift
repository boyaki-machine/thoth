//
//  SecureInfoKeyAction.swift
//
//  Thoth
//  GitHub: https://github.com/boyaki-machine/Thoth
//

import AppKit

/// セキュア情報確認ウィンドウでキー入力に割り当てられた操作。
///
/// 対応表（`CPYSecureInfoSplitViewController.keyAction(...)` が実際の写像）:
///
/// | キー | 操作 |
/// |---|---|
/// | `j` / `k` | 一覧の選択を上下に動かす |
/// | `Ctrl+j` / `Ctrl+k` | 並べ替え（右ペインに編集中の行があればフィールド、無ければアイテム） |
/// | `l` / `→` / `Return` | 右ペインへフォーカスを移す |
/// | `h` / `←` | 一覧へフォーカスを戻す |
/// | `/` / `⌘F` | 検索欄へフォーカスを移す |
/// | `⌘N` | アイテムを追加 |
/// | `⌘Delete` | 選択中アイテムを削除 |
/// | `⌘S` | 明示保存 |
/// | `⌘G` | パスワード生成シートを開く |
/// | `⌘Z` / `⌘⇧Z` | 直前の変更を取り消す / やり直す（**入力中は割り当てない**） |
/// | `Esc` | 入力中なら編集の確定、そうでなければウィンドウを閉じる |
/// | `⌘W` | ウィンドウを閉じる |
enum SecureInfoKeyAction: Equatable {
    case focusSearch
    case focusList
    case focusDetail
    case moveSelectionDown
    case moveSelectionUp
    case reorderDown
    case reorderUp
    case addItem
    case deleteItem
    case save
    case generatePassword
    case undo
    case redo
    case endEditing
    case close
}

/// キー処理で使う仮想キーコード。数値の直書きを避けて意図を読めるようにする
enum KeyCode {
    static let letterH: UInt16 = 4
    static let letterJ: UInt16 = 38
    static let letterK: UInt16 = 40
    static let letterL: UInt16 = 37
    static let returnKey: UInt16 = 36
    static let slash: UInt16 = 44
    static let delete: UInt16 = 51
    static let escape: UInt16 = 53
    static let leftArrow: UInt16 = 123
    static let rightArrow: UInt16 = 124
}
