//
//  PickerPanelSupport.swift
//
//  Thoth
//  GitHub: https://github.com/boyaki-machine/Thoth
//

import Cocoa

/// 履歴・セキュアアイテムの選択パネルが共有する、配置の計算と部品。
/// 2 つのパネルは同じ見た目・同じ操作感にそろえているので、ここを 1 箇所で直せるようにする
enum PickerPanelSupport {

    /// 画面の端からこの分だけ離して置く
    static let screenInset: CGFloat = 4
    /// メインパネルとサブパネルの隙間
    static let subPanelGap: CGFloat = 4

    /// サブパネルの置き場所
    struct SubPanelPlacement: Equatable {
        let origin: NSPoint
        /// メインパネルの左側に置いたか（← → / h l の操作方向の入れ替えに使う）
        let isOnLeft: Bool
    }

    /// 指定位置を含む画面の作業領域（画面が 1 枚も無いときは空の矩形）
    static func visibleFrame(containing point: NSPoint) -> NSRect {
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        return screen?.visibleFrame ?? .zero
    }

    /// 指定の矩形と重なる画面の作業領域（画面が 1 枚も無いときは空の矩形）
    static func visibleFrame(intersecting frame: NSRect) -> NSRect {
        let screen = NSScreen.screens.first { $0.frame.intersects(frame) } ?? NSScreen.main
        return screen?.visibleFrame ?? .zero
    }

    /// メインパネルの位置を決める（純粋関数）。カーソルの右下に出し、画面に収める
    static func panelOrigin(near point: NSPoint, panelSize: NSSize, visible: NSRect) -> NSPoint {
        return NSPoint(x: max(visible.minX + screenInset, min(point.x + 15, visible.maxX - panelSize.width - screenInset)),
                       y: max(visible.minY + screenInset, min(point.y - panelSize.height + 15, visible.maxY - panelSize.height - screenInset)))
    }

    /// サブパネルの位置を決める（純粋関数）。
    /// 右側を優先し、画面右端に収まらない場合はメインパネルに被せず左側へ配置する。
    /// 左側にも収まらない場合のみ右側でクランプする（被りは許容する最終手段）
    /// - Parameter rowTopY: サブパネルの上端をそろえる行の上端（画面座標）
    static func subPanelPlacement(mainFrame: NSRect, subPanelSize: NSSize, rowTopY: CGFloat, visible: NSRect) -> SubPanelPlacement {
        let rightX = mainFrame.maxX + subPanelGap
        let leftX = mainFrame.minX - subPanelGap - subPanelSize.width
        let originX: CGFloat
        var isOnLeft = false
        if rightX + subPanelSize.width <= visible.maxX - screenInset {
            originX = rightX
        } else if leftX >= visible.minX + screenInset {
            originX = leftX
            isOnLeft = true
        } else {
            originX = max(visible.minX + screenInset, min(rightX, visible.maxX - subPanelSize.width - screenInset))
        }
        let originY = max(visible.minY + screenInset, min(rowTopY - subPanelSize.height, visible.maxY - subPanelSize.height - screenInset))
        return SubPanelPlacement(origin: NSPoint(x: originX, y: originY), isOnLeft: isOnLeft)
    }

    /// 1 行のテキストを表示するセルを作る
    static func makeTextCell(identifier: NSUserInterfaceItemIdentifier, indent: CGFloat = 6) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = identifier
        let textField = NSTextField(labelWithString: "")
        textField.lineBreakMode = .byTruncatingTail
        textField.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(textField)
        cell.textField = textField
        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: indent),
            textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
            textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        return cell
    }

    /// 区切り線の行を作る
    static func makeSeparatorView(identifier: NSUserInterfaceItemIdentifier) -> NSView {
        let view = NSView()
        view.identifier = identifier
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(box)
        NSLayoutConstraint.activate([
            box.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            box.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            box.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        return view
    }
}

/// パネル外のクリックを検知するイベントモニタ（グローバル/ローカルの組）
final class PanelOutsideClickMonitor {

    private var monitors: [Any] = []

    /// 登録中のモニタ数（テストでのライフサイクル検証用）
    var count: Int { monitors.count }

    deinit { remove() }

    /// - Parameters:
    ///   - belongsToPanel: クリックされたウィンドウがパネル（群）に属するか
    ///   - onOutsideClick: パネルの外がクリックされたときに呼ばれる
    func install(belongsToPanel: @escaping (NSWindow?) -> Bool, onOutsideClick: @escaping () -> Void) {
        remove()
        let events: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]
        // 他のアプリのクリックはグローバルモニタにしか届かない
        let global = NSEvent.addGlobalMonitorForEvents(matching: events) { _ in onOutsideClick() }
        let local = NSEvent.addLocalMonitorForEvents(matching: events) { event in
            if !belongsToPanel(event.window) { onOutsideClick() }
            return event
        }
        monitors = [global, local].compactMap { $0 }
    }

    func remove() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []
    }
}
