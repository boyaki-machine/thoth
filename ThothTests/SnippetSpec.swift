import Quick
import Nimble
import RealmSwift
@testable import Thoth

// スニペット（`CPYSnippet`）の Realm 同期操作。
// インポートしたスニペットは「同じ identifier の既存レコードへ内容を反映する」
// 形で取り込むため、merge / remove が identifier を手掛かりに正しい
// レコードへ届くことを確かめる。DB はテストごとにインメモリで作り直す。
class SnippetSpec: QuickSpec {
    override class func spec() {

        beforeEach {
            Realm.Configuration.defaultConfiguration.inMemoryIdentifier = NSUUID().uuidString
        }

        describe("Realm への同期（identifier を手掛かりにした反映）") {

            it("merge すると、同じ identifier の既存レコードへ内容が反映され、複製は DB に残らない") {
                let snippet = CPYSnippet()
                let realm = try! Realm()
                realm.transaction { realm.add(snippet) }

                let snippet2 = CPYSnippet()
                snippet2.identifier = snippet.identifier
                snippet2.index = 100
                snippet2.title = "title"
                snippet2.content = "content"
                snippet2.merge()
                expect(snippet2.realm) == nil

                expect(snippet.index) == snippet2.index
                expect(snippet.title) == snippet2.title
                expect(snippet.content) == snippet2.content
            }

            it("remove すると、同じ identifier の既存レコードが DB から消える") {
                let realm = try! Realm()
                expect(realm.objects(CPYSnippet.self).count) == 0

                let snippet = CPYSnippet()
                realm.transaction { realm.add(snippet) }

                expect(realm.objects(CPYSnippet.self).count) == 1

                let snippet2 = CPYSnippet()
                snippet2.identifier = snippet.identifier
                snippet2.remove()

                expect(realm.objects(CPYSnippet.self).count) == 0
            }

            afterEach {
                let realm = try! Realm()
                realm.transaction { realm.deleteAll() }
            }

        }

    }
}
