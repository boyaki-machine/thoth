//
//  SecureItemEditViewController+Keyboard.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Copyright © 2015-2018 Clipy Project.
//

import AppKit

// MARK: - Tab Navigation / Keyboard Handling
//
// セキュアアイテム編集シートのキーボード操作（Tab 巡回・j/k 行移動・Ctrl+j/k 並べ替え）。
// UI 構築（本体ファイル）・テーブル表示（+TableView）と関心を分離するため独立ファイルにしている。
//
// 列の特定はインデックスの直書きではなく ColID（列識別子）から解決する。
// 過去に dragHandle 列の追加で列番号がずれ、Tab ナビゲーションが壊れた経緯があるため、
// 列構成の変更に自動で追従できるようにしている。
extension SecureItemEditViewController {

    // MARK: - Column Index Resolution

    private var labelColumnIndex: Int { return fieldsTable.column(withIdentifier: ColID.label) }
    private var valueColumnIndex: Int { return fieldsTable.column(withIdentifier: ColID.value) }
    private var passColumnIndex: Int { return fieldsTable.column(withIdentifier: ColID.pass) }

    // MARK: - Focus Helpers

    /// 指定行の Label 列テキストフィールドにフォーカスを移す。
    /// `makeIfNecessary: true` でセルビューを強制生成してからフォーカスする
    /// （`editColumn` はビューが未生成の行では動作しない場合がある）。
    private func activateLabelField(row: Int) {
        guard row < fields.count else { return }
        fieldsTable.scrollRowToVisible(row)
        if let cell = fieldsTable.view(atColumn: labelColumnIndex, row: row, makeIfNecessary: true) as? NSTableCellView,
           let textField = cell.textField {
            view.window?.makeFirstResponder(textField)
        }
    }

    /// 指定行の Value 列テキストフィールド（プレーンまたはセキュア）にフォーカスを移す。
    private func activateValueField(row: Int) {
        guard row < fields.count else { return }
        fieldsTable.scrollRowToVisible(row)
        if let cell = fieldsTable.view(atColumn: valueColumnIndex, row: row, makeIfNecessary: true) as? FieldValueCell,
           let textField = cell.textField {
            view.window?.makeFirstResponder(textField)
        }
    }

    /// 指定行のパスワードチェックボックスにフォーカスを移す。
    private func activateCheckbox(row: Int) {
        guard row < fields.count else { return }
        fieldsTable.scrollRowToVisible(row)
        if let cell = fieldsTable.view(atColumn: passColumnIndex, row: row, makeIfNecessary: true),
           let button = cell.subviews.first(where: { $0 is TabCapturingButton }) as? TabCapturingButton {
            view.window?.makeFirstResponder(button)
        }
    }

    /// チェックボックスから Tab を押した際のフォーカス先を決定する。
    /// 次の行があれば Label[row+1]、なければ +ボタン へ移動する。
    private func tabFromCheckbox(row: Int) {
        if row < fields.count - 1 { activateLabelField(row: row + 1) } else { view.window?.makeFirstResponder(addFieldBtnRef) }
    }

    // MARK: - Local Event Monitor (Tab キー全体を一括処理)

    // swiftlint:disable:next cyclomatic_complexity
    func handleTabKey(shift: Bool) -> Bool {
        guard let window = view.window else { return false }
        let currentResponder = window.firstResponder

        // ── titleField ────────────────────────────────────────────────────
        if titleField.currentEditor() != nil || currentResponder === titleField {
            if shift { window.makeFirstResponder(saveBtnRef) } else if fields.isEmpty { window.makeFirstResponder(addFieldBtnRef) } else { activateLabelField(row: 0) }
            return true
        }

        // ── テーブル内の各行 ──────────────────────────────────────────────
        for row in 0..<fields.count {
            // Label 列
            if let cell = fieldsTable.view(atColumn: labelColumnIndex, row: row, makeIfNecessary: false) as? NSTableCellView,
               let labelTF = cell.textField,
               labelTF.currentEditor() != nil || currentResponder === labelTF {
                if shift {
                    if row > 0 { activateCheckbox(row: row - 1) } else { window.makeFirstResponder(titleField) }
                } else { activateValueField(row: row) }
                return true
            }
            // Value 列: プレーン／セキュアの両フィールドを確認
            if let cell = fieldsTable.view(atColumn: valueColumnIndex, row: row, makeIfNecessary: false) as? FieldValueCell,
               cell.plainField.currentEditor() != nil || currentResponder === cell.plainField
                || cell.secureField.currentEditor() != nil || currentResponder === cell.secureField {
                if shift {
                    activateLabelField(row: row)
                } else {
                    if fields[row].isTOTP {
                        // TOTP フィールドは値の編集・チェックボックスが無いため次の行へ
                        if row < fields.count - 1 { activateLabelField(row: row + 1) } else { view.window?.makeFirstResponder(addFieldBtnRef) }
                    } else {
                        activateCheckbox(row: row)
                    }
                }
                return true
            }
            // Checkbox 列
            if let cell = fieldsTable.view(atColumn: passColumnIndex, row: row, makeIfNecessary: false),
               let button = cell.subviews.first(where: { $0 is TabCapturingButton }) as? TabCapturingButton,
               currentResponder === button {
                if shift { activateValueField(row: row) } else { tabFromCheckbox(row: row) }
                return true
            }
        }

        // ── ボトムバーのボタン ────────────────────────────────────────────
        switch currentResponder {
        case addFieldBtnRef:
            if shift {
                if fields.isEmpty {
                    window.makeFirstResponder(titleField)
                } else {
                    // 逆方向: 最後の「チェックボックスを持つ」（= TOTP でない）行へ戻る
                    var targetRow = fields.count - 1
                    while targetRow >= 0 && fields[targetRow].isTOTP {
                        targetRow -= 1
                    }
                    if targetRow >= 0 {
                        activateCheckbox(row: targetRow)
                    } else {
                        window.makeFirstResponder(titleField)
                    }
                }
            } else { window.makeFirstResponder(removeFieldBtnRef) }
            return true
        case removeFieldBtnRef:
            if shift { window.makeFirstResponder(addFieldBtnRef) } else { window.makeFirstResponder(passwordGeneratorBtnRef) }
            return true
        case passwordGeneratorBtnRef:
            if shift { window.makeFirstResponder(removeFieldBtnRef) } else { window.makeFirstResponder(cancelBtnRef) }
            return true
        case cancelBtnRef:
            if shift { window.makeFirstResponder(passwordGeneratorBtnRef) } else { window.makeFirstResponder(saveBtnRef) }
            return true
        case saveBtnRef:
            if shift { window.makeFirstResponder(cancelBtnRef) } else { window.makeFirstResponder(titleField) }
            return true
        default:
            return false
        }
    }

    // MARK: - Row Navigation (j/k) & Reordering (Ctrl+j/k)

    /// 選択行を上下に移動する（vim の j/k 相当）
    func navigateFieldRow(offset: Int) {
        let current = fieldsTable.selectedRow
        let next = current < 0 ? (offset > 0 ? 0 : fields.count - 1) : current + offset
        guard next >= 0, next < fields.count else { return }
        fieldsTable.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        fieldsTable.scrollRowToVisible(next)
    }

    /// 選択行のフィールドを上下に並べ替える（Ctrl+j/k 相当。Save で保存に反映される）
    func moveFieldRow(by delta: Int) {
        let row = fieldsTable.selectedRow
        guard row >= 0 else { return }
        let newRow = row + delta
        guard newRow >= 0, newRow < fields.count else { NSSound.beep(); return }
        fields.swapAt(row, newRow)
        fieldsTable.reloadData(forRowIndexes: IndexSet([row, newRow]),
                               columnIndexes: IndexSet(0..<fieldsTable.numberOfColumns))
        fieldsTable.selectRowIndexes(IndexSet(integer: newRow), byExtendingSelection: false)
    }
}
