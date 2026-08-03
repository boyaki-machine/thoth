//
//  CPYSecureInfoSplitViewController+Undo.swift
//
//  Thoth
//  GitHub: https://github.com/boyaki-machine/Thoth
//

import Cocoa

// MARK: - Undo / Redo
//
// 取り消し（⌘Z）／やり直し（⌘⇧Z）。積む単位は **「Keychain へ 1 回書き込むごと」** で、
// 打鍵単位の取り消しは AppKit 標準のテキスト編集 Undo に任せる（2 層構成）。
//
// | 層 | 担当 | 範囲 | 寿命 |
// |---|---|---|---|
// | 入力中 | フィールドエディタ / NSTextView | 打鍵単位 | フォーカスが外れるまで |
// | 確定後 | SecureInfoUndoStack | 保存 1 回分 | ウィンドウを閉じるまで |
//
// 控えを積むのは Keychain を書き換える経路のみ。編集系（タイトル・ラベル・値・
// マスク指定・フィールドの追加削除並べ替え）はすべて `save(_:)` を通るため、
// そこ 1 箇所で足りる。
extension CPYSecureInfoSplitViewController {

    /// 変更を加える**直前**の状態を控える。
    /// 読み取り専用では保存自体が拒否されるので積まない
    func pushUndoSnapshot(action: SecureInfoUndoAction) {
        guard !isPerformingUndo, !editor.isReadOnly else { return }
        undoStack.push(editor.committedSnapshot(action: action))
    }

    /// 控えてある状態をすべて捨てる。
    ///
    /// **取り消しの世代は削除・編集前の平文を保持している。** 呼ぶ場所は 3 つ:
    /// ウィンドウを閉じるとき / データを読み直すとき /
    /// 他の画面の変更で控えが陳腐化したとき（案内バーを出す経路）
    func clearUndoHistory() {
        undoStack.clear()
    }

    func performUndo() {
        applyHistory(isRedo: false)
    }

    func performRedo() {
        applyHistory(isRedo: true)
    }

    /// 取り消し／やり直しを実行する。
    ///
    /// 書き戻しには `SecureMenuService.save(_:)` ではなく `reorderItems(_:)` を使う。
    /// `save(_:)` は値が変わるたびに変更履歴を 1 件積むため、取り消しのたびに履歴が
    /// 消費され、上限 10 件の本当の旧値が押し出されてしまう。
    /// `reorderItems(_:)` は渡した配列をそのまま書き戻すので履歴を汚さない
    private func applyHistory(isRedo: Bool) {
        guard !editor.isReadOnly else { NSSound.beep(); return }
        // 打ちかけの内容を取り残さないよう先に確定させる。
        // ここで積まれた世代を直後に取り消すのが「入力 → フォーカスを外す → ⌘Z」の流れ
        view.window?.makeFirstResponder(nil)
        guard commitIfNeeded() else { return }

        isPerformingUndo = true
        defer { isPerformingUndo = false }

        let current = editor.committedSnapshot(action: .edit)
        let restored = isRedo ? undoStack.redo(current: current) : undoStack.undo(current: current)
        guard let snapshot = restored else {
            NSSound.beep()
            return
        }
        let service = AppEnvironment.current.secureMenuService
        performLocalChange {
            guard service.reorderItems(snapshot.items) else {
                showCommitFailure(informative: L10n.secureInfoSaveFailed)
                return
            }
            editor.restore(snapshot)
            // reload が選択の同期と右ペインの再描画（onSelectionChange）まで面倒を見る
            listViewController.reload()
            detailViewController.hideExternalChangeBanner()
        }
    }
}
