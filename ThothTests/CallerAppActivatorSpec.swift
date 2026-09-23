import Quick
import Nimble
import AppKit
@testable import Thoth

/// パネルで選んだ値を貼り付ける前に、貼り付け先のアプリを前面へ戻す処理のスペック。
/// 「ホットキーを押した時点のアプリへ戻す」「前面に来たのを確かめてから送る」を固定する
class CallerAppActivatorSpec: QuickSpec {

    override class func spec() {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        // 常に動いている別アプリ（貼り付け先の代わり）
        let otherApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first

        describe("戻す先の判定") {
            it("Thoth 自身・終了済みのアプリは戻す先にしない") {
                expect(CallerAppActivator.isReturnTarget(processIdentifier: ownPID, isTerminated: false)) == false
                expect(CallerAppActivator.isReturnTarget(processIdentifier: ownPID + 1, isTerminated: true)) == false
                expect(CallerAppActivator.isReturnTarget(processIdentifier: ownPID + 1, isTerminated: false)) == true
            }

            it("前面に来たかはプロセス ID で判定する") {
                expect(CallerAppActivator.isFrontmost(frontmostProcessIdentifier: 42, callerProcessIdentifier: 42)) == true
                expect(CallerAppActivator.isFrontmost(frontmostProcessIdentifier: ownPID, callerProcessIdentifier: 42)) == false
                expect(CallerAppActivator.isFrontmost(frontmostProcessIdentifier: nil, callerProcessIdentifier: 42)) == false
            }
        }

        describe("貼り付け先として覚えておくアプリ") {
            it("ホットキーを押した時点のアプリを、パネルを出す時点の最前面より優先する（認証ダイアログを挟んでも元のアプリへ戻す）") {
                guard let otherApp = otherApp else { fail("Dock が見つからない"); return }
                let target = CallerAppActivator.returnTarget(atHotKey: otherApp, atShow: NSRunningApplication.current)
                expect(target?.processIdentifier) == otherApp.processIdentifier
            }

            it("どちらも使えるアプリなら、ホットキーを押した時点のアプリを選ぶ") {
                guard let otherApp = otherApp,
                      let anotherApp = NSWorkspace.shared.runningApplications.first(where: {
                          $0.processIdentifier != ownPID && $0.processIdentifier != otherApp.processIdentifier && !$0.isTerminated
                      }) else { fail("別アプリが見つからない"); return }
                let target = CallerAppActivator.returnTarget(atHotKey: otherApp, atShow: anotherApp)
                expect(target?.processIdentifier) == otherApp.processIdentifier
            }

            it("ホットキーの時点が Thoth 自身なら、パネルを出す時点の最前面を使う") {
                guard let otherApp = otherApp else { fail("Dock が見つからない"); return }
                let target = CallerAppActivator.returnTarget(atHotKey: NSRunningApplication.current, atShow: otherApp)
                expect(target?.processIdentifier) == otherApp.processIdentifier
            }

            it("どちらも使えなければ戻す先は無い") {
                expect(CallerAppActivator.returnTarget(atHotKey: nil, atShow: NSRunningApplication.current)) == nil
                expect(CallerAppActivator.returnTarget(atHotKey: nil, atShow: nil)) == nil
            }
        }

        describe("前面化を待つ") {
            it("条件が満たされるまで確かめ続け、満たされたら true で知らせる") {
                var checks = 0
                var result: Bool?
                CallerAppActivator.waitUntil({ checks += 1; return checks >= 3 }, timeout: 2, interval: 0.01, completion: { result = $0 })
                expect(result).toEventually(equal(true))
                expect(checks) == 3
            }

            it("上限まで待っても満たされなければ false で知らせる（送らずに黙って終わらない）") {
                var result: Bool?
                let started = Date()
                CallerAppActivator.waitUntil({ false }, timeout: 0.1, interval: 0.01, completion: { result = $0 })
                expect(result).toEventually(equal(false))
                expect(Date().timeIntervalSince(started)) >= 0.1
            }

            it("戻す先が無いときも、少し待ってから送る") {
                var performed = false
                CallerAppActivator.activate(nil) { performed = true }
                expect(performed) == false
                expect(performed).toEventually(beTrue())
            }
        }
    }
}
