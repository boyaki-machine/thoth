import Foundation
import Quick
import Nimble
import ServiceManagement
@testable import Thoth

// ログイン項目の同期で「何をするか」の判定（純粋関数）だけを確かめる。
//
// 実際の register / unregister はテストホストのアプリを本当にログイン項目へ
// 登録してしまうため、ここでは呼ばない。
class LoginItemServiceSpec: QuickSpec {

    override class func spec() {
        describe("設定値と登録状態から操作を決める") {
            it("オンにしたいとき、未登録なら登録する") {
                expect(LoginItemService.action(desired: true, status: .notRegistered)) == .register
                expect(LoginItemService.action(desired: true, status: .notFound)) == .register
            }

            // 起動のたびに解除 → 再登録していた（LoginServiceKit 時代の流儀）のをやめた
            it("オンにしたいとき、登録済みなら何もしない") {
                expect(LoginItemService.action(desired: true, status: .enabled)) == LoginItemService.Action.none
            }

            it("オンにしたいとき、システム設定で利用者がオフにしていれば上書きしない") {
                expect(LoginItemService.action(desired: true, status: .requiresApproval)) == LoginItemService.Action.none
            }

            it("オフにしたいとき、登録が残っていれば解除する") {
                expect(LoginItemService.action(desired: false, status: .enabled)) == .unregister
                expect(LoginItemService.action(desired: false, status: .requiresApproval)) == .unregister
            }

            it("オフにしたいとき、未登録なら何もしない") {
                expect(LoginItemService.action(desired: false, status: .notRegistered)) == LoginItemService.Action.none
                expect(LoginItemService.action(desired: false, status: .notFound)) == LoginItemService.Action.none
            }
        }
    }
}
