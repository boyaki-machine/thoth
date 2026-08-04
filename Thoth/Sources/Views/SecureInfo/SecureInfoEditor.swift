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

    /// 絞り込み結果のキャッシュ。
    /// `visibleItems` は一覧の行数取得・各行の描画・選択位置の解決から何度も呼ばれる。
    /// 都度フィルタし直すと、1 回の再描画で「アイテム数 × アイテム数」回だけ
    /// 検索対象テキスト（メモ本文を含む）を組み立てることになり、
    /// アイテムが増えるほど急激に重くなる
    private var cachedVisibleItems: [SecureMenuItem]?

    // MARK: - Items / Query

    func setItems(_ items: [SecureMenuItem]) {
        self.items = items
        cachedVisibleItems = nil
    }

    func setQuery(_ query: String) {
        guard self.query != query else { return }
        self.query = query
        cachedVisibleItems = nil
    }

    /// 現在のクエリで絞り込んだ表示対象。
    /// 絞り込みの条件は選択パネルと共通で、`SecureItemSearch` に集約している
    var visibleItems: [SecureMenuItem] {
        if let cachedVisibleItems = cachedVisibleItems { return cachedVisibleItems }
        let filtered = SecureItemSearch.filter(items, query: query)
        cachedVisibleItems = filtered
        return filtered
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

    /// 作業コピーの末尾にフィールドを追加する。
    /// - Returns: 追加したフィールド（読み取り専用・未選択の場合は nil）
    @discardableResult
    func addField(kind: SecureMenuItem.Field.Kind, label: String,
                  value: String = "", isPassword: Bool = false) -> SecureMenuItem.Field? {
        guard !isReadOnly, var current = draft else { return nil }
        let field = SecureMenuItem.Field(label: label, value: value, isPassword: isPassword, kind: kind)
        current.fields.append(field)
        draft = current
        isDirty = true
        return field
    }

    /// 作業コピーからフィールドを取り除く
    @discardableResult
    func removeField(fieldID: String) -> Bool {
        guard !isReadOnly, var current = draft,
              let index = current.fields.firstIndex(where: { $0.fieldID == fieldID }) else { return false }
        current.fields.remove(at: index)
        draft = current
        isDirty = true
        return true
    }

    /// 作業コピーのフィールドを上下に動かす（Ctrl+j / Ctrl+k 相当）。
    /// 端を越える移動は行わない
    @discardableResult
    func moveField(fieldID: String, by offset: Int) -> Bool {
        guard let index = draft?.fields.firstIndex(where: { $0.fieldID == fieldID }) else { return false }
        return moveField(fieldID: fieldID, toIndex: index + offset)
    }

    /// 作業コピーのフィールドを指定位置へ動かす（ドラッグ&ドロップ用）。
    /// 範囲外・移動なしの場合は何もしない
    @discardableResult
    func moveField(fieldID: String, toIndex destination: Int) -> Bool {
        guard !isReadOnly, var current = draft,
              let index = current.fields.firstIndex(where: { $0.fieldID == fieldID }) else { return false }
        guard destination >= 0, destination < current.fields.count, destination != index else { return false }
        let field = current.fields.remove(at: index)
        current.fields.insert(field, at: destination)
        draft = current
        isDirty = true
        return true
    }

    /// アイテムを上下に動かした並びを返す（純粋関数のためユニットテスト可能）。
    /// 端を越える場合や対象が見つからない場合は nil
    static func reordered(_ items: [SecureMenuItem], movingItemID: String, by offset: Int) -> [SecureMenuItem]? {
        guard let index = items.firstIndex(where: { $0.itemID == movingItemID }) else { return nil }
        return reordered(items, movingItemID: movingItemID, toIndex: index + offset)
    }

    /// 一覧をドラッグ&ドロップで並べ替えてよいか（純粋関数）。
    ///
    /// **絞り込み中は許さない。** 見えている順と保存順が一致しないため、
    /// 行番号から正しい移動先を決められない（キー操作の並べ替えも同じ理由で止めている）
    static func canReorderItems(query: String, isReadOnly: Bool) -> Bool {
        return !isReadOnly && query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// NSTableView のドロップ位置を、移動後の配列に対する添字へ直す（純粋関数）。
    ///
    /// `proposedRow` は**取り除く前の配列**に対する挿入位置なので、
    /// 下方向へ動かす場合は自分が抜けたぶん 1 つ手前になる。
    /// ここを間違えると 1 行ずつずれて落ちる
    static func dropDestinationIndex(fromRow: Int, proposedRow: Int) -> Int {
        return fromRow < proposedRow ? proposedRow - 1 : proposedRow
    }

    /// アイテムを指定位置へ動かした並びを返す（ドラッグ&ドロップ用の純粋関数）。
    /// 範囲外・移動なし・対象が見つからない場合は nil
    static func reordered(_ items: [SecureMenuItem], movingItemID: String, toIndex destination: Int) -> [SecureMenuItem]? {
        guard let index = items.firstIndex(where: { $0.itemID == movingItemID }) else { return nil }
        guard destination >= 0, destination < items.count, destination != index else { return nil }
        var reordered = items
        let item = reordered.remove(at: index)
        reordered.insert(item, at: destination)
        return reordered
    }

    /// 保存すべき内容を判定する。
    ///
    /// ラベルも値も空のフィールドは取り除く（v1.2 以前の編集シートから引き継いだ規則）。
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

    // MARK: - Undo Snapshot

    /// 「最後に Keychain へ保存された状態」を切り出す（取り消し用）。
    ///
    /// `draft` には**編集中の作業コピーではなく、`items` の中の保存済みの姿**を入れる。
    /// 変更を加える直前にこれを控えておけば、取り消しで保存前の状態へ戻せる。
    /// `items` は `markCommitted` / `setItems` で保存済みの内容に追従している
    func committedSnapshot(action: SecureInfoUndoAction) -> SecureInfoSnapshot {
        let committed = selectedItemID.flatMap { itemID in items.first { $0.itemID == itemID } }
        return SecureInfoSnapshot(items: items, draft: committed,
                                  selectedItemID: selectedItemID, action: action)
    }

    /// 控えておいた状態へ戻す。**Keychain への書き戻しは呼び出し側が行うこと**
    /// （このクラスはサービスを知らない）
    func restore(_ snapshot: SecureInfoSnapshot) {
        setItems(snapshot.items)
        selectedItemID = snapshot.selectedItemID
        draft = snapshot.draft
        isDirty = false
    }

    /// 保持している機微情報を破棄する（ウィンドウを閉じるときに呼ぶ）。
    /// シングルトンのウィンドウなので、閉じたあともメモリに平文が残り続けないようにする。
    /// **未保存の変更も捨てるため、必ずコミット後に呼ぶこと。
    /// 取り消しスタック（`SecureInfoUndoStack`）も平文を保持しているので、
    /// あわせて `clear()` すること**
    func clearSensitiveData() {
        items = []
        draft = nil
        isDirty = false
        selectedItemID = nil
        query = ""
        cachedVisibleItems = nil
    }

    /// 保存の成功を記録する。
    /// - Parameter savedItem: 保存後に読み直したアイテム（値変更履歴が追記された状態）
    func markCommitted(_ savedItem: SecureMenuItem) {
        isDirty = false
        draft = savedItem
        if let index = items.firstIndex(where: { $0.itemID == savedItem.itemID }) {
            items[index] = savedItem
            cachedVisibleItems = nil
        }
    }

}
