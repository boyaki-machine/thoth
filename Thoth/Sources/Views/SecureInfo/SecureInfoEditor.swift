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
