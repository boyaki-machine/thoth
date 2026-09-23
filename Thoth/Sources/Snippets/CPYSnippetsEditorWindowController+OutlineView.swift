//
//  CPYSnippetsEditorWindowController+OutlineView.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Copyright © 2015-2018 Clipy Project.
//

import Cocoa

// MARK: - NSOutlineView DataSource
extension CPYSnippetsEditorWindowController: NSOutlineViewDataSource {
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil {
            return Int(folders.count)
        } else if let folder = item as? SnippetFolderNode {
            return folder.snippets.count
        }
        return 0
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        if let folder = item as? SnippetFolderNode {
            return !folder.snippets.isEmpty
        }
        return false
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil {
            return folders[index]
        } else if let folder = item as? SnippetFolderNode {
            return folder.snippets[index]
        }
        return ""
    }

    func outlineView(_ outlineView: NSOutlineView, objectValueFor tableColumn: NSTableColumn?, byItem item: Any?) -> Any? {
        if let folder = item as? SnippetFolderNode {
            return folder.title
        } else if let snippet = item as? SnippetNode {
            return snippet.title
        }
        return ""
    }

    // MARK: - Drag and Drop
    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        let pasteboardItem = NSPasteboardItem()
        if let folder = item as? SnippetFolderNode, let index = folders.firstIndex(where: { $0 === folder }) {
            let draggedData = CPYDraggedData(type: .folder, folderIdentifier: folder.id, snippetIdentifier: nil, index: index)
            let data = (try? NSKeyedArchiver.archivedData(withRootObject: draggedData, requiringSecureCoding: false)) ?? Data()
            pasteboardItem.setData(data, forType: NSPasteboard.PasteboardType(rawValue: Constants.Common.draggedDataType))
        } else if let snippet = item as? SnippetNode, let folder = outlineView.parent(forItem: snippet) as? SnippetFolderNode {
            guard let index = folder.snippets.firstIndex(where: { $0 === snippet }) else { return nil }
            let draggedData = CPYDraggedData(type: .snippet, folderIdentifier: folder.id, snippetIdentifier: snippet.id, index: index)
            let data = (try? NSKeyedArchiver.archivedData(withRootObject: draggedData, requiringSecureCoding: false)) ?? Data()
            pasteboardItem.setData(data, forType: NSPasteboard.PasteboardType(rawValue: Constants.Common.draggedDataType))
        } else {
            return nil
        }
        return pasteboardItem
    }

    func outlineView(_ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem item: Any?, proposedChildIndex index: Int) -> NSDragOperation {
        guard isEditable else { return NSDragOperation() }
        let pasteboard = info.draggingPasteboard
        guard let data = pasteboard.data(forType: NSPasteboard.PasteboardType(rawValue: Constants.Common.draggedDataType)) else { return NSDragOperation() }
        guard let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data) else { return NSDragOperation() }
        unarchiver.requiresSecureCoding = false
        guard let draggedData = unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey) as? CPYDraggedData else { return NSDragOperation() }

        switch draggedData.type {
        case .folder where item == nil:
            return .move
        case .snippet where item is SnippetFolderNode:
            return .move
        default:
            return NSDragOperation()
        }
    }

    func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
        let pasteboard = info.draggingPasteboard
        guard let data = pasteboard.data(forType: NSPasteboard.PasteboardType(rawValue: Constants.Common.draggedDataType)) else { return false }
        guard let unarchiver2 = try? NSKeyedUnarchiver(forReadingFrom: data) else { return false }
        unarchiver2.requiresSecureCoding = false
        guard let draggedData = unarchiver2.decodeObject(forKey: NSKeyedArchiveRootObjectKey) as? CPYDraggedData else { return false }

        switch draggedData.type {
        case .folder where index != draggedData.index:
            guard index >= 0 else { return false }
            guard let folder = folders.first(where: { $0.id == draggedData.folderIdentifier }) else { return false }
            folders.insert(folder, at: index)
            let removedIndex = (index < draggedData.index) ? draggedData.index + 1 : draggedData.index
            folders.remove(at: removedIndex)
            outlineView.reloadData()
            outlineView.selectRowIndexes(IndexSet(integer: outlineView.row(forItem: folder)), byExtendingSelection: false)
            saveFolderOrder()
            changeItemFocus()
            return true
        case .snippet:
            guard let fromFolder = folders.first(where: { $0.id == draggedData.folderIdentifier }) else { return false }
            guard let toFolder = item as? SnippetFolderNode else { return false }
            guard let snippet = fromFolder.snippets.first(where: { $0.id == draggedData.snippetIdentifier }) else { return false }

            if fromFolder.id == toFolder.id {
                guard index >= 0 else { return false }
                if index == draggedData.index { return false }
                // Move to same folder
                fromFolder.snippets.insert(snippet, at: index)
                let removedIndex = (index < draggedData.index) ? draggedData.index + 1 : draggedData.index
                fromFolder.snippets.remove(at: removedIndex)
                outlineView.reloadData()
                outlineView.selectRowIndexes(NSIndexSet(index: outlineView.row(forItem: snippet)) as IndexSet, byExtendingSelection: false)
                saveSnippetOrder(of: fromFolder)
                changeItemFocus()
                return true
            } else {
                // Move to other folder
                let index = max(0, index)
                toFolder.snippets.insert(snippet, at: index)
                fromFolder.snippets.remove(at: draggedData.index)
                outlineView.reloadData()
                outlineView.expandItem(toFolder)
                outlineView.selectRowIndexes(NSIndexSet(index: outlineView.row(forItem: snippet)) as IndexSet, byExtendingSelection: false)
                // 移動先を先に保存する（移動先の並びにスニペットを含めることで、元のフォルダから移る）
                saveSnippetOrder(of: toFolder)
                saveSnippetOrder(of: fromFolder)
                changeItemFocus()
                return true
            }
        default: return false
        }
    }
}

// MARK: - NSOutlineView Delegate
extension CPYSnippetsEditorWindowController: NSOutlineViewDelegate {
    func outlineView(_ outlineView: NSOutlineView, willDisplayCell cell: Any, for tableColumn: NSTableColumn?, item: Any) {
        guard let cell = cell as? CPYSnippetsEditorCell else { return }
        if let folder = item as? SnippetFolderNode {
            cell.iconType = .folder
            cell.isItemEnabled = folder.enable
        } else if let snippet = item as? SnippetNode {
            cell.iconType = .none
            cell.isItemEnabled = snippet.enable
        }
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        changeItemFocus()
    }

    func control(_ control: NSControl, textShouldEndEditing fieldEditor: NSText) -> Bool {
        guard isEditable else { return false }
        let text = fieldEditor.string
        guard !text.isEmpty else { return false }
        guard let outlineView = control as? NSOutlineView else { return false }
        guard let item = outlineView.item(atRow: outlineView.selectedRow) else { return false }
        if let folder = item as? SnippetFolderNode {
            folder.title = text
            snippetStore.saveFolder(folder.record)
        } else if let snippet = item as? SnippetNode, let folder = outlineView.parent(forItem: item) as? SnippetFolderNode {
            snippet.title = text
            snippetStore.saveSnippet(snippet.record, folderID: folder.id)
        }
        changeItemFocus()
        return true
    }
}
