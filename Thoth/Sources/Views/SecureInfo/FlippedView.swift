//
//  FlippedView.swift
//
//  Thoth
//  GitHub: https://github.com/boyaki-machine/Thoth
//

import Cocoa

/// 座標系を上下反転させたビュー。
///
/// `NSClipView` は上下反転していないため、`NSScrollView` のドキュメントビューが
/// 可視領域より小さいと内容が**下端に寄って**表示される。
/// ドキュメントビューをこれにすると上詰めになる。
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
