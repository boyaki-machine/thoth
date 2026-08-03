import Quick
import Nimble
import Security
@testable import Thoth

// MARK: - Secure Items Import / Export Tests
//
// ファイル入出力。任意のファイルを読み込む経路なので、壊れた入力で落ちないこと、
// 指紋パスワードの扱い、そして **TOTP secret が往復で無傷であること** を固定する
// （TOTP の再登録は各サービスの 2FA 設定をやり直す作業になり、実質データ消失と同じ）。

class SecureItemsTransferSpec: QuickSpec {

    private typealias Transfer = SecureItemsTransfer

    private static let testKeychainService = "io.github.boyaki-machine.ThothTests.SecureItemsTransfer"

    override class func spec() {
        parseSpecs()
        encodeSpecs()
        roundTripSpecs()
        cryptoPasswordSpecs()
        exportGuardSpecs()
        applySpecs()
    }

    // MARK: - Export guard

    /// **読み出せないまま書き出すと 0 件の JSON ができ、ユーザーが自分の
    /// バックアップを空で上書きしてしまう。** 呼び出し側の入口判定は直近の
    /// 読み込み結果を写した控えなので、書き出す直前に確かめ直す必要がある
    private static func exportGuardSpecs() {
        describe("書き出し前の読み出し確認") {

            var service: SecureMenuService!

            beforeEach {
                service = SecureMenuService(keychainService: testKeychainService)
                service.deleteAllItems()
            }
            afterEach {
                removeRawUserData()
                service.deleteAllItems()
            }

            it("読めているときは書き出せる") {
                expect(service.save(SecureMenuItem(itemID: "i1", title: "A"))) == true
                let data = try? Transfer.exportData(using: service)
                expect(data) != nil
                let parsed = data.flatMap { try? Transfer.parseImport($0) }
                expect(parsed?.items.map { $0.itemID }) == ["i1"]
            }

            it("読めない状態では書き出さずに throw する") {
                expect(service.save(SecureMenuItem(itemID: "i1", title: "A"))) == true
                // 解釈できないデータを置いて「読めない」状態を作る
                writeRawUserData(Data("{ broken".utf8))
                expect(service.loadAllItems().isEmpty) == true
                expect(service.isKeychainAccessDenied) == true

                expect(try? Transfer.exportData(using: service)) == nil
            }

            // アイテムが 1 件も無い状態と、読めない状態を取り違えない
            it("本当に 0 件のときは書き出せる") {
                expect(service.loadAllItems().isEmpty) == true
                expect(service.isKeychainAccessDenied) == false
                expect(try? Transfer.exportData(using: service)) != nil
            }
        }
    }

    // MARK: - Apply

    private static func applySpecs() {
        describe("取り込みの反映") {

            var service: SecureMenuService!

            beforeEach {
                service = SecureMenuService(keychainService: testKeychainService)
                service.deleteAllItems()
                service.deleteCryptoPassword()
            }
            afterEach {
                service.deleteCryptoPassword()
                service.deleteAllItems()
            }

            it("アイテムと指紋パスワードを反映する") {
                let applied = Transfer.apply(items: [SecureMenuItem(itemID: "i1", title: "A")],
                                             cryptoPassword: "pw", using: service)
                expect(applied) == true
                expect(service.loadAllItems().map { $0.itemID }) == ["i1"]
                expect(service.loadCryptoPassword()) == "pw"
            }

            it("同じ ID は上書きし、他は末尾に足す") {
                expect(service.save(SecureMenuItem(itemID: "i1", title: "旧"))) == true
                _ = Transfer.apply(items: [SecureMenuItem(itemID: "i1", title: "新"),
                                           SecureMenuItem(itemID: "i2", title: "追加")],
                                   cryptoPassword: nil, using: service)
                expect(service.loadAllItems().map { $0.title }) == ["新", "追加"]
            }

            it("0 件のファイルでは何もしない") {
                expect(service.save(SecureMenuItem(itemID: "i1", title: "A"))) == true
                expect(Transfer.apply(items: [], cryptoPassword: nil, using: service)) == true
                expect(service.loadAllItems().map { $0.itemID }) == ["i1"]
            }

            // 握りつぶすと「N 件インポートしました」と出たまま
            // 指紋パスワードだけ入っていない状態に気づけない
            it("指紋パスワードの保存に失敗したら成功と報告しない") {
                writeRawUserData(Data("{ broken".utf8))
                expect(service.loadAllItems().isEmpty) == true
                expect(Transfer.apply(items: [], cryptoPassword: "pw", using: service)) == false
                removeRawUserData()
            }
        }
    }

    // MARK: - Keychain helpers

    /// 解釈できないデータを直接書き込み、「読めない」状態を再現する
    private static func writeRawUserData(_ data: Data) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: testKeychainService,
            kSecAttrAccount as String: "user-data"
        ]
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = data
        SecItemAdd(attributes as CFDictionary, nil)
    }

    private static func removeRawUserData() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: testKeychainService,
            kSecAttrAccount as String: "user-data"
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Parse

    private static func parseSpecs() {
        describe("インポートファイルの解釈") {

            it("現行形式（SecureUserData）を読み込む") {
                let json = """
                {"version":2,"items":[{"itemID":"i1","title":"A","displayOrder":0,"fields":[]}],
                 "cryptoPassword":"pw"}
                """
                let parsed = try? Transfer.parseImport(Data(json.utf8))
                expect(parsed?.items.map { $0.itemID }) == ["i1"]
                expect(parsed?.cryptoPassword) == "pw"
            }

            it("旧形式（アイテムの配列のみ）もフォールバックで読み込む") {
                let json = """
                [{"itemID":"i1","title":"A","displayOrder":0,"fields":[]}]
                """
                let parsed = try? Transfer.parseImport(Data(json.utf8))
                expect(parsed?.items.map { $0.itemID }) == ["i1"]
                expect(parsed?.cryptoPassword) == nil
            }

            // 空文字の指紋パスワードで既存の登録を潰さない
            it("指紋パスワードが空文字なら取り込まない") {
                let json = """
                {"version":2,"items":[],"cryptoPassword":""}
                """
                expect((try? Transfer.parseImport(Data(json.utf8)))?.cryptoPassword) == nil
            }

            it("指紋パスワードが無ければ nil を返す") {
                let json = """
                {"version":2,"items":[]}
                """
                expect((try? Transfer.parseImport(Data(json.utf8)))?.cryptoPassword) == nil
            }

            // 特殊値: 壊れた入力で落ちずにエラーになること
            it("解釈できない入力はエラーになる") {
                expect(try? Transfer.parseImport(Data("{ broken".utf8))) == nil
                expect(try? Transfer.parseImport(Data())) == nil
                expect(try? Transfer.parseImport(Data("[1,2,3]".utf8))) == nil
                expect(try? Transfer.parseImport(Data("\"just a string\"".utf8))) == nil
            }

            // 未知の種別を含むファイルでも取り込める（前方互換）
            it("未知の種別を含むファイルも取り込める") {
                let json = """
                {"version":2,"items":[{"itemID":"i1","title":"A","displayOrder":0,
                 "fields":[{"label":"L","value":"V","isPassword":false,"kind":"kind-from-the-future"}]}]}
                """
                let parsed = try? Transfer.parseImport(Data(json.utf8))
                expect(parsed?.items.first?.fields.first?.kind) == SecureMenuItem.Field.Kind.plain
                expect(parsed?.items.first?.fields.first?.value) == "V"
            }
        }
    }

    // MARK: - Encode

    private static func encodeSpecs() {
        describe("エクスポートファイルの書き出し") {

            it("バージョン付きの SecureUserData として書き出す") {
                let data = try? Transfer.encode(items: [SecureMenuItem(itemID: "i1", title: "A")],
                                                cryptoPassword: "pw")
                guard let data = data,
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    return fail("expected object")
                }
                expect(object["version"] as? Int) == SecureUserData.currentVersion
                expect(object["cryptoPassword"] as? String) == "pw"
                expect((object["items"] as? [Any])?.count) == 1
            }

            // バックアップ同士を差分で比べられるよう、整形と並びを固定している
            it("整形してキーを並べ替える") {
                let data = try? Transfer.encode(items: [SecureMenuItem(itemID: "i1", title: "A")],
                                                cryptoPassword: nil)
                let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                expect(text.contains("\n")) == true
                // sortedKeys なので cryptoPassword より items より version の順に並ぶ
                guard let itemsAt = text.range(of: "\"items\"")?.lowerBound,
                      let versionAt = text.range(of: "\"version\"")?.lowerBound else {
                    return fail("expected keys")
                }
                expect(itemsAt < versionAt) == true
            }

            it("指紋パスワードが未登録でも書き出せる") {
                expect(try? Transfer.encode(items: [], cryptoPassword: nil)) != nil
            }
        }
    }

    // MARK: - Round trip

    private static func roundTripSpecs() {
        describe("書き出しと取り込みの往復") {

            it("アイテムと指紋パスワードがそのまま戻る") {
                let items = [
                    SecureMenuItem(itemID: "i1", title: "GitHub", fields: [
                        SecureMenuItem.Field(fieldID: "f1", label: "ID", value: "alice"),
                        SecureMenuItem.Field(fieldID: "f2", label: "PW", value: "s3cr3t", isPassword: true)
                    ], displayOrder: 0),
                    SecureMenuItem(itemID: "i2", title: "経理システム", fields: [
                        SecureMenuItem.Field(fieldID: "f3", label: "メモ",
                                             value: "契約番号: 12345\nサポート: 03-0000-0000", kind: .note)
                    ], displayOrder: 1)
                ]
                guard let data = try? Transfer.encode(items: items, cryptoPassword: "pw"),
                      let parsed = try? Transfer.parseImport(data) else { return fail("round trip failed") }

                expect(parsed.cryptoPassword) == "pw"
                expect(parsed.items) == items
            }

            // TOTP の再登録は 2FA 設定のやり直しになる。secret は絶対に落とさない
            it("TOTP の secret が無傷で戻る") {
                let secret = "otpauth://totp/AWS:alice?secret=JBSWY3DPEHPK3PXP&issuer=AWS&digits=6&period=30"
                let items = [SecureMenuItem(itemID: "i1", title: "AWS", fields: [
                    SecureMenuItem.Field(fieldID: "f1", label: "TOTP", value: secret, kind: .totp)
                ])]
                guard let data = try? Transfer.encode(items: items, cryptoPassword: nil),
                      let parsed = try? Transfer.parseImport(data) else { return fail("round trip failed") }

                let field = parsed.items.first?.fields.first
                expect(field?.value) == secret
                expect(field?.kind) == SecureMenuItem.Field.Kind.totp
                expect(field?.fieldID) == "f1"
            }

            /// 固定のフィクスチャ。将来ワイヤーフォーマットを変えたときに、
            /// 過去に書き出されたファイルが読めなくなったことを検出する
            it("過去に書き出したファイルを読み込める") {
                let json = """
                {
                  "cryptoPassword" : "fixture-pw",
                  "items" : [
                    {
                      "displayOrder" : 0,
                      "fields" : [
                        {
                          "createdAt" : 745000000,
                          "fieldID" : "f-totp",
                          "history" : [],
                          "isPassword" : false,
                          "kind" : "totp",
                          "label" : "TOTP",
                          "value" : "otpauth://totp/Legacy?secret=JBSWY3DPEHPK3PXP"
                        },
                        {
                          "contentKind" : "note",
                          "createdAt" : 745000000,
                          "fieldID" : "f-note",
                          "history" : [],
                          "isPassword" : false,
                          "kind" : "plain",
                          "label" : "メモ",
                          "value" : "1 行目\\n2 行目"
                        }
                      ],
                      "itemID" : "fixture-item",
                      "title" : "Fixture"
                    }
                  ],
                  "version" : 2
                }
                """
                guard let parsed = try? Transfer.parseImport(Data(json.utf8)) else {
                    return fail("fixture must be readable")
                }
                expect(parsed.cryptoPassword) == "fixture-pw"
                let fields = parsed.items.first?.fields
                expect(fields?.map { $0.fieldID }) == ["f-totp", "f-note"]
                expect(fields?.first?.value) == "otpauth://totp/Legacy?secret=JBSWY3DPEHPK3PXP"
                expect(fields?.first?.kind) == SecureMenuItem.Field.Kind.totp
                // 拡張種別は contentKind から復元する（kind は旧版向けの互換値）
                expect(fields?.last?.kind) == SecureMenuItem.Field.Kind.note
                expect(fields?.last?.value) == "1 行目\n2 行目"
            }

            // 境界値・特殊値が往復で壊れないこと
            it("空文字・改行・全角・結合絵文字が保たれる") {
                let odd = ["", "\n", "a\r\nb", "　全角　", "👨‍👩‍👧‍👦", "\"quoted\"", "\\backslash"]
                let fields = odd.enumerated().map { index, value in
                    SecureMenuItem.Field(fieldID: "f\(index)", label: "L\(index)", value: value)
                }
                let items = [SecureMenuItem(itemID: "i1", title: "Odd", fields: fields)]
                guard let data = try? Transfer.encode(items: items, cryptoPassword: nil),
                      let parsed = try? Transfer.parseImport(data) else { return fail("round trip failed") }
                expect(parsed.items.first?.fields.map { $0.value }) == odd
            }
        }
    }

    // MARK: - Crypto password

    /// 指紋パスワードを上書きすると、以前そのパスワードで暗号化したファイルを
    /// 開けなくなることがある。確認を出す条件をここで固定する
    private static func cryptoPasswordSpecs() {
        describe("指紋パスワードの上書き判定") {

            it("登録済みで内容が違うときだけ確認が要る") {
                expect(Transfer.replacesCryptoPassword(current: "old", incoming: "new")) == true
            }

            it("同じ内容なら確認は要らない") {
                expect(Transfer.replacesCryptoPassword(current: "same", incoming: "same")) == false
            }

            it("未登録なら確認は要らない") {
                expect(Transfer.replacesCryptoPassword(current: nil, incoming: "new")) == false
                expect(Transfer.replacesCryptoPassword(current: "", incoming: "new")) == false
            }

            it("取り込むパスワードが無ければ確認は要らない") {
                expect(Transfer.replacesCryptoPassword(current: "old", incoming: nil)) == false
                expect(Transfer.replacesCryptoPassword(current: "old", incoming: "")) == false
            }
        }
    }
}
