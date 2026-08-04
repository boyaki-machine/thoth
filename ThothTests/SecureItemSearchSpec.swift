import Quick
import Nimble
import AppKit
@testable import Thoth

// セキュアアイテム絞り込みの共通ロジック。
//
// 検索条件はセキュア情報確認ウィンドウと選択パネル（⌘⇧.）で共通のため、
// 条件そのものはここで固定し、画面側のスペックは「共通ロジックに繋がっているか」
// だけを見る。最後の describe で両画面の結果が一致することも確かめている。
class SecureItemSearchSpec: QuickSpec {

    override class func spec() {
        termsSpecs()
        searchableTextSpecs()
        filterSpecs()
        screenAgreementSpecs()
    }

    // MARK: - Fixtures

    /// 種別 × マスク指定を一通り並べたアイテム群
    private static func sampleItems() -> [SecureMenuItem] {
        return [
            SecureMenuItem(itemID: "github", title: "GitHub", fields: [
                SecureMenuItem.Field(label: "ID", value: "alice@example.com"),
                SecureMenuItem.Field(label: "Password", value: "s3cr3t", isPassword: true)
            ]),
            SecureMenuItem(itemID: "aws", title: "AWS Console", fields: [
                SecureMenuItem.Field(label: "Login ID", value: "bob"),
                SecureMenuItem.Field(label: "TOTP", value: "otpauth://totp/AWS?secret=JBSWY3DPEHPK3PXP",
                                     kind: .totp)
            ]),
            SecureMenuItem(itemID: "portal", title: "社内ポータル", fields: [
                SecureMenuItem.Field(label: "URL", value: "https://portal.example.co.jp/login", kind: .url),
                SecureMenuItem.Field(label: "秘密の URL", value: "https://masked.example.com/x",
                                     isPassword: true, kind: .url),
                SecureMenuItem.Field(label: "メモ", value: "契約番号: 12345-678\nサポート: 03-0000-0000",
                                     kind: .note)
            ])
        ]
    }

    private static func titles(_ items: [SecureMenuItem]) -> [String] {
        return items.map { $0.title }
    }

    private static func hits(_ query: String) -> [String] {
        return titles(SecureItemSearch.filter(sampleItems(), query: query))
    }

    // MARK: - Terms

    private static func termsSpecs() {
        describe("検索語の分解") {

            it("空白区切りで分解し小文字化する") {
                expect(SecureItemSearch.terms(from: "GitHub Password")) == ["github", "password"]
            }

            // 特殊値: 空・空白のみは「絞り込みなし」として空配列になる
            it("空クエリは検索語なしになる") {
                expect(SecureItemSearch.terms(from: "")).to(beEmpty())
            }

            it("空白と改行だけのクエリは検索語なしになる") {
                expect(SecureItemSearch.terms(from: "   \n \t ")).to(beEmpty())
            }

            it("連続した空白で空の検索語を作らない") {
                expect(SecureItemSearch.terms(from: "  a   b  ")) == ["a", "b"]
            }

            it("改行も区切りとして扱う") {
                expect(SecureItemSearch.terms(from: "a\nb")) == ["a", "b"]
            }
        }
    }

    // MARK: - Searchable text

    /// 検索対象に「入れてよいもの」と「入れてはいけないもの」を明示的に固定する。
    /// マスクした値や TOTP secret が対象に入ると、値の断片を検索窓へ
    /// 打たせる動機を作ってしまう
    private static func searchableTextSpecs() {
        describe("検索対象テキスト") {

            it("タイトルとラベルを含む") {
                let text = SecureItemSearch.searchableText(of: sampleItems()[0])
                expect(text).to(contain("github"))
                expect(text).to(contain("password"))
            }

            it("マスクを掛けていないテキストの値を含む") {
                let text = SecureItemSearch.searchableText(of: sampleItems()[0])
                expect(text).to(contain("alice@example.com"))
            }

            it("URL の値を含む") {
                let text = SecureItemSearch.searchableText(of: sampleItems()[2])
                expect(text).to(contain("portal.example.co.jp"))
            }

            it("メモ本文を含む") {
                let text = SecureItemSearch.searchableText(of: sampleItems()[2])
                expect(text).to(contain("契約番号"))
            }

            it("マスクを掛けたテキストの値は含まない") {
                let text = SecureItemSearch.searchableText(of: sampleItems()[0])
                expect(text).toNot(contain("s3cr3t"))
            }

            // URL にもマスクは掛けられる。種別ではなくマスク指定で決まる
            it("マスクを掛けた URL の値は含まない") {
                let text = SecureItemSearch.searchableText(of: sampleItems()[2])
                expect(text).toNot(contain("masked.example.com"))
                expect(text).to(contain("秘密の url"))
            }

            it("TOTP secret は含まない") {
                let text = SecureItemSearch.searchableText(of: sampleItems()[1])
                expect(text).toNot(contain("jbswy3dpehpk3pxp"))
                expect(text).to(contain("totp"))
            }

            // メモはマスクを持たない種別なので、旧データで isPassword が
            // 立っていても本文は検索対象に含める
            it("旧データでマスク指定が残っているメモも本文を含む") {
                let item = SecureMenuItem(title: "T", fields: [
                    SecureMenuItem.Field(label: "Memo", value: "contract-content",
                                         isPassword: true, kind: .note)
                ])
                expect(SecureItemSearch.searchableText(of: item)).to(contain("contract-content"))
            }

            it("小文字化される") {
                let item = SecureMenuItem(title: "MiXeD", fields: [
                    SecureMenuItem.Field(label: "LaBeL", value: "VaLuE")
                ])
                let text = SecureItemSearch.searchableText(of: item)
                expect(text) == "mixed\nlabel\nvalue"
            }
        }
    }

    // MARK: - Filter

    private static func filterSpecs() {
        describe("絞り込み") {

            it("空クエリでは全件を返す") {
                expect(hits("")) == ["GitHub", "AWS Console", "社内ポータル"]
                expect(hits("   \n ")).to(haveCount(3))
            }

            it("タイトルの部分一致でヒットする（大文字小文字無視）") {
                expect(hits("GITHUB")) == ["GitHub"]
            }

            it("ラベルでヒットする") {
                expect(hits("totp")) == ["AWS Console"]
            }

            it("テキストの値でヒットする") {
                expect(hits("alice@example.com")) == ["GitHub"]
            }

            it("URL の値でヒットする") {
                expect(hits("portal.example.co.jp")) == ["社内ポータル"]
            }

            it("メモ本文でヒットする") {
                expect(hits("12345-678")) == ["社内ポータル"]
            }

            // 選択パネルは v1.3.1 以前、1 つのラベル内でしか AND が効かなかった
            it("複数語はタイトル・ラベル・値をまたいで AND 一致する") {
                expect(hits("github alice")) == ["GitHub"]
                expect(hits("ポータル 契約番号")) == ["社内ポータル"]
            }

            it("一語でも外れると除外される") {
                expect(hits("github totp")).to(beEmpty())
            }

            it("マスクを掛けた値では探せない") {
                expect(hits("s3cr3t")).to(beEmpty())
                expect(hits("masked.example.com")).to(beEmpty())
            }

            it("TOTP secret では探せない") {
                expect(hits("JBSWY3DPEHPK3PXP")).to(beEmpty())
            }

            it("ヒットしないクエリでは空になる") {
                expect(hits("no-such-item")).to(beEmpty())
            }

            it("アイテムが 0 件でも破綻しない") {
                expect(SecureItemSearch.filter([], query: "anything")).to(beEmpty())
            }

            it("順序は元の並びのまま保たれる") {
                expect(hits("o")) == ["GitHub", "AWS Console", "社内ポータル"]
            }
        }
    }

    // MARK: - Screen agreement

    /// 確認ウィンドウと選択パネルが同じクエリで同じアイテムを返すことを固定する。
    /// 片方だけ独自の絞り込みを持つと「登録したはずのものが片方で見つからない」
    /// 状態に戻ってしまう
    private static func screenAgreementSpecs() {
        describe("画面間で条件が揃っていること") {

            let queries = ["", "   ", "github", "alice@example.com", "portal.example.co.jp",
                           "12345-678", "github alice", "s3cr3t", "JBSWY3DPEHPK3PXP", "no-such-item"]

            it("確認ウィンドウと選択パネルの絞り込み結果が一致する") {
                for query in queries {
                    let editor = SecureInfoEditor()
                    editor.setItems(sampleItems())
                    editor.setQuery(query)

                    let panel = CPYSecurePickerPanel(items: sampleItems(), context: SecureSelectionContext())
                    panel.searchField.stringValue = query
                    let panelTitles = titles(panel.filteredItems())
                    panel.close()

                    expect(panelTitles).to(equal(titles(editor.visibleItems)),
                                           description: "クエリ「\(query)」で結果が食い違った")
                }
            }
        }
    }
}
