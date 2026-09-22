import Foundation
import Cocoa
import Quick
import Nimble
@testable import Thoth

// 履歴のサムネイル（ClipThumbnail）。
//
// v1.4.x までは「縮小」しているつもりで元の解像度の画像がそのまま平文のキャッシュに
// 残っていた。ここでは**実際に画素数が減っていること**と、保存層に入れて取り出せること、
// 移行後に .data から作り直せること、旧キャッシュを消せることを確かめる。
class ClipThumbnailSpec: QuickSpec {

    /// 指定した画素数の単色画像（表示サイズは画素数と同じにしておく）
    static func makeImage(pixelsWide: Int, pixelsHigh: Int, color: NSColor = .red) -> NSImage {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixelsWide, pixelsHigh: pixelsHigh,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                      colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        color.setFill()
        NSRect(x: 0, y: 0, width: pixelsWide, height: pixelsHigh).fill()
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: NSSize(width: pixelsWide, height: pixelsHigh))
        image.addRepresentation(bitmap)
        return image
    }

    static func pixelSize(ofPNG data: Data) -> (width: Int, height: Int)? {
        guard let bitmap = NSBitmapImageRep(data: data) else { return nil }
        return (bitmap.pixelsWide, bitmap.pixelsHigh)
    }

    override class func spec() {
        renderSpecs()
        storeSpecs()
        regenerateSpecs()
        legacyCacheSpecs()
    }

    // MARK: - Render

    private static func renderSpecs() {
        describe("縮小") {
            it("表示サイズの 2 倍の画素に描き直す（元の解像度のままにしない）") {
                let original = makeImage(pixelsWide: 3_000, pixelsHigh: 2_000)
                guard let png = ClipThumbnail.render(original, pointSize: NSSize(width: 100, height: 32)),
                      let size = pixelSize(ofPNG: png) else {
                    fail("PNG を作れない")
                    return
                }
                expect(size.width) == 200
                expect(size.height) == 64
                // 元画像（3000x2000）をそのまま持つより桁違いに小さい
                expect(png.count) < 50_000
            }

            it("PNG から作った画像の表示サイズは、画素数の半分になる") {
                guard let png = ClipThumbnail.render(makeImage(pixelsWide: 400, pixelsHigh: 400),
                                                     pointSize: NSSize(width: 50, height: 50)),
                      let image = ClipThumbnail.image(fromPNG: png) else {
                    fail("PNG を作れない")
                    return
                }
                expect(image.size) == NSSize(width: 50, height: 50)
            }

            it("カラーコードのクリップはカラープレビューを PNG にする") {
                let data = CPYClipData(image: makeImage(pixelsWide: 10, pixelsHigh: 10))
                expect(ClipThumbnail.pngData(for: data)) != nil
            }
        }
    }

    // MARK: - Store

    private static func storeSpecs() {
        describe("保存層とのやり取り") {
            func makeStore() -> HistoryStore {
                guard let cipher = FieldCipher(rootKey: Data((1...32).map { UInt8($0) })),
                      let library = try? SwiftDataLibrary.inMemory(cipher: cipher) else {
                    fatalError("保存層を作れない（前提が崩れている）")
                }
                return SwiftDataHistoryStore(library: library)
            }

            it("サムネイル付きで保存すると、同じ PNG が取り出せる") {
                let store = makeStore()
                guard let png = ClipThumbnail.render(makeImage(pixelsWide: 100, pixelsHigh: 100),
                                                     pointSize: NSSize(width: 20, height: 20)) else {
                    fail("PNG を作れない")
                    return
                }
                store.upsert(LibraryStoreContract.clip("c1", time: 1), thumbnail: png)
                expect(store.thumbnail(forClipID: "c1")) == png
                expect(store.clip(id: "c1")?.hasThumbnail) == true
            }

            it("サムネイル無しで保存し直すと、サムネイルは消える") {
                let store = makeStore()
                let png = ClipThumbnail.render(makeImage(pixelsWide: 10, pixelsHigh: 10), pointSize: NSSize(width: 5, height: 5))
                store.upsert(LibraryStoreContract.clip("c1", time: 1), thumbnail: png)
                store.upsert(LibraryStoreContract.clip("c1", time: 2), thumbnail: nil)
                expect(store.thumbnail(forClipID: "c1")) == nil
                expect(store.clip(id: "c1")?.hasThumbnail) == false
            }

            it("履歴を削除すると、サムネイルも消える") {
                let store = makeStore()
                let png = ClipThumbnail.render(makeImage(pixelsWide: 10, pixelsHigh: 10), pointSize: NSSize(width: 5, height: 5))
                store.upsert(LibraryStoreContract.clip("c1", time: 1), thumbnail: png)
                store.deleteClip(id: "c1")
                expect(store.thumbnail(forClipID: "c1")) == nil
            }
        }
    }

    // MARK: - Regenerate

    private static func regenerateSpecs() {
        describe("移行後の作り直し") {
            var directory: URL!
            var dataStore: ClipDataStore!
            var store: HistoryStore!

            beforeEach {
                directory = FileManager.default.temporaryDirectory.appendingPathComponent("ThothThumb-\(UUID().uuidString)")
                try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                dataStore = ClipDataStore(key: Data(repeating: 0x42, count: 32))
                guard let cipher = FieldCipher(rootKey: Data((1...32).map { UInt8($0) })),
                      let library = try? SwiftDataLibrary.inMemory(cipher: cipher) else {
                    fail("保存層を作れない（前提が崩れている）")
                    return
                }
                store = SwiftDataHistoryStore(library: library)
            }
            afterEach {
                try? FileManager.default.removeItem(at: directory)
            }

            /// .data ファイルを作って、その履歴を保存層に入れる
            func addClip(id: String, data: CPYClipData) -> Bool {
                let path = directory.appendingPathComponent("\(id).data").path
                guard let archived = try? NSKeyedArchiver.archivedData(withRootObject: data, requiringSecureCoding: false),
                      dataStore.write(archived, toPath: path) else { return false }
                store.upsert(ClipRecord(id: id, dataPath: path, title: "t", primaryType: "public.tiff",
                                        updateTime: 1, hasThumbnail: false, isColorCode: false))
                return true
            }

            it("画像クリップは .data から作り直され、サムネイルが付く") {
                guard addClip(id: "img", data: CPYClipData(image: makeImage(pixelsWide: 800, pixelsHigh: 600))) else {
                    fail(".data を用意できない（前提が崩れている）")
                    return
                }
                expect(ClipThumbnail.regenerate(clipIDs: ["img"], in: store, dataStore: dataStore)) == 1
                expect(store.clip(id: "img")?.hasThumbnail) == true
                guard let png = store.thumbnail(forClipID: "img"), let size = pixelSize(ofPNG: png) else {
                    fail("作り直したサムネイルが取り出せない")
                    return
                }
                // 元画像（800x600）より小さくなっている
                expect(size.width) <= 800
                expect(png.count) < 100_000
            }

            it(".data が無い履歴は飛ばし、サムネイルは付かない") {
                store.upsert(ClipRecord(id: "missing", dataPath: directory.appendingPathComponent("none.data").path,
                                        title: "t", primaryType: "public.tiff", updateTime: 1,
                                        hasThumbnail: false, isColorCode: false))
                expect(ClipThumbnail.regenerate(clipIDs: ["missing"], in: store, dataStore: dataStore)) == 0
                expect(store.clip(id: "missing")?.hasThumbnail) == false
            }
        }
    }

    // MARK: - Legacy Cache

    private static func legacyCacheSpecs() {
        describe("旧キャッシュの削除") {
            it("平文のサムネイルのキャッシュを消す（無ければ何もしない）") {
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ThothLegacy-\(UUID().uuidString)")
                try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                FileManager.default.createFile(atPath: directory.appendingPathComponent("1700000000").path,
                                               contents: Data("plaintext thumbnail".utf8))
                ClipThumbnail.removeLegacyCache(at: directory)
                expect(FileManager.default.fileExists(atPath: directory.path)) == false
                // 2 回目は何も起きない
                ClipThumbnail.removeLegacyCache(at: directory)
                expect(FileManager.default.fileExists(atPath: directory.path)) == false
            }
        }
    }
}
