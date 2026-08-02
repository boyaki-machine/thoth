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

    // MARK: - Focus Order (純粋ロジック)

    /// Tab キーで巡回するフォーカス対象。
    /// 行ごとにどのコントロールが対象になるかは種別によって変わる（`focusOrder(for:)` を参照）
    enum FocusStop: Equatable {
        case title
        case label(row: Int)
        case value(row: Int)
        case checkbox(row: Int)
        case addField
        case removeField
        case passwordGenerator
        case cancel
        case save
    }

    /// Tab の巡回順を組み立てる。UI に依存しない純粋関数のためユニットテスト可能。
    ///
    /// 各行のフォーカス対象は種別の capability で決まる:
    /// - **Label** は常に対象
    /// - **Value** は単一行で編集できる種別（plain / url）のみ。TOTP は secret を表示せず、
    ///   メモは改行が失われるため、いずれも単一行セルでは編集させない
    /// - **チェックボックス（🔒）** はマスク切り替えを許す種別（plain / url / note）のみ。
    ///   TOTP だけが対象外
    ///
    /// 末尾は Save のあと title へ戻る循環。
    /// 「TOTP追加...」ボタンは従来から巡回に含まれていないため、この順序でも対象外にしている。
    static func focusOrder(for fields: [SecureMenuItem.Field]) -> [FocusStop] {
        var order: [FocusStop] = [.title]
        for (row, field) in fields.enumerated() {
            order.append(.label(row: row))
            if field.kind.allowsSingleLineEditing { order.append(.value(row: row)) }
            if field.kind.allowsPasswordToggle { order.append(.checkbox(row: row)) }
        }
        order.append(contentsOf: [.addField, .removeField, .passwordGenerator, .cancel, .save])
        return order
    }

    // MARK: - Local Event Monitor (Tab キー全体を一括処理)

    func handleTabKey(shift: Bool) -> Bool {
        guard let window = view.window, let current = currentFocusStop() else { return false }
        let order = Self.focusOrder(for: fields)
        guard let index = order.firstIndex(of: current) else {
            // 巡回対象に含まれないコントロールにフォーカスが残っている場合
            // （種別変更で Value が編集不可になった直後など）は同じ行の Label へ引き戻す
            if case .value(let row) = current {
                activateLabelField(row: row)
                return true
            }
            return false
        }
        let offset = shift ? order.count - 1 : 1
        activate(order[(index + offset) % order.count], in: window)
        return true
    }

    /// 現在フォーカスされている巡回対象を特定する。
    /// テキストフィールドは編集中に first responder がフィールドエディタ（NSTextView）へ
    /// 移るため、`currentEditor()` による判定を併用する
    private func currentFocusStop() -> FocusStop? {
        guard let window = view.window else { return nil }
        let responder = window.firstResponder

        if titleField.currentEditor() != nil || responder === titleField { return .title }

        for row in 0..<fields.count {
            if let cell = fieldsTable.view(atColumn: labelColumnIndex, row: row, makeIfNecessary: false) as? NSTableCellView,
               let labelField = cell.textField,
               labelField.currentEditor() != nil || responder === labelField {
                return .label(row: row)
            }
            if let cell = fieldsTable.view(atColumn: valueColumnIndex, row: row, makeIfNecessary: false) as? FieldValueCell,
               cell.plainField.currentEditor() != nil || responder === cell.plainField
                || cell.secureField.currentEditor() != nil || responder === cell.secureField {
                return .value(row: row)
            }
            if let cell = fieldsTable.view(atColumn: passColumnIndex, row: row, makeIfNecessary: false),
               let button = cell.subviews.first(where: { $0 is TabCapturingButton }) as? TabCapturingButton,
               responder === button {
                return .checkbox(row: row)
            }
        }

        switch responder {
        case addFieldBtnRef:          return .addField
        case removeFieldBtnRef:       return .removeField
        case passwordGeneratorBtnRef: return .passwordGenerator
        case cancelBtnRef:            return .cancel
        case saveBtnRef:              return .save
        default:                      return nil
        }
    }

    private func activate(_ stop: FocusStop, in window: NSWindow) {
        switch stop {
        case .title:             window.makeFirstResponder(titleField)
        case .label(let row):    activateLabelField(row: row)
        case .value(let row):    activateValueField(row: row)
        case .checkbox(let row): activateCheckbox(row: row)
        case .addField:          window.makeFirstResponder(addFieldBtnRef)
        case .removeField:       window.makeFirstResponder(removeFieldBtnRef)
        case .passwordGenerator: window.makeFirstResponder(passwordGeneratorBtnRef)
        case .cancel:            window.makeFirstResponder(cancelBtnRef)
        case .save:              window.makeFirstResponder(saveBtnRef)
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
