//
//  SecureMenuItem.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Copyright © 2015-2018 Clipy Project.
//

import Foundation

// MARK: - SecureMenuItem

struct SecureMenuItem: Codable, Equatable {
    let itemID: String
    var title: String
    var fields: [Field]
    var displayOrder: Int

    init(itemID: String = UUID().uuidString, title: String, fields: [Field] = [], displayOrder: Int = 0) {
        self.itemID = itemID
        self.title = title
        self.fields = fields
        self.displayOrder = displayOrder
    }

    /// 過去の Val 値と、その値が別の値に置き換えられた日時
    struct FieldHistoryEntry: Codable, Equatable {
        let value: String
        let replacedAt: Date
    }

    struct Field: Codable, Equatable {

        /// フィールドの種別。
        ///
        /// - `.plain`: 通常のテキスト（ID・パスワードなど）
        /// - `.totp`: `value` に TOTP secret（`otpauth://` URI または Base32 secret）を保持し、
        ///   選択時にその時点のワンタイムコードを計算して出力する
        /// - `.url`: ログイン先などの URL。ブラウザで開ける
        /// - `.note`: 契約番号・連絡先といった複数行のメモ
        ///
        /// 種別ごとの振る舞いは Bool の直判定ではなく、下部の capability
        /// （`retainsValueHistory` など）を通して分岐すること。capability は
        /// `default` の無い switch で定義してあるため、種別を追加すると
        /// 判断が必要な箇所がすべてコンパイルエラーとして表面化する。
        enum Kind: String, Codable {
            case plain
            case totp
            case url
            case note
        }

        /// フィールドの安定 ID。Label を変更しても Val の変更履歴が追従できるようにするためのもの
        let fieldID: String
        let label: String
        let value: String
        let isPassword: Bool
        /// フィールド種別（旧データには存在しないため decode 時は `.plain` にフォールバック）
        let kind: Kind
        /// Val の変更履歴（新しい値に置き換えられた旧値のリスト）。
        /// 履歴の追記・上限管理は `SecureMenuService.save(_:)` が保存時に自動で行う。
        let history: [FieldHistoryEntry]
        /// フィールド作成日時。TOTP フィールドの場合、編集画面で作成日時をプレースホルダーに表示する。
        let createdAt: Date

        var isTOTP: Bool { kind == .totp }

        init(fieldID: String = UUID().uuidString, label: String, value: String,
             isPassword: Bool = false, kind: Kind = .plain, history: [FieldHistoryEntry] = [],
             createdAt: Date = Date()) {
            self.fieldID = fieldID
            self.label = label
            self.value = value
            self.isPassword = isPassword
            self.kind = kind
            self.history = history
            self.createdAt = createdAt
        }

        /// 指定したプロパティだけを差し替えた新しい Field を返す（copy-with）。
        ///
        /// `Field` は全プロパティが `let` のため、編集のたびに作り直す必要がある。
        /// このときイニシャライザを直接呼ぶと、引数を省略したプロパティが既定値へ
        /// 黙って初期化される。特に `fieldID` は値変更履歴の対応付けを、
        /// `createdAt` は TOTP の登録日時表示を壊すため、
        /// **既存フィールドの差分更新は必ずこのメソッドを通すこと**。
        ///
        /// `fieldID` と `createdAt` はフィールドの同一性・生成時刻を表すため変更できない。
        func updating(label: String? = nil,
                      value: String? = nil,
                      isPassword: Bool? = nil,
                      kind: Kind? = nil,
                      history: [FieldHistoryEntry]? = nil) -> Field {
            return Field(fieldID: fieldID,
                         label: label ?? self.label,
                         value: value ?? self.value,
                         isPassword: isPassword ?? self.isPassword,
                         kind: kind ?? self.kind,
                         history: history ?? self.history,
                         createdAt: createdAt)
        }

        private enum CodingKeys: String, CodingKey {
            case fieldID, label, value, isPassword, kind, history, createdAt
            /// v1.2.0 で追加した拡張種別（`url` / `note`）の保存先。
            /// 旧バージョンは知らないキーとして黙って無視するため、
            /// ダウングレードしてもデータが壊れない（`encode(to:)` の注記を参照）
            case contentKind
        }

        /// 旧形式（`fieldID` / `kind` / `history` / `createdAt` キーなし）の保存データ・エクスポートファイルも読めるようにする
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            fieldID = try container.decodeIfPresent(String.self, forKey: .fieldID) ?? UUID().uuidString
            label = try container.decode(String.self, forKey: .label)
            value = try container.decode(String.self, forKey: .value)
            isPassword = try container.decode(Bool.self, forKey: .isPassword)
            // 種別は enum ではなく String として読む。enum で直接デコードすると
            // 未知の raw 値（将来の版が書いた種別）で decodeIfPresent が throw し、
            // ユーザーデータ全体が読めなくなる。読めないデータは
            // SecureMenuService が保存を拒否するため、アプリが編集不能に陥る
            let rawKind = try container.decodeIfPresent(String.self, forKey: .kind)
            let rawContentKind = try container.decodeIfPresent(String.self, forKey: .contentKind)
            kind = rawContentKind.flatMap(Kind.init(rawValue:))
                ?? rawKind.flatMap(Kind.init(rawValue:))
                ?? .plain
            history = try container.decodeIfPresent([FieldHistoryEntry].self, forKey: .history) ?? []
            createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        }

        /// 拡張種別を `kind` ではなく `contentKind` に書き分ける。
        ///
        /// `kind` には旧バージョンが解釈できる値（`plain` / `totp`）だけを書く。
        /// ここに `url` / `note` を書いてしまうと、v1.1.x 以前の
        /// `decodeIfPresent(Kind.self, forKey: .kind)` が throw してユーザーデータ全体が
        /// 読めなくなる。旧バージョンから見ると拡張種別のフィールドは「ただのテキスト」
        /// として扱われ、値は無傷のまま残る（TOTP secret も同様）。
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(fieldID, forKey: .fieldID)
            try container.encode(label, forKey: .label)
            try container.encode(value, forKey: .value)
            try container.encode(isPassword, forKey: .isPassword)
            try container.encode(kind.legacyCompatibleKind, forKey: .kind)
            if kind != kind.legacyCompatibleKind {
                try container.encode(kind, forKey: .contentKind)
            }
            try container.encode(history, forKey: .history)
            try container.encode(createdAt, forKey: .createdAt)
        }
    }
}

// MARK: - Field Kind Capabilities

/// 種別ごとの振る舞いをここに集約する。呼び出し側で `kind == .totp` のような
/// 直判定を書くと、種別が増えたときに修正漏れが静かに発生する。
/// すべて `default` の無い switch で書いてあるため、`Kind` に case を追加すると
/// 判断が必要な箇所がコンパイルエラーとして列挙される。
extension SecureMenuItem.Field.Kind {

    /// 値が置き換えられたときに旧値を変更履歴として残すか。
    /// TOTP は secret が極めて機微なため、メモは長文が履歴メニューの 1 行表示を
    /// 壊し上限 10 件を推敲で使い切ってしまうため、いずれも残さない
    var retainsValueHistory: Bool {
        switch self {
        case .plain, .url: return true
        case .totp, .note: return false
        }
    }

    /// 単一行のテキストフィールドで値を直接編集できるか。
    /// false の種別は、テーブルのセルから値を読み取ってはならない
    /// （TOTP は secret を表示しないため、メモは改行が失われるため、
    /// いずれもセルの内容が実際の値と一致しない）
    var allowsSingleLineEditing: Bool {
        switch self {
        case .plain, .url: return true
        case .totp, .note: return false
        }
    }

    /// マスク表示（🔒）の切り替えを許すか。
    /// メモは長文の覚書で、伏せ字にすると内容を確認できず用を成さないため対象外。
    /// TOTP は secret を表示しないため、そもそもマスクの概念が無い
    var allowsPasswordToggle: Bool {
        switch self {
        case .plain, .url: return true
        case .totp, .note: return false
        }
    }

    /// セキュア選択パネル（幅 260px・1 行 22px）に表示するか。
    /// メモは長文でこのパネルに収まらないため、確認ウィンドウ専用にする
    var isVisibleInPicker: Bool {
        switch self {
        case .plain, .totp, .url: return true
        case .note: return false
        }
    }

    /// 値が複数行になりうるか（確認ウィンドウで NSTextView を使うか）
    var isMultiline: Bool {
        switch self {
        case .note: return true
        case .plain, .totp, .url: return false
        }
    }

    /// 保存されている値をそのまま画面に表示してよいか。
    /// TOTP は secret ではなくその時点のワンタイムコードだけを表示する
    var displaysRawValue: Bool {
        switch self {
        case .plain, .url, .note: return true
        case .totp: return false
        }
    }

    /// v1.1.x 以前が解釈できる種別への写像（保存形式の後方互換に使う）。
    /// 拡張種別は旧バージョンから見ると「ただのテキスト」になる
    var legacyCompatibleKind: SecureMenuItem.Field.Kind {
        switch self {
        case .plain, .url, .note: return .plain
        case .totp: return .totp
        }
    }
}

// MARK: - Picker Fields

extension SecureMenuItem {

    /// セキュア選択パネルのサブパネルに表示するフィールド。
    ///
    /// 選択確定時の `fieldIndex` はこの配列に対する添字として記録・復元されるため、
    /// 表示と確定の両方で必ずこのプロパティを通すこと（`item.fields` を直接使うと
    /// 継続ペーストモードの復元位置がずれる）
    var pickerFields: [Field] {
        return fields.filter { $0.kind.isVisibleInPicker }
    }
}

// MARK: - SecureFieldSelection

final class SecureFieldSelection: NSObject {
    let parentItemID: String
    /// 通常フィールドはペーストする文字列。TOTP フィールドの場合は secret（`value`）を保持し、
    /// 出力時に TOTPService でその時点のコードを計算する。
    let fieldValue: String
    let fieldIndex: Int
    let kind: SecureMenuItem.Field.Kind

    var isTOTP: Bool { kind == .totp }

    init(parentItemID: String, fieldValue: String, fieldIndex: Int,
         kind: SecureMenuItem.Field.Kind = .plain) {
        self.parentItemID = parentItemID
        self.fieldValue = fieldValue
        self.fieldIndex = fieldIndex
        self.kind = kind
    }
}

// MARK: - SecureSelectionContext

final class SecureSelectionContext {
    private(set) var lastParentItemID: String?
    private(set) var lastFieldIndex: Int?
    private(set) var lastSelectedDate: Date?

    static let recencyWindow: TimeInterval = 30

    var isWithinWindow: Bool {
        guard let date = lastSelectedDate else { return false }
        return Date().timeIntervalSince(date) < SecureSelectionContext.recencyWindow
    }

    func record(parentItemID: String, fieldIndex: Int) {
        lastParentItemID = parentItemID
        lastFieldIndex = fieldIndex
        lastSelectedDate = Date()
    }

    func clear() {
        lastParentItemID = nil
        lastFieldIndex = nil
        lastSelectedDate = nil
    }
}
