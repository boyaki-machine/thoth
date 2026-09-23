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

    // 同じクラスの拡張（+OutlineView）から使うため internal
    var folders = [SnippetFolderNode]()
    var snippetStore: SnippetStore { AppEnvironment.current.snippetStore }
    /// 暗号鍵が使えないときは一覧を読めないため、編集もさせない（作ったものが黙って消えるのを防ぐ）
    var isEditable: Bool { AppEnvironment.current.isLibraryUsable }
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
        guard !isEditable else { return }
        NSAlert.showNotice(message: L10n.snippetsUnavailable, informative: L10n.snippetsUnavailableMessage, for: window)
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
        guard isEditable else {
            NSSound.beep()
            return
        }
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
        guard isEditable else {
            NSSound.beep()
            return
        }
        let folder = SnippetFolderNode(SnippetFolderRecord(index: snippetStore.nextFolderIndex(), title: "untitled folder"))
        folders.append(folder)
        snippetStore.saveFolder(folder.record)
        outlineView.reloadData()
        outlineView.selectRowIndexes(IndexSet(integer: outlineView.row(forItem: folder)), byExtendingSelection: false)
        changeItemFocus()
    }

    @IBAction private func deleteButtonTapped(_ sender: AnyObject) {
        guard isEditable else {
            NSSound.beep()
            return
        }
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
        guard isEditable else {
            NSSound.beep()
            return
        }
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
        guard isEditable else {
            NSSound.beep()
            return
        }
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
extension CPYSnippetsEditorWindowController {
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
extension CPYSnippetsEditorWindowController {
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

// MARK: - NSTextView Delegate
extension CPYSnippetsEditorWindowController: NSTextViewDelegate {
    func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
        guard isEditable else { return false }
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
