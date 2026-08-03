//
//  SecureFieldDropView.swift
//
//  Thoth
//  GitHub: https://github.com/boyaki-machine/Thoth
//

import Cocoa

/// 右ペインのフィールド行を並べる入れ物であり、並べ替えドラッグの受け皿。
///
/// 行は `NSTableView` ではなく `NSStackView` に積んでいる（理由は
/// `CPYSecureInfoDetailViewController` の冒頭を参照）。テーブルなら標準で付いてくる
/// 並べ替えドラッグが無いので、挿入位置の判定と目印の描画をここで受け持つ。
///
/// 座標系は上下反転させたまま（`isFlipped = true`）。`NSClipView` は反転していないため、
/// 内容が可視領域より短いとドキュメントビューが下端に寄ってしまう。
final class SecureFieldDropView: NSView {

    override var isFlipped: Bool { true }

    /// 現在並んでいる行の矩形（このビューの座標系）。表示側が供給する
    var rowFrames: (() -> [CGRect])?
    /// ドロップされた。`gapIndex` は**行と行のすき間**の番号（0 は先頭の上、行数なら末尾の下）
    var onFieldDropped: ((_ fieldID: String, _ gapIndex: Int) -> Void)?

    /// 目印を描いているすき間の番号。ドラッグ中だけ値が入る
    private(set) var insertionGapIndex: Int?

    private enum Layout {
        static let indicatorHeight: CGFloat = 2
        /// 行の左端に合わせるための差し込み量（掴み手の幅ぶん食い込ませない）
        static let indicatorInset: CGFloat = 0
    }

    init() {
        super.init(frame: .zero)
        registerForDraggedTypes([.thothSecureFieldRow])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Insertion index

    /// ドロップ位置がどのすき間に当たるかを求める（純粋関数のためユニットテスト可能）。
    ///
    /// 各行の中点より上なら「その行の手前」、どの行の中点にも届かなければ末尾。
    /// - Parameters:
    ///   - dropY: 上下反転座標系での y（上端が 0）
    ///   - rowFrames: 上から下へ並んだ行の矩形
    static func insertionGapIndex(dropY: CGFloat, rowFrames: [CGRect]) -> Int {
        for (index, frame) in rowFrames.enumerated() where dropY < frame.midY {
            return index
        }
        return rowFrames.count
    }

    // MARK: - NSDraggingDestination

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        return updateInsertion(with: sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        // 行数が多いとき、掴んだまま端へ寄せればスクロールする
        if let event = NSApp.currentEvent { autoscroll(with: event) }
        return updateInsertion(with: sender)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        clearInsertion()
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        clearInsertion()
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        return insertionGapIndex != nil
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let gapIndex = insertionGapIndex
        clearInsertion()
        guard let gapIndex = gapIndex,
              let fieldID = sender.draggingPasteboard.pasteboardItems?.first?
                  .string(forType: .thothSecureFieldRow) else { return false }
        onFieldDropped?(fieldID, gapIndex)
        return true
    }

    private func updateInsertion(with sender: NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingPasteboard.pasteboardItems?.first?
                .string(forType: .thothSecureFieldRow) != nil else { return [] }
        let point = convert(sender.draggingLocation, from: nil)
        let gapIndex = Self.insertionGapIndex(dropY: point.y, rowFrames: rowFrames?() ?? [])
        if insertionGapIndex != gapIndex {
            insertionGapIndex = gapIndex
            needsDisplay = true
        }
        return .move
    }

    private func clearInsertion() {
        guard insertionGapIndex != nil else { return }
        insertionGapIndex = nil
        needsDisplay = true
    }

    // MARK: - Insertion indicator

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let gapIndex = insertionGapIndex, let frames = rowFrames?(), !frames.isEmpty else { return }
        // すき間の番号を y 座標に直す。末尾のすき間だけ最後の行の下端になる
        let indicatorY = gapIndex < frames.count ? frames[gapIndex].minY : frames[frames.count - 1].maxY
        let rect = NSRect(x: Layout.indicatorInset,
                          y: indicatorY - Layout.indicatorHeight / 2,
                          width: bounds.width - Layout.indicatorInset * 2,
                          height: Layout.indicatorHeight)
        NSColor.controlAccentColor.setFill()
        rect.fill()
    }
}
