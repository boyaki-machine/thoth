import AppKit
import Nimble
import Quick
@testable import Thoth

/// CPYClipData を装って、許可していないクラスをアーカイブに紛れ込ませるテスト用の型
final class PlantedClip: NSObject, NSCoding {
    override init() { super.init() }
    required init?(coder: NSCoder) { super.init() }

    func encode(with coder: NSCoder) {
        coder.encode(["public.utf8-plain-text"], forKey: "types")
        coder.encode("planted", forKey: "stringValue")
        coder.encode(NSURLRequest(url: URL(string: "https://example.com")!), forKey: "planted")
    }
}

/// コードレビューで見つかった不具合の回帰テスト。
/// どれも「修正を戻すと落ちる」ことを確かめてある
class ReliabilityFixesSpec: QuickSpec {

    override class func spec() {
        totpSpecs()
        clipHashSpecs()
        legacyArchiveSpecs()
        dataCleanSpecs()
        concealedPasteSpecs()
        pasteAndDeleteSpecs()
        fieldHistorySpecs()
        secureHotKeySpecs()
        pickerPanelSpecs()
        pickerGeometrySpecs()
        miscSpecs()
    }

    // MARK: - Fixtures

    static func makeWorkDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("thoth-reliability-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// 寸法が同じで色だけが違う画像
    static func solidImage(_ color: NSColor, size: NSSize = NSSize(width: 64, height: 64)) -> NSImage {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                      colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        color.setFill()
        NSRect(origin: .zero, size: size).fill()
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: size)
        image.addRepresentation(bitmap)
        return image
    }

    static func archive(_ data: CPYClipData) -> Data {
        return try! NSKeyedArchiver.archivedData(withRootObject: data, requiringSecureCoding: false)
    }

    // MARK: - TOTP

    static func totpSpecs() {
        describe("TOTP の入力の境界") {
            it("digits=10 の otpauth でもクラッシュせず 10 桁を返す（10^10 は UInt32 に入らない）") {
                let params = TOTPService.parse("otpauth://totp/a?secret=GEZDGNBVGY3TQOJQ&digits=10")
                expect(params?.digits) == 10
                let code = params.flatMap { TOTPService().code(for: $0, at: Date(timeIntervalSince1970: 59)) }
                expect(code?.count) == 10
            }

            it("ラベルを二重にデコードしない（%25 は % のまま）") {
                let params = TOTPService.parse("otpauth://totp/100%2541:me?secret=GEZDGNBV")
                expect(params?.issuer) == "100%41"
            }
        }
    }

    // MARK: - Clip hash

    static func clipHashSpecs() {
        describe("クリップの内容ハッシュ") {
            it("寸法が同じ別の画像は別の履歴になる") {
                expect(CPYClipData(image: solidImage(.red)).hash) != CPYClipData(image: solidImage(.blue)).hash
            }

            it("同じ画像は同じ履歴になる") {
                let image = solidImage(.green)
                expect(CPYClipData(image: image).hash) == CPYClipData(image: image).hash
            }

            it("貼り付けで書き戻した画像を取り込み直しても同じ履歴になる（貼り付けのたびに増えない）") {
                let original = CPYClipData(image: solidImage(.orange))
                let tiff = original.image!.tiffRepresentation!
                let reloaded = CPYClipData(image: NSImage(data: tiff)!)
                expect(reloaded.hash) == original.hash
            }

            it("半透明の画像でも、貼り付けで書き戻したものは同じ履歴になる") {
                let original = CPYClipData(image: solidImage(NSColor.red.withAlphaComponent(0.5)))
                let reloaded = CPYClipData(image: NSImage(data: original.image!.tiffRepresentation!)!)
                expect(reloaded.hash) == original.hash
            }
        }

        describe("RTF の型へ書き込むデータ") {
            let attributed = NSAttributedString(string: "styled")
            let range = NSRange(location: 0, length: attributed.length)

            it("RTFD のバイト列は RTF に変換する") {
                let data = CPYClipData(image: solidImage(.red))
                data.RTFData = attributed.rtfd(from: range, documentAttributes: [:])
                expect(data.rtfDataForPasteboard?.starts(with: Data("{\\rtf".utf8))) == true
            }

            it("RTF はそのまま返す") {
                let data = CPYClipData(image: solidImage(.red))
                let rtf = attributed.rtf(from: range, documentAttributes: [:])
                data.RTFData = rtf
                expect(data.rtfDataForPasteboard) == rtf
            }
        }
    }

    // MARK: - Legacy archive

    static func legacyArchiveSpecs() {
        describe("平文の .data の読み込み") {
            let key = Data(repeating: 9, count: 32)
            var directory: URL!

            beforeEach { directory = makeWorkDirectory() }
            afterEach { try? FileManager.default.removeItem(at: directory) }

            /// ルートは CPYClipData として読めるが、許可していないクラス（NSURLRequest）を含むアーカイブ
            func plantedArchive() -> Data {
                let archiver = NSKeyedArchiver(requiringSecureCoding: false)
                archiver.setClassName(NSStringFromClass(CPYClipData.self), for: PlantedClip.self)
                archiver.encode(PlantedClip(), forKey: NSKeyedArchiveRootObjectKey)
                archiver.finishEncoding()
                return archiver.encodedData
            }

            it("正規の文字列クリップを読める") {
                let clip = CPYClipData(image: solidImage(.red))
                clip.image = nil
                clip.types = [.deprecatedString]
                clip.stringValue = "legacy text"
                let url = directory.appendingPathComponent("a.data")
                try! archive(clip).write(to: url)

                expect(ClipDataStore(key: key).readClip(fromPath: url.path)?.stringValue) == "legacy text"
            }

            it("正規の画像クリップを読める（許可リストが画像の表現を含む）") {
                let url = directory.appendingPathComponent("a.data")
                try! archive(CPYClipData(image: solidImage(.red))).write(to: url)
                expect(ClipDataStore(key: key).readClip(fromPath: url.path)?.image) != nil
            }

            it("暗号化形式の画像クリップも読める") {
                let store = ClipDataStore(key: key)
                let path = directory.appendingPathComponent("a.data").path
                expect(store.write(archive(CPYClipData(image: solidImage(.blue))), toPath: path)) == true
                expect(store.readClip(fromPath: path)?.image) != nil
            }

            it("許可していないクラスを含む平文ファイルは読まない") {
                let url = directory.appendingPathComponent("planted.data")
                try! plantedArchive().write(to: url)
                expect(ClipDataStore(key: key).readClip(fromPath: url.path)) == nil
            }

            it("許可していないクラスを含むファイルを暗号化して正規のデータにしない") {
                let url = directory.appendingPathComponent("planted.data")
                let planted = plantedArchive()
                try! planted.write(to: url)
                ClipDataStore(key: key).encryptPlaintextFiles(inDirectory: directory.path)
                expect(try? Data(contentsOf: url)) == planted
            }
        }
    }

    // MARK: - Data clean

    static func dataCleanSpecs() {
        describe("孤児ファイルの掃除") {
            var directory: URL!

            beforeEach { directory = makeWorkDirectory() }
            afterEach { try? FileManager.default.removeItem(at: directory) }

            it("参照されていない .data だけを対象にする") {
                let orphans = DataCleanService.orphanDataFileNames(fileNames: ["a.data", "b.data", "notes.txt", ".DS_Store"],
                                                                   referencedPaths: ["/x/a.data", "/x/missing.data"])
                expect(orphans) == ["b.data"]
            }

            it("保存層が使えない起動中は、ディスクの .data を消さない") {
                let file = directory.appendingPathComponent("existing.data")
                try! Data("clip".utf8).write(to: file)
                AppEnvironment.push(isLibraryUsable: false)
                defer { AppEnvironment.popLast() }

                DataCleanService().cleanDatasNow(directory: directory.path)

                expect(FileManager.default.fileExists(atPath: file.path)) == true
            }

            it("保存層が使えるときは孤児を消す") {
                let file = directory.appendingPathComponent("orphan.data")
                try! Data("clip".utf8).write(to: file)
                AppEnvironment.push(isLibraryUsable: true)
                defer { AppEnvironment.popLast() }

                DataCleanService().cleanDatasNow(directory: directory.path)

                expect(FileManager.default.fileExists(atPath: file.path)) == false
            }
        }
    }

    // MARK: - Concealed paste

    static func concealedPasteSpecs() {
        describe("秘匿値の連続貼り付け") {
            var pasteboard: NSPasteboard!

            beforeEach {
                pasteboard = NSPasteboard(name: NSPasteboard.Name("io.github.boyaki-machine.ThothTests.\(UUID().uuidString)"))
                pasteboard.clearContents()
            }
            afterEach { pasteboard.releaseGlobally() }

            func writeConcealed(_ string: String) {
                pasteboard.declareTypes([.string, Constants.Pasteboard.concealedType, Constants.Pasteboard.transientType], owner: nil)
                pasteboard.setString(string, forType: .string)
                pasteboard.setString("", forType: Constants.Pasteboard.concealedType)
                pasteboard.setString("", forType: Constants.Pasteboard.transientType)
            }

            it("前の貼り付けを戻す前に次を選んでも、最後は元の内容へ戻る（秘匿値を残さない）") {
                let service = PasteService()
                pasteboard.declareTypes([.string], owner: nil)
                pasteboard.setString("元の内容", forType: .string)

                let first = service.snapshotBeforeConcealedWrite(of: pasteboard)
                writeConcealed("user-id")
                let firstCount = pasteboard.changeCount
                service.noteConcealedWrite(snapshot: first, writtenChangeCount: firstCount)

                let second = service.snapshotBeforeConcealedWrite(of: pasteboard)
                writeConcealed("password")
                let secondCount = pasteboard.changeCount
                service.noteConcealedWrite(snapshot: second, writtenChangeCount: secondCount)

                var restored: Bool?
                service.restorePasteboard(second, to: pasteboard, ifUnchangedSince: secondCount, after: 0.01) { restored = $0 }
                expect(restored).toEventually(equal(true))
                expect(pasteboard.string(forType: .string)) == "元の内容"
            }

            it("他のアプリがコピーした秘匿値は書き戻さない") {
                writeConcealed("other-manager-secret")
                let snapshot = PasteService().snapshotBeforeConcealedWrite(of: pasteboard)
                expect(snapshot.isEmpty) == true
            }

            it("別のコピーを挟んだあとは、その時点の内容を控える") {
                let service = PasteService()
                pasteboard.declareTypes([.string], owner: nil)
                pasteboard.setString("元の内容", forType: .string)
                let first = service.snapshotBeforeConcealedWrite(of: pasteboard)
                writeConcealed("secret")
                service.noteConcealedWrite(snapshot: first, writtenChangeCount: pasteboard.changeCount)

                pasteboard.declareTypes([.string], owner: nil)
                pasteboard.setString("新しいコピー", forType: .string)
                let second = service.snapshotBeforeConcealedWrite(of: pasteboard)
                writeConcealed("secret2")
                second.restore(to: pasteboard)

                expect(pasteboard.string(forType: .string)) == "新しいコピー"
            }
        }
    }

    // MARK: - Paste and delete

    static func pasteAndDeleteSpecs() {
        describe("貼り付けて履歴から消す") {
            it("データを読めなかったときは、次のコピーを無視する印を付けない") {
                let clipService = ClipService()
                let clip = ClipRecord(id: "missing", dataPath: "/nonexistent/\(UUID().uuidString).data", title: "t",
                                      primaryType: "", updateTime: 0, hasThumbnail: false, isColorCode: false)
                AppEnvironment.push(clipService: clipService)
                defer { AppEnvironment.popLast() }
                let before = clipService.cachedChangeCountForTesting

                PasteService().paste(with: clip, actions: PasteService.PasteActions(pasteAndDelete: true))

                expect(clipService.cachedChangeCountForTesting).toNever(equal(before + 1), until: .milliseconds(300))
            }
        }
    }

    // MARK: - Field history

    static func fieldHistorySpecs() {
        describe("値の変更履歴の対応付け") {
            let service = SecureMenuService(keychainService: "io.github.boyaki-machine.ThothTests.ReliabilityFixes")

            beforeEach { service.deleteAllItems() }
            afterEach { service.deleteAllItems() }

            it("既存と同じ Label のフィールドを追加しても、別のフィールドの旧値を履歴に入れない") {
                let existing = SecureMenuItem.Field(label: "Password", value: "old-secret")
                let item = SecureMenuItem(title: "A", fields: [existing])
                expect(service.save(item)) == true

                var updated = item
                updated.fields.append(SecureMenuItem.Field(label: "Password", value: "another"))
                expect(service.save(updated)) == true

                let added = service.loadAllItems().first?.fields.last
                expect(added?.value) == "another"
                expect(added?.history.isEmpty) == true
            }

            it("fieldID を持たないデータの移行では Label で履歴を引き継ぐ") {
                let item = SecureMenuItem(title: "A", fields: [SecureMenuItem.Field(label: "Password", value: "old")])
                expect(service.save(item)) == true

                let migrated = SecureMenuItem(itemID: item.itemID, title: "A",
                                              fields: [SecureMenuItem.Field(label: "Password", value: "new")])
                expect(service.save(migrated)) == true

                expect(service.loadAllItems().first?.fields.first?.history.map(\.value)) == ["old"]
            }
        }
    }

    // MARK: - Secure hot key

    static func secureHotKeySpecs() {
        describe("セキュアメニューのホットキー") {
            it("認証の結果待ちの間は何もしない（確認ダイアログとパネルを二重にしない）") {
                expect(MenuManager.secureHotKeyAction(isActive: true, isPanelVisible: false, isAuthenticating: true)) == .ignore
            }

            it("パネルが表示中なら前面に戻す") {
                expect(MenuManager.secureHotKeyAction(isActive: true, isPanelVisible: true, isAuthenticating: false)) == .reactivatePanel
            }

            it("パネルが消えて状態だけ残っていれば片付ける") {
                expect(MenuManager.secureHotKeyAction(isActive: true, isPanelVisible: false, isAuthenticating: false)) == .resetStaleState
            }

            it("何も表示していなければ認証する") {
                expect(MenuManager.secureHotKeyAction(isActive: false, isPanelVisible: false, isAuthenticating: false)) == .authenticate
            }
        }
    }
}
