//
//  CPYSnippetsEditorWindowController.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Econa77 on 2016/05/18.
//
//  Copyright © 2015-2018 Clipy Project.
//

import Cocoa
import UniformTypeIdentifiers
import KeyHolder
import Magnet
import AEXML

final class CPYSnippetsEditorWindowController: NSWindowController {

    // MARK: - Properties
    static let sharedController = CPYSnippetsEditorWindowController(windowNibName: "CPYSnippetsEditorWindowController")
    @IBOutlet private weak var splitView: CPYSplitView!
    @IBOutlet private weak var folderSettingView: NSView!
    @IBOutlet private weak var folderTitleTextField: NSTextField!
    @IBOutlet private weak var folderShortcutRecordView: RecordView! {
        didSet {
            folderShortcutRecordView.delegate = self
        }
    }
    @IBOutlet private var textView: CPYPlaceHolderTextView! {
        didSet {
            textView.font = NSFont.systemFont(ofSize: 14)
            textView.isAutomaticQuoteSubstitutionEnabled = false
            textView.enabledTextCheckingTypes = 0
            textView.isRichText = false
            textView.placeHolderText = L10n.pleaseFillInTheContentsOfTheSnippet
        }
    }
    @IBOutlet private weak var outlineView: NSOutlineView! {
        didSet {
            // Enable Drag and Drop
            outlineView.registerForDraggedTypes([NSPasteboard.PasteboardType(rawValue: Constants.Common.draggedDataType)])
        }
    }

    private var folders = [SnippetFolderNode]()
    private var snippetStore: SnippetStore { AppEnvironment.current.snippetStore }
    private var selectedSnippet: SnippetNode? {
        return outlineView.item(atRow: outlineView.selectedRow) as? SnippetNode
    }
    private var selectedFolder: SnippetFolderNode? {
        guard let item = outlineView.item(atRow: outlineView.selectedRow) else { return nil }
        if let folder = outlineView.parent(forItem: item) as? SnippetFolderNode {
            return folder
        } else if let folder = item as? SnippetFolderNode {
            return folder
        }
        return nil
    }

    // MARK: - Window Life Cycle
    override func windowDidLoad() {
        super.windowDidLoad()
        self.window?.collectionBehavior = NSWindow.CollectionBehavior.canJoinAllSpaces
        self.window?.backgroundColor = NSColor(white: 0.99, alpha: 1)
        self.window?.titlebarAppearsTransparent = true
        // 画面では編集用のノードを持ち、変更のたびに SnippetStore へ書き戻す
        folders = snippetStore.folders().map(SnippetFolderNode.init)
        outlineView.reloadData()
        // Select first folder
        if let folder = folders.first {
            outlineView.selectRowIndexes(IndexSet(integer: outlineView.row(forItem: folder)), byExtendingSelection: false)
            changeItemFocus()
        }
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(self)
    }

    // MARK: - Close on Esc
    /// 他のウィンドウと同様に Esc で閉じる。
    /// テキスト編集中の Esc はフィールドエディタが編集キャンセルを先に処理するため、
    /// 未編集状態での Esc がレスポンダチェーン経由でここに届いて閉じる
    override func cancelOperation(_ sender: Any?) {
        close()
    }
}

// MARK: - IBActions
extension CPYSnippetsEditorWindowController {
    @IBAction private func addSnippetButtonTapped(_ sender: AnyObject) {
        guard let folder = selectedFolder else {
            NSSound.beep()
            return
        }
        let snippet = SnippetNode(SnippetRecord(index: folder.snippets.count, title: "untitled snippet"))
        folder.snippets.append(snippet)
        snippetStore.saveSnippet(snippet.record, folderID: folder.id)
        outlineView.reloadData()
        outlineView.expandItem(folder)
        outlineView.selectRowIndexes(IndexSet(integer: outlineView.row(forItem: snippet)), byExtendingSelection: false)
        changeItemFocus()
    }

    @IBAction private func addFolderButtonTapped(_ sender: AnyObject) {
        let folder = SnippetFolderNode(SnippetFolderRecord(index: snippetStore.nextFolderIndex(), title: "untitled folder"))
        folders.append(folder)
        snippetStore.saveFolder(folder.record)
        outlineView.reloadData()
        outlineView.selectRowIndexes(IndexSet(integer: outlineView.row(forItem: folder)), byExtendingSelection: false)
        changeItemFocus()
    }

    @IBAction private func deleteButtonTapped(_ sender: AnyObject) {
        guard let item = outlineView.item(atRow: outlineView.selectedRow) else {
            NSSound.beep()
            return
        }

        let alert = NSAlert()
        alert.messageText = L10n.deleteItem
        alert.informativeText = L10n.areYouSureWantToDeleteThisItem
        alert.addButton(withTitle: L10n.deleteItem)
        alert.addButton(withTitle: L10n.cancel)
        NSApp.activate(ignoringOtherApps: true)
        let result = alert.runModal()
        if result != NSApplication.ModalResponse.alertFirstButtonReturn { return }

        if let folder = item as? SnippetFolderNode {
            folders.removeAll { $0 === folder }
            snippetStore.deleteFolder(id: folder.id)
            AppEnvironment.current.hotKeyService.unregisterSnippetHotKey(with: folder.id)
        } else if let snippet = item as? SnippetNode, let folder = outlineView.parent(forItem: item) as? SnippetFolderNode,
                  let index = folder.snippets.firstIndex(where: { $0 === snippet }) {
            folder.snippets.remove(at: index)
            snippetStore.deleteSnippet(id: snippet.id)
        }
        outlineView.reloadData()
        changeItemFocus()
    }

    @IBAction private func changeStatusButtonTapped(_ sender: AnyObject) {
        guard let item = outlineView.item(atRow: outlineView.selectedRow) else {
            NSSound.beep()
            return
        }
        if let folder = item as? SnippetFolderNode {
            folder.enable = !folder.enable
            snippetStore.saveFolder(folder.record)
        } else if let snippet = item as? SnippetNode, let folder = outlineView.parent(forItem: item) as? SnippetFolderNode {
            snippet.enable = !snippet.enable
            snippetStore.saveSnippet(snippet.record, folderID: folder.id)
        }
        outlineView.reloadData()
        changeItemFocus()
    }

    @IBAction private func importSnippetButtonTapped(_ sender: AnyObject) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory())
        panel.allowedContentTypes = [.xml]
        let returnCode = panel.runModal()

        if returnCode != NSApplication.ModalResponse.OK { return }

        let fileURLs = panel.urls
        guard let url = fileURLs.first else { return }
        guard let data = try? Data(contentsOf: url) else { return }

        do {
            var folderIndex = snippetStore.nextFolderIndex()
            // Create Document
            var options = AEXMLOptions()
            options.parserSettings.shouldTrimWhitespace = false
            let xmlDocument = try AEXMLDocument(xml: data, options: options)
            var imported = [SnippetFolderRecord]()
            xmlDocument[Constants.Xml.rootElement]
                .children
                .forEach { folderElement in
                    var folder = SnippetFolderRecord(index: folderIndex,
                                                     title: folderElement[Constants.Xml.titleElement].value ?? "untitled folder")
                    // Snippet
                    var snippetIndex = 0
                    folderElement[Constants.Xml.snippetsElement][Constants.Xml.snippetElement]
                        .all?
                        .forEach { snippetElement in
                            folder.snippets.append(SnippetRecord(index: snippetIndex,
                                                                 title: snippetElement[Constants.Xml.titleElement].value ?? "untitled snippet",
                                                                 content: snippetElement[Constants.Xml.contentElement].value ?? ""))
                            snippetIndex += 1
                        }
                    folderIndex += 1
                    imported.append(folder)
                }
            snippetStore.importFolders(imported)
            folders.append(contentsOf: imported.map(SnippetFolderNode.init))
            outlineView.reloadData()
        } catch {
            NSSound.beep()
        }
    }

    @IBAction private func exportSnippetButtonTapped(_ sender: AnyObject) {
        let xmlDocument = AEXMLDocument()
        let rootElement = xmlDocument.addChild(name: Constants.Xml.rootElement)

        snippetStore.folders().forEach { folder in
            let folderElement = rootElement.addChild(name: Constants.Xml.folderElement)

            folderElement.addChild(name: Constants.Xml.titleElement, value: folder.title)

            let snippetsElement = folderElement.addChild(name: Constants.Xml.snippetsElement)
            folder.snippets
                .forEach { snippet in
                    let snippetElement = snippetsElement.addChild(name: Constants.Xml.snippetElement)
                    snippetElement.addChild(name: Constants.Xml.titleElement, value: snippet.title)
                    snippetElement.addChild(name: Constants.Xml.contentElement, value: snippet.content)
                }
        }

        let panel = NSSavePanel()
        panel.accessoryView = nil
        panel.canSelectHiddenExtension = true
        panel.allowedContentTypes = [.xml]
        panel.allowsOtherFileTypes = false
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory())
        panel.nameFieldStringValue = "snippets"
        let returnCode = panel.runModal()

        if returnCode != NSApplication.ModalResponse.OK { return }

        guard let data = xmlDocument.xml.data(using: String.Encoding.utf8) else { return }
        guard let url = panel.url else { return }

        do {
            try data.write(to: url, options: .atomic)
        } catch {
            NSSound.beep()
        }
    }
}

// MARK: - Item Selected
private extension CPYSnippetsEditorWindowController {
    func changeItemFocus() {
        // Reset TextView Undo/Redo history
        textView.undoManager?.removeAllActions()
        guard let item = outlineView.item(atRow: outlineView.selectedRow) else {
            folderSettingView.isHidden = true
            textView.isHidden = true
            folderShortcutRecordView.keyCombo = nil
            folderTitleTextField.stringValue = ""
            return
        }
        if let folder = item as? SnippetFolderNode {
            textView.string = ""
            folderTitleTextField.stringValue = folder.title
            folderShortcutRecordView.keyCombo = AppEnvironment.current.hotKeyService.snippetKeyCombo(forIdentifier: folder.id)
            folderSettingView.isHidden = false
            textView.isHidden = true
        } else if let snippet = item as? SnippetNode {
            textView.string = snippet.content
            folderTitleTextField.stringValue = ""
            folderShortcutRecordView.keyCombo = nil
            folderSettingView.isHidden = true
            textView.isHidden = false
        }
    }
}

// MARK: - Save Order
private extension CPYSnippetsEditorWindowController {
    /// 画面上のフォルダの並びを番号に反映して保存する
    func saveFolderOrder() {
        folders.enumerated().forEach { $0.element.index = $0.offset }
        snippetStore.reorderFolders(folders.map(\.id))
    }

    /// フォルダ内のスニペットの並びを番号に反映して保存する
    func saveSnippetOrder(of folder: SnippetFolderNode) {
        folder.snippets.enumerated().forEach { $0.element.index = $0.offset }
        snippetStore.reorderSnippets(folder.snippets.map(\.id), inFolder: folder.id)
    }
}

// MARK: - NSSplitView Delegate
extension CPYSnippetsEditorWindowController: NSSplitViewDelegate {
    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        return proposedMinimumPosition + 150
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        return proposedMaximumPosition / 2
    }
}

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

// MARK: - NSTextView Delegate
extension CPYSnippetsEditorWindowController: NSTextViewDelegate {
    func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
        guard let replacementString = replacementString else { return false }
        let text = textView.string
        guard let snippet = selectedSnippet, let folder = selectedFolder else { return false }
        let string = (text as NSString).replacingCharacters(in: affectedCharRange, with: replacementString)
        snippet.content = string
        snippetStore.saveSnippet(snippet.record, folderID: folder.id)
        return true
    }
}

// MARK: - RecordView Delegate
extension CPYSnippetsEditorWindowController: RecordViewDelegate {
    func recordViewShouldBeginRecording(_ recordView: RecordView) -> Bool {
        guard selectedFolder != nil else { return false }
        return true
    }

    func recordView(_ recordView: RecordView, canRecordKeyCombo keyCombo: KeyCombo) -> Bool {
        guard selectedFolder != nil else { return false }
        return true
    }

    func recordView(_ recordView: RecordView, didChangeKeyCombo keyCombo: KeyCombo?) {
        guard let selectedFolder = selectedFolder else { return }
        guard let keyCombo = keyCombo else {
            AppEnvironment.current.hotKeyService.unregisterSnippetHotKey(with: selectedFolder.id)
            return
        }
        AppEnvironment.current.hotKeyService.registerSnippetHotKey(with: selectedFolder.id, keyCombo: keyCombo)
    }

    func recordViewDidEndRecording(_ recordView: RecordView) {}
}
