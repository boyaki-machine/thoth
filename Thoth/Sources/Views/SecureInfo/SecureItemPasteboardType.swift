//
//  SecureItemPasteboardType.swift
//
//  Thoth
//  GitHub: https://github.com/boyaki-machine/Thoth
//

import AppKit

// MARK: - Pasteboard Types
//
// セキュアアイテム／フィールドの並べ替えドラッグで使う型。
// **アプリ内の並べ替え専用**で、載せるのは行番号やフィールド ID だけ。
// 値そのものは決して載せない（ドラッグ中のペイストボードは他アプリからも読める）。
extension NSPasteboard.PasteboardType {

    /// セキュアアイテムの行（確認ウィンドウ左ペインの一覧で使う）。
    /// 中身は表示中の行番号を 10 進で書いた文字列
    static let thothSecureItemRow = NSPasteboard.PasteboardType("io.github.boyaki-machine.thoth.secureItemRow")

    /// セキュア情報確認ウィンドウ右ペインのフィールド行。
    /// 中身はフィールドの安定 ID（`fieldID`）
    static let thothSecureFieldRow = NSPasteboard.PasteboardType("io.github.boyaki-machine.thoth.secureFieldRow")
}
