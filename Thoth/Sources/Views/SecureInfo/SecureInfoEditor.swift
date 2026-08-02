//
//  SecureInfoEditor.swift
//
//  Thoth
//  GitHub: https://github.com/boyaki-machine/Thoth
//

import Foundation

/// セキュア情報確認ウィンドウの UI 非依存な状態。
///
/// 一覧の絞り込みと選択の追従をここに集約し、AppKit 抜きでユニットテストできるようにする。
/// ビュー側（左ペイン・右ペイン）はこのオブジェクトを共有し、表示の組み立てだけを担当する。
final class SecureInfoEditor {

    /// 読み込み済みの全アイテム（displayOrder 順）
    private(set) var items: [SecureMenuItem] = []
    /// 検索クエリ
    private(set) var query: String = ""
    /// 選択中アイテムの安定 ID。
    /// 絞り込みで一時的に隠れても保持するため、クエリを消すと選択が戻る
    private(set) var selectedItemID: String?

    // MARK: - Items / Query

    func setItems(_ items: [SecureMenuItem]) {
        self.items = items
    }

    func setQuery(_ query: String) {
        self.query = query
    }

    /// 現在のクエリで絞り込んだ表示対象
    var visibleItems: [SecureMenuItem] {
        return Self.filter(items, query: query)
    }

    // MARK: - Selection

    /// 選択中アイテム。絞り込みで隠れている場合は nil を返す
    /// （右ペインには「選択なし」を表示する）
    var selectedItem: SecureMenuItem? {
        guard let selectedItemID = selectedItemID else { return nil }
        return visibleItems.first { $0.itemID == selectedItemID }
    }

    /// 表示対象のなかでの選択行。隠れている場合は nil
    var selectedRow: Int? {
        guard let selectedItemID = selectedItemID else { return nil }
        return visibleItems.firstIndex { $0.itemID == selectedItemID }
    }

    func selectItem(itemID: String?) {
        selectedItemID = itemID
    }

    /// 表示対象の行番号で選択する。範囲外の指定は無視する
    func selectRow(_ row: Int) {
        let visible = visibleItems
        guard row >= 0, row < visible.count else { return }
        selectedItemID = visible[row].itemID
    }

    /// 選択が無い、または絞り込みで隠れている場合に先頭を選び直す。
    /// - Returns: 選択を変更した場合 true
    @discardableResult
    func selectFirstVisibleIfNeeded() -> Bool {
        guard selectedItem == nil, let first = visibleItems.first else { return false }
        selectedItemID = first.itemID
        return true
    }

    // MARK: - Editing

    /// 編集中の作業コピー。選択が変わるたびに差し替える。
    /// 右ペインはこちらを表示する（一覧は保存済みの `items` を表示する）
    private(set) var draft: SecureMenuItem?
    /// 作業コピーが未保存の変更を含むか
    private(set) var isDirty = false
    /// Keychain を読み出せない状態では編集を受け付けない。
    /// 編集させても保存が拒否されるだけなので、入力の時点で止める
    var isReadOnly = false

    /// 保存の要否と可否
    enum CommitOutcome: Equatable {
        /// 変更が無いので保存不要
        case notNeeded
        /// タイトルが空のため保存できない（編集内容は破棄せず保持する）
        case titleRequired
        /// 保存すべき内容
        case ready(SecureMenuItem)
    }

    /// 指定アイテムの編集を開始する（選択変更時に呼ぶ）。
    /// **呼び出し側は直前に未保存の変更をコミットしておくこと**
    func beginEditing(itemID: String?) {
        isDirty = false
        guard let itemID = itemID else {
            draft = nil
            return
        }
        draft = items.first { $0.itemID == itemID }
    }

    /// - Returns: 実際に値が変わった場合 true
    @discardableResult
    func updateTitle(_ title: String) -> Bool {
        guard !isReadOnly, var current = draft, current.title != title else { return false }
        current.title = title
        draft = current
        isDirty = true
        return true
    }

    /// フィールドの一部を差し替える。nil を渡した項目は現在値を維持する。
    /// - Returns: 実際に値が変わった場合 true
    @discardableResult
    func updateField(fieldID: String, label: String? = nil, value: String? = nil,
                     isPassword: Bool? = nil) -> Bool {
        guard !isReadOnly, var current = draft,
              let index = current.fields.firstIndex(where: { $0.fieldID == fieldID }) else { return false }
        let field = current.fields[index]
        let changed = (label != nil && label != field.label)
            || (value != nil && value != field.value)
            || (isPassword != nil && isPassword != field.isPassword)
        guard changed else { return false }
        current.fields[index] = field.updating(label: label, value: value, isPassword: isPassword)
        draft = current
        isDirty = true
        return true
    }

    /// 保存すべき内容を判定する。
    ///
    /// ラベルも値も空のフィールドは取り除く（既存の編集シートと同じ規則）。
    /// タイトルが空の場合は保存せず、編集内容も破棄しない
    func commitOutcome() -> CommitOutcome {
        guard isDirty, let draft = draft else { return .notNeeded }
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return .titleRequired }
        var payload = draft
        payload.title = title
        payload.fields = draft.fields.filter {
            !$0.label.trimmingCharacters(in: .whitespaces).isEmpty
                || !$0.value.trimmingCharacters(in: .whitespaces).isEmpty
        }
        return .ready(payload)
    }

    /// 保存の成功を記録する。
    /// - Parameter savedItem: 保存後に読み直したアイテム（値変更履歴が追記された状態）
    func markCommitted(_ savedItem: SecureMenuItem) {
        isDirty = false
        draft = savedItem
        if let index = items.firstIndex(where: { $0.itemID == savedItem.itemID }) {
            items[index] = savedItem
        }
    }

    // MARK: - Filtering

    /// クエリでアイテムを絞り込む（純粋関数）。
    ///
    /// 空白区切りの複数語は AND 条件、大文字小文字は無視する。
    /// 選択パネルの絞り込みと違い、語がタイトルとラベルにまたがって一致してもよい
    /// （"github password" のような探し方ができる）。
    static func filter(_ items: [SecureMenuItem], query: String) -> [SecureMenuItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return items }
        let terms = trimmed.lowercased().components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard !terms.isEmpty else { return items }
        return items.filter { item in
            let haystack = searchableText(of: item)
            return terms.allSatisfy { haystack.contains($0) }
        }
    }

    /// 1 アイテム分の検索対象テキスト（小文字化済み）。
    ///
    /// 対象はタイトル・全フィールドのラベル・メモ本文。
    /// **パスワード等の値と TOTP secret は対象外**にする。値の断片で探す用途が無いうえ、
    /// 秘密情報を検索窓へ打たせる動機を作らないため。
    /// メモでもマスク指定（🔒）があるものは本文を対象から外す。
    static func searchableText(of item: SecureMenuItem) -> String {
        var parts = [item.title]
        for field in item.fields {
            parts.append(field.label)
            if field.kind == .note && !field.isPassword {
                parts.append(field.value)
            }
        }
        return parts.joined(separator: "\n").lowercased()
    }
}
