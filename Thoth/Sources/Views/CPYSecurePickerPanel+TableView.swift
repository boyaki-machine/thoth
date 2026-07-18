//
//  CPYSecurePickerPanel+TableView.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Copyright © 2015-2018 Clipy Project.
//

import Cocoa

// MARK: - NSTableViewDataSource

extension CPYSecurePickerPanel: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
}

// MARK: - NSTableViewDelegate

extension CPYSecurePickerPanel: NSTableViewDelegate {

    func tableView(_ tableView: NSTableView,
                   viewFor tableColumn: NSTableColumn?,
                   row: Int) -> NSView? {
        switch rows[row] {
        case .parent(let item):
            let cell = (tableView.makeView(withIdentifier: CellID.parent, owner: nil) as? NSTableCellView)
                       ?? makeTextCell(identifier: CellID.parent)
            cell.textField?.stringValue = "▸ \(item.title)"
            cell.textField?.font = .boldSystemFont(ofSize: Layout.fontSize)
            return cell

        case .separator:
            if let existing = tableView.makeView(withIdentifier: CellID.sep, owner: nil) { return existing }
            let sepView = NSView()
            sepView.identifier = CellID.sep
            let box = NSBox()
            box.boxType = .separator
            box.translatesAutoresizingMaskIntoConstraints = false
            sepView.addSubview(box)
            NSLayoutConstraint.activate([
                box.leadingAnchor.constraint(equalTo: sepView.leadingAnchor),
                box.trailingAnchor.constraint(equalTo: sepView.trailingAnchor),
                box.centerYAnchor.constraint(equalTo: sepView.centerYAnchor)
            ])
            return sepView

        case .noResults:
            let cell = (tableView.makeView(withIdentifier: CellID.info, owner: nil) as? NSTableCellView)
                       ?? makeTextCell(identifier: CellID.info, indent: 14)
            cell.textField?.stringValue = L10n.secureMenuNoResults
            cell.textField?.font        = .systemFont(ofSize: Layout.fontSize)
            cell.textField?.textColor   = .secondaryLabelColor
            return cell

        case .manage:
            let cell = (tableView.makeView(withIdentifier: CellID.manage, owner: nil) as? NSTableCellView)
                       ?? makeTextCell(identifier: CellID.manage)
            cell.textField?.stringValue = "\(L10n.manageSecureItems) (&p)"
            cell.textField?.font        = .systemFont(ofSize: Layout.fontSize)
            return cell

        case .pageControl:
            let view: PageControlView
            if let existing = tableView.makeView(withIdentifier: CellID.page, owner: nil) as? PageControlView {
                view = existing
            } else {
                view = PageControlView()
                view.onPrev = { [weak self] in self?.goToPrevPage() }
                view.onNext = { [weak self] in self?.goToNextPage() }
            }
            let total = max(1, (allFilteredItems.count + Layout.pageSize - 1) / Layout.pageSize)
            view.configure(current: currentPage + 1, total: total)
            return view
        }
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        switch rows[row] {
        case .separator:   return Layout.sepRowH
        case .pageControl: return Layout.pageControlH
        default:           return Layout.rowH
        }
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        rows[row].isSelectable
    }
}

// MARK: - NSSearchFieldDelegate

extension CPYSecurePickerPanel: NSSearchFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        guard (obj.object as? NSSearchField) === searchField else { return }
        currentPage = 0  // クエリ変更時は先頭ページに戻す
        rebuildRows()
    }
}
