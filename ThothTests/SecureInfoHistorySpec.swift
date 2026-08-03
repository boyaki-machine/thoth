import Quick
import Nimble
import AppKit
@testable import Thoth

// MARK: - Secure Info Window Value History Tests
//
// 過去の値（Field.history）の参照 UI。
//
// この画面の存在理由は「新しいパスワードを決める前に過去の値を目視で見比べる」ことなので、
// 値は画面に出る。そのぶん **行と同じ平文保護の規律**（既定はマスク / 30 秒で自動再マスク /
// 非アクティブ化で即伏せ字 / 秘匿コピー）が履歴にも通っていることを固定する。
//
// 履歴はこの画面では読み取り専用（削除も復元もしない）。

// swiftlint:disable:next type_body_length
class SecureInfoHistorySpec: QuickSpec {

    private typealias Row = SecureFieldRowView
    private typealias Entry = SecureHistoryEntryView

    override class func spec() {
        buttonVisibilitySpecs()
        sortingSpecs()
        entryDisplaySpecs()
        expirySpecs()
        expansionSpecs()
        contextMenuSpecs()
        copySpecs()
    }

    // MARK: - Fixtures

    private static func entries(_ values: [(String, TimeInterval)]) -> [SecureMenuItem.FieldHistoryEntry] {
        return values.map { value, offset in
            SecureMenuItem.FieldHistoryEntry(value: value, replacedAt: Date(timeIntervalSince1970: offset))
        }
    }

    private static func passwordField(history: [SecureMenuItem.FieldHistoryEntry]) -> SecureMenuItem.Field {
        return SecureMenuItem.Field(fieldID: "f1", label: "PW", value: "current",
                                    isPassword: true, kind: .plain, history: history)
    }

    private static var sampleHistory: [SecureMenuItem.FieldHistoryEntry] {
        return entries([("old-1", 1_000), ("old-2", 2_000)])
    }

    // MARK: - Button visibility

    /// v1.2.1 で行を整理したばかりなので、🕘 は「履歴がある行」に限り、
    /// さらに触れているときだけ出す
    private static func buttonVisibilitySpecs() {
        describe("🕘 を出す条件") {

            it("履歴があってマウスが乗っていれば出す") {
                expect(Row.showsHistoryButton(kind: .plain, historyCount: 1,
                                              isHovered: true, hasFocus: false)) == true
            }

            it("その行を編集中でも出す") {
                expect(Row.showsHistoryButton(kind: .plain, historyCount: 1,
                                              isHovered: false, hasFocus: true)) == true
            }

            it("触れていなければ出さない") {
                expect(Row.showsHistoryButton(kind: .plain, historyCount: 1,
                                              isHovered: false, hasFocus: false)) == false
            }

            // 押しても何も出ないボタンを見せない
            it("履歴が 0 件なら出さない") {
                expect(Row.showsHistoryButton(kind: .plain, historyCount: 0,
                                              isHovered: true, hasFocus: true)) == false
            }

            // TOTP の secret は「極めて機微なため履歴を残さない」設計。
            // 旧データに残っていたとしても見せない（編集シートと同じ扱い）
            it("履歴を残さない種別では、件数があっても出さない") {
                expect(Row.showsHistoryButton(kind: .totp, historyCount: 3,
                                              isHovered: true, hasFocus: true)) == false
                expect(Row.showsHistoryButton(kind: .note, historyCount: 3,
                                              isHovered: true, hasFocus: true)) == false
            }

            it("URL の履歴は出す") {
                expect(Row.showsHistoryButton(kind: .url, historyCount: 1,
                                              isHovered: true, hasFocus: false)) == true
            }

            // 閲覧は破壊的でないので、削除ボタンと違い読み取り専用でも使える
            it("読み取り専用でも閲覧できる") {
                let row = Row(field: passwordField(history: sampleHistory), isReadOnly: true)
                expect(row.hasValueHistory) == true
                row.setHovered(true)
                expect(row.historyButton.isEnabled) == true
            }

            // スタックの中ほどに居るため isHidden にすると幅が畳まれ、
            // 現れた瞬間にコピー ⧉ が横へ動いてしまう
            it("出し入れしてもコピーの位置が変わらない") {
                let row = Row(field: passwordField(history: sampleHistory))
                row.frame = NSRect(x: 0, y: 0, width: 420, height: 24)
                row.layoutSubtreeIfNeeded()
                let hiddenCopyFrame = row.copyButton.frame

                row.setHovered(true)
                row.layoutSubtreeIfNeeded()
                expect(row.copyButton.frame) == hiddenCopyFrame
                expect(row.historyButton.alphaValue) == 1
            }

            it("履歴の無い行にはボタン自体を並べない") {
                let row = Row(field: passwordField(history: []))
                expect(row.hasValueHistory) == false
                expect(row.historyButton.superview is NSStackView) == false
            }
        }
    }

    // MARK: - Sorting

    private static func sortingSpecs() {
        describe("履歴の並び") {

            // 保存時は末尾に追記されるが、見たいのはたいてい直近の値
            it("新しい順に並べる") {
                let sorted = Row.sortedHistory(entries([("a", 1_000), ("c", 3_000), ("b", 2_000)]))
                expect(sorted.map { $0.value }) == ["c", "b", "a"]
            }

            it("0 件・1 件でも壊れない") {
                expect(Row.sortedHistory([])).to(beEmpty())
                expect(Row.sortedHistory(entries([("only", 1)])).map { $0.value }) == ["only"]
            }

            it("同時刻の項目を落とさない") {
                let sorted = Row.sortedHistory(entries([("a", 1_000), ("b", 1_000)]))
                expect(sorted.count) == 2
                expect(Set(sorted.map { $0.value })) == Set(["a", "b"])
            }
        }
    }

    // MARK: - Entry display

    private static func entryDisplaySpecs() {
        describe("履歴 1 件の表示") {

            let entry = SecureMenuItem.FieldHistoryEntry(value: "old-pass",
                                                         replacedAt: Date(timeIntervalSince1970: 1_000))

            it("マスク指定のフィールドの履歴は伏せ字にする") {
                expect(Entry.displayedValue(for: entry, isPassword: true, isRevealed: false))
                    == SecureFieldRowView.maskedPlaceholder
                expect(Entry.displayedValue(for: entry, isPassword: true, isRevealed: true)) == "old-pass"
            }

            // ID や URL の旧値は現在値も平文なので、履歴だけ隠す意味がない
            it("マスク指定でないフィールドの履歴は平文で出す") {
                expect(Entry.displayedValue(for: entry, isPassword: false, isRevealed: false)) == "old-pass"
            }

            it("日時を編集シートと同じ書式で出す") {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy/MM/dd HH:mm"
                let date = Date(timeIntervalSince1970: 1_700_000_000)
                expect(Entry.timestampText(for: date)) == formatter.string(from: date)
            }

            it("👁 でマスクと平文が切り替わる") {
                let view = Entry(entry: entry, isPassword: true)
                expect(view.valueField.stringValue) == SecureFieldRowView.maskedPlaceholder
                view.toggleReveal()
                expect(view.valueField.stringValue) == "old-pass"
                view.toggleReveal()
                expect(view.valueField.stringValue) == SecureFieldRowView.maskedPlaceholder
            }

            it("マスク指定でない履歴には 👁 を並べない") {
                let masked = Entry(entry: entry, isPassword: true)
                let plain = Entry(entry: entry, isPassword: false)
                expect(masked.revealButton.superview is NSStackView) == true
                expect(plain.revealButton.superview is NSStackView) == false
                expect(plain.copyButton.superview is NSStackView) == true
            }

            // 履歴はこの画面では読み取り専用
            it("値を編集できない") {
                let view = Entry(entry: entry, isPassword: false)
                expect(view.valueField.isEditable) == false
                expect(view.valueField.isSelectable) == true
            }
        }
    }

    // MARK: - Expiry

    /// 表示したまま離席したときに、過去のパスワードが画面へ残り続けないようにする
    private static func expirySpecs() {
        describe("平文表示の自動解除") {

            let entry = SecureMenuItem.FieldHistoryEntry(value: "old-pass",
                                                         replacedAt: Date(timeIntervalSince1970: 1_000))

            it("失効時間は行と共有する") {
                let start = Date()
                let view = Entry(entry: entry, isPassword: true)
                view.toggleReveal(at: start)
                let timeout = SecureFieldRowView.revealTimeout
                expect(view.hideRevealedValueIfExpired(now: start.addingTimeInterval(timeout - 1))) == false
                expect(view.isRevealed) == true
                expect(view.hideRevealedValueIfExpired(now: start.addingTimeInterval(timeout))) == true
                expect(view.isRevealed) == false
            }

            it("平文表示していなければ何もしない") {
                let view = Entry(entry: entry, isPassword: true)
                expect(view.hideRevealedValueIfExpired(now: Date().addingTimeInterval(9_999))) == false
            }

            // 現在値だけ伏せて過去の値が平文で残ると、守っているつもりで守れていない
            it("行の全伏せ字が履歴も畳む") {
                let row = Row(field: passwordField(history: sampleHistory))
                row.setHistoryExpanded(true)
                row.toggleReveal()
                row.historyEntryViews.forEach { $0.toggleReveal() }
                expect(row.isRevealed) == true
                expect(row.hasRevealedHistoryValue) == true

                row.hideRevealedValue()
                expect(row.isRevealed) == false
                expect(row.hasRevealedHistoryValue) == false
            }

            it("行を畳むと履歴の平文表示も戻る") {
                let row = Row(field: passwordField(history: sampleHistory))
                row.setHistoryExpanded(true)
                row.historyEntryViews.forEach { $0.toggleReveal() }
                expect(row.hasRevealedHistoryValue) == true

                row.setHistoryExpanded(false)
                row.setHistoryExpanded(true)
                expect(row.hasRevealedHistoryValue) == false
            }

            it("右ペインの失効処理が履歴も数える") {
                let start = Date()
                let detail = CPYSecureInfoDetailViewController()
                _ = detail.view
                detail.show(item: SecureMenuItem(itemID: "s1", title: "GitHub",
                                                 fields: [passwordField(history: sampleHistory)]))
                guard let row = detail.fieldRows.first else { return fail("no row") }
                row.setHistoryExpanded(true)
                row.historyEntryViews.forEach { $0.toggleReveal(at: start) }

                let timeout = SecureFieldRowView.revealTimeout
                expect(detail.expireRevealedValues(now: start.addingTimeInterval(timeout - 1))) == 0
                expect(detail.expireRevealedValues(now: start.addingTimeInterval(timeout))) == 2
                expect(row.hasRevealedHistoryValue) == false
            }

            // 非アクティブ化・画面ロック・スリープはこの経路を通る
            it("右ペインの全伏せ字が履歴も畳む") {
                let detail = CPYSecureInfoDetailViewController()
                _ = detail.view
                detail.show(item: SecureMenuItem(itemID: "s1", title: "GitHub",
                                                 fields: [passwordField(history: sampleHistory)]))
                guard let row = detail.fieldRows.first else { return fail("no row") }
                row.setHistoryExpanded(true)
                row.historyEntryViews.forEach { $0.toggleReveal() }

                detail.hideAllRevealedValues()
                expect(row.hasRevealedHistoryValue) == false
            }
        }
    }

    // MARK: - Expansion

    private static func expansionSpecs() {
        describe("履歴の展開") {

            it("展開すると件数分の行が並ぶ") {
                let row = Row(field: passwordField(history: sampleHistory))
                expect(row.isHistoryExpanded) == false
                expect(row.historyEntryViews).to(beEmpty())

                row.toggleHistory()
                expect(row.isHistoryExpanded) == true
                expect(row.historyEntryViews.count) == 2
                // 新しい順に並ぶ
                expect(row.historyEntryViews.map { $0.entry.value }) == ["old-2", "old-1"]
            }

            it("畳むと履歴の行が消える") {
                let row = Row(field: passwordField(history: sampleHistory))
                row.toggleHistory()
                row.toggleHistory()
                expect(row.isHistoryExpanded) == false
                expect(row.historyEntryViews).to(beEmpty())
            }

            // 行の高さの基準が切り替わらないと、履歴が行からはみ出して重なる
            it("行の高さの基準が入れ替わる") {
                let row = Row(field: passwordField(history: sampleHistory))
                expect(row.collapsedBottomConstraint?.isActive) == true

                row.setHistoryExpanded(true)
                expect(row.collapsedBottomConstraint?.isActive) == false
                expect(row.expandedBottomConstraint?.isActive) == true

                row.setHistoryExpanded(false)
                expect(row.collapsedBottomConstraint?.isActive) == true
                expect(row.expandedBottomConstraint?.isActive) != true
            }

            it("展開すると行が高くなる") {
                let row = Row(field: passwordField(history: sampleHistory))
                row.frame = NSRect(x: 0, y: 0, width: 420, height: 24)
                row.layoutSubtreeIfNeeded()
                let collapsedHeight = row.fittingSize.height

                row.setHistoryExpanded(true)
                row.layoutSubtreeIfNeeded()
                expect(row.fittingSize.height) > collapsedHeight
            }

            it("履歴の無い行は展開できない") {
                let row = Row(field: passwordField(history: []))
                row.toggleHistory()
                expect(row.isHistoryExpanded) == false
            }

            it("展開中は 🕘 を出したままにする") {
                let row = Row(field: passwordField(history: sampleHistory))
                row.setHistoryExpanded(true)
                row.setHovered(false)
                expect(row.historyButton.alphaValue) == 1
            }
        }
    }

    // MARK: - Context menu

    private static func contextMenuSpecs() {
        describe("右クリックメニュー") {

            func menu(for row: Row) -> NSMenu? {
                let event = NSEvent.mouseEvent(with: .rightMouseDown, location: .zero,
                                               modifierFlags: [], timestamp: 0, windowNumber: 0,
                                               context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
                guard let event = event else { return nil }
                return row.menu(for: event)
            }

            it("履歴があれば先頭に「変更履歴」が並ぶ") {
                let row = Row(field: passwordField(history: sampleHistory))
                expect(menu(for: row)?.items.first?.title) == L10n.valueHistory
            }

            // 🕘 が現れないのと揃える。押しても何も起きない項目を見せない
            it("履歴が無ければ項目ごと出さない") {
                let row = Row(field: passwordField(history: []))
                let titles = menu(for: row)?.items.map { $0.isSeparatorItem ? "-" : $0.title }
                expect(titles?.contains(L10n.valueHistory)) == false
            }

            // 閲覧は破壊的でないので読み取り専用でも使える
            it("読み取り専用でも履歴だけは出す") {
                let row = Row(field: passwordField(history: sampleHistory), isReadOnly: true)
                let titles = menu(for: row)?.items.map { $0.title }
                expect(titles) == [L10n.valueHistory]
            }

            it("読み取り専用で履歴も無ければメニューを出さない") {
                let row = Row(field: passwordField(history: []), isReadOnly: true)
                expect(menu(for: row)) == nil
            }

            it("メニューから展開できる") {
                let row = Row(field: passwordField(history: sampleHistory))
                guard let item = menu(for: row)?.items.first else { return fail("no menu") }
                _ = item.target?.perform(item.action, with: item)
                expect(row.isHistoryExpanded) == true
            }
        }
    }

    // MARK: - Copy

    /// 過去のパスワードも現在値と同じ扱いにする。
    /// 秘匿マーカーが無いと、自分のクリップボード履歴に旧パスワードが残る。
    ///
    /// 注意: 実ペーストボード（NSPasteboard.general）を使うため、
    /// `ClipboardConcealSpec` と同じく直列実行を前提とし afterEach で必ずクリアする
    private static func copySpecs() {
        describe("履歴のコピー") {

            afterEach {
                NSPasteboard.general.clearContents()
            }

            it("秘匿マーカー付きで書き込む") {
                let detail = CPYSecureInfoDetailViewController()
                _ = detail.view
                detail.show(item: SecureMenuItem(itemID: "s1", title: "GitHub",
                                                 fields: [passwordField(history: sampleHistory)]))
                guard let row = detail.fieldRows.first else { return fail("no row") }
                row.setHistoryExpanded(true)
                guard let entryView = row.historyEntryViews.first else { return fail("no entry") }

                entryView.copyButton.performClick(nil)

                let types = NSPasteboard.general.types ?? []
                // 新しい順に並ぶので先頭は old-2
                expect(NSPasteboard.general.string(forType: .deprecatedString)) == "old-2"
                expect(types).to(contain(Constants.Pasteboard.concealedType))
                // 書き込んだ内容が履歴除外判定に引っかかることを end-to-end で確認
                expect(ClipService.shouldExcludeFromHistory(types: types)) == true
            }
        }
    }
}
