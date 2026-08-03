import Quick
import Nimble
@testable import Thoth

// MARK: - Drag & Drop Reordering Logic Tests
//
// `SecureItemEditViewController.reorderedFields(_:from:toDropRow:)` は
// ドラッグ&ドロップの並べ替え結果を計算する純粋関数。
// NSTableView の `.above` は「その行の *上* に挿入する」意味なので、
// ドロップ行が元の行より後ろの場合は挿入位置が 1 つ手前になる。

class SecureItemFieldReorderingSpec: QuickSpec {

    private typealias EditVC = SecureItemEditViewController

    override class func spec() {
        basicReorderingSpecs()
        rejectionSpecs()
        integritySpecs()
    }

    // MARK: - Helper

    private static func makeTestFields(_ count: Int) -> [SecureMenuItem.Field] {
        return (0..<count).map { index in
            SecureMenuItem.Field(label: "Field \(index)", value: "value\(index)")
        }
    }

    /// 並べ替え後のラベル列を返す（移動しない場合は nil）
    private static func labelsAfterMove(count: Int, from sourceRow: Int, toDropRow dropRow: Int) -> [String]? {
        return EditVC.reorderedFields(makeTestFields(count), from: sourceRow, toDropRow: dropRow)?
            .fields.map { $0.label }
    }

    // MARK: - Basic Reordering

    private static func basicReorderingSpecs() {
        describe("並べ替えの計算（.above セマンティクス）") {

            it("後ろへ移動すると取り除いた分だけ挿入位置が 1 つ手前になる") {
                expect(labelsAfterMove(count: 5, from: 1, toDropRow: 3))
                    == ["Field 0", "Field 2", "Field 1", "Field 3", "Field 4"]
            }

            it("前へ移動するとドロップ行がそのまま挿入位置になる") {
                expect(labelsAfterMove(count: 5, from: 3, toDropRow: 1))
                    == ["Field 0", "Field 3", "Field 1", "Field 2", "Field 4"]
            }

            // 境界値: 先頭・末尾への移動
            it("最終行を先頭へ移動できる") {
                expect(labelsAfterMove(count: 5, from: 4, toDropRow: 0))
                    == ["Field 4", "Field 0", "Field 1", "Field 2", "Field 3"]
            }

            it("先頭行を末尾へ移動できる（ドロップ行は要素数と同じ値になる）") {
                expect(labelsAfterMove(count: 5, from: 0, toDropRow: 5))
                    == ["Field 1", "Field 2", "Field 3", "Field 4", "Field 0"]
            }

            it("隣へ 1 つだけ移動できる") {
                expect(labelsAfterMove(count: 5, from: 0, toDropRow: 2))
                    == ["Field 1", "Field 0", "Field 2", "Field 3", "Field 4"]
            }

            it("移動先の行番号を返す") {
                expect(EditVC.reorderedFields(makeTestFields(5), from: 1, toDropRow: 3)?.targetRow) == 2
                expect(EditVC.reorderedFields(makeTestFields(5), from: 3, toDropRow: 1)?.targetRow) == 1
                expect(EditVC.reorderedFields(makeTestFields(5), from: 0, toDropRow: 5)?.targetRow) == 4
            }

            it("要素数が変わらない") {
                expect(labelsAfterMove(count: 5, from: 4, toDropRow: 0)?.count) == 5
            }

            it("2 要素でも入れ替えられる") {
                expect(labelsAfterMove(count: 2, from: 0, toDropRow: 2)) == ["Field 1", "Field 0"]
                expect(labelsAfterMove(count: 2, from: 1, toDropRow: 0)) == ["Field 1", "Field 0"]
            }
        }
    }

    // MARK: - Rejection

    private static func rejectionSpecs() {
        describe("並べ替えにならないドロップの拒否") {

            // 境界値: 自分自身の上（= sourceRow）と、自分のすぐ下（= sourceRow + 1）は
            // どちらも「動かない」ドロップなので拒否する
            it("自分の上へのドロップは nil を返す") {
                expect(EditVC.reorderedFields(makeTestFields(5), from: 2, toDropRow: 2)) == nil
            }

            it("自分のすぐ下へのドロップは nil を返す") {
                expect(EditVC.reorderedFields(makeTestFields(5), from: 2, toDropRow: 3)) == nil
            }

            it("2 つ以上離れたドロップは受け付ける") {
                expect(EditVC.reorderedFields(makeTestFields(5), from: 2, toDropRow: 4)) != nil
                expect(EditVC.reorderedFields(makeTestFields(5), from: 2, toDropRow: 1)) != nil
            }

            it("1 要素しか無い場合はどこへ落としても移動にならない") {
                expect(EditVC.reorderedFields(makeTestFields(1), from: 0, toDropRow: 0)) == nil
                expect(EditVC.reorderedFields(makeTestFields(1), from: 0, toDropRow: 1)) == nil
            }

            it("空の配列では何もできない") {
                expect(EditVC.reorderedFields([], from: 0, toDropRow: 0)) == nil
            }

            // 境界値: 範囲外の添字でクラッシュせず nil を返す
            it("範囲外の元行は nil を返す") {
                expect(EditVC.reorderedFields(makeTestFields(5), from: -1, toDropRow: 2)) == nil
                expect(EditVC.reorderedFields(makeTestFields(5), from: 5, toDropRow: 2)) == nil
                expect(EditVC.reorderedFields(makeTestFields(5), from: 99, toDropRow: 2)) == nil
            }

            it("範囲外のドロップ行は nil を返す") {
                expect(EditVC.reorderedFields(makeTestFields(5), from: 2, toDropRow: -1)) == nil
                expect(EditVC.reorderedFields(makeTestFields(5), from: 2, toDropRow: 6)) == nil
            }

            // 境界値: ドロップ行は要素数と同じ値まで有効（末尾への挿入）
            it("ドロップ行が要素数と同じ値なら有効") {
                expect(EditVC.reorderedFields(makeTestFields(5), from: 0, toDropRow: 5)) != nil
            }
        }
    }

    // MARK: - Field Integrity

    private static func integritySpecs() {
        describe("並べ替えでフィールドの中身が壊れないこと") {

            it("種別・マスク指定・安定 ID・作成日時・履歴が保持される") {
                let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
                let history = [SecureMenuItem.FieldHistoryEntry(value: "old", replacedAt: createdAt)]
                let original = SecureMenuItem.Field(fieldID: "stable-id", label: "Important",
                                                    value: "secret123", isPassword: true,
                                                    kind: .url, history: history, createdAt: createdAt)
                let fields = [SecureMenuItem.Field(label: "First", value: "val1"),
                              original,
                              SecureMenuItem.Field(label: "Third", value: "val3")]

                guard let moved = EditVC.reorderedFields(fields, from: 1, toDropRow: 3) else {
                    fail("reordering should succeed")
                    return
                }
                let rearranged = moved.fields[2]
                expect(rearranged.fieldID) == "stable-id"
                expect(rearranged.label) == "Important"
                expect(rearranged.value) == "secret123"
                expect(rearranged.isPassword) == true
                expect(rearranged.kind) == SecureMenuItem.Field.Kind.url
                expect(rearranged.history.count) == 1
                expect(rearranged.createdAt) == createdAt
            }

            // TOTP secret は再登録の手間が大きいため、並べ替えで壊れないことを明示的に担保する
            it("TOTP の secret と種別が並べ替えで壊れない") {
                let secret = "otpauth://totp/GitHub:user?secret=JBSWY3DPEHPK3PXP&issuer=GitHub"
                let fields = [SecureMenuItem.Field(label: "Username", value: "alice"),
                              SecureMenuItem.Field(label: "GitHub TOTP", value: secret, kind: .totp),
                              SecureMenuItem.Field(label: "Password", value: "secret"),
                              SecureMenuItem.Field(label: "AWS TOTP", value: "otpauth://totp/AWS?secret=GEZDGNBVGY3TQOJQ", kind: .totp)]

                guard let moved = EditVC.reorderedFields(fields, from: 1, toDropRow: 3) else {
                    fail("reordering should succeed")
                    return
                }
                expect(moved.fields.map { $0.label }) == ["Username", "Password", "GitHub TOTP", "AWS TOTP"]
                expect(moved.fields[2].value) == secret
                expect(moved.fields[2].isTOTP) == true
                expect(moved.fields[3].isTOTP) == true
            }

            it("メモの改行が並べ替えで失われない") {
                let memo = "契約番号: 12345\nサポート: 03-0000-0000"
                let fields = [SecureMenuItem.Field(label: "ID", value: "user"),
                              SecureMenuItem.Field(label: "Memo", value: memo, kind: .note)]

                guard let moved = EditVC.reorderedFields(fields, from: 1, toDropRow: 0) else {
                    fail("reordering should succeed")
                    return
                }
                expect(moved.fields[0].value) == memo
                expect(moved.fields[0].kind) == SecureMenuItem.Field.Kind.note
            }

            // 操作シーケンス: 何度動かしても要素の集合は変わらない
            it("繰り返し動かしても要素が増減・重複しない") {
                var fields = makeTestFields(5)
                let moves = [(0, 5), (4, 0), (2, 4), (1, 3), (3, 1)]
                for (source, drop) in moves {
                    if let moved = EditVC.reorderedFields(fields, from: source, toDropRow: drop) {
                        fields = moved.fields
                    }
                }
                expect(fields.count) == 5
                expect(Set(fields.map { $0.label }).count) == 5
                expect(Set(fields.map { $0.fieldID }).count) == 5
            }
        }
    }
}
