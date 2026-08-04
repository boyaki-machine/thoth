//
//  SecureItemSearch.swift
//
//  Thoth
//  GitHub: https://github.com/boyaki-machine/Thoth
//

import Foundation

/// セキュアアイテムの絞り込み（UI 非依存の純粋関数）。
///
/// **検索条件はセキュア情報確認ウィンドウと選択パネル（⌘⇧.）で共通です。**
/// 画面ごとに条件が違うと、同じ語で探しても片方にしか出ないアイテムが生まれ、
/// 「登録したはずのものが見つからない」という誤解に直結します
/// （v1.3.0 までは実際に、確認ウィンドウはメモ本文まで、選択パネルは
/// タイトルとラベルだけ、と条件がずれていました）。
/// 条件を変えるときは、呼び出し側ではなくこの型だけを直すこと。
enum SecureItemSearch {

    /// クエリでアイテムを絞り込む。
    ///
    /// 空白区切りの複数語は AND 条件、大文字小文字は無視する。
    /// 語はタイトル・ラベル・値をまたいで一致してよい
    /// （"github password" のような探し方ができる）。
    static func filter(_ items: [SecureMenuItem], query: String) -> [SecureMenuItem] {
        let terms = terms(from: query)
        guard !terms.isEmpty else { return items }
        return items.filter { item in
            let haystack = searchableText(of: item)
            return terms.allSatisfy { haystack.contains($0) }
        }
    }

    /// クエリを検索語へ分解する（小文字化し、空要素を落とす）。
    /// 空白だけのクエリは「絞り込みなし」として空配列になる
    static func terms(from query: String) -> [String] {
        return query.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
    }

    /// 1 アイテム分の検索対象テキスト（小文字化済み）。
    ///
    /// 対象はタイトルと全フィールドのラベル、および値のうち
    /// `Field.isValueSearchable` が真のもの（テキスト・URL・メモ）。
    /// **マスク（🔒）を掛けたフィールドの値と TOTP secret は対象外**にする。
    /// 値の断片で探す用途が無いうえ、秘密情報を検索窓へ打たせる動機を作らないため。
    /// どの種別の値を対象にするかは `Field.Kind.valueSearchability` に集約してある。
    ///
    /// 選択パネルに出ないフィールド（メモ）も対象に含める。選択パネルは
    /// 絞り込みの結果として**アイテム**を並べるだけで、一致した値そのものは
    /// 表示しないため、対象を画面ごとに変える理由が無い。
    static func searchableText(of item: SecureMenuItem) -> String {
        var parts = [item.title]
        for field in item.fields {
            parts.append(field.label)
            if field.isValueSearchable {
                parts.append(field.value)
            }
        }
        return parts.joined(separator: "\n").lowercased()
    }
}
