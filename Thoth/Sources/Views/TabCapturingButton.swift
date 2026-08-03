//
//  TabCapturingButton.swift
//
//  Thoth
//  GitHub: https://github.com/boyaki-machine/Thoth
//

import Cocoa

/// `acceptsFirstResponder` を `true` にオーバーライドした NSButton。
///
/// NSButton は「フルキーボードアクセス」が無効だとフォーカスを受け取らないため、
/// `makeFirstResponder` を呼んでも素通りしてしまう。Tab でボタン間を巡回させたい
/// 画面ではこれを使い、確実にフォーカスを受け取れるようにする。
/// Tab イベント自体は各画面のローカルイベントモニターが処理する。
///
/// 元は廃止したセキュアアイテム編集シートの中に置かれていたが、
/// 暗号化ウィンドウからも使われているためここへ切り出した。
final class TabCapturingButton: NSButton {
    override var acceptsFirstResponder: Bool { true }
}
