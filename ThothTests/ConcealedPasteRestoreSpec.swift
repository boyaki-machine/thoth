import Quick
import Nimble
import AppKit
@testable import Thoth

/// セキュアアイテムを貼り付けた後、クリップボードを書き込む前の内容へ戻す処理のスペック。
/// 秘匿値がクリップボードに残り続けて ⌘V でもう一度貼り付けられてしまう不具合の回帰防止。
/// 実クリップボードは使わず、テストごとに専用のペーストボードを作る
class ConcealedPasteRestoreSpec: QuickSpec {

    override class func spec() {
        var pasteboard: NSPasteboard!

        beforeEach {
            pasteboard = NSPasteboard(name: NSPasteboard.Name("io.github.boyaki-machine.ThothTests.\(UUID().uuidString)"))
            pasteboard.clearContents()
        }
        afterEach {
            pasteboard.releaseGlobally()
        }

        func writeConcealed(_ string: String) {
            pasteboard.declareTypes([.string, Constants.Pasteboard.concealedType, Constants.Pasteboard.transientType], owner: nil)
            pasteboard.setString(string, forType: .string)
            pasteboard.setString("", forType: Constants.Pasteboard.concealedType)
            pasteboard.setString("", forType: Constants.Pasteboard.transientType)
        }

        describe("PasteboardSnapshot") {
            it("複数のアイテムと型の並びを保って控え、元どおりに戻す") {
                let first = NSPasteboardItem()
                first.setString("<b>hello</b>", forType: .html)
                first.setString("hello", forType: .string)
                let second = NSPasteboardItem()
                second.setString("https://example.com", forType: .URL)
                pasteboard.writeObjects([first, second])

                let snapshot = PasteboardSnapshot(pasteboard: pasteboard)
                writeConcealed("s3cr3t")
                snapshot.restore(to: pasteboard)

                let items = pasteboard.pasteboardItems ?? []
                expect(items.count) == 2
                expect(items.first?.types.first) == .html
                expect(items.first?.string(forType: .string)) == "hello"
                expect(items.last?.string(forType: .URL)) == "https://example.com"
                expect(pasteboard.types ?? []).toNot(contain(Constants.Pasteboard.concealedType))
            }

            it("空のクリップボードを控えた場合は、戻すと空になる（秘匿値を残さない）") {
                let snapshot = PasteboardSnapshot(pasteboard: pasteboard)
                expect(snapshot.isEmpty) == true
                writeConcealed("s3cr3t")
                snapshot.restore(to: pasteboard)
                expect(pasteboard.string(forType: .string)) == nil
                expect(pasteboard.pasteboardItems ?? []).to(beEmpty())
            }
        }

        describe("restorePasteboard") {
            it("貼り付け後、秘匿値を消して書き込む前の内容へ戻す") {
                pasteboard.declareTypes([.string], owner: nil)
                pasteboard.setString("元の内容", forType: .string)
                let snapshot = PasteboardSnapshot(pasteboard: pasteboard)
                writeConcealed("s3cr3t")

                var restored: Bool?
                PasteService().restorePasteboard(snapshot, to: pasteboard, ifUnchangedSince: pasteboard.changeCount,
                                                 after: 0.05) { restored = $0 }
                expect(restored).toEventually(equal(true))
                expect(pasteboard.string(forType: .string)) == "元の内容"
            }

            it("既定の待ち時間は 30 秒より十分短い（秘匿値を長く残さない）") {
                expect(PasteService.concealedPasteRestoreDelay) <= 5
                expect(PasteService.concealedPasteRestoreDelay) >= 1
            }

            it("その間に利用者が別の内容をコピーしていたら、上書きしない") {
                pasteboard.declareTypes([.string], owner: nil)
                pasteboard.setString("元の内容", forType: .string)
                let snapshot = PasteboardSnapshot(pasteboard: pasteboard)
                writeConcealed("s3cr3t")
                let writtenChangeCount = pasteboard.changeCount
                pasteboard.declareTypes([.string], owner: nil)
                pasteboard.setString("新しくコピーした内容", forType: .string)

                var restored: Bool?
                PasteService().restorePasteboard(snapshot, to: pasteboard, ifUnchangedSince: writtenChangeCount,
                                                 after: 0.05) { restored = $0 }
                expect(restored).toEventually(equal(false))
                expect(pasteboard.string(forType: .string)) == "新しくコピーした内容"
            }
        }
    }
}
