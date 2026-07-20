import Quick
import Nimble
import AppKit
@testable import Thoth

/// 履歴全文検索インデクサーと検索フィルタのスペック。
/// クリップデータは実運用と同じ形式（NSKeyedArchiver → ClipDataStore 暗号化）で
/// 一時ディレクトリに作成する（Realm・Keychain には触れない）
class ClipFullTextIndexerSpec: QuickSpec {

    override class func spec() {
        var workDirectory: URL!
        let testKey = Data((0..<32).map { UInt8($0 &+ 13) })
        var store: ClipDataStore!

        beforeEach {
            workDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("clipy-fulltext-test-\(UUID().uuidString)", isDirectory: true)
            try? FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
            store = ClipDataStore(key: testKey)
        }
        afterEach {
            try? FileManager.default.removeItem(at: workDirectory)
        }

        func path(_ name: String) -> String {
            return workDirectory.appendingPathComponent(name).path
        }

        /// 文字列クリップを実運用と同じ形式でファイル化し、参照を返す
        func makeStringClip(_ string: String, file: String) -> ClipFullTextIndexer.ClipRef {
            let pasteboard = NSPasteboard(name: NSPasteboard.Name("thoth-fulltext-\(UUID().uuidString)"))
            pasteboard.declareTypes([.deprecatedString], owner: nil)
            pasteboard.setString(string, forType: .deprecatedString)
            let clipData = CPYClipData(pasteboard: pasteboard, types: [.deprecatedString])
            pasteboard.releaseGlobally()
            let archived = try! NSKeyedArchiver.archivedData(withRootObject: clipData, requiringSecureCoding: false)
            _ = store.write(archived, toPath: path(file))
            return ClipFullTextIndexer.ClipRef(dataHash: file,
                                               dataPath: path(file),
                                               primaryType: NSPasteboard.PasteboardType.deprecatedString.rawValue)
        }

        matchingSpecs()
        extractionSpecs(makeStringClip: makeStringClip, store: { store }, path: path)
        buildSpecs(makeStringClip: makeStringClip, store: { store })
        filterSpecs()
        layoutSpecs()
        titleSpecs()
    }

    /// テスト用 ClipItem を生成する（Realm 非管理の CPYClip から）
    private static func makeItem(_ hash: String, title: String, index: Int) -> CPYHistoryPickerPanel.ClipItem {
        let clip = CPYClip()
        clip.dataHash = hash
        clip.title = title
        clip.primaryType = NSPasteboard.PasteboardType.deprecatedString.rawValue
        clip.dataPath = "/tmp/\(hash).data"
        return CPYHistoryPickerPanel.ClipItem(clip: clip, index: index)
    }

    // MARK: - Matching

    private static func matchingSpecs() {
        describe("検索語の分解とマッチング") {
            it("クエリをトリム・小文字化・空白区切りで分解する") {
                expect(ClipFullTextIndexer.terms(from: "  foo  Bar ")) == ["foo", "bar"]
                expect(ClipFullTextIndexer.terms(from: "")) == []
                expect(ClipFullTextIndexer.terms(from: "   ")) == []
            }

            it("大文字小文字を無視した AND 部分一致で判定する") {
                let text = "the quick brown fox".lowercased()
                expect(ClipFullTextIndexer.matches(text, terms: ["quick", "fox"])) == true
                expect(ClipFullTextIndexer.matches(text, terms: ["quick", "dog"])) == false
                expect(ClipFullTextIndexer.matches(text, terms: [])) == true
            }

            it("日本語の部分一致ができる") {
                let text = "これはテスト用の日本語テキストです".lowercased()
                expect(ClipFullTextIndexer.matches(text, terms: ["日本語"])) == true
                expect(ClipFullTextIndexer.matches(text, terms: ["中国語"])) == false
            }
        }
    }

    // MARK: - Extraction

    private static func extractionSpecs(makeStringClip: @escaping (String, String) -> ClipFullTextIndexer.ClipRef,
                                 store: @escaping () -> ClipDataStore,
                                 path: @escaping (String) -> String) {
        describe("本文の抽出") {
            it("暗号化ファイルから本文を復号して小文字化した文字列を返す") {
                let ref = makeStringClip("Hello WORLD 日本語", "clip1.data")
                let indexer = ClipFullTextIndexer(store: store())
                expect(indexer.extractIndexableText(from: ref)) == "hello world 日本語"
            }

            it("上限文字数で切り詰める") {
                let ref = makeStringClip(String(repeating: "A", count: 100), "clip2.data")
                let indexer = ClipFullTextIndexer(store: store(), maxIndexedCharacters: 10)
                expect(indexer.extractIndexableText(from: ref)) == String(repeating: "a", count: 10)
            }

            it("TIFF / PDF タイプはファイルを読まずスキップする") {
                let indexer = ClipFullTextIndexer(store: store())
                // ファイルが存在しなくても nil を返す（読みに行かないことの傍証）
                let tiffRef = ClipFullTextIndexer.ClipRef(dataHash: "t", dataPath: path("missing-tiff.data"),
                                                          primaryType: NSPasteboard.PasteboardType.deprecatedTIFF.rawValue)
                let pdfRef = ClipFullTextIndexer.ClipRef(dataHash: "p", dataPath: path("missing-pdf.data"),
                                                         primaryType: NSPasteboard.PasteboardType.deprecatedPDF.rawValue)
                expect(indexer.extractIndexableText(from: tiffRef)).to(beNil())
                expect(indexer.extractIndexableText(from: pdfRef)).to(beNil())
            }

            it("ファイルが存在しない文字列クリップは nil を返す") {
                let indexer = ClipFullTextIndexer(store: store())
                let ref = ClipFullTextIndexer.ClipRef(dataHash: "x", dataPath: path("missing.data"),
                                                      primaryType: NSPasteboard.PasteboardType.deprecatedString.rawValue)
                expect(indexer.extractIndexableText(from: ref)).to(beNil())
            }
        }
    }

    // MARK: - Async Build

    private static func buildSpecs(makeStringClip: @escaping (String, String) -> ClipFullTextIndexer.ClipRef,
                            store: @escaping () -> ClipDataStore) {
        describe("非同期ビルド") {
            it("全クリップの索引が最終的に揃う") {
                let refs = [
                    makeStringClip("alpha content", "b1.data"),
                    makeStringClip("beta content", "b2.data"),
                    makeStringClip("gamma content", "b3.data")
                ]
                let indexer = ClipFullTextIndexer(store: store())
                var latest = [String: String]()
                indexer.build(clips: refs) { latest = $0 }
                expect(latest.count).toEventually(equal(3), timeout: .seconds(5))
                expect(latest["b1.data"]) == "alpha content"
                expect(latest["b3.data"]) == "gamma content"
            }

            it("cancel 後はコールバックが発火しない") {
                let refs = (0..<5).map { makeStringClip("text \($0)", "c\($0).data") }
                let indexer = ClipFullTextIndexer(store: store())
                var fired = false
                indexer.cancel()
                indexer.build(clips: refs) { _ in fired = true }
                // 少し待ってもコールバックが来ないことを確認する
                Thread.sleep(forTimeInterval: 0.3)
                expect(fired) == false
            }
        }
    }

    // MARK: - Panel Filter

    private static func filterSpecs() {
        let item = makeItem

        describe("履歴パネルのフィルタ") {
            let items = [
                item("h1", "meeting notes", 0),
                item("h2", "shopping list", 1),
                item("h3", "random text", 2)
            ]

            it("空クエリは全件を元順で返す") {
                let result = CPYHistoryPickerPanel.filter(items: items, fullText: [:], query: "")
                expect(result.map { $0.dataHash }) == ["h1", "h2", "h3"]
            }

            it("タイトル一致で絞り込む") {
                let result = CPYHistoryPickerPanel.filter(items: items, fullText: [:], query: "Shopping")
                expect(result.map { $0.dataHash }) == ["h2"]
            }

            it("タイトルに無くても全文一致でヒットする") {
                let fullText = ["h3": "this clip contains a secret keyword inside its body"]
                let result = CPYHistoryPickerPanel.filter(items: items, fullText: fullText, query: "keyword")
                expect(result.map { $0.dataHash }) == ["h3"]
            }

            it("複数語は AND 条件になる") {
                let result = CPYHistoryPickerPanel.filter(items: items, fullText: [:], query: "meeting notes")
                expect(result.map { $0.dataHash }) == ["h1"]
                let none = CPYHistoryPickerPanel.filter(items: items, fullText: [:], query: "meeting list")
                expect(none).to(beEmpty())
            }

            it("ヒットなしは空配列を返す") {
                let result = CPYHistoryPickerPanel.filter(items: items, fullText: [:], query: "nomatch")
                expect(result).to(beEmpty())
            }
        }
    }

    // MARK: - Layout

    private static func layoutSpecs() {
        let item = makeItem

        describe("履歴パネルのレイアウト（インライン + グルーピング）") {
            // 20 件の履歴（インデックス 0..19）
            let twenty = (0..<20).map { item("g\($0)", "clip number \($0)", $0) }

            func layout(_ items: [CPYHistoryPickerPanel.ClipItem],
                        fullText: [String: String] = [:], query: String = "",
                        totalCount: Int, placeInline: Int = 0, groupSize: Int = 10,
                        numberOffset: Int = 0)
                -> (inline: [CPYHistoryPickerPanel.ClipItem], groups: [CPYHistoryPickerPanel.ClipGroup]) {
                let spec = CPYHistoryPickerPanel.LayoutSpec(placeInline: placeInline,
                                                            groupSize: groupSize,
                                                            numberOffset: numberOffset)
                return CPYHistoryPickerPanel.makeLayout(items: items, fullText: fullText,
                                                        query: query, totalCount: totalCount,
                                                        spec: spec)
            }

            it("空クエリは 10 件ずつのグループに分かれ、ラベルは元の区切りを表す") {
                let result = layout(twenty, totalCount: 20)
                expect(result.inline).to(beEmpty())
                expect(result.groups.count) == 2
                expect(result.groups[0].title) == "0 - 9"
                expect(result.groups[1].title) == "10 - 19"
                expect(result.groups[0].clips.count) == 10
                expect(result.groups[1].clips.count) == 10
            }

            it("番号を 1 開始にするとラベルも 1 開始になる") {
                let result = layout(twenty, totalCount: 20, numberOffset: 1)
                expect(result.groups[0].title) == "1 - 10"
                expect(result.groups[1].title) == "11 - 20"
            }

            it("インライン表示数を指定すると先頭がインラインになり、グループはその後から始まる") {
                let result = layout(twenty, totalCount: 20, placeInline: 5)
                expect(result.inline.map { $0.dataHash }) == (0..<5).map { "g\($0)" }
                expect(result.groups.count) == 2
                expect(result.groups[0].startIndex) == 5
                expect(result.groups[0].title) == "5 - 14"
                expect(result.groups[1].title) == "15 - 19"
            }

            it("グループサイズの設定が反映される") {
                let result = layout(twenty, totalCount: 20, groupSize: 5)
                expect(result.groups.count) == 4
                expect(result.groups[0].title) == "0 - 4"
                expect(result.groups[3].title) == "15 - 19"
            }

            it("検索時も前に詰めず、元の位置のグループにヒットが残る") {
                // 元の 3 番目と 15 番目だけがヒットするクエリ
                let fullText = ["g3": "unique-aaa-token", "g15": "unique-aaa-token"]
                let result = layout(twenty, fullText: fullText, query: "unique-aaa", totalCount: 20)
                expect(result.groups.count) == 2
                expect(result.groups[0].title) == "0 - 9"
                expect(result.groups[0].clips.map { $0.dataHash }) == ["g3"]
                expect(result.groups[1].title) == "10 - 19"
                expect(result.groups[1].clips.map { $0.dataHash }) == ["g15"]
            }

            it("検索時のインラインヒットもインライン枠に残る") {
                let fullText = ["g2": "inline-hit", "g15": "inline-hit"]
                let result = layout(twenty, fullText: fullText, query: "inline-hit",
                                    totalCount: 20, placeInline: 5)
                expect(result.inline.map { $0.dataHash }) == ["g2"]
                expect(result.groups.count) == 1
                expect(result.groups[0].clips.map { $0.dataHash }) == ["g15"]
            }

            it("ヒットの無いグループは含まれない") {
                let fullText = ["g15": "only-here"]
                let result = layout(twenty, fullText: fullText, query: "only-here", totalCount: 20)
                expect(result.groups.count) == 1
                expect(result.groups[0].title) == "10 - 19"
            }

            it("端数グループのラベルは実際の末尾で閉じる") {
                let fifteen = (0..<15).map { item("f\($0)", "clip \($0)", $0) }
                let result = layout(fifteen, totalCount: 15)
                expect(result.groups.count) == 2
                expect(result.groups[1].title) == "10 - 14"
                expect(result.groups[1].clips.count) == 5
            }

            it("ヒットなしはインライン・グループとも空を返す") {
                let result = layout(twenty, query: "nomatch", totalCount: 20)
                expect(result.inline).to(beEmpty())
                expect(result.groups).to(beEmpty())
            }
        }
    }

    // MARK: - Title Trimming

    private static func titleSpecs() {
        describe("タイトルの最大表示文字数") {
            it("最大長を超えるタイトルは切り詰められ、検索は元の 1 行目に対して行われる") {
                let clip = CPYClip()
                clip.dataHash = "t1"
                clip.title = "abcdefghijklmnopqrstuvwxyz"
                clip.primaryType = NSPasteboard.PasteboardType.deprecatedString.rawValue
                clip.dataPath = "/tmp/t1.data"
                let item = CPYHistoryPickerPanel.ClipItem(clip: clip, index: 0, maxTitleLength: 10)
                expect(item.title) == "abcdefg..."
                // 検索用の文字列は切り詰め前
                expect(item.lowercasedTitle) == "abcdefghijklmnopqrstuvwxyz"
            }
        }
    }
}
