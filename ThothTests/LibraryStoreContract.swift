import Foundation
import Quick
import Nimble
@testable import Thoth

// 保存層（HistoryStore / SnippetStore）の契約。
//
// 保存先（Realm / SwiftData）に関係なく守るべき振る舞いをここに集め、
// 各実装のスペックから同じ内容を走らせる。移行の前後で挙動が変わらないことを、
// 同じテストが両方の実装で通ることで確かめる。
//
// 旧 FolderSpec / SnippetSpec（Realm モデルの merge / remove / rearranges を
// 確かめていたもの）の観点はすべてここへ引き継いでいる。
// make はテストごとに空の保存先を作って返すこと（テスト同士でデータを共有しない）。
enum LibraryStoreContract: SyncDSLUser {
    typealias Stores = (history: HistoryStore, snippets: SnippetStore)

    static func specs(_ make: @escaping () -> Stores) {
        historySpecs(make)
        folderSpecs(make)
        snippetSpecs(make)
        orderingSpecs(make)
        notificationSpecs(make)
    }

    // MARK: - Fixtures

    static func clip(_ id: String, time: Int, title: String = "title") -> ClipRecord {
        return ClipRecord(id: id, dataPath: "/tmp/\(id).data", title: title,
                          primaryType: "public.utf8-plain-text", updateTime: time,
                          thumbnailPath: "", isColorCode: false)
    }

    // MARK: - History

    private static func historySpecs(_ make: @escaping () -> Stores) {
        describe("履歴の保存") {
            it("追加した履歴は、同じ id で全項目がそのまま引ける") {
                let store = make().history
                let record = ClipRecord(id: "a", dataPath: "/tmp/a.data", title: "タイトル 😀\r\n2 行目",
                                        primaryType: "public.tiff", updateTime: 1_700_000_000,
                                        thumbnailPath: "1700000000", isColorCode: true)
                store.upsert(record)
                expect(store.clip(id: "a")) == record
            }

            it("同じ id で追加すると置き換わり、件数は増えない") {
                let store = make().history
                store.upsert(clip("a", time: 1, title: "old"))
                store.upsert(clip("a", time: 2, title: "new"))
                expect(store.clips(ascending: true).map(\.title)) == ["new"]
            }

            it("日時の昇順・降順で並べて返す") {
                let store = make().history
                store.upsert(clip("b", time: 20))
                store.upsert(clip("c", time: 30))
                store.upsert(clip("a", time: 10))
                expect(store.clips(ascending: true).map(\.id)) == ["a", "b", "c"]
                expect(store.clips(ascending: false).map(\.id)) == ["c", "b", "a"]
            }

            it("空かどうかを返す") {
                let store = make().history
                expect(store.isEmpty) == true
                store.upsert(clip("a", time: 1))
                expect(store.isEmpty) == false
            }

            it("1 件削除すると、消した履歴を返し、ほかは残る") {
                let store = make().history
                store.upsert(clip("a", time: 1))
                store.upsert(clip("b", time: 2))
                expect(store.deleteClip(id: "a")?.id) == "a"
                expect(store.clips(ascending: true).map(\.id)) == ["b"]
            }

            it("無い id を削除しても何も起きず nil を返す") {
                let store = make().history
                store.upsert(clip("a", time: 1))
                expect(store.deleteClip(id: "missing")) == nil
                expect(store.clips(ascending: true).map(\.id)) == ["a"]
            }

            it("全件削除すると、消した履歴をすべて返し、空になる") {
                let store = make().history
                store.upsert(clip("a", time: 1))
                store.upsert(clip("b", time: 2))
                expect(store.deleteAllClips().map(\.id).sorted()) == ["a", "b"]
                expect(store.clips(ascending: true)).to(beEmpty())
            }

            it("内容ハッシュからの id は、同じ入力なら同じ値、違う入力なら違う値になる") {
                let store = make().history
                expect(store.clipID(forContentHash: "12345")) == store.clipID(forContentHash: "12345")
                expect(store.clipID(forContentHash: "12345")) != store.clipID(forContentHash: "12346")
            }

            it("日時で削除すると、指定より古いものだけが消え、同じ時刻のものは残る") {
                let store = make().history
                store.upsert(clip("old", time: 10))
                store.upsert(clip("edge", time: 20))
                store.upsert(clip("new", time: 30))
                expect(store.deleteClips(olderThan: 20).map(\.id)) == ["old"]
                expect(store.clips(ascending: true).map(\.id)) == ["edge", "new"]
            }
        }
    }

    // MARK: - Folders

    private static func folderSpecs(_ make: @escaping () -> Stores) {
        describe("フォルダの保存") {
            it("未保存のフォルダを保存すると追加され、同じ id で引ける") {
                let store = make().snippets
                let folder = SnippetFolderRecord(id: "f1", index: 0, enable: false, title: "フォルダ")
                store.saveFolder(folder)
                expect(store.folder(id: "f1")) == folder
            }

            it("保存済みのフォルダを保存すると、名前・番号・有効が上書きされ、中のスニペットは残る") {
                let store = make().snippets
                store.importFolders([SnippetFolderRecord(id: "f1", index: 0, title: "old",
                                                         snippets: [SnippetRecord(id: "s1", index: 0, title: "snippet")])])
                store.saveFolder(SnippetFolderRecord(id: "f1", index: 5, enable: false, title: "new"))
                guard let saved = store.folder(id: "f1") else {
                    fail("保存済みのフォルダが見つからない（前提が崩れている）")
                    return
                }
                expect(saved.title) == "new"
                expect(saved.index) == 5
                expect(saved.enable) == false
                expect(saved.snippets.map(\.id)) == ["s1"]
                expect(store.folders().count) == 1
            }

            it("まとめて追加すると、中のスニペットも同じ id と内容のまま保存される") {
                let store = make().snippets
                let folder = SnippetFolderRecord(id: "f1", index: 3, title: "imported", snippets: [
                    SnippetRecord(id: "s1", index: 0, title: "one", content: "本文\r\n😀"),
                    SnippetRecord(id: "s2", index: 1, enable: false, title: "two", content: "")
                ])
                store.importFolders([folder])
                expect(store.folder(id: "f1")) == folder
                expect(store.snippet(id: "s1")) == folder.snippets[0]
            }

            it("フォルダを削除すると、中のスニペットも一緒に消える") {
                let store = make().snippets
                store.importFolders([
                    SnippetFolderRecord(id: "f1", index: 0, title: "drop", snippets: [SnippetRecord(id: "s1", index: 0, title: "a")]),
                    SnippetFolderRecord(id: "f2", index: 1, title: "keep", snippets: [SnippetRecord(id: "s2", index: 0, title: "b")])
                ])
                store.deleteFolder(id: "f1")
                expect(store.folders().map(\.id)) == ["f2"]
                expect(store.snippet(id: "s1")) == nil
                expect(store.snippet(id: "s2")?.title) == "b"
            }

            it("新しいフォルダの番号は、既存の最大番号の次になる") {
                let store = make().snippets
                expect(store.nextFolderIndex()) == 0
                store.saveFolder(SnippetFolderRecord(id: "f1", index: 0, title: "a"))
                store.saveFolder(SnippetFolderRecord(id: "f2", index: 4, title: "b"))
                expect(store.nextFolderIndex()) == 5
            }

            it("無い id のフォルダ・スニペットは nil を返す") {
                let store = make().snippets
                expect(store.folder(id: "missing")) == nil
                expect(store.snippet(id: "missing")) == nil
            }
        }
    }

    // MARK: - Snippets

    private static func snippetSpecs(_ make: @escaping () -> Stores) {
        describe("スニペットの保存") {
            it("未保存のスニペットを保存すると、指定したフォルダに 1 件増える") {
                let store = make().snippets
                store.saveFolder(SnippetFolderRecord(id: "f1", index: 0, title: "folder"))
                let snippet = SnippetRecord(id: "s1", index: 0, title: "new", content: "body")
                store.saveSnippet(snippet, folderID: "f1")
                expect(store.folder(id: "f1")?.snippets) == [snippet]
            }

            it("保存済みのスニペットを保存すると、同じ id のまま内容が上書きされ、増えない") {
                let store = make().snippets
                store.importFolders([SnippetFolderRecord(id: "f1", index: 0, title: "folder",
                                                         snippets: [SnippetRecord(id: "s1", index: 0, title: "old", content: "old")])])
                let updated = SnippetRecord(id: "s1", index: 0, enable: false, title: "new", content: "new body")
                store.saveSnippet(updated, folderID: "f1")
                expect(store.folder(id: "f1")?.snippets) == [updated]
            }

            it("保存済みのスニペットは、別のフォルダを指定して保存しても移らない") {
                let store = make().snippets
                store.importFolders([
                    SnippetFolderRecord(id: "f1", index: 0, title: "a", snippets: [SnippetRecord(id: "s1", index: 0, title: "x")]),
                    SnippetFolderRecord(id: "f2", index: 1, title: "b")
                ])
                store.saveSnippet(SnippetRecord(id: "s1", index: 0, title: "renamed"), folderID: "f2")
                expect(store.folder(id: "f1")?.snippets.map(\.title)) == ["renamed"]
                expect(store.folder(id: "f2")?.snippets).to(beEmpty())
            }

            it("存在しないフォルダを指定した新しいスニペットは作らない") {
                let store = make().snippets
                store.saveSnippet(SnippetRecord(id: "s1", index: 0, title: "orphan"), folderID: "missing")
                expect(store.snippet(id: "s1")) == nil
            }

            it("スニペットを削除すると、そのスニペットだけが消える") {
                let store = make().snippets
                store.importFolders([SnippetFolderRecord(id: "f1", index: 0, title: "folder", snippets: [
                    SnippetRecord(id: "s1", index: 0, title: "drop"),
                    SnippetRecord(id: "s2", index: 1, title: "keep")
                ])])
                store.deleteSnippet(id: "s1")
                expect(store.folder(id: "f1")?.snippets.map(\.id)) == ["s2"]
            }
        }
    }

    // MARK: - Ordering

    private static func orderingSpecs(_ make: @escaping () -> Stores) {
        describe("並び順") {
            it("フォルダもスニペットも番号順に返す（保存した順ではない）") {
                let store = make().snippets
                store.importFolders([
                    SnippetFolderRecord(id: "f2", index: 1, title: "second", snippets: [
                        SnippetRecord(id: "s3", index: 2, title: "c"),
                        SnippetRecord(id: "s1", index: 0, title: "a"),
                        SnippetRecord(id: "s2", index: 1, title: "b")
                    ]),
                    SnippetFolderRecord(id: "f1", index: 0, title: "first")
                ])
                expect(store.folders().map(\.id)) == ["f1", "f2"]
                expect(store.folder(id: "f2")?.snippets.map(\.id)) == ["s1", "s2", "s3"]
            }

            it("フォルダを並べ替えると、指定した順に番号が 0 から振り直される") {
                let store = make().snippets
                store.importFolders([
                    SnippetFolderRecord(id: "a", index: 0, title: "a"),
                    SnippetFolderRecord(id: "b", index: 5, title: "b"),
                    SnippetFolderRecord(id: "c", index: 9, title: "c")
                ])
                store.reorderFolders(["c", "a", "b"])
                expect(store.folders().map(\.id)) == ["c", "a", "b"]
                expect(store.folders().map(\.index)) == [0, 1, 2]
            }

            it("フォルダ内でスニペットを並べ替えると、指定した順に番号が 0 から振り直される") {
                let store = make().snippets
                store.importFolders([SnippetFolderRecord(id: "f1", index: 0, title: "folder", snippets: [
                    SnippetRecord(id: "a", index: 0, title: "a"),
                    SnippetRecord(id: "b", index: 3, title: "b"),
                    SnippetRecord(id: "c", index: 7, title: "c")
                ])])
                store.reorderSnippets(["b", "c", "a"], inFolder: "f1")
                expect(store.folder(id: "f1")?.snippets.map(\.id)) == ["b", "c", "a"]
                expect(store.folder(id: "f1")?.snippets.map(\.index)) == [0, 1, 2]
            }

            it("別のフォルダのスニペットを並びに含めると、そのフォルダへ移り、元のフォルダからは消える") {
                let store = make().snippets
                store.importFolders([
                    SnippetFolderRecord(id: "from", index: 0, title: "from", snippets: [
                        SnippetRecord(id: "move", index: 0, title: "move"),
                        SnippetRecord(id: "stay", index: 1, title: "stay")
                    ]),
                    SnippetFolderRecord(id: "to", index: 1, title: "to", snippets: [SnippetRecord(id: "x", index: 0, title: "x")])
                ])
                store.reorderSnippets(["move", "x"], inFolder: "to")
                store.reorderSnippets(["stay"], inFolder: "from")
                expect(store.folder(id: "to")?.snippets.map(\.id)) == ["move", "x"]
                expect(store.folder(id: "from")?.snippets.map(\.id)) == ["stay"]
                expect(store.folder(id: "from")?.snippets.map(\.index)) == [0]
            }
        }
    }

    // MARK: - Notification

    private static func notificationSpecs(_ make: @escaping () -> Stores) {
        describe("変更の通知") {
            /// store が出した変更通知を数える（他のテストの遅れて届く通知は数えない）
            func countNotifications(from store: AnyObject, during action: () -> Void) -> () -> Int {
                var count = 0
                let token = NotificationCenter.default.addObserver(forName: .thothLibraryDidChange, object: nil, queue: .main) { note in
                    if (note.object as AnyObject?) === store { count += 1 }
                }
                action()
                return {
                    _ = token
                    return count
                }
            }

            it("履歴を書き換えると、メインスレッドで変更が通知される") {
                let store = make().history
                let count = countNotifications(from: store) { store.upsert(clip("a", time: 1)) }
                expect(count()).toEventually(equal(1))
            }

            it("スニペットを書き換えると、メインスレッドで変更が通知される") {
                let store = make().snippets
                let count = countNotifications(from: store) {
                    store.saveFolder(SnippetFolderRecord(id: "f1", index: 0, title: "folder"))
                }
                expect(count()).toEventually(equal(1))
            }
        }
    }
}
