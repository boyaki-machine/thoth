//
//  ClipThumbnail.swift
//
//  Thoth
//  GitHub: https://github.com/boyaki-machine/Thoth
//

import Cocoa

/// 履歴のサムネイル（画像・カラープレビュー）の生成・表示・後片付け。
///
/// v1.4.x までは PINCache に NSImage をそのまま保存していた。`resizeImage` は元画像の
/// 表現に表示サイズを付けるだけなので、実際には**元の解像度の画像が平文で**
/// `~/Library/Caches` に残っていた（スクリーンショットの全体が読める）。
/// v1.5 からは表示サイズの 2 倍の画素に描き直した PNG を作り、保存層が暗号化して持つ。
/// 表示するときはメモリ上のキャッシュだけを使う。
enum ClipThumbnail {

    /// 描き直すときの倍率（Retina 表示で粗く見えないよう 2 倍）
    static let scale: CGFloat = 2
    /// v1.4.x までのサムネイルのキャッシュ（平文）
    static var legacyCacheDirectory: URL {
        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.pinterest.PINDiskCache.PINCacheShared", isDirectory: true)
    }

    // MARK: - Make

    /// クリップのサムネイルを縮小済みの PNG にする。サムネイルを持たないクリップなら nil
    static func pngData(for data: CPYClipData) -> Data? {
        if let colorImage = data.colorCodeImage {
            return render(colorImage, pointSize: colorImage.size)
        }
        guard let image = data.thumbnailImage else { return nil }
        return render(image, pointSize: image.size)
    }

    /// 画像を pointSize の scale 倍の画素に描き直して PNG にする
    static func render(_ image: NSImage, pointSize: NSSize) -> Data? {
        let width = max(1, Int((pointSize.width * scale).rounded()))
        let height = max(1, Int((pointSize.height * scale).rounded()))
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        bitmap.size = pointSize
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: pointSize), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.representation(using: .png, properties: [:])
    }

    /// PNG から表示用の画像を作る（画素数の 1/scale を表示サイズにする）
    static func image(fromPNG data: Data) -> NSImage? {
        guard let bitmap = NSBitmapImageRep(data: data) else { return nil }
        let size = NSSize(width: CGFloat(bitmap.pixelsWide) / scale, height: CGFloat(bitmap.pixelsHigh) / scale)
        bitmap.size = size
        let image = NSImage(size: size)
        image.addRepresentation(bitmap)
        return image
    }

    // MARK: - Load

    private static let cache = NSCache<NSString, NSImage>()
    private static let loadQueue = DispatchQueue(label: "io.github.boyaki-machine.Thoth.ClipThumbnail", qos: .userInitiated)

    /// サムネイルを読み込み、メインスレッドで completion を呼ぶ（メモリ上のキャッシュだけを使う）
    static func load(clipID: String, from store: HistoryStore = AppEnvironment.current.historyStore,
                     completion: @escaping (NSImage?) -> Void) {
        if let cached = cache.object(forKey: clipID as NSString) {
            completion(cached)
            return
        }
        loadQueue.async {
            let image = store.thumbnail(forClipID: clipID).flatMap(Self.image(fromPNG:))
            if let image = image { cache.setObject(image, forKey: clipID as NSString) }
            DispatchQueue.main.async { completion(image) }
        }
    }

    // MARK: - Migration

    /// 移行した履歴のサムネイルを .data から作り直す（旧キャッシュの画像は読まない。
    /// 安全でないアンアーカイブを避けるため）。作れなかったものは飛ばす
    /// - Returns: 作り直した件数
    @discardableResult
    static func regenerate(clipIDs: [String], in store: HistoryStore, dataStore: ClipDataStore = .shared) -> Int {
        var regenerated = 0
        for id in clipIDs {
            autoreleasepool {
                guard let clip = store.clip(id: id),
                      let fileData = dataStore.read(fromPath: clip.dataPath),
                      let data = CPYClipData.unarchived(from: fileData),
                      let png = pngData(for: data) else { return }
                store.upsert(clip, thumbnail: png)
                regenerated += 1
            }
        }
        return regenerated
    }

    /// v1.4.x までの平文のサムネイルのキャッシュを消す（無ければ何もしない）
    static func removeLegacyCache(at directory: URL = legacyCacheDirectory) {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        do {
            try FileManager.default.removeItem(at: directory)
            NSLog("[ClipThumbnail] removed the legacy plaintext thumbnail cache")
        } catch {
            NSLog("[ClipThumbnail] could not remove the legacy thumbnail cache: \(error)")
        }
    }
}
