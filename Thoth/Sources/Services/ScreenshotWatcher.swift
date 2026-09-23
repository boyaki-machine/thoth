//
//  ScreenshotWatcher.swift
//
//  Thoth
//
//  スクリーンショットの保存を検知して、その画像を知らせる（ベータ機能「スクリーンショットを履歴に保存」）
//

import Cocoa
import CoreServices
import ImageIO

/// スクリーンショットの保存を検知して、その画像を知らせる。
///
/// v1.5.1 までは Screeen（Spotlight の `NSMetadataQuery` で `kMDItemIsScreenCapture = 1` を待つ）を使っていたが、
/// Spotlight の索引が追いつくまで数秒〜数十秒かかり、索引から漏れると取りこぼしていた。
/// ここでは保存先フォルダを FSEvents で直接見張り、ファイルの拡張属性
/// `com.apple.metadata:kMDItemIsScreenCapture`（macOS がスクリーンショットに付ける）で判定する。
///
/// - 保存先は `com.apple.screencapture` の `location`（⌘⇧5 のオプションで変えられる）。未設定ならデスクトップ。
///   設定の変更に追従するため、定期的に確かめ直す
/// - 監視を始める前からあったファイルは取り込まない（古いスクリーンショットの移動・改名で増えないように）
/// - 同じファイル（inode）は 1 回だけ取り込む（一時ファイルからの改名・属性の後付けで何度も通知が来る）
final class ScreenshotWatcher {

    // MARK: - Settings
    /// スクリーンショットとして扱う拡張子（`screencapture` の type で選べる形式）
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "tif", "tiff", "gif", "bmp"]
    /// macOS がスクリーンショットに付ける拡張属性
    static let screenCaptureAttribute = "com.apple.metadata:kMDItemIsScreenCapture"
    /// 監視を始める少し前に作られたファイルも拾う（開始と撮影がほぼ同時のとき）
    static let startTolerance: TimeInterval = 2
    /// 書き込み途中の画像を読み直す間隔と回数（約 3 秒まで待つ）
    static let loadRetryInterval: TimeInterval = 0.2
    static let loadRetryLimit = 15
    /// 保存先の設定を確かめ直す間隔
    static let locationCheckInterval: TimeInterval = 15

    // MARK: - Properties
    /// 取り込んだ画像を受け取る（メインスレッドで呼ぶ）
    var onCapture: ((NSImage) -> Void)?
    /// 見張るフォルダを決める。テストでは一時フォルダに差し替える
    var directoryProvider: () -> URL = { ScreenshotWatcher.currentScreenshotDirectory() }

    private(set) var watchedDirectory: URL?
    private(set) var isRunning = false
    private var stream: FSEventStreamRef?
    private var startedAt = Date()
    private var importedFiles = Set<FileIdentity>()
    private var locationTimer: Timer?
    /// FSEvents のコールバック・ファイルの判定と読み込みを行う直列キュー
    private let queue = DispatchQueue(label: "io.github.boyaki-machine.Thoth.ScreenshotWatcher", qos: .utility)

    deinit {
        locationTimer?.invalidate()
        stopStream()
    }

    // MARK: - Start / Stop
    /// 監視を始める（二重に呼んでもよい）。メインスレッドから呼ぶ
    func start() {
        guard !isRunning else { return }
        isRunning = true
        startedAt = Date()
        startStream(directory: directoryProvider())
        locationTimer = Timer.scheduledTimer(withTimeInterval: Self.locationCheckInterval, repeats: true) { [weak self] _ in
            self?.followLocationChange()
        }
    }

    /// 監視をやめる（二重に呼んでもよい）。メインスレッドから呼ぶ
    func stop() {
        guard isRunning else { return }
        isRunning = false
        locationTimer?.invalidate()
        locationTimer = nil
        stopStream()
    }

    /// 保存先の設定が変わっていたら、見張るフォルダを移す
    func followLocationChange() {
        guard isRunning else { return }
        let directory = directoryProvider()
        guard directory.standardizedFileURL != watchedDirectory?.standardizedFileURL else { return }
        stopStream()
        startStream(directory: directory)
    }

    private func startStream(directory: URL) {
        watchedDirectory = directory
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents
                                             | kFSEventStreamCreateFlagNoDefer)
        guard let stream = FSEventStreamCreate(nil, Self.eventCallback, &context, [directory.path] as CFArray,
                                               FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.1, flags) else {
            NSLog("[ScreenshotWatcher] could not watch \(directory.path)")
            return
        }
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    private func stopStream() {
        guard let stream = stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    private static let eventCallback: FSEventStreamCallback = { _, info, count, paths, flags, _ in
        guard let info = info else { return }
        let watcher = Unmanaged<ScreenshotWatcher>.fromOpaque(info).takeUnretainedValue()
        let pathList = unsafeBitCast(paths, to: NSArray.self)
        for index in 0..<count {
            guard let path = pathList[index] as? String,
                  isRelevantEvent(flags[index]) else { continue }
            watcher.examine(URL(fileURLWithPath: path))
        }
    }

    // MARK: - Examine（queue 上で動く）
    private func examine(_ url: URL, attempt: Int = 0) {
        guard Self.isCandidateFileName(url.lastPathComponent),
              let identity = FileIdentity(url: url),
              !importedFiles.contains(identity),
              Self.isRecent(creationDate: identity.creationDate, startedAt: startedAt),
              Self.isScreenCapture(attributeValue: Self.extendedAttribute(Self.screenCaptureAttribute, of: url)) else { return }
        guard let image = Self.loadCompleteImage(at: url) else {
            // 書き込み途中。少し待って読み直す
            guard attempt < Self.loadRetryLimit else {
                NSLog("[ScreenshotWatcher] gave up reading \(url.lastPathComponent)")
                return
            }
            queue.asyncAfter(deadline: .now() + Self.loadRetryInterval) { [weak self] in
                self?.examine(url, attempt: attempt + 1)
            }
            return
        }
        importedFiles.insert(identity)
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.isRunning else { return }
            self.onCapture?(image)
        }
    }
}

// MARK: - Decisions（純粋関数）
extension ScreenshotWatcher {
    /// 取り込みを検討する FSEvents か。ファイルの作成・改名（一時ファイル → 本来の名前）・
    /// 変更・拡張属性の付与を対象にする。フォルダやシンボリックリンクは除く
    static func isRelevantEvent(_ flags: FSEventStreamEventFlags) -> Bool {
        let flags = Int(flags)
        guard flags & kFSEventStreamEventFlagItemIsFile != 0 else { return false }
        let interesting = kFSEventStreamEventFlagItemCreated | kFSEventStreamEventFlagItemRenamed
            | kFSEventStreamEventFlagItemModified | kFSEventStreamEventFlagItemXattrMod
        return flags & interesting != 0
    }

    /// 名前から見て、スクリーンショットの候補か。隠しファイル（書き込み中の一時ファイル `.スクリーンショット…`）は除く
    static func isCandidateFileName(_ name: String) -> Bool {
        guard !name.hasPrefix(".") else { return false }
        let pathExtension = (name as NSString).pathExtension.lowercased()
        return imageExtensions.contains(pathExtension)
    }

    /// 監視を始めた後に作られたファイルか
    static func isRecent(creationDate: Date?, startedAt: Date) -> Bool {
        guard let creationDate = creationDate else { return false }
        return creationDate >= startedAt.addingTimeInterval(-startTolerance)
    }

    /// 拡張属性 `kMDItemIsScreenCapture` の値（バイナリ plist の真偽値）がスクリーンショットを示すか
    static func isScreenCapture(attributeValue data: Data?) -> Bool {
        guard let data = data else { return false }
        let value = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        if let flag = value as? Bool { return flag }
        if let number = value as? NSNumber { return number.boolValue }
        // 形式が読めなくても、属性が付いていること自体がスクリーンショットの印
        return true
    }

    /// `com.apple.screencapture` の `location` から保存先を決める。未設定・存在しないフォルダならデスクトップ
    static func screenshotDirectory(location: String?, homeDirectory: URL,
                                    isDirectory: (URL) -> Bool) -> URL {
        let desktop = homeDirectory.appendingPathComponent("Desktop", isDirectory: true)
        guard let location = location?.trimmingCharacters(in: .whitespacesAndNewlines), !location.isEmpty else { return desktop }
        let expanded: URL
        if location == "~" {
            expanded = homeDirectory
        } else if location.hasPrefix("~/") {
            expanded = homeDirectory.appendingPathComponent(String(location.dropFirst(2)), isDirectory: true)
        } else if location.hasPrefix("/") {
            expanded = URL(fileURLWithPath: location, isDirectory: true)
        } else {
            return desktop
        }
        return isDirectory(expanded) ? expanded : desktop
    }

    /// 現在のスクリーンショットの保存先
    static func currentScreenshotDirectory() -> URL {
        let location = CFPreferencesCopyAppValue("location" as CFString, "com.apple.screencapture" as CFString) as? String
        return screenshotDirectory(location: location,
                                   homeDirectory: FileManager.default.homeDirectoryForCurrentUser) { url in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
        }
    }
}

// MARK: - File access
extension ScreenshotWatcher {
    /// ファイルの同一性（改名しても変わらない）と作成日時
    struct FileIdentity: Hashable {
        let device: UInt64
        let inode: UInt64
        let creationDate: Date?

        init?(url: URL) {
            var info = stat()
            guard stat(url.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { return nil }
            device = UInt64(bitPattern: Int64(info.st_dev))
            inode = UInt64(info.st_ino)
            creationDate = Date(timeIntervalSince1970: TimeInterval(info.st_birthtimespec.tv_sec)
                                + TimeInterval(info.st_birthtimespec.tv_nsec) / 1_000_000_000)
        }

        static func == (lhs: FileIdentity, rhs: FileIdentity) -> Bool {
            return lhs.device == rhs.device && lhs.inode == rhs.inode
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(device)
            hasher.combine(inode)
        }
    }

    static func extendedAttribute(_ name: String, of url: URL) -> Data? {
        let length = getxattr(url.path, name, nil, 0, 0, 0)
        guard length >= 0 else { return nil }
        var data = Data(count: length)
        let read = data.withUnsafeMutableBytes { getxattr(url.path, name, $0.baseAddress, length, 0, 0) }
        return read == length ? data : nil
    }

    /// 画像を最後まで読めたときだけ返す（書き込み途中なら nil）
    static func loadCompleteImage(at url: URL) -> NSImage? {
        guard let data = try? Data(contentsOf: url), !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetStatus(source) == .statusComplete,
              CGImageSourceGetCount(source) > 0,
              CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else { return nil }
        // 解像度（Retina の 144dpi など）を保つため、ファイルの中身から作る（従来の NSImage(contentsOfFile:) と同じ）
        return NSImage(data: data)
    }
}
