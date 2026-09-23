//
//  PasteService.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Econa77 on 2016/11/23.
//
//  Copyright © 2015-2018 Clipy Project.
//

import Foundation
import Cocoa
import Sauce

/// ペースト操作全般を担うサービス。
///
/// 出力経路は 3 種類:
/// - **クリップボード経由ペースト**: copyToPasteboard → CGEvent で Cmd+V 送出（paste()）
/// - **秘匿コピー**: copyConcealedToPasteboard。秘匿マーカー付きで書き込み、
///   Clipy 自身と対応クリップボードマネージャーの履歴保存を抑止。遅延クリアとセットで使う
/// - **直接タイプ**: typeString。クリップボードを一切経由せず CGEvent で 1 文字ずつ送出
///   （TOTP コードなど、いかなる履歴にも残したくない値に使用）
///
/// Cmd+V 送出と直接タイプにはアクセシビリティ権限が必要。
/// 修飾キーによる動作分岐（プレーンテキストペースト・ペースト後削除）にも対応する。
final class PasteService {

    // MARK: - Properties
    fileprivate let lock = NSRecursiveLock(name: "io.github.boyaki-machine.Thoth.Pastable")
    fileprivate var isPastePlainText: Bool {
        guard AppEnvironment.current.defaults.bool(forKey: Constants.Beta.pastePlainText) else { return false }

        let modifierSetting = AppEnvironment.current.defaults.integer(forKey: Constants.Beta.pastePlainTextModifier)
        return isPressedModifier(modifierSetting)
    }
    fileprivate var isDeleteHistory: Bool {
        guard AppEnvironment.current.defaults.bool(forKey: Constants.Beta.deleteHistory) else { return false }

        let modifierSetting = AppEnvironment.current.defaults.integer(forKey: Constants.Beta.deleteHistoryModifier)
        return isPressedModifier(modifierSetting)
    }
    fileprivate var isPasteAndDeleteHistory: Bool {
        guard AppEnvironment.current.defaults.bool(forKey: Constants.Beta.pasteAndDeleteHistory) else { return false }

        let modifierSetting = AppEnvironment.current.defaults.integer(forKey: Constants.Beta.pasteAndDeleteHistoryModifier)
        return isPressedModifier(modifierSetting)
    }

    // MARK: - Modifiers
    private func isPressedModifier(_ flag: Int) -> Bool {
        let flags = NSEvent.modifierFlags
        if flag == 0 && flags.contains(.command) {
            return true
        } else if flag == 1 && flags.contains(.shift) {
            return true
        } else if flag == 2 && flags.contains(.control) {
            return true
        } else if flag == 3 && flags.contains(.option) {
            return true
        }
        return false
    }
}

// MARK: - Paste by Primary Key
extension PasteService {
    /// 履歴クリップを主キーで取得してペーストする。
    /// メニュー項目のアクション（AppDelegate）から保存層へのアクセスを分離するための入口。
    /// - Returns: クリップが見つからなかった場合 false
    @discardableResult
    func pasteClip(withPrimaryKey primaryKey: String) -> Bool {
        guard let clip = AppEnvironment.current.historyStore.clip(id: primaryKey) else { return false }
        paste(with: clip)
        return true
    }

    /// スニペットを主キーで取得してペーストする。
    /// - Returns: スニペットが見つからなかった場合 false
    @discardableResult
    func pasteSnippet(withPrimaryKey primaryKey: String) -> Bool {
        guard let snippet = AppEnvironment.current.snippetStore.snippet(id: primaryKey) else { return false }
        copyToPasteboard(with: snippet.content)
        paste()
        return true
    }
}

// MARK: - Copy
extension PasteService {
    private static func unarchiveClipData(atPath path: String) -> CPYClipData? {
        // ClipDataStore が暗号化形式（CLPYDAT）と旧平文形式を自動判別して読み込む
        guard let fileData = ClipDataStore.shared.read(fromPath: path) else { return nil }
        return CPYClipData.unarchived(from: fileData)
    }

    /// クリップをクリップボードへ書き込んでペーストする。
    /// アンアーカイブ（画像等は数 MB 規模）はバックグラウンドで行い UI をブロックしない。
    /// 修飾キーの押下状態に応じてプレーンテキスト化・履歴削除も行う
    func paste(with clip: ClipRecord) {
        let dataPath = clip.dataPath
        let clipID = clip.id

        // Handling modifier actions（NSEvent.modifierFlags は呼び出し元スレッドで評価する）
        let isPastePlainText = self.isPastePlainText
        let isPasteAndDeleteHistory = self.isPasteAndDeleteHistory
        let isDeleteHistory = self.isDeleteHistory

        // Increment change count for don't copy paste item
        if isPasteAndDeleteHistory {
            AppEnvironment.current.clipService.incrementChangeCount()
        }

        // 大きなクリップ（画像・RTF 等）のファイル読み込みとアンアーカイブは
        // 時間がかかるため、バックグラウンドで実行してメニュー選択直後の UI ブロックを避ける
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            // Paste history
            if isPastePlainText || !isDeleteHistory || isPasteAndDeleteHistory {
                guard let data = Self.unarchiveClipData(atPath: dataPath) else { return }
                if isPastePlainText {
                    self.copyToPasteboard(with: data.stringValue)
                } else {
                    self.copyToPasteboard(with: data)
                }
                self.paste()
            }
            // Delete clip
            if isDeleteHistory || isPasteAndDeleteHistory {
                DispatchQueue.main.async {
                    AppEnvironment.current.clipService.delete(clipID: clipID)
                }
            }
        }
    }

    /// 文字列を通常のコピーとしてクリップボードへ書き込む（履歴にも保存される）。
    /// 秘匿情報には copyConcealedToPasteboard を使うこと
    func copyToPasteboard(with string: String) {
        lock.lock(); defer { lock.unlock() }

        let pasteboard = NSPasteboard.general
        pasteboard.declareTypes([.deprecatedString], owner: nil)
        pasteboard.setString(string, forType: .deprecatedString)
    }

    /// 秘匿マーカー（org.nspasteboard.ConcealedType / TransientType）付きで
    /// ペーストボードへ書き込む。セキュアメニューの値など「履歴に残してはならない」
    /// 文字列のコピーには必ずこちらを使うこと。
    ///
    /// マーカーにより Clipy 自身のクリップボード監視（ClipService）と、
    /// 同規約に対応した他のクリップボードマネージャーの双方が履歴保存をスキップする。
    func copyConcealedToPasteboard(with string: String) {
        lock.lock(); defer { lock.unlock() }

        let pasteboard = NSPasteboard.general
        pasteboard.declareTypes([.deprecatedString,
                                 Constants.Pasteboard.concealedType,
                                 Constants.Pasteboard.transientType], owner: nil)
        pasteboard.setString(string, forType: .deprecatedString)
        // マーカー型は「型が存在すること」自体が意味を持つ。値は空文字でよい
        pasteboard.setString("", forType: Constants.Pasteboard.concealedType)
        pasteboard.setString("", forType: Constants.Pasteboard.transientType)
    }

    /// 一定時間後にペーストボードをクリアする。ただしその間にユーザーが別の内容を
    /// コピーしていた場合（changeCount が変化していた場合）は何もしない。
    /// 秘匿コピーの後始末として copyConcealedToPasteboard とセットで使う。
    func scheduleConcealedClear(after delay: TimeInterval = SecureSelectionContext.recencyWindow) {
        let changeCountAtWrite = NSPasteboard.general.changeCount
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard NSPasteboard.general.changeCount == changeCountAtWrite else { return }
            NSPasteboard.general.clearContents()
        }
    }

    /// 秘匿値を貼り付けてから、元のクリップボードへ戻すまでの時間。
    /// 貼り付け先が ⌘V を処理してクリップボードを読み終えるのを待つ
    /// （短すぎると、遅いアプリでは戻した後の内容が貼り付けられてしまう）
    static let concealedPasteRestoreDelay: TimeInterval = 2.0

    /// 秘匿値の貼り付けの後始末として、`snapshot`（書き込む前の内容）へクリップボードを戻す。
    /// その間に別のコピーがあった（changeCount が `writtenChangeCount` から変わった）場合は何もしない。
    ///
    /// 貼り付け後もクリップボードに秘匿値が残っていると、⌘V でもう一度貼り付けられてしまう。
    /// 30 秒後に消すだけだった以前の方式では、その間は残り、元のクリップボードの内容も失われていた
    func restorePasteboard(_ snapshot: PasteboardSnapshot,
                           to pasteboard: NSPasteboard = .general,
                           ifUnchangedSince writtenChangeCount: Int,
                           after delay: TimeInterval = PasteService.concealedPasteRestoreDelay,
                           completion: ((Bool) -> Void)? = nil) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard pasteboard.changeCount == writtenChangeCount else {
                completion?(false)
                return
            }
            // 戻した内容を「新しいコピー」として履歴に取り込まない。
            // 先に進めておく（戻した後に進めると、その間に監視が変化を拾ったとき次の本物のコピーを取りこぼす）
            if pasteboard == NSPasteboard.general {
                AppEnvironment.current.clipService.incrementChangeCount()
            }
            snapshot.restore(to: pasteboard)
            completion?(true)
        }
    }

    func copyToPasteboard(with clip: ClipRecord) {
        lock.lock(); defer { lock.unlock() }

        guard let data = Self.unarchiveClipData(atPath: clip.dataPath) else { return }

        if isPastePlainText {
            copyToPasteboard(with: data.stringValue)
            return
        }

        copyToPasteboard(with: data)
    }

    /// アンアーカイブ済みデータを直接ペーストボードへ書き込む。
    /// 同じファイルを二重にアンアーカイブしないよう、paste(with:) からはこちらを使う。
    func copyToPasteboard(with data: CPYClipData) {
        lock.lock(); defer { lock.unlock() }

        let pasteboard = NSPasteboard.general
        let types = data.types
        pasteboard.declareTypes(types, owner: nil)
        types.forEach { type in
            switch type {
            case .deprecatedString:
                let pbString = data.stringValue
                pasteboard.setString(pbString, forType: .deprecatedString)
            case .deprecatedRTFD:
                guard let rtfData = data.RTFData else { return }
                pasteboard.setData(rtfData, forType: .deprecatedRTFD)
            case .deprecatedRTF:
                guard let rtfData = data.RTFData else { return }
                pasteboard.setData(rtfData, forType: .deprecatedRTF)
            case .deprecatedPDF:
                guard let pdfData = data.PDF, let pdfRep = NSPDFImageRep(data: pdfData) else { return }
                pasteboard.setData(pdfRep.pdfRepresentation, forType: .deprecatedPDF)
            case .deprecatedFilenames:
                let fileNames = data.fileNames
                pasteboard.setPropertyList(fileNames, forType: .deprecatedFilenames)
            case .deprecatedURL:
                let url = data.URLs
                pasteboard.setPropertyList(url, forType: .deprecatedURL)
            case .deprecatedTIFF:
                guard let image = data.image, let imageData = image.tiffRepresentation else { return }
                pasteboard.setData(imageData, forType: .deprecatedTIFF)
            default: break
            }
        }
    }
}

// MARK: - Type (直接キー入力)
extension PasteService {

    /// クリップボードを一切経由せず、CGEvent で文字列を直接タイプする。
    /// TOTP など「OS のコピー履歴・Clipy 履歴に残したくない値」の入力に使う。
    /// `paste()` と同じくアクセシビリティ権限が必要。
    func typeString(_ string: String) {
        guard !string.isEmpty else { return }
        guard AppEnvironment.current.accessibilityService.isAccessibilityEnabled(isPrompt: false) else {
            DispatchQueue.main.async {
                AppEnvironment.current.accessibilityService.showAccessibilityAuthenticationAlert()
            }
            return
        }

        DispatchQueue.main.async {
            let source = CGEventSource(stateID: .combinedSessionState)
            source?.setLocalEventsFilterDuringSuppressionState([.permitLocalMouseEvents, .permitSystemDefinedEvents],
                                                               state: .eventSuppressionStateSuppressionInterval)
            // 1 文字ずつ keyDown/keyUp を送る。keyboardSetUnicodeString で
            // 物理キーのレイアウトに依存せず任意の文字を送出できる。
            for character in string {
                var utf16 = Array(String(character).utf16)
                guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                      let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else { continue }
                keyDown.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
                keyUp.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
                keyDown.post(tap: .cgAnnotatedSessionEventTap)
                keyUp.post(tap: .cgAnnotatedSessionEventTap)
            }
        }
    }
}

// MARK: - Paste
extension PasteService {
    /// CGEvent で Cmd+V を送出し、最前面アプリにペーストさせる。
    /// 「ペーストコマンドを入力する」設定が無効の場合は何もしない
    /// - Returns: Cmd+V を送出した（送出を予約した）場合 true。設定が無効・権限が無い場合 false
    @discardableResult
    func paste() -> Bool {
        guard AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.inputPasteCommand) else {
            Diagnostics.paste.info("paste: ⌘V input is turned off in Preferences")
            return false
        }
        // Check Accessibility Permission
        guard AppEnvironment.current.accessibilityService.isAccessibilityEnabled(isPrompt: false) else {
            Diagnostics.paste.error("paste: accessibility permission is missing")
            // バックグラウンドスレッドから呼ばれる場合があるため、アラート表示はメインスレッドで行う
            DispatchQueue.main.async {
                AppEnvironment.current.accessibilityService.showAccessibilityAuthenticationAlert()
            }
            return false
        }

        let vKeyCode = Sauce.shared.keyCode(for: .v)
        DispatchQueue.main.async {
            let source = CGEventSource(stateID: .combinedSessionState)
            // Disable local keyboard events while pasting
            source?.setLocalEventsFilterDuringSuppressionState([.permitLocalMouseEvents, .permitSystemDefinedEvents], state: .eventSuppressionStateSuppressionInterval)
            // Press Command + V
            let keyVDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true)
            keyVDown?.flags = .maskCommand
            // Release Command + V
            let keyVUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
            keyVUp?.flags = .maskCommand
            // Post Paste Command
            keyVDown?.post(tap: .cgAnnotatedSessionEventTap)
            keyVUp?.post(tap: .cgAnnotatedSessionEventTap)
            Diagnostics.paste.info("paste: posted ⌘V (keyCode \(vKeyCode, privacy: .public)) frontmost=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "nil", privacy: .public) thothActive=\(NSApp.isActive, privacy: .public)")
        }
        return true
    }
}

// MARK: - PasteboardSnapshot
/// クリップボードの内容（全アイテム・全型のデータ）の控え。
/// 秘匿値を貼り付ける間だけクリップボードを借り、終わったら元へ戻すために使う
struct PasteboardSnapshot {
    /// アイテムごとの（型, データ）。型の並び（優先順）を保つため辞書にしない
    let items: [[(type: NSPasteboard.PasteboardType, data: Data)]]

    init(pasteboard: NSPasteboard) {
        items = (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in
                item.data(forType: type).map { (type: type, data: $0) }
            }
        }
        .filter { !$0.isEmpty }
    }

    var isEmpty: Bool { items.isEmpty }

    /// 控えた内容でクリップボードを置き換える。控えが空ならクリアだけ行う
    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let restored = items.map { entries -> NSPasteboardItem in
            let item = NSPasteboardItem()
            entries.forEach { item.setData($0.data, forType: $0.type) }
            return item
        }
        guard !restored.isEmpty else { return }
        pasteboard.writeObjects(restored)
    }
}
