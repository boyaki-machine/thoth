//
//  CPYSecureInfoSplitViewController+Transfer.swift
//
//  Thoth
//  GitHub: https://github.com/boyaki-machine/Thoth
//

import Cocoa
import UniformTypeIdentifiers

// MARK: - Import / Export
//
// ファイルへの書き出しと取り込み。中身の処理は `SecureItemsTransfer`（UI 非依存）に
// 集約してあり、ここはパネルの提示と確認・取り消しの段取りだけを行う。
//
// **読み出せない状態（isKeychainAccessDenied）ではどちらも実行しない。**
// 取り込みは saveAllItems に拒否されるだけだが、書き出しは 0 件の JSON を
// 作ってしまい、ユーザーが既存のバックアップを空で上書きする事故につながる。
extension CPYSecureInfoSplitViewController {

    /// 入出力を受け付けられる状態か
    var allowsTransfer: Bool { !editor.isReadOnly }

    // MARK: - Export

    /// 書き出し。平文で出力される旨を警告してから保存先を選ばせる
    func presentExport() {
        guard allowsTransfer, let window = view.window else { NSSound.beep(); return }
        NSAlert.showConfirmation(message: L10n.exportSecureItems,
                                 informative: L10n.secureItemsExportWarning,
                                 confirmTitle: L10n.exportSecureItems, cancelTitle: L10n.cancel,
                                 for: window) { [weak self] in
            self?.showExportPanel()
        }
    }

    private func showExportPanel() {
        guard let window = view.window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = SecureItemsTransfer.defaultFileName
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.exportItems(to: url)
        }
    }

    private func exportItems(to url: URL) {
        // 打ちかけの内容も書き出しに含める
        view.window?.makeFirstResponder(nil)
        guard commitIfNeeded() else { return }
        // 入口の allowsTransfer が見ているのは直近の読み込み結果を写した控え。
        // パネルを開いている間に読めなくなった場合に備え、exportData 側で確かめ直す
        do {
            let data = try SecureItemsTransfer.exportData(using: AppEnvironment.current.secureMenuService)
            try data.write(to: url, options: .atomic)
        } catch {
            showTransferError(error)
        }
    }

    // MARK: - Import

    /// 取り込み。同じ ID のアイテムは上書き、それ以外は末尾に追加される
    func presentImport() {
        guard allowsTransfer, let window = view.window else { NSSound.beep(); return }
        // 打ちかけの内容を確定させてから読み込む（取り込みで上書きされて消えないように）
        view.window?.makeFirstResponder(nil)
        guard commitIfNeeded() else { return }

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.importItems(from: url)
        }
    }

    private func importItems(from url: URL) {
        do {
            let parsed = try SecureItemsTransfer.parseImport(try Data(contentsOf: url))
            let service = AppEnvironment.current.secureMenuService
            // 指紋パスワードの上書きは、以前そのパスワードで暗号化したファイルを
            // 開けなくすることがあるため、登録済みで内容が異なる場合だけ確認する
            let replacesPassword = SecureItemsTransfer.replacesCryptoPassword(
                current: service.loadCryptoPassword(), incoming: parsed.cryptoPassword)
            guard replacesPassword, let window = view.window else {
                applyImport(parsed.items, cryptoPassword: parsed.cryptoPassword)
                return
            }
            NSAlert.showConfirmation(message: L10n.importSecureItems,
                                     informative: L10n.secureItemsImportOverwritesCryptoPassword,
                                     confirmTitle: L10n.importSecureItems, cancelTitle: L10n.cancel,
                                     for: window) { [weak self] in
                self?.applyImport(parsed.items, cryptoPassword: parsed.cryptoPassword)
            }
        } catch {
            showTransferError(error)
        }
    }

    /// 取り込みを反映する。
    ///
    /// **取り消しが必ず効く状態にする。** 既存のアイテムをまとめて上書きしうる操作で、
    /// この機能のなかで最も取り返しがつかない。読み直しは取り消しの世代を捨ててしまうため、
    /// ここだけは `clearsUndoHistory: false` で読み直す
    private func applyImport(_ items: [SecureMenuItem], cryptoPassword: String?) {
        pushUndoSnapshot(action: .importItems)
        let service = AppEnvironment.current.secureMenuService
        let saved: Bool = performLocalChange {
            SecureItemsTransfer.apply(items: items, cryptoPassword: cryptoPassword, using: service)
        }
        reloadItems(clearsUndoHistory: false)
        NSAlert.showNotice(message: L10n.importSecureItems,
                           informative: L10n.importedSecureItemsFormat(saved ? items.count : 0),
                           style: .informational, for: view.window)
    }

    private func showTransferError(_ error: Error) {
        NSAlert.showNotice(message: L10n.secureInfo,
                           informative: error.localizedDescription,
                           for: view.window)
    }
}
