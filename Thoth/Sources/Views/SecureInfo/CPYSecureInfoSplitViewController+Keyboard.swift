//
//  CPYSecureInfoSplitViewController+Keyboard.swift
//
//  Thoth
//  GitHub: https://github.com/boyaki-machine/Thoth
//

import Cocoa

// MARK: - Keyboard Handling
//
// セキュア情報確認ウィンドウのキー操作。
// 「キー入力 → 操作」の写像を純粋関数 keyAction(...) に切り出し、
// ハンドラはその結果を実行するだけにしている（割り当ての仕様をテストで固定できる）。
//
// ローカルイベントモニターは Split VC が 1 つだけ持つ。左右のペインそれぞれに
// 登録すると、アプリ全体を監視するモニターが増えて他ウィンドウと干渉するため。
extension CPYSecureInfoSplitViewController {

    func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, event.window === self.view.window else { return event }
            return self.handleKeyDown(event) ? nil : event
        }
    }

    /// - Returns: イベントを消費した場合 true
    private func handleKeyDown(_ event: NSEvent) -> Bool {
        // テキスト入力中（検索欄・値の編集など）は文字入力を優先する。
        // NSTextField はフォーカスを受けた時点でフィールドエディタ（NSTextView）が
        // first responder になるため、これで「入力欄にいるか」を判定できる
        let isEditingText = view.window?.firstResponder is NSTextView
        guard let action = Self.keyAction(keyCode: event.keyCode,
                                          character: event.charactersIgnoringModifiers?.lowercased(),
                                          modifiers: event.modifierFlags,
                                          isEditingText: isEditingText) else { return false }
        perform(action)
        return true
    }

    /// キー入力から実行するアクションを決める（純粋関数のためユニットテスト可能）。
    ///
    /// - ⌘ 付きのショートカットはキーボード配列に依存しないよう文字で判定する
    /// - vim 風のキー（h/j/k/l）は本アプリの他の画面と同じくキーコードで判定する
    /// - **Esc は 2 段階**: 入力中なら編集の確定、そうでなければウィンドウを閉じる
    /// - 入力中は h/j/k/l と `/` を効かせない（文字として打てなくなるため）
    static func keyAction(keyCode: UInt16, character: String?,
                          modifiers: NSEvent.ModifierFlags, isEditingText: Bool) -> SecureInfoKeyAction? {
        let flags = modifiers.intersection(.deviceIndependentFlagsMask)

        if flags == .command {
            switch character {
            case "f": return .focusSearch
            case "s": return .save
            case "n": return .addItem
            case "w": return .close
            default:
                // ⌘Delete はテキスト入力中だと「行頭まで削除」の標準操作。
                // 横取りするとアイテムごと消えてしまうため、入力中は割り当てない
                return (keyCode == KeyCode.delete && !isEditingText) ? .deleteItem : nil
            }
        }

        if flags == .control {
            switch keyCode {
            case KeyCode.letterJ: return .reorderDown
            case KeyCode.letterK: return .reorderUp
            default: return nil
            }
        }

        guard flags.isEmpty else { return nil }

        if keyCode == KeyCode.escape {
            return isEditingText ? .endEditing : .close
        }
        guard !isEditingText else { return nil }

        switch keyCode {
        case KeyCode.letterJ:                              return .moveSelectionDown
        case KeyCode.letterK:                              return .moveSelectionUp
        case KeyCode.letterL, KeyCode.rightArrow, KeyCode.returnKey: return .focusDetail
        case KeyCode.letterH, KeyCode.leftArrow:           return .focusList
        case KeyCode.slash:                          return .focusSearch
        default:                                     return nil
        }
    }

    private func perform(_ action: SecureInfoKeyAction) {
        switch action {
        case .focusSearch:
            listViewController.focusSearchField()
        case .focusList:
            listViewController.focusList()
        case .focusDetail:
            detailViewController.focusTitleField()
        case .moveSelectionDown:
            listViewController.moveSelection(by: 1)
        case .moveSelectionUp:
            listViewController.moveSelection(by: -1)
        case .reorderDown:
            reorder(by: 1)
        case .reorderUp:
            reorder(by: -1)
        case .addItem:
            addItem()
        case .deleteItem:
            confirmDeleteSelectedItem()
        case .save:
            // 編集中のテキストを確定させてから保存する
            view.window?.makeFirstResponder(nil)
            hasShownCommitFailure = false
            commitIfNeeded()
        case .endEditing:
            view.window?.makeFirstResponder(nil)
            commitIfNeeded()
        case .close:
            view.window?.performClose(nil)
        }
    }

    /// 右ペインに編集中の行があればフィールドを、無ければ一覧のアイテムを動かす
    private func reorder(by offset: Int) {
        if detailViewController.focusedRow != nil {
            moveFocusedField(by: offset)
        } else {
            moveSelectedItem(by: offset)
        }
    }
}
