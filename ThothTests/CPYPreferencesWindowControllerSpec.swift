import Quick
import Nimble
@testable import Thoth

/// 設定ウィンドウの Esc 判定ロジックのスペック。
/// 実イベント配送（モニタ発火・ウィンドウが実際に閉じる）は自動化できないため、
/// 閉じる/閉じないの分岐を担う純粋関数だけを担保する
class CPYPreferencesWindowControllerSpec: QuickSpec {

    override class func spec() {
        describe("Esc で閉じる判定") {
            let escKeyCode: UInt16 = 53
            func shouldClose(_ keyCode: UInt16, recording: Bool) -> Bool {
                return CPYPreferencesWindowController.shouldCloseOnEsc(keyCode: keyCode, isRecordingShortcut: recording)
            }

            it("Esc かつショートカット非記録中なら閉じる") {
                expect(shouldClose(escKeyCode, recording: false)) == true
            }

            it("ショートカット記録中の Esc は閉じない（記録キャンセルを優先）") {
                expect(shouldClose(escKeyCode, recording: true)) == false
            }

            it("Esc 以外のキーでは閉じない") {
                // Return(36) / Space(49)
                expect(shouldClose(36, recording: false)) == false
                expect(shouldClose(49, recording: false)) == false
            }
        }
    }
}
