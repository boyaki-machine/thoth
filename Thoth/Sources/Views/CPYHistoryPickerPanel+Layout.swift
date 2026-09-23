//
//  CPYHistoryPickerPanel+Layout.swift
//
//  Thoth
//
//  履歴パネルの部品の組み立てと配置
//

import Cocoa

// MARK: - Build Views

extension CPYHistoryPickerPanel {
    func buildViews() {
        effectView.material             = .menu
        effectView.blendingMode         = .behindWindow
        effectView.state                = .active
        effectView.wantsLayer           = true
        effectView.layer?.cornerRadius  = Layout.corner
        effectView.layer?.masksToBounds = true
        contentView = effectView

        searchField.placeholderString            = L10n.historySearchPlaceholder
        searchField.sendsSearchStringImmediately = true
        searchField.focusRingType                = .none
        searchField.delegate                     = self
        searchField.translatesAutoresizingMaskIntoConstraints = false
        effectView.addSubview(searchField)

        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        effectView.addSubview(divider)

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("col"))
        col.isEditable = false
        tableView.addTableColumn(col)
        tableView.headerView              = nil
        tableView.intercellSpacing        = .zero
        tableView.backgroundColor         = .clear
        tableView.focusRingType           = .none
        tableView.selectionHighlightStyle = .regular
        tableView.style = .plain
        tableView.usesAutomaticRowHeights = false
        tableView.delegate                = self
        tableView.dataSource              = self
        tableView.target                  = self
        tableView.action                  = #selector(rowClicked)

        scrollView.hasVerticalScroller = true
        // 画面に収まっているときはスクローラーを出さない
        scrollView.autohidesScrollers  = true
        scrollView.drawsBackground     = false
        scrollView.documentView        = tableView
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        effectView.addSubview(scrollView)

        // マウスホバーで行をハイライトするためのトラッキング（NSMenu と同じ操作感）。
        // .inVisibleRect によりサイズ変更へ自動追従する
        tableView.addTrackingArea(NSTrackingArea(rect: .zero,
                                                 options: [.mouseMoved, .activeAlways, .inVisibleRect],
                                                 owner: self, userInfo: nil))

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: effectView.topAnchor, constant: Layout.vPad),
            searchField.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: Layout.hPad),
            searchField.trailingAnchor.constraint(equalTo: effectView.trailingAnchor, constant: -Layout.hPad),
            searchField.heightAnchor.constraint(equalToConstant: Layout.searchH),
            divider.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: Layout.vPad - 2),
            divider.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 2),
            scrollView.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: effectView.bottomAnchor, constant: -4)
        ])
    }
}
