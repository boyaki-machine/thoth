import Quick
import Nimble
import AppKit
@testable import Thoth

// MARK: - Secure Info Window View Tests
//
// セキュア情報確認ウィンドウのビュー側（行の表示・編集可否・ボタン構成・
// URL 判定・詳細ペインの組み立て・平文表示の自動解除）。

// BDD スペックは多数の it ブロックを含み型本体が長くなるため型長ルールを緩める
// swiftlint:disable:next type_body_length
class SecureInfoViewSpec: QuickSpec {

    override class func spec() {
        viewIntegrationSpecs()
        fieldRowSpecs()
        editabilitySpecs()
        openableURLSpecs()
        detailRowBuildingSpecs()
        rowButtonSpecs()
        revealExpirySpecs()
        windowProtectionSpecs()
    }

    // MARK: - Fixtures

    private static func sampleItems() -> [SecureMenuItem] {
        return [
            SecureMenuItem(itemID: "github", title: "GitHub", fields: [
                SecureMenuItem.Field(label: "ID", value: "alice"),
                SecureMenuItem.Field(label: "Password", value: "s3cr3t", isPassword: true)
            ]),
            SecureMenuItem(itemID: "aws", title: "AWS Console", fields: [
                SecureMenuItem.Field(label: "Login ID", value: "bob"),
                SecureMenuItem.Field(label: "TOTP", value: "otpauth://totp/AWS?secret=JBSWY3DPEHPK3PXP", kind: .totp)
            ]),
            SecureMenuItem(itemID: "accounting", title: "経理システム", fields: [
                SecureMenuItem.Field(label: "ID", value: "carol"),
                SecureMenuItem.Field(label: "メモ", value: "契約番号: 12345-678\nサポート: 03-0000-0000", kind: .note)
            ])
        ]
    }

    private static func makeEditor() -> SecureInfoEditor {
        let editor = SecureInfoEditor()
        editor.setItems(sampleItems())
        return editor
    }

    private static func titles(_ items: [SecureMenuItem]) -> [String] {
        return items.map { $0.title }
    }

    // MARK: - Reveal expiry

    /// 平文表示は時間で必ず伏せ字へ戻す。
    /// 表示したまま離席されると、画面に平文が残り続けてしまうため
    private static func revealExpirySpecs() {
        describe("平文表示の自動解除") {

            func maskedRow() -> SecureFieldRowView {
                return SecureFieldRowView(field: SecureMenuItem.Field(label: "PW", value: "s3cr3t", isPassword: true))
            }

            it("表示を始めた時刻を覚える") {
                let row = maskedRow()
                let now = Date(timeIntervalSince1970: 1_700_000_000)
                row.toggleReveal(at: now)
                expect(row.isRevealed) == true
                expect(row.revealedAt) == now
            }

            it("伏せ字へ戻すと時刻も忘れる") {
                let row = maskedRow()
                row.toggleReveal()
                row.hideRevealedValue()
                expect(row.revealedAt) == nil
            }

            // 境界値: ちょうど 30 秒で解除し、29 秒では解除しない
            it("期限ちょうどで解除し、それ未満では解除しない") {
                let start = Date(timeIntervalSince1970: 1_700_000_000)
                let timeout = SecureFieldRowView.revealTimeout

                let notYet = maskedRow()
                notYet.toggleReveal(at: start)
                expect(notYet.hideRevealedValueIfExpired(now: start.addingTimeInterval(timeout - 1))) == false
                expect(notYet.isRevealed) == true
                expect(notYet.valueField.stringValue) == "s3cr3t"

                let expired = maskedRow()
                expired.toggleReveal(at: start)
                expect(expired.hideRevealedValueIfExpired(now: start.addingTimeInterval(timeout))) == true
                expect(expired.isRevealed) == false
                expect(expired.valueField.stringValue) == SecureFieldRowView.maskedPlaceholder
            }

            it("表示していない行は解除の対象にならない") {
                let row = maskedRow()
                expect(row.hideRevealedValueIfExpired(now: Date().addingTimeInterval(9_999))) == false
            }

            // 操作シーケンス: 一度隠して再表示すると期限も引き直される
            it("表示し直すと期限が引き直される") {
                let start = Date(timeIntervalSince1970: 1_700_000_000)
                let row = maskedRow()
                row.toggleReveal(at: start)
                row.toggleReveal(at: start.addingTimeInterval(10))          // 隠す
                row.toggleReveal(at: start.addingTimeInterval(20))          // 再表示
                expect(row.hideRevealedValueIfExpired(now: start.addingTimeInterval(45))) == false
                expect(row.hideRevealedValueIfExpired(now: start.addingTimeInterval(50))) == true
            }

            it("詳細ペインが期限切れの行をまとめて伏せ字へ戻す") {
                let detail = CPYSecureInfoDetailViewController()
                _ = detail.view
                detail.show(item: SecureMenuItem(title: "T", fields: [
                    SecureMenuItem.Field(label: "PW1", value: "a", isPassword: true),
                    SecureMenuItem.Field(label: "PW2", value: "b", isPassword: true),
                    SecureMenuItem.Field(label: "ID", value: "c")
                ]))
                let start = Date(timeIntervalSince1970: 1_700_000_000)
                detail.fieldRows[0].toggleReveal(at: start)
                detail.fieldRows[1].toggleReveal(at: start.addingTimeInterval(20))

                // 先に表示した行だけが期限切れになる
                expect(detail.expireRevealedValues(now: start.addingTimeInterval(35))) == 1
                expect(detail.fieldRows[0].isRevealed) == false
                expect(detail.fieldRows[1].isRevealed) == true

                expect(detail.expireRevealedValues(now: start.addingTimeInterval(55))) == 1
                expect(detail.fieldRows[1].isRevealed) == false
            }
        }
    }

    // MARK: - Window protection

    private static func windowProtectionSpecs() {
        describe("ウィンドウの保護") {

            // 値を平文で表示するため、画面共有・画面収録から除外する
            it("画面共有・画面収録から除外される") {
                expect(CPYSecureInfoWindowController.shared.window?.sharingType) == NSWindow.SharingType.none
            }

            it("画面ロックの通知名を持つ") {
                expect(CPYSecureInfoSplitViewController.screenIsLockedNotification.rawValue) == "com.apple.screenIsLocked"
            }

            // 閉じたあともメモリに平文が残らないようにする
            it("保持データの破棄で機微情報が残らない") {
                let editor = SecureInfoEditor()
                editor.setItems([
                    SecureMenuItem(itemID: "s1", title: "GitHub", fields: [
                        SecureMenuItem.Field(label: "PW", value: "s3cr3t", isPassword: true)
                    ])
                ])
                editor.setQuery("git")
                editor.selectItem(itemID: "s1")
                editor.beginEditing(itemID: "s1")
                _ = editor.updateTitle("Edited")

                editor.clearSensitiveData()
                expect(editor.items.isEmpty) == true
                expect(editor.draft?.itemID) == nil
                expect(editor.isDirty) == false
                expect(editor.selectedItemID) == nil
                expect(editor.query) == ""
                expect(editor.visibleItems.isEmpty) == true
            }
        }
    }

    // MARK: - Row buttons

    private static func rowButtonSpecs() {
        describe("行のボタン構成") {

            func shownButtons(_ row: SecureFieldRowView) -> [NSButton] {
                return [row.maskButton, row.revealButton, row.openButton, row.copyButton, row.deleteButton]
                    .filter { $0.superview is NSStackView }
            }

            it("通常フィールドはマスク切替・コピー・削除が並ぶ") {
                let row = SecureFieldRowView(field: SecureMenuItem.Field(label: "ID", value: "a"))
                expect(shownButtons(row)) == [row.maskButton, row.copyButton, row.deleteButton]
            }

            it("マスク中は表示切替も並ぶ") {
                let row = SecureFieldRowView(field: SecureMenuItem.Field(label: "PW", value: "a", isPassword: true))
                expect(shownButtons(row)) == [row.maskButton, row.revealButton, row.copyButton, row.deleteButton]
            }

            it("URL は「開く」も並ぶ") {
                let row = SecureFieldRowView(field: SecureMenuItem.Field(label: "U", value: "a", kind: .url))
                expect(shownButtons(row)) == [row.maskButton, row.openButton, row.copyButton, row.deleteButton]
            }

            // TOTP はマスク切替を持たない（secret を表示しない設計のため）
            it("TOTP はコピーと削除だけが並ぶ") {
                let row = SecureFieldRowView(field: SecureMenuItem.Field(label: "T", value: "a", kind: .totp))
                expect(shownButtons(row)) == [row.copyButton, row.deleteButton]
            }

            // 読み取り専用では編集系のボタンを出さない（押しても何も起きないボタンを見せない）
            it("読み取り専用ではマスク切替と削除を出さない") {
                let row = SecureFieldRowView(field: SecureMenuItem.Field(label: "PW", value: "a", isPassword: true),
                                             isReadOnly: true)
                expect(shownButtons(row)) == [row.revealButton, row.copyButton]
            }

            it("マスク切替はいまと逆の状態を通知する") {
                var reported: [Bool] = []
                let plain = SecureFieldRowView(field: SecureMenuItem.Field(label: "ID", value: "a"))
                plain.onMaskToggled = { _, isPassword in reported.append(isPassword) }
                plain.maskButton.performClick(nil)

                let masked = SecureFieldRowView(field: SecureMenuItem.Field(label: "PW", value: "a", isPassword: true))
                masked.onMaskToggled = { _, isPassword in reported.append(isPassword) }
                masked.maskButton.performClick(nil)

                expect(reported) == [true, false]
            }

            it("削除ボタンが対象の行を通知する") {
                var deleted: String?
                let row = SecureFieldRowView(field: SecureMenuItem.Field(fieldID: "f1", label: "ID", value: "a"))
                row.onDelete = { deleted = $0.field.fieldID }
                row.deleteButton.performClick(nil)
                expect(deleted) == "f1"
            }
        }
    }

    // MARK: - Editability

    /// どの状態でどこを編集できるか。**マスク中の編集を許すと、画面に見えている
    /// 伏せ字がそのまま値として保存されてしまう**ため、ここが最重要
    private static func editabilitySpecs() {
        describe("編集できる場所の判定") {
            typealias Row = SecureFieldRowView

            func editable(_ field: SecureMenuItem.Field, revealed: Bool = false, readOnly: Bool = false) -> Bool {
                return Row.isValueEditable(field: field, isRevealed: revealed, isReadOnly: readOnly)
            }

            it("通常フィールドと URL とメモは編集できる") {
                expect(editable(SecureMenuItem.Field(label: "ID", value: "a"))) == true
                expect(editable(SecureMenuItem.Field(label: "U", value: "a", kind: .url))) == true
                expect(editable(SecureMenuItem.Field(label: "M", value: "a", kind: .note))) == true
            }

            // 伏せ字を編集させると「••••••••」が値として保存される
            it("マスク中は編集できず、表示切替で編集できるようになる") {
                let masked = SecureMenuItem.Field(label: "PW", value: "s3cr3t", isPassword: true)
                expect(editable(masked, revealed: false)) == false
                expect(editable(masked, revealed: true)) == true
            }

            it("マスク中のメモも編集できない") {
                let masked = SecureMenuItem.Field(label: "M", value: "a\nb", isPassword: true, kind: .note)
                expect(editable(masked, revealed: false)) == false
                expect(editable(masked, revealed: true)) == true
            }

            // TOTP は secret を表示しないので、編集させると空文字で潰れる
            it("TOTP は表示切替に関係なく編集できない") {
                let totp = SecureMenuItem.Field(label: "T", value: "secret", kind: .totp)
                expect(editable(totp, revealed: false)) == false
                expect(editable(totp, revealed: true)) == false
            }

            it("読み取り専用モードでは何も編集できない") {
                expect(editable(SecureMenuItem.Field(label: "ID", value: "a"), readOnly: true)) == false
                let masked = SecureMenuItem.Field(label: "PW", value: "a", isPassword: true)
                expect(editable(masked, revealed: true, readOnly: true)) == false
                expect(Row.isLabelEditable(isReadOnly: true)) == false
                expect(Row.isLabelEditable(isReadOnly: false)) == true
            }

            it("行ビューの編集可否が判定と一致する") {
                let masked = SecureFieldRowView(field: SecureMenuItem.Field(label: "PW", value: "s3cr3t", isPassword: true))
                expect(masked.valueField.isEditable) == false
                masked.toggleReveal()
                expect(masked.valueField.isEditable) == true
                masked.hideRevealedValue()
                expect(masked.valueField.isEditable) == false

                let note = SecureFieldRowView(field: SecureMenuItem.Field(label: "M", value: "a", kind: .note))
                expect(note.noteTextView.isEditable) == true

                let readOnlyRow = SecureFieldRowView(field: SecureMenuItem.Field(label: "ID", value: "a"), isReadOnly: true)
                expect(readOnlyRow.valueField.isEditable) == false
                expect(readOnlyRow.labelField.isEditable) == false
            }
        }
    }

    // MARK: - Field row rendering

    /// 行ビューが「値をどう見せるか」。TOTP secret とマスク値を
    /// 画面へ出さないことを固定する
    private static func fieldRowSpecs() {
        describe("フィールド行の表示") {
            typealias Row = SecureFieldRowView

            it("通常フィールドは値をそのまま表示する") {
                let field = SecureMenuItem.Field(label: "ID", value: "alice")
                expect(Row.displayedValue(for: field, isRevealed: false)) == "alice"
            }

            it("マスク指定は伏せ字にし、表示切替で平文になる") {
                let field = SecureMenuItem.Field(label: "PW", value: "s3cr3t", isPassword: true)
                expect(Row.displayedValue(for: field, isRevealed: false)) == Row.maskedPlaceholder
                expect(Row.displayedValue(for: field, isRevealed: true)) == "s3cr3t"
            }

            // TOTP は secret を決して画面に出さない。表示はその時点のコードだけ
            it("TOTP は表示切替に関係なく値を出さない") {
                let field = SecureMenuItem.Field(label: "TOTP", value: "JBSWY3DPEHPK3PXP", kind: .totp)
                expect(Row.displayedValue(for: field, isRevealed: false)) == ""
                expect(Row.displayedValue(for: field, isRevealed: true)) == ""
            }

            it("URL とメモは値をそのまま表示する") {
                let url = SecureMenuItem.Field(label: "URL", value: "https://example.com", kind: .url)
                let note = SecureMenuItem.Field(label: "Memo", value: "line1\nline2", kind: .note)
                expect(Row.displayedValue(for: url, isRevealed: false)) == "https://example.com"
                expect(Row.displayedValue(for: note, isRevealed: false)) == "line1\nline2"
            }

            it("マスク指定のメモも伏せ字になる") {
                let field = SecureMenuItem.Field(label: "Memo", value: "hidden", isPassword: true, kind: .note)
                expect(Row.displayedValue(for: field, isRevealed: false)) == Row.maskedPlaceholder
                expect(Row.displayedValue(for: field, isRevealed: true)) == "hidden"
            }

            it("TOTP の表示は桁区切りと残り秒数を含む") {
                expect(Row.totpDisplayString(code: "123456", remainingSeconds: 18)) == "123 456 · 18s"
                expect(Row.totpDisplayString(code: "12345678", remainingSeconds: 5)) == "1234 5678 · 5s"
            }

            // 境界値: secret を解釈できない場合でも画面が壊れない
            it("コードを生成できない TOTP はプレースホルダーを表示する") {
                expect(Row.totpDisplayString(code: nil, remainingSeconds: 0)) == "------"
            }

            it("マスクを持つ行だけ表示切替が効く") {
                let masked = SecureFieldRowView(field: SecureMenuItem.Field(label: "PW", value: "s3cr3t", isPassword: true))
                masked.toggleReveal()
                expect(masked.isRevealed) == true
                expect(masked.valueField.stringValue) == "s3cr3t"
                masked.hideRevealedValue()
                expect(masked.isRevealed) == false
                expect(masked.valueField.stringValue) == SecureFieldRowView.maskedPlaceholder

                // マスク指定の無いフィールドでは切り替わらない
                let plain = SecureFieldRowView(field: SecureMenuItem.Field(label: "ID", value: "alice"))
                plain.toggleReveal()
                expect(plain.isRevealed) == false
                expect(plain.valueField.stringValue) == "alice"
            }

            // 押せないボタンは並べない（TOTP に表示切替、URL 以外に「開く」を出さない）
            it("種別に応じたボタンだけを並べる") {
                func buttonCount(_ field: SecureMenuItem.Field) -> Int {
                    let row = SecureFieldRowView(field: field)
                    return [row.revealButton, row.openButton, row.copyButton]
                        .filter { $0.superview is NSStackView }.count
                }
                expect(buttonCount(SecureMenuItem.Field(label: "ID", value: "a"))) == 1
                expect(buttonCount(SecureMenuItem.Field(label: "PW", value: "a", isPassword: true))) == 2
                expect(buttonCount(SecureMenuItem.Field(label: "URL", value: "a", kind: .url))) == 2
                expect(buttonCount(SecureMenuItem.Field(label: "T", value: "a", kind: .totp))) == 1
                expect(buttonCount(SecureMenuItem.Field(label: "M", value: "a", kind: .note))) == 1
            }

            it("メモは複数行ビュー、それ以外は単一行ビューに値が入る") {
                let note = SecureFieldRowView(field: SecureMenuItem.Field(label: "M", value: "a\nb", kind: .note))
                expect(note.noteTextView.string) == "a\nb"

                let plain = SecureFieldRowView(field: SecureMenuItem.Field(label: "ID", value: "alice"))
                expect(plain.valueField.stringValue) == "alice"
            }

            // メモ内の URL を自動リンク化すると、クリックだけで外部アプリが開いてしまう
            it("メモの自動リンク検出は無効にする") {
                let note = SecureFieldRowView(field: SecureMenuItem.Field(label: "M", value: "https://example.com", kind: .note))
                expect(note.noteTextView.isAutomaticLinkDetectionEnabled) == false
            }

            // コード生成の NSTextView はスクロールビューへの載せ方を自前で設定しないと
            // 本文が折り返されず、行数に応じたスクロールもできない
            it("メモのテキストビューが折り返しと縦スクロールの設定を持つ") {
                let note = SecureFieldRowView(field: SecureMenuItem.Field(label: "M", value: "a\nb", kind: .note))
                expect(note.noteTextView.isVerticallyResizable) == true
                expect(note.noteTextView.isHorizontallyResizable) == false
                expect(note.noteTextView.textContainer?.widthTracksTextView) == true
            }

            it("マスク指定のメモは複数行ビュー側で伏せ字になり、表示切替で戻る") {
                let field = SecureMenuItem.Field(label: "M", value: "line1\nline2", isPassword: true, kind: .note)
                let row = SecureFieldRowView(field: field)
                expect(row.noteTextView.string) == SecureFieldRowView.maskedPlaceholder
                row.toggleReveal()
                expect(row.noteTextView.string) == "line1\nline2"
                row.hideRevealedValue()
                expect(row.noteTextView.string) == SecureFieldRowView.maskedPlaceholder
            }

            // マスク指定の URL では表示切替・開く・コピーの 3 つが並ぶ
            it("マスク指定の URL では 3 つのボタンが並ぶ") {
                let field = SecureMenuItem.Field(label: "URL", value: "https://example.com", isPassword: true, kind: .url)
                let row = SecureFieldRowView(field: field)
                let shown = [row.revealButton, row.openButton, row.copyButton]
                    .filter { $0.superview is NSStackView }
                expect(shown.count) == 3
                // マスク中でも「開く」対象は実際の値
                expect(row.valueField.stringValue) == SecureFieldRowView.maskedPlaceholder
                expect(CPYSecureInfoDetailViewController.openableURL(from: row.field.value)?.host) == "example.com"
            }
        }
    }

    // MARK: - URL opening

    /// ボタン 1 つで外部アプリが起動するため、開いてよいスキームを厳密に絞る
    private static func openableURLSpecs() {
        describe("URL を開く判定") {
            typealias Detail = CPYSecureInfoDetailViewController

            it("http と https を許可する") {
                expect(Detail.openableURL(from: "https://example.com")?.absoluteString) == "https://example.com"
                expect(Detail.openableURL(from: "http://example.com/login")?.absoluteString) == "http://example.com/login"
            }

            it("大文字のスキームも許可する") {
                expect(Detail.openableURL(from: "HTTPS://example.com")?.scheme?.lowercased()) == "https"
            }

            it("前後の空白を無視する") {
                expect(Detail.openableURL(from: "  https://example.com \n")?.host) == "example.com"
            }

            // 特殊値: インポートしたデータや打ち間違いで危険なスキームが入りうる
            it("file:// や独自スキームは拒否する") {
                expect(Detail.openableURL(from: "file:///etc/passwd")) == nil
                expect(Detail.openableURL(from: "ftp://example.com")) == nil
                expect(Detail.openableURL(from: "javascript:alert(1)")) == nil
                expect(Detail.openableURL(from: "mailto:someone@example.com")) == nil
                expect(Detail.openableURL(from: "x-apple-script://run")) == nil
            }

            it("ホスト名の無い URL は拒否する") {
                expect(Detail.openableURL(from: "https://")) == nil
                expect(Detail.openableURL(from: "http://")) == nil
            }

            it("スキームの無い文字列や空文字は拒否する") {
                expect(Detail.openableURL(from: "example.com")) == nil
                expect(Detail.openableURL(from: "")) == nil
                expect(Detail.openableURL(from: "   ")) == nil
                expect(Detail.openableURL(from: "not a url at all")) == nil
            }

            it("クエリやポートを含む URL は許可する") {
                expect(Detail.openableURL(from: "https://example.com:8443/path?a=1&b=2")?.port) == 8443
            }
        }
    }

    // MARK: - Detail pane rows

    private static func detailRowBuildingSpecs() {
        describe("詳細ペインの行構築") {

            func makeDetail() -> CPYSecureInfoDetailViewController {
                let detailViewController = CPYSecureInfoDetailViewController()
                _ = detailViewController.view
                return detailViewController
            }

            it("フィールドの数だけ行を並べる（メモも含む）") {
                let detail = makeDetail()
                detail.show(item: sampleItems()[2])
                expect(detail.fieldRows.count) == 2
                expect(detail.fieldRows.map { $0.field.label }) == ["ID", "メモ"]
            }

            it("選択なしでは行を出さない") {
                let detail = makeDetail()
                detail.show(item: nil)
                expect(detail.fieldRows.isEmpty) == true
                expect(detail.displayedItem?.itemID) == nil
            }

            // 操作シーケンス: アイテムを切り替えても前のアイテムの行が残らない
            it("アイテムを切り替えると行が作り直される") {
                let detail = makeDetail()
                detail.show(item: sampleItems()[0])
                expect(detail.fieldRows.count) == 2
                detail.show(item: sampleItems()[1])
                expect(detail.fieldRows.map { $0.field.label }) == ["Login ID", "TOTP"]
            }

            // 行ビューを使い捨てにしている理由そのもの。
            // 再利用があると「表示中のパスワードが別アイテムの行に残る」事故になる
            it("アイテムを切り替えると表示中の平文が残らない") {
                let detail = makeDetail()
                detail.show(item: sampleItems()[0])
                detail.fieldRows[1].toggleReveal()
                expect(detail.fieldRows[1].isRevealed) == true

                detail.show(item: sampleItems()[0])
                expect(detail.fieldRows[1].isRevealed) == false
                expect(detail.fieldRows[1].valueField.stringValue) == SecureFieldRowView.maskedPlaceholder
            }

            it("表示中の平文をまとめて伏せ字に戻せる") {
                let detail = makeDetail()
                detail.show(item: sampleItems()[0])
                detail.fieldRows[1].toggleReveal()
                detail.hideAllRevealedValues()
                expect(detail.fieldRows.allSatisfy { !$0.isRevealed }) == true
            }

            // コピー対象: TOTP は secret ではなくその時点のコード
            it("TOTP のコピー対象は 6 桁のコードで secret ではない") {
                let detail = makeDetail()
                let secret = "otpauth://totp/AWS?secret=JBSWY3DPEHPK3PXP"
                let field = SecureMenuItem.Field(label: "TOTP", value: secret, kind: .totp)
                let copied = detail.copyableValue(of: field)
                expect(copied?.count) == 6
                expect(copied) != secret
            }

            it("通常フィールドのコピー対象は値そのもの") {
                let detail = makeDetail()
                let field = SecureMenuItem.Field(label: "PW", value: "s3cr3t", isPassword: true)
                expect(detail.copyableValue(of: field)) == "s3cr3t"
            }

            it("解釈できない TOTP はコピー対象を返さない") {
                let detail = makeDetail()
                let field = SecureMenuItem.Field(label: "TOTP", value: "not-a-secret!!!", kind: .totp)
                expect(detail.copyableValue(of: field)) == nil
            }

            it("TOTP 行は現在のコードと残り秒数を表示する") {
                let detail = makeDetail()
                detail.show(item: sampleItems()[1])
                detail.refreshTOTPRows()
                let totpRow = detail.fieldRows.first { $0.field.isTOTP }
                expect(totpRow?.valueField.stringValue).to(match(#"^\d{3} \d{3} · \d{1,2}s$"#))
                // secret は画面に出ない
                expect(totpRow?.valueField.stringValue).toNot(contain("JBSWY3DPEHPK3PXP"))
            }

            it("フィールドを持たないアイテムでも破綻しない") {
                let detail = makeDetail()
                detail.show(item: SecureMenuItem(title: "Empty"))
                expect(detail.fieldRows.isEmpty) == true
                expect(detail.titleField.stringValue) == "Empty"
                expect(detail.placeholderLabel.isHidden) == true
            }
        }
    }

    // MARK: - View integration
    //
    // ウィンドウを実際に表示せず、ビューの組み立てとエディタとの連携だけを検証する。
    // Keychain には触れず、エディタへ直接アイテムを流し込む
    private static func viewIntegrationSpecs() {
        describe("ビューの組み立て") {

            it("2 ペイン構成でサイドバーは折りたためない") {
                let splitViewController = CPYSecureInfoSplitViewController()
                _ = splitViewController.view
                expect(splitViewController.splitViewItems.count) == 2
                // 折りたためると右ペインだけになり、アイテムを選び直せなくなる
                expect(splitViewController.splitViewItems[0].canCollapse) == false
                expect(splitViewController.splitViewItems[0].minimumThickness) == 180
            }

            it("一覧に表示対象の件数が並び、絞り込みに追従する") {
                let editor = makeEditor()
                let listViewController = CPYSecureInfoListViewController(editor: editor)
                _ = listViewController.view
                listViewController.reload()
                expect(listViewController.tableView.numberOfRows) == 3

                editor.setQuery("github")
                listViewController.reload()
                expect(listViewController.tableView.numberOfRows) == 1
            }

            it("再読み込みで先頭が選択され、詳細へ通知される") {
                let editor = makeEditor()
                let listViewController = CPYSecureInfoListViewController(editor: editor)
                _ = listViewController.view
                var notified: [String?] = []
                listViewController.onSelectionChange = { notified.append($0?.itemID) }

                listViewController.reload()
                expect(notified.last.flatMap { $0 }) == "github"
                expect(listViewController.tableView.selectedRow) == 0
            }

            // 操作シーケンス: j / k 相当の移動。端では動かない
            it("選択を上下に動かせて端では止まる") {
                let editor = makeEditor()
                let listViewController = CPYSecureInfoListViewController(editor: editor)
                _ = listViewController.view
                listViewController.reload()

                listViewController.moveSelection(by: 1)
                expect(editor.selectedItem?.itemID) == "aws"
                listViewController.moveSelection(by: -1)
                expect(editor.selectedItem?.itemID) == "github"
                listViewController.moveSelection(by: -1)
                expect(editor.selectedItem?.itemID) == "github"

                listViewController.moveSelection(by: 2)
                expect(editor.selectedItem?.itemID) == "accounting"
                listViewController.moveSelection(by: 1)
                expect(editor.selectedItem?.itemID) == "accounting"
            }

            it("アイテムが 0 件でも移動操作で破綻しない") {
                let editor = SecureInfoEditor()
                let listViewController = CPYSecureInfoListViewController(editor: editor)
                _ = listViewController.view
                listViewController.reload()
                listViewController.moveSelection(by: 1)
                expect(listViewController.tableView.numberOfRows) == 0
                expect(editor.selectedItem?.itemID) == nil
            }

            it("詳細ペインは選択なしでプレースホルダー、選択ありでタイトルを表示する") {
                let detailViewController = CPYSecureInfoDetailViewController()
                _ = detailViewController.view

                expect(detailViewController.titleField.isHidden) == true
                expect(detailViewController.placeholderLabel.isHidden) == false

                detailViewController.show(item: sampleItems()[1])
                expect(detailViewController.titleField.isHidden) == false
                expect(detailViewController.titleField.stringValue) == "AWS Console"
                expect(detailViewController.placeholderLabel.isHidden) == true

                // 絞り込みで選択が隠れた場合は再びプレースホルダーへ戻る
                detailViewController.show(item: nil)
                expect(detailViewController.titleField.isHidden) == true
                expect(detailViewController.placeholderLabel.isHidden) == false
            }
        }
    }
}
