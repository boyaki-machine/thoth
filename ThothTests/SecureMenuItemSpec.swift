import Foundation
import Quick
import Nimble
@testable import Thoth

/// v1.1.x 以前の `Field` デコーダを再現したもの。
/// `kind` を enum として直接デコードするため、未知の raw 値が来ると throw する。
/// 新バージョンが書いた JSON をこれで読めることが
/// 「ダウングレードしてもデータが壊れない」ことの証明になる。
private struct LegacyField: Decodable {

    enum LegacyKind: String, Decodable { case plain, totp }

    let label: String
    let value: String
    let isPassword: Bool
    let kind: LegacyKind

    enum CodingKeys: String, CodingKey { case label, value, isPassword, kind }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        label = try container.decode(String.self, forKey: .label)
        value = try container.decode(String.self, forKey: .value)
        isPassword = try container.decode(Bool.self, forKey: .isPassword)
        kind = try container.decodeIfPresent(LegacyKind.self, forKey: .kind) ?? .plain
    }
}

// BDD スペックは多数の it ブロックを含み型本体が長くなるため型長ルールを緩める
// swiftlint:disable:next type_body_length
class SecureMenuItemSpec: QuickSpec {
    override class func spec() {
        secureMenuItemSpecs()
        fieldUpdatingSpecs()
        fieldKindSpecs()
        downgradeCompatibilitySpecs()
        pickerFieldsSpecs()
        codableCompatibilitySpecs()
        fieldSelectionSpecs()
        selectionContextSpecs()
    }

    /// 種別ごとの capability。呼び出し側の分岐はすべてこの表に従うため、
    /// 意図しない変更が起きたらここで検出できる
    private static func fieldKindSpecs() {
        describe("Field.Kind capabilities") {
            typealias Kind = SecureMenuItem.Field.Kind

            it("Retains value history only for plain and url") {
                expect(Kind.plain.retainsValueHistory) == true
                expect(Kind.url.retainsValueHistory) == true
                expect(Kind.totp.retainsValueHistory) == false
                expect(Kind.note.retainsValueHistory) == false
            }

            // false の種別はテーブルのセルから値を読んではいけない
            // （TOTP は secret を表示しない、メモは改行が失われる）
            it("Allows single line editing only for plain and url") {
                expect(Kind.plain.allowsSingleLineEditing) == true
                expect(Kind.url.allowsSingleLineEditing) == true
                expect(Kind.totp.allowsSingleLineEditing) == false
                expect(Kind.note.allowsSingleLineEditing) == false
            }

            // メモは伏せ字にすると覚書として用を成さないため対象外。
            // TOTP は secret を表示しないためマスクの概念が無い
            it("Allows the password toggle only for plain and url") {
                expect(Kind.plain.allowsPasswordToggle) == true
                expect(Kind.url.allowsPasswordToggle) == true
                expect(Kind.note.allowsPasswordToggle) == false
                expect(Kind.totp.allowsPasswordToggle) == false
            }

            it("Hides only note from the picker panel") {
                expect(Kind.plain.isVisibleInPicker) == true
                expect(Kind.totp.isVisibleInPicker) == true
                expect(Kind.url.isVisibleInPicker) == true
                expect(Kind.note.isVisibleInPicker) == false
            }

            it("Treats only note as multiline") {
                expect(Kind.note.isMultiline) == true
                expect(Kind.plain.isMultiline) == false
                expect(Kind.totp.isMultiline) == false
                expect(Kind.url.isMultiline) == false
            }

            it("Never displays the raw value of a totp secret") {
                expect(Kind.totp.displaysRawValue) == false
                expect(Kind.plain.displaysRawValue) == true
                expect(Kind.url.displaysRawValue) == true
                expect(Kind.note.displaysRawValue) == true
            }

            // 保存形式の後方互換の要。totp が plain に丸められると
            // ワンタイムコード生成が壊れるため、totp だけは必ず維持する
            it("Maps extended kinds to plain but keeps totp intact") {
                expect(Kind.plain.legacyCompatibleKind) == Kind.plain
                expect(Kind.url.legacyCompatibleKind) == Kind.plain
                expect(Kind.note.legacyCompatibleKind) == Kind.plain
                expect(Kind.totp.legacyCompatibleKind) == Kind.totp
            }
        }
    }

    /// アプリのバージョンを戻したときにデータが壊れないことを担保する。
    /// 拡張種別を `kind` キーに書くと旧バージョンのデコードが throw し、
    /// ユーザーデータ全体が読めなくなる（保存も拒否され編集不能になる）ため、
    /// 新しいキー `contentKind` に分離している。
    private static func downgradeCompatibilitySpecs() {
        describe("Downgrade compatibility") {

            func encodedField(_ field: SecureMenuItem.Field) -> [String: Any] {
                let data = try! JSONEncoder().encode(field)
                return (try! JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
            }

            it("Writes only legacy-safe values into the kind key") {
                expect(encodedField(SecureMenuItem.Field(label: "URL", value: "https://example.com", kind: .url))["kind"] as? String) == "plain"
                expect(encodedField(SecureMenuItem.Field(label: "Memo", value: "line1\nline2", kind: .note))["kind"] as? String) == "plain"
                expect(encodedField(SecureMenuItem.Field(label: "TOTP", value: "SECRET", kind: .totp))["kind"] as? String) == "totp"
                expect(encodedField(SecureMenuItem.Field(label: "ID", value: "user"))["kind"] as? String) == "plain"
            }

            it("Emits contentKind only for the extended kinds") {
                expect(encodedField(SecureMenuItem.Field(label: "URL", value: "u", kind: .url))["contentKind"] as? String) == "url"
                expect(encodedField(SecureMenuItem.Field(label: "Memo", value: "m", kind: .note))["contentKind"] as? String) == "note"
                // 既存の種別では新しいキーを出さないので、保存 JSON は従来と同一のまま
                expect(encodedField(SecureMenuItem.Field(label: "ID", value: "user")).keys.contains("contentKind")) == false
                expect(encodedField(SecureMenuItem.Field(label: "T", value: "s", kind: .totp)).keys.contains("contentKind")) == false
            }

            // 中核の回帰テスト: 旧バージョンのデコーダが throw しないこと
            it("Can still be decoded by the v1.1.x decoder without throwing") {
                let fields = [SecureMenuItem.Field(label: "ID", value: "user"),
                              SecureMenuItem.Field(label: "Password", value: "s3cr3t", isPassword: true),
                              SecureMenuItem.Field(label: "TOTP", value: "otpauth://totp/X?secret=JBSWY3DPEHPK3PXP", kind: .totp),
                              SecureMenuItem.Field(label: "URL", value: "https://example.com", kind: .url),
                              SecureMenuItem.Field(label: "Memo", value: "contract 12345\ntel 03-0000-0000", kind: .note)]
                let data = try! JSONEncoder().encode(fields)

                let legacy = try? JSONDecoder().decode([LegacyField].self, from: data)
                expect(legacy?.count) == 5
                // 値はすべて無傷。特に TOTP は secret と種別の両方が保たれる
                expect(legacy?[2].kind) == LegacyField.LegacyKind.totp
                expect(legacy?[2].value) == "otpauth://totp/X?secret=JBSWY3DPEHPK3PXP"
                // 拡張種別は「ただのテキスト」として見えるが、値は失われない
                expect(legacy?[3].kind) == LegacyField.LegacyKind.plain
                expect(legacy?[3].value) == "https://example.com"
                expect(legacy?[4].kind) == LegacyField.LegacyKind.plain
                expect(legacy?[4].value) == "contract 12345\ntel 03-0000-0000"
            }

            // なぜ contentKind に分離しているのかを示す対照実験。
            // 拡張種別を kind キーに直接書いていたら旧バージョンは読めなくなる
            it("Shows why the extended kind must not go into the kind key") {
                let json = """
                [{"label":"Memo","value":"m","isPassword":false,"kind":"note"}]
                """
                let decodedByLegacy = try? JSONDecoder().decode([LegacyField].self, from: Data(json.utf8))
                expect(decodedByLegacy?.count) == nil
            }

            it("Falls back to plain for an unknown kind instead of throwing") {
                let json = """
                [{"label":"X","value":"v","isPassword":false,"kind":"kind-from-the-future"}]
                """
                let decoded = try? JSONDecoder().decode([SecureMenuItem.Field].self, from: Data(json.utf8))
                expect(decoded?.count) == 1
                expect(decoded?.first?.kind) == SecureMenuItem.Field.Kind.plain
                expect(decoded?.first?.value) == "v"
            }

            // 将来 contentKind に未知の値が入っても、kind の解釈にフォールバックする
            it("Falls back to the kind key when contentKind is unknown") {
                let json = """
                [{"label":"X","value":"v","isPassword":false,"kind":"totp","contentKind":"attachment"}]
                """
                let decoded = try? JSONDecoder().decode([SecureMenuItem.Field].self, from: Data(json.utf8))
                expect(decoded?.first?.kind) == SecureMenuItem.Field.Kind.totp
            }

            it("Round trips the extended kinds within the current version") {
                let fields = [SecureMenuItem.Field(label: "URL", value: "https://example.com", kind: .url),
                              SecureMenuItem.Field(label: "Memo", value: "a\nb\nc", kind: .note)]
                let data = try! JSONEncoder().encode(fields)
                let decoded = try! JSONDecoder().decode([SecureMenuItem.Field].self, from: data)
                expect(decoded[0].kind) == SecureMenuItem.Field.Kind.url
                expect(decoded[1].kind) == SecureMenuItem.Field.Kind.note
                expect(decoded[1].value) == "a\nb\nc"
            }
        }
    }

    private static func pickerFieldsSpecs() {
        describe("SecureMenuItem.pickerFields") {

            // fieldIndex はこの配列に対する添字として記録・復元されるため、
            // 除外と順序が変わると継続ペーストモードの復元位置がずれる
            it("Excludes note fields while preserving the order of the rest") {
                let item = SecureMenuItem(title: "Item", fields: [
                    SecureMenuItem.Field(label: "ID", value: "user"),
                    SecureMenuItem.Field(label: "Memo", value: "note", kind: .note),
                    SecureMenuItem.Field(label: "Password", value: "pw", isPassword: true),
                    SecureMenuItem.Field(label: "URL", value: "https://example.com", kind: .url),
                    SecureMenuItem.Field(label: "TOTP", value: "secret", kind: .totp)
                ])
                expect(item.pickerFields.map { $0.label }) == ["ID", "Password", "URL", "TOTP"]
            }

            it("Returns an empty array for an item that only has notes") {
                let item = SecureMenuItem(title: "Memo only", fields: [
                    SecureMenuItem.Field(label: "Memo", value: "note", kind: .note)
                ])
                expect(item.pickerFields).to(beEmpty())
                // 元のフィールドは失われない
                expect(item.fields.count) == 1
            }
        }
    }

    /// `Field.updating(...)` は編集画面・履歴マージから呼ばれる唯一の差分更新手段。
    /// 指定しなかったプロパティが黙って既定値へリセットされないことを担保する
    /// （イニシャライザを直接呼んでいた頃は `createdAt` が毎回現在時刻へ戻っていた）。
    private static func fieldUpdatingSpecs() {
        describe("SecureMenuItem.Field.updating") {

            let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
            let history = [SecureMenuItem.FieldHistoryEntry(value: "old", replacedAt: Date(timeIntervalSince1970: 1_000))]
            func makeField() -> SecureMenuItem.Field {
                return SecureMenuItem.Field(fieldID: "stable-field-id", label: "Password", value: "current",
                                            isPassword: true, kind: .totp, history: history, createdAt: createdAt)
            }

            it("Preserve identity and metadata when nothing is specified") {
                let updated = makeField().updating()
                expect(updated.fieldID) == "stable-field-id"
                expect(updated.label) == "Password"
                expect(updated.value) == "current"
                expect(updated.isPassword) == true
                expect(updated.kind) == SecureMenuItem.Field.Kind.totp
                expect(updated.history.count) == 1
                expect(updated.createdAt) == createdAt
            }

            // 実際のバグ: ラベルだけ変えたつもりが createdAt が現在時刻にリセットされていた
            it("Preserve fieldID, createdAt, kind and history when updating a single property") {
                let updated = makeField().updating(label: "Renamed")
                expect(updated.label) == "Renamed"
                expect(updated.fieldID) == "stable-field-id"
                expect(updated.createdAt) == createdAt
                expect(updated.kind) == SecureMenuItem.Field.Kind.totp
                expect(updated.history.first?.value) == "old"
                expect(updated.value) == "current"
                expect(updated.isPassword) == true
            }

            it("Apply every specified property") {
                let replaced = [SecureMenuItem.FieldHistoryEntry(value: "older", replacedAt: Date(timeIntervalSince1970: 500))]
                let updated = makeField().updating(label: "ID", value: "user", isPassword: false,
                                                   kind: .plain, history: replaced)
                expect(updated.label) == "ID"
                expect(updated.value) == "user"
                expect(updated.isPassword) == false
                expect(updated.kind) == SecureMenuItem.Field.Kind.plain
                expect(updated.history.count) == 1
                expect(updated.history.first?.value) == "older"
                // 差し替え不可のプロパティは維持される
                expect(updated.fieldID) == "stable-field-id"
                expect(updated.createdAt) == createdAt
            }

            it("Allow clearing the history") {
                let updated = makeField().updating(history: [])
                expect(updated.history).to(beEmpty())
                expect(updated.createdAt) == createdAt
            }
        }
    }

    private static func secureMenuItemSpecs() {
        describe("SecureMenuItem") {

            it("Create item with default values") {
                let item = SecureMenuItem(title: "GitHub")
                expect(UUID(uuidString: item.itemID)) != nil
                expect(item.title) == "GitHub"
                expect(item.fields).to(beEmpty())
                expect(item.displayOrder) == 0
            }

            it("Create item with explicit values") {
                let field = SecureMenuItem.Field(label: "Password", value: "s3cr3t", isPassword: true)
                let item = SecureMenuItem(itemID: "fixed-id", title: "AWS", fields: [field], displayOrder: 5)
                expect(item.itemID) == "fixed-id"
                expect(item.title) == "AWS"
                expect(item.fields.count) == 1
                expect(item.displayOrder) == 5
            }

            it("Create field with default values") {
                let field = SecureMenuItem.Field(label: "ID", value: "user")
                expect(field.label) == "ID"
                expect(field.value) == "user"
                expect(field.isPassword) == false
            }
        }
    }

    private static func codableCompatibilitySpecs() {
        describe("Codable compatibility") {

            it("Encode and decode round trip") {
                let fields = [SecureMenuItem.Field(label: "ID", value: "user", isPassword: false),
                              SecureMenuItem.Field(label: "Password", value: "s3cr3t", isPassword: true)]
                let item = SecureMenuItem(itemID: "round-trip-id", title: "GitHub", fields: fields, displayOrder: 3)

                let data = try! JSONEncoder().encode([item])
                let decoded = try! JSONDecoder().decode([SecureMenuItem].self, from: data)

                expect(decoded.count) == 1
                expect(decoded.first?.itemID) == "round-trip-id"
                expect(decoded.first?.title) == "GitHub"
                expect(decoded.first?.displayOrder) == 3
                expect(decoded.first?.fields.count) == 2
                expect(decoded.first?.fields[0].label) == "ID"
                expect(decoded.first?.fields[0].value) == "user"
                expect(decoded.first?.fields[0].isPassword) == false
                expect(decoded.first?.fields[1].label) == "Password"
                expect(decoded.first?.fields[1].value) == "s3cr3t"
                expect(decoded.first?.fields[1].isPassword) == true
            }

            // fieldID / history キーを持たない旧形式のデータも読み込めることを担保する（後方互換）
            it("Decode legacy format without fieldID and history keys") {
                let json = """
                [{"itemID":"legacy-id","title":"Legacy","displayOrder":0,
                  "fields":[{"label":"ID","value":"user","isPassword":false}]}]
                """
                let decoded = try! JSONDecoder().decode([SecureMenuItem].self, from: json.data(using: .utf8)!)
                expect(decoded.first?.fields.first?.history.isEmpty) == true
                // fieldID は自動採番される
                expect(UUID(uuidString: decoded.first?.fields.first?.fieldID ?? "")) != nil
            }

            it("History entries survive the round trip") {
                let history = [SecureMenuItem.FieldHistoryEntry(value: "old-1", replacedAt: Date(timeIntervalSince1970: 1_000)),
                               SecureMenuItem.FieldHistoryEntry(value: "old-2", replacedAt: Date(timeIntervalSince1970: 2_000))]
                let field = SecureMenuItem.Field(label: "Password", value: "current", isPassword: true, history: history)
                let item = SecureMenuItem(itemID: "history-id", title: "Item", fields: [field])

                let data = try! JSONEncoder().encode([item])
                let decoded = try! JSONDecoder().decode([SecureMenuItem].self, from: data)

                let decodedHistory = decoded.first?.fields.first?.history
                expect(decodedHistory?.count) == 2
                expect(decodedHistory?[0].value) == "old-1"
                expect(decodedHistory?[0].replacedAt) == Date(timeIntervalSince1970: 1_000)
                expect(decodedHistory?[1].value) == "old-2"
            }

            // Keychain 保存形式および Export/Import ファイル形式との互換性を担保する。
            // このテストが落ちる変更（プロパティ名の変更など）は既存の保存データや
            // エクスポート済みファイルが読めなくなるため、マイグレーションの検討が必要。
            it("Decode fixed persistence format") {
                let json = """
                [{"itemID":"11111111-2222-3333-4444-555555555555","title":"GitHub","displayOrder":2,
                  "fields":[{"label":"ID","value":"user","isPassword":false},
                            {"label":"Password","value":"s3cr3t","isPassword":true}]}]
                """
                let decoded = try! JSONDecoder().decode([SecureMenuItem].self, from: json.data(using: .utf8)!)

                expect(decoded.count) == 1
                expect(decoded.first?.itemID) == "11111111-2222-3333-4444-555555555555"
                expect(decoded.first?.title) == "GitHub"
                expect(decoded.first?.displayOrder) == 2
                expect(decoded.first?.fields.count) == 2
                expect(decoded.first?.fields[1].isPassword) == true
            }

            it("Encode emits stable JSON keys") {
                let item = SecureMenuItem(itemID: "key-check", title: "Title",
                                          fields: [SecureMenuItem.Field(label: "L", value: "V")], displayOrder: 0)
                let data = try! JSONEncoder().encode(item)
                let object = (try! JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]

                expect(Set(object.keys)) == Set(["itemID", "title", "fields", "displayOrder"])
                let fieldObject = (object["fields"] as? [[String: Any]])?.first ?? [:]
                expect(Set(fieldObject.keys)) == Set(["fieldID", "label", "value", "isPassword", "kind", "history", "createdAt"])
            }
        }
    }

    private static func fieldSelectionSpecs() {
        describe("SecureFieldSelection") {
            it("Store selection values") {
                let selection = SecureFieldSelection(parentItemID: "parent-id", fieldValue: "s3cr3t", fieldIndex: 1)
                expect(selection.parentItemID) == "parent-id"
                expect(selection.fieldValue) == "s3cr3t"
                expect(selection.fieldIndex) == 1
            }
        }
    }

    private static func selectionContextSpecs() {
        describe("SecureSelectionContext") {

            it("Initial state is outside the window") {
                let context = SecureSelectionContext()
                expect(context.isWithinWindow) == false
                expect(context.lastParentItemID) == nil
                expect(context.lastFieldIndex) == nil
                expect(context.lastSelectedDate) == nil
            }

            it("Record selection enters the window") {
                let context = SecureSelectionContext()
                context.record(parentItemID: "parent-id", fieldIndex: 2)
                expect(context.isWithinWindow) == true
                expect(context.lastParentItemID) == "parent-id"
                expect(context.lastFieldIndex) == 2
                expect(context.lastSelectedDate) != nil
            }

            it("Clear selection leaves the window") {
                let context = SecureSelectionContext()
                context.record(parentItemID: "parent-id", fieldIndex: 0)
                context.clear()
                expect(context.isWithinWindow) == false
                expect(context.lastParentItemID) == nil
                expect(context.lastFieldIndex) == nil
                expect(context.lastSelectedDate) == nil
            }

            it("Recency window is 30 seconds") {
                // 「継続ペーストモード」の仕様値。変更時はドキュメントも更新すること
                expect(SecureSelectionContext.recencyWindow) == 30
            }
        }
    }
}
