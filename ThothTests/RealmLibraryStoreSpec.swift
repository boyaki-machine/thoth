import Foundation
import Quick
import Nimble
import RealmSwift
@testable import Thoth

// Realm 版の保存層（RealmHistoryStore / RealmSnippetStore）が保存層の契約を満たすこと。
// 契約の中身は LibraryStoreContract にあり、ここではテストごとに空のインメモリ Realm を用意するだけ。
class RealmLibraryStoreSpec: QuickSpec {

    /// インメモリ Realm は参照が無くなると中身が消えるため、テストの間は 1 つ保持しておく
    private static var keepAlive: Realm?

    override class func spec() {
        afterEach {
            keepAlive = nil
        }
        LibraryStoreContract.specs {
            Realm.Configuration.defaultConfiguration.inMemoryIdentifier = UUID().uuidString
            keepAlive = try? Realm()
            return (history: RealmHistoryStore(), snippets: RealmSnippetStore())
        }
    }
}
