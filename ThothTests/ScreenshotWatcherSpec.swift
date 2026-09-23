import Quick
import Nimble
import AppKit
import CoreServices
@testable import Thoth

/// スクリーンショット監視（ベータ機能）のスペック。
/// Spotlight の索引を待たずに、保存先フォルダの変化と拡張属性で取り込むことを固定する。
/// 実際の保存先には触れず、テストごとの一時フォルダを見張らせる
class ScreenshotWatcherSpec: QuickSpec {

    override class func spec() {
        decisionSpecs()
        watchingSpecs()
    }

    // MARK: - 判定（純粋関数）
    private static func decisionSpecs() {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        let desktop = home.appendingPathComponent("Desktop", isDirectory: true)

        describe("保存先の決定") {
            it("~ で始まる設定はホームからのパスとして展開する（例: ~/Desktop/Screen-Shot）") {
                let url = ScreenshotWatcher.screenshotDirectory(location: "~/Desktop/Screen-Shot", homeDirectory: home) { _ in true }
                expect(url.path) == "/Users/tester/Desktop/Screen-Shot"
            }

            it("絶対パスはそのまま使う") {
                let url = ScreenshotWatcher.screenshotDirectory(location: "/Volumes/Data/Shots", homeDirectory: home) { _ in true }
                expect(url.path) == "/Volumes/Data/Shots"
            }

            it("未設定・空・相対パス・存在しないフォルダならデスクトップ") {
                expect(ScreenshotWatcher.screenshotDirectory(location: nil, homeDirectory: home) { _ in true }) == desktop
                expect(ScreenshotWatcher.screenshotDirectory(location: "  ", homeDirectory: home) { _ in true }) == desktop
                expect(ScreenshotWatcher.screenshotDirectory(location: "Shots", homeDirectory: home) { _ in true }) == desktop
                expect(ScreenshotWatcher.screenshotDirectory(location: "/nowhere", homeDirectory: home) { _ in false }) == desktop
            }
        }

        describe("ファイルの判定") {
            it("画像の拡張子で、隠しファイルでないものだけを候補にする") {
                expect(ScreenshotWatcher.isCandidateFileName("スクリーンショット 2026-09-23 1.23.45.png")) == true
                expect(ScreenshotWatcher.isCandidateFileName("Screenshot.JPG")) == true
                expect(ScreenshotWatcher.isCandidateFileName("Screenshot.heic")) == true
                expect(ScreenshotWatcher.isCandidateFileName(".スクリーンショット 2026-09-23 1.23.45.png")) == false
                expect(ScreenshotWatcher.isCandidateFileName("memo.txt")) == false
                expect(ScreenshotWatcher.isCandidateFileName("Screen Recording.mov")) == false
            }

            it("拡張属性 kMDItemIsScreenCapture が真ならスクリーンショット") {
                let trueValue = try? PropertyListSerialization.data(fromPropertyList: true, format: .binary, options: 0)
                let falseValue = try? PropertyListSerialization.data(fromPropertyList: false, format: .binary, options: 0)
                expect(ScreenshotWatcher.isScreenCapture(attributeValue: trueValue)) == true
                expect(ScreenshotWatcher.isScreenCapture(attributeValue: falseValue)) == false
                expect(ScreenshotWatcher.isScreenCapture(attributeValue: nil)) == false
                // 形式が読めなくても、属性が付いていればスクリーンショットとみなす
                expect(ScreenshotWatcher.isScreenCapture(attributeValue: Data([0x01]))) == true
            }

            it("監視を始める前に作られたファイルは取り込まない（許容幅 2 秒）") {
                let startedAt = Date(timeIntervalSince1970: 1_000_000)
                expect(ScreenshotWatcher.isRecent(creationDate: startedAt.addingTimeInterval(5), startedAt: startedAt)) == true
                expect(ScreenshotWatcher.isRecent(creationDate: startedAt.addingTimeInterval(-1), startedAt: startedAt)) == true
                expect(ScreenshotWatcher.isRecent(creationDate: startedAt.addingTimeInterval(-60), startedAt: startedAt)) == false
                expect(ScreenshotWatcher.isRecent(creationDate: nil, startedAt: startedAt)) == false
            }

            it("ファイルの作成・改名・変更・属性の付与を見て、フォルダの変化は見ない") {
                let file = FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsFile)
                expect(ScreenshotWatcher.isRelevantEvent(file | FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated))) == true
                expect(ScreenshotWatcher.isRelevantEvent(file | FSEventStreamEventFlags(kFSEventStreamEventFlagItemRenamed))) == true
                expect(ScreenshotWatcher.isRelevantEvent(file | FSEventStreamEventFlags(kFSEventStreamEventFlagItemXattrMod))) == true
                expect(ScreenshotWatcher.isRelevantEvent(file | FSEventStreamEventFlags(kFSEventStreamEventFlagItemRemoved))) == false
                expect(ScreenshotWatcher.isRelevantEvent(FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsDir | kFSEventStreamEventFlagItemCreated))) == false
            }
        }
    }

    // MARK: - 実際のフォルダを見張る
    private static func watchingSpecs() {
        describe("保存先フォルダの監視") {
            var directory: URL!
            var watcher: ScreenshotWatcher!
            var captured: [NSImage] = []

            beforeEach {
                directory = FileManager.default.temporaryDirectory
                    .appendingPathComponent("ThothScreenshotSpec-\(UUID().uuidString)", isDirectory: true)
                try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                captured = []
                watcher = ScreenshotWatcher()
                let watched = directory!
                watcher.directoryProvider = { watched }
                watcher.onCapture = { captured.append($0) }
                watcher.start()
            }
            afterEach {
                watcher.stop()
                watcher = nil
                try? FileManager.default.removeItem(at: directory)
            }

            it("一時ファイルから改名されたスクリーンショットを、Spotlight を待たずに 1 回だけ取り込む") {
                let temporary = directory.appendingPathComponent(".スクリーンショット 1.png")
                writePNG(to: temporary, markAsScreenshot: true)
                try? FileManager.default.moveItem(at: temporary, to: directory.appendingPathComponent("スクリーンショット 1.png"))
                expect(captured.count).toEventually(equal(1), timeout: .seconds(3))
                expect(captured.first?.size.width) == 8
                // 属性の付け直し・改名などで何度通知が来ても、同じファイルは 1 回だけ
                let final = directory.appendingPathComponent("スクリーンショット 1.png")
                markAsScreenshot(final)
                try? FileManager.default.moveItem(at: final, to: directory.appendingPathComponent("スクリーンショット 1 (改名).png"))
                expect(captured.count).toNever(beGreaterThan(1), until: .seconds(1))
            }

            it("スクリーンショットの印が無い画像は取り込まない") {
                writePNG(to: directory.appendingPathComponent("photo.png"), markAsScreenshot: false)
                expect(captured.count).toNever(beGreaterThan(0), until: .seconds(1))
            }

            it("書き込み途中の画像は取り込まず、書き終わってから取り込む") {
                let url = directory.appendingPathComponent("スクリーンショット 2.png")
                let data = pngData()
                // 前半だけ書いて印を付ける（この時点では取り込まない）→ 残りを書く
                FileManager.default.createFile(atPath: url.path, contents: data.prefix(data.count / 2))
                markAsScreenshot(url)
                expect(captured.count).toNever(beGreaterThan(0), until: .milliseconds(700))
                if let handle = try? FileHandle(forWritingTo: url) {
                    handle.seekToEndOfFile()
                    handle.write(data.suffix(from: data.count / 2))
                    try? handle.close()
                }
                expect(captured.count).toEventually(equal(1), timeout: .seconds(4))
                expect(captured.first?.size.width) == 8
            }

            it("止めた後は取り込まない") {
                watcher.stop()
                writePNG(to: directory.appendingPathComponent("スクリーンショット 3.png"), markAsScreenshot: true)
                expect(captured.count).toNever(beGreaterThan(0), until: .seconds(1))
            }
        }
    }

    // MARK: - Helpers
    private static func pngData() -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        return rep?.representation(using: .png, properties: [:]) ?? Data()
    }

    private static func markAsScreenshot(_ url: URL) {
        guard let value = try? PropertyListSerialization.data(fromPropertyList: true, format: .binary, options: 0) else { return }
        _ = value.withUnsafeBytes {
            setxattr(url.path, ScreenshotWatcher.screenCaptureAttribute, $0.baseAddress, value.count, 0, 0)
        }
    }

    private static func writePNG(to url: URL, markAsScreenshot mark: Bool) {
        FileManager.default.createFile(atPath: url.path, contents: pngData())
        if mark { markAsScreenshot(url) }
    }
}
