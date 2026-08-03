import Quick
import Nimble
import AppKit
@testable import Thoth

// MARK: - Exclude App Service Tests
//
// 「除外アプリケーション」は、パスワードマネージャー等からのコピーを履歴に
// 残さないための機能。**取りこぼすと機微情報が平文で履歴 DB に入る**ため、
// 判定と永続化の両方を押さえておく。
//
// 除外の経路は 2 つある。
//
// | 経路 | 判定 |
// |---|---|
// | 最前面アプリが除外リストにある | `frontProcessIsExcludedApplication()` |
// | コピー内容に特別扱いのマーカー型が付いている | `copiedProcessIsExcludedApplications(pasteboard:)` |
//
// 後者は nspasteboard.org の規約に沿ったもので、1Password のブラウザ拡張のように
// 「コピー元が最前面アプリとして観測できない」場合を拾う。

class ExcludeAppServiceSpec: QuickSpec {

    private static func appInfo(identifier: String, name: String) -> CPYAppInfo {
        // CPYAppInfo は Info.plist 由来の辞書からしか作れない
        let info: [String: AnyObject] = [
            kCFBundleIdentifierKey as String: identifier as AnyObject,
            kCFBundleNameKey as String: name as AnyObject
        ]
        return CPYAppInfo(info: info)!
    }

    override class func spec() {
        specialApplicationSpecs()
        listManagementSpecs()
        appInfoSpecs()
    }

    // MARK: - 特別扱いのアプリ（ペーストボード型による判定）

    /// 1Password のブラウザ拡張からのコピーは、最前面アプリがブラウザになるため
    /// バンドル ID では拾えない。代わりにペーストボードへ載る専用の型で判定する
    private static func specialApplicationSpecs() {
        describe("ペーストボード型による除外") {

            let onePasswordType = NSPasteboard.PasteboardType("com.agilebits.onepassword")

            afterEach {
                NSPasteboard.general.clearContents()
            }

            /// 指定した型を載せたペーストボードを用意する
            func pasteboardCarrying(_ types: [NSPasteboard.PasteboardType]) -> NSPasteboard {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.declareTypes(types, owner: nil)
                return pasteboard
            }

            it("1Password が除外リストにあれば除外する") {
                // 除外リストには Mac アプリ側の ID が登録されている
                let service = ExcludeAppService(applications: [
                    appInfo(identifier: "com.agilebits.onepassword7", name: "1Password 7")
                ])
                let pasteboard = pasteboardCarrying([.string, onePasswordType])
                expect(service.copiedProcessIsExcludedApplications(pasteboard: pasteboard)) == true
            }

            // 1Password 6 系の ID でも拾えること（ID が 2 つ登録されている）
            it("1Password 6 の識別子でも除外する") {
                let service = ExcludeAppService(applications: [
                    appInfo(identifier: "com.agilebits.onepassword-osx", name: "1Password")
                ])
                let pasteboard = pasteboardCarrying([.string, onePasswordType])
                expect(service.copiedProcessIsExcludedApplications(pasteboard: pasteboard)) == true
            }

            // 除外リストに登録していなければ、マーカーが付いていても除外しない
            // （利用者が明示的に登録したときだけ効く設計）
            it("除外リストに無ければ除外しない") {
                let service = ExcludeAppService(applications: [])
                let pasteboard = pasteboardCarrying([.string, onePasswordType])
                expect(service.copiedProcessIsExcludedApplications(pasteboard: pasteboard)) == false
            }

            it("無関係なアプリだけ登録していても除外しない") {
                let service = ExcludeAppService(applications: [
                    appInfo(identifier: "com.example.other", name: "Other")
                ])
                let pasteboard = pasteboardCarrying([.string, onePasswordType])
                expect(service.copiedProcessIsExcludedApplications(pasteboard: pasteboard)) == false
            }

            it("マーカーの無い通常のコピーは除外しない") {
                let service = ExcludeAppService(applications: [
                    appInfo(identifier: "com.agilebits.onepassword7", name: "1Password 7")
                ])
                let pasteboard = pasteboardCarrying([.string, .rtf])
                expect(service.copiedProcessIsExcludedApplications(pasteboard: pasteboard)) == false
            }
        }
    }

    // MARK: - 除外リストの管理

    private static func listManagementSpecs() {
        describe("除外リストの管理") {

            var defaults: UserDefaults!

            beforeEach {
                // 本番の設定を汚さないよう専用のドメインを使う
                defaults = UserDefaults(suiteName: "io.github.boyaki-machine.ThothTests.ExcludeApp")!
                defaults.removePersistentDomain(forName: "io.github.boyaki-machine.ThothTests.ExcludeApp")
                AppEnvironment.push(environment: Environment(defaults: defaults))
            }
            afterEach {
                defaults.removePersistentDomain(forName: "io.github.boyaki-machine.ThothTests.ExcludeApp")
                AppEnvironment.popLast()
            }

            it("追加すると保持され、UserDefaults へ永続化される") {
                let service = ExcludeAppService(applications: [])
                service.add(with: appInfo(identifier: "com.example.a", name: "A"))

                expect(service.applications.map { $0.identifier }) == ["com.example.a"]
                expect(defaults.data(forKey: Constants.UserDefaults.excludeApplications)) != nil
            }

            // 同じアプリを何度も登録できてしまうと、削除しても消えたように見えない
            it("同じアプリは重複して追加しない") {
                let service = ExcludeAppService(applications: [])
                service.add(with: appInfo(identifier: "com.example.a", name: "A"))
                service.add(with: appInfo(identifier: "com.example.a", name: "A"))

                expect(service.applications.count) == 1
            }

            // 識別子が同じでも表示名が違えば別物として扱う（CPYAppInfo の等価判定に従う）
            it("識別子が同じでも名前が違えば別のアプリとして扱う") {
                let service = ExcludeAppService(applications: [])
                service.add(with: appInfo(identifier: "com.example.a", name: "A"))
                service.add(with: appInfo(identifier: "com.example.a", name: "A (Beta)"))

                expect(service.applications.count) == 2
            }

            it("削除するとリストから消える") {
                let target = appInfo(identifier: "com.example.a", name: "A")
                let service = ExcludeAppService(applications: [
                    target, appInfo(identifier: "com.example.b", name: "B")
                ])
                service.delete(with: target)

                expect(service.applications.map { $0.identifier }) == ["com.example.b"]
            }

            it("添字でも削除できる") {
                let service = ExcludeAppService(applications: [
                    appInfo(identifier: "com.example.a", name: "A"),
                    appInfo(identifier: "com.example.b", name: "B")
                ])
                service.delete(with: 0)

                expect(service.applications.map { $0.identifier }) == ["com.example.b"]
            }
        }
    }

    // MARK: - CPYAppInfo

    /// 除外判定は `CPYAppInfo` の等価判定に乗っているので、そこも押さえておく
    private static func appInfoSpecs() {
        describe("CPYAppInfo") {

            it("識別子と名前が同じなら等しい") {
                expect(appInfo(identifier: "com.example.a", name: "A"))
                    == appInfo(identifier: "com.example.a", name: "A")
            }

            it("識別子が違えば等しくない") {
                expect(appInfo(identifier: "com.example.a", name: "A"))
                    != appInfo(identifier: "com.example.b", name: "A")
            }

            // 実行ファイル名しか持たない Info.plist からも作れる必要がある
            it("CFBundleName が無ければ CFBundleExecutable で代替する") {
                let info: [String: AnyObject] = [
                    kCFBundleIdentifierKey as String: "com.example.a" as AnyObject,
                    kCFBundleExecutableKey as String: "ExecName" as AnyObject
                ]
                expect(CPYAppInfo(info: info)?.name) == "ExecName"
            }

            it("識別子が無ければ生成できない") {
                let info: [String: AnyObject] = [kCFBundleNameKey as String: "A" as AnyObject]
                expect(CPYAppInfo(info: info)) == nil
            }

            // 除外リストは NSKeyedArchiver で永続化されるため、往復できること
            it("アーカイブして復元できる") {
                let original = appInfo(identifier: "com.example.a", name: "A")
                let data = try? NSKeyedArchiver.archivedData(withRootObject: original,
                                                             requiringSecureCoding: false)
                guard let data = data else { return fail("アーカイブに失敗") }
                let restored = (try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(data)) as? CPYAppInfo
                expect(restored?.identifier) == "com.example.a"
                expect(restored?.name) == "A"
            }
        }
    }
}
