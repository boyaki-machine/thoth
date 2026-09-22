import Foundation
import Cocoa
import Magnet
import Quick
import Nimble
@testable import Thoth

// 暗号鍵が使えない起動（Environment.isLibraryUsable == false）での振る舞い。
//
// この状態ではストアを開かないので、スニペットの一覧は「空」に見える。そのまま
// 編集させると、作ったものが終了時に黙って消え、復旧後に二重にもなる。
// そのため一覧も編集も止めて、理由をその場で示す（セキュア情報の既存の扱いと同じ流儀）。
// 履歴はメモリ上だけで記録し、貼り付けには使える。
class LibraryUnavailableSpec: QuickSpec {

    static func makeStores() -> (history: HistoryStore, snippets: SnippetStore) {
        guard let cipher = FieldCipher(rootKey: Data((1...32).map { UInt8($0) })),
              let library = try? SwiftDataLibrary.inMemory(cipher: cipher) else {
            fatalError("保存層を作れない（前提が崩れている）")
        }
        return (SwiftDataHistoryStore(library: library), SwiftDataSnippetStore(library: library))
    }

    override class func spec() {
        var stores: (history: HistoryStore, snippets: SnippetStore)!

        beforeEach {
            stores = makeStores()
            stores.snippets.importFolders([
                SnippetFolderRecord(id: "f1", index: 0, title: "フォルダ", snippets: [
                    SnippetRecord(id: "s1", index: 0, title: "スニペット", content: "本文")
                ])
            ])
        }
        afterEach {
            AppEnvironment.popLast()
        }

        func pushEnvironment(isLibraryUsable: Bool) {
            AppEnvironment.push(historyStore: stores.history, snippetStore: stores.snippets,
                                isLibraryUsable: isLibraryUsable)
        }

        describe("スニペットのメニュー") {
            it("使えるときはフォルダとスニペットが並ぶ") {
                pushEnvironment(isLibraryUsable: true)
                let menu = NSMenu()
                MenuManager().addSnippetItems(menu, separateMenu: false)
                expect(menu.items.map(\.title)).to(contain("フォルダ"))
            }

            it("使えないときは理由を示す無効な 1 行だけにする（空に見せない）") {
                pushEnvironment(isLibraryUsable: false)
                let menu = NSMenu()
                MenuManager().addSnippetItems(menu, separateMenu: false)
                expect(menu.items.map(\.title)) == [L10n.snippetsUnavailable]
                expect(menu.items.first?.isEnabled) == false
            }
        }

        describe("フォルダのホットキー") {
            it("使えないときは、フォルダが見つからないと誤判定してホットキーを消さない") {
                // 鍵が使えない起動では、保存層はメモリ上の空のストアになる（フォルダを引けない）
                let empty = makeStores()
                AppEnvironment.push(historyStore: empty.history, snippetStore: empty.snippets, isLibraryUsable: false)
                let service = AppEnvironment.current.hotKeyService
                let keyCombo = KeyCombo(doubledCocoaModifiers: .command)
                service.registerSnippetHotKey(with: "f1", keyCombo: keyCombo!)
                expect(service.snippetKeyCombo(forIdentifier: "f1")) != nil

                service.popupSnippetFolder(HotKey(identifier: "f1", keyCombo: keyCombo!, target: service,
                                                  action: #selector(HotKeyService.popupSnippetFolder(_:))))
                expect(service.snippetKeyCombo(forIdentifier: "f1")) != nil

                service.unregisterSnippetHotKey(with: "f1")
            }
        }

        describe("履歴") {
            it("使えないときも、その起動中はメモリ上に記録して貼り付けに使える") {
                pushEnvironment(isLibraryUsable: false)
                let history = AppEnvironment.current.historyStore
                history.upsert(LibraryStoreContract.clip("c1", time: 1, title: "コピーした文字列"))
                expect(history.clip(id: "c1")?.title) == "コピーした文字列"
            }
        }
    }
}
