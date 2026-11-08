//
//  CPYClipData.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Econa77 on 2015/06/21.
//
//  Copyright © 2015-2018 Clipy Project.
//

import Cocoa
import CryptoKit
import SwiftHEXColors

/// クリップの実データ（全ペーストボード型の内容）を保持するシリアライズ用モデル。
/// NSKeyedArchiver でアーカイブして .data ファイルに保存される（NSCoding 準拠）。
///
/// 注意: 旧式 NSCoding（encodeWithCoder）のまま維持している。NSSecureCoding 化は
/// 既存の全履歴ファイルとの互換を壊すため行わず、改竄検知は保存側
/// （ClipDataStore の AES-GCM 認証タグ）が担う設計とする。
/// キー名（"types" 等）も保存済みデータとの互換のため変更してはならない。
final class CPYClipData: NSObject {

    // MARK: - Properties
    fileprivate let kTypesKey       = "types"
    fileprivate let kStringValueKey = "stringValue"
    fileprivate let kRTFDataKey     = "RTFData"
    fileprivate let kPDFKey         = "PDF"
    fileprivate let kFileNamesKey   = "filenames"
    fileprivate let kURLsKey        = "URL"
    fileprivate let kImageKey       = "image"

    var types          = [NSPasteboard.PasteboardType]()
    var fileNames      = [String]()
    var URLs           = [String]()
    var stringValue    = ""
    var RTFData: Data?
    var PDF: Data?
    var image: NSImage?

    // 画像クリップでは TIFF エンコードを伴う重い計算のため、初回算出後はキャッシュを返す
    // （プロパティは init 後に変化しないためキャッシュしても安全）
    fileprivate var cachedHash: Int?

    override var hash: Int {
        if let cachedHash = cachedHash { return cachedHash }
        var hash = types.map { $0.rawValue }.joined().hash
        // 画像・PDF・RTF は長さではなく中身で見分ける。無圧縮の TIFF は寸法だけで長さが決まるので、
        // 長さを使うと同じ寸法の別の画像（全画面のスクリーンショットなど）が同じ履歴として上書きされる
        if let image = self.image, let imageData = image.tiffRepresentation {
            hash ^= Self.pixelHash(ofTIFF: imageData)
        } else if let image = self.image {
            hash ^= image.hash
        }
        if !fileNames.isEmpty {
            fileNames.forEach { hash ^= $0.hash }
        } else if !self.URLs.isEmpty {
            URLs.forEach { hash ^= $0.hash }
        } else if let pdf = PDF {
            hash ^= Self.contentHash(of: pdf)
        } else if !stringValue.isEmpty {
            hash ^= stringValue.hash
        }
        if let data = RTFData {
            hash ^= Self.contentHash(of: data)
        }
        cachedHash = hash
        return hash
    }

    /// 起動をまたいでも同じ値になる、中身全体のハッシュ（`Data.hashValue` は起動ごとに変わる）
    private static func contentHash(of data: Data) -> Int {
        return SHA256.hash(data: data).withUnsafeBytes { $0.loadUnaligned(as: Int.self) }
    }

    /// 画像の画素から決まるハッシュ。
    /// TIFF はタグの違いで、書き戻して読み直すとバイト列が変わる。バイト列のままハッシュすると、
    /// 貼り付けで書き戻した画像を別の内容と判断して、貼り付けのたびに履歴が増えてしまう
    private static func pixelHash(ofTIFF tiff: Data) -> Int {
        guard let bitmap = NSBitmapImageRep(data: tiff), let samples = bitmap.bitmapData else { return contentHash(of: tiff) }
        return withExtendedLifetime(bitmap) {
            let pixels = Data(bytesNoCopy: samples, count: bitmap.bytesPerRow * bitmap.pixelsHigh, deallocator: .none)
            return contentHash(of: pixels) ^ (bitmap.pixelsWide &* 31 &+ bitmap.pixelsHigh)
        }
    }

    /// `.data` に含まれてよいクラス（`KeyedArchiveGuard` の許可リスト）。
    /// CPYClipData 自身と、保持するデータ・画像（NSImage の表現）のクラスだけ
    static var archiveClassNames: Set<String> {
        return [NSStringFromClass(CPYClipData.self), "NSData", "NSMutableData", "NSImage", "NSImageRep",
                "NSBitmapImageRep", "NSPDFImageRep", "NSCGImageSnapshotRep", "NSColor", "NSColorSpace", "NSValue", "NSNull"]
    }

    /// .data ファイルの中身（復号済みのアーカイブ）から読み戻す。
    /// requiresSecureCoding=false は、CPYClipData が旧式 NSCoding（NSImage 等を含む）で、
    /// SecureCoding 化すると既存の全履歴が読めなくなるため据え置き。
    /// **認証タグの無いデータをここへ直接渡さないこと**（`ClipDataStore.readClip` を通す）
    static func unarchived(from fileData: Data) -> CPYClipData? {
        guard let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: fileData) else { return nil }
        unarchiver.requiresSecureCoding = false
        return unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey) as? CPYClipData
    }

    var primaryType: NSPasteboard.PasteboardType? {
        return types.first
    }
    var isOnlyStringType: Bool {
        return types == [.deprecatedString]
    }
    var thumbnailImage: NSImage? {
        let defaults = UserDefaults.standard
        let width = defaults.integer(forKey: Constants.UserDefaults.thumbnailWidth)
        let height = defaults.integer(forKey: Constants.UserDefaults.thumbnailHeight)

        if let image = image, fileNames.isEmpty {
            // Image only data
            return image.resizeImage(CGFloat(width), CGFloat(height))
        } else if let fileName = fileNames.first {
             // In the case of the local file correct data is not included in the image variable
             // Judge the image from the path and create a thumbnail
            switch (fileName as NSString).pathExtension.lowercased() {
            case "jpg", "jpeg", "png", "bmp", "tiff":
                return NSImage(contentsOfFile: fileName)?.resizeImage(CGFloat(width), CGFloat(height))
            default: break
            }
        }
        return nil
    }
    /// RTF の型へ書き込むデータ。
    ///
    /// `RTFData` はコピー時に RTFD があれば RTFD のバイト列を持つ。それをそのまま RTF の型へ書くと、
    /// RTF しか読めないアプリには壊れたデータが渡るので、RTF に変換してから渡す
    var rtfDataForPasteboard: Data? {
        guard let data = RTFData else { return nil }
        if data.starts(with: Data("{\\rtf".utf8)) { return data }
        guard let attributed = NSAttributedString(rtfd: data, documentAttributes: nil) else { return nil }
        return attributed.rtf(from: NSRange(location: 0, length: attributed.length), documentAttributes: [:])
    }
    var colorCodeImage: NSImage? {
        guard let color = NSColor(hexString: stringValue) else { return nil }
        return NSImage.create(with: color, size: NSSize(width: 20, height: 20))
    }

    static var availableTypes: [NSPasteboard.PasteboardType] {
        return [.deprecatedString,
                .deprecatedRTF,
                .deprecatedRTFD,
                .deprecatedPDF,
                .deprecatedFilenames,
                .deprecatedURL,
                .deprecatedTIFF]
    }
    static var availableTypesString: [String] {
        return ["String",
                "RTF",
                "RTFD",
                "PDF",
                "Filenames",
                "URL",
                "TIFF"]
    }
    static var availableTypesDictinary: [NSPasteboard.PasteboardType: String] {
        var availableTypes = [NSPasteboard.PasteboardType: String]()
        zip(CPYClipData.availableTypes, CPYClipData.availableTypesString).forEach { availableTypes[$0] = $1 }
        return availableTypes
    }

    // MARK: - Init
    init(pasteboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) {
        super.init()
        self.types = types
        types.forEach { type in
            switch type {
            case .deprecatedString:
                guard let string = pasteboard.string(forType: .deprecatedString) else { return }
                stringValue = string
            case .deprecatedRTFD:
                RTFData = pasteboard.data(forType: .deprecatedRTFD)
            case .deprecatedRTF where RTFData == nil:
                RTFData = pasteboard.data(forType: .deprecatedRTF)
            case .deprecatedPDF:
                PDF = pasteboard.data(forType: .deprecatedPDF)
            case .deprecatedFilenames:
                guard let filenames = pasteboard.propertyList(forType: .deprecatedFilenames) as? [String] else { return }
                self.fileNames = filenames
            case .deprecatedURL:
                guard let urls = pasteboard.propertyList(forType: .deprecatedURL) as? [String] else { return }
                URLs = urls
            case .deprecatedTIFF:
                image = pasteboard.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage
            default: break
            }
        }
    }

    init(image: NSImage) {
        self.types = [.deprecatedTIFF]
        self.image = image
    }

    deinit {
        self.RTFData = nil
        self.PDF = nil
        self.image = nil
    }

    // MARK: - NSCoding
    @objc func encodeWithCoder(_ aCoder: NSCoder) {
        aCoder.encode(types.map { $0.rawValue }, forKey: kTypesKey)
        aCoder.encode(stringValue, forKey: kStringValueKey)
        aCoder.encode(RTFData, forKey: kRTFDataKey)
        aCoder.encode(PDF, forKey: kPDFKey)
        aCoder.encode(fileNames, forKey: kFileNamesKey)
        aCoder.encode(URLs, forKey: kURLsKey)
        aCoder.encode(image, forKey: kImageKey)
    }

    @objc required init(coder aDecoder: NSCoder) {
        types = (aDecoder.decodeObject(forKey: kTypesKey) as? [String])?.compactMap { NSPasteboard.PasteboardType(rawValue: $0) } ?? []
        fileNames = aDecoder.decodeObject(forKey: kFileNamesKey) as? [String] ?? [String]()
        URLs = aDecoder.decodeObject(forKey: kURLsKey) as? [String] ?? [String]()
        stringValue = aDecoder.decodeObject(forKey: kStringValueKey) as? String ?? ""
        RTFData = aDecoder.decodeObject(forKey: kRTFDataKey) as? Data
        PDF = aDecoder.decodeObject(forKey: kPDFKey) as? Data
        image = aDecoder.decodeObject(forKey: kImageKey) as? NSImage
        super.init()
    }
}
