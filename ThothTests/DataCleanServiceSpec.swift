import Quick
import Nimble
@testable import Thoth

// 履歴の上限超過で消す範囲の判定（DataCleanService.overflowCutoff、純粋関数）。
// 境界の時刻より古い履歴だけを消すので、上限件目と同じ時刻の履歴は残る。
class DataCleanServiceSpec: QuickSpec {
    override class func spec() {
        describe("上限を超えた履歴の境界") {
            it("件数が上限以下なら、何も消さない") {
                expect(DataCleanService.overflowCutoff(updateTimesNewestFirst: [30, 20, 10], maxHistorySize: 3)) == nil
                expect(DataCleanService.overflowCutoff(updateTimesNewestFirst: [], maxHistorySize: 3)) == nil
            }

            it("上限を超えると、上限件目の時刻を境界にする（それより古いものを消す）") {
                expect(DataCleanService.overflowCutoff(updateTimesNewestFirst: [50, 40, 30, 20, 10], maxHistorySize: 2)) == 40
            }

            it("上限件目と同じ時刻の履歴があっても、境界はその時刻のまま（同じ時刻のものは残る）") {
                expect(DataCleanService.overflowCutoff(updateTimesNewestFirst: [30, 20, 20, 10], maxHistorySize: 2)) == 20
            }

            // 以前は上限 0 で履歴があると配列の範囲外を読んで落ちていた
            it("上限が 0 以下なら、何も消さず落ちもしない") {
                expect(DataCleanService.overflowCutoff(updateTimesNewestFirst: [30, 20], maxHistorySize: 0)) == nil
                expect(DataCleanService.overflowCutoff(updateTimesNewestFirst: [30, 20], maxHistorySize: -1)) == nil
            }
        }
    }
}
