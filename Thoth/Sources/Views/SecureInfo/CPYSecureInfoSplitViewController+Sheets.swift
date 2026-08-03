//
//  CPYSecureInfoSplitViewController+Sheets.swift
//
//  Thoth
//  GitHub: https://github.com/boyaki-machine/Thoth
//

import Cocoa

// MARK: - Sheets
//
// 他の画面をシートとして呼び出す導線。どちらも既存のビューコントローラを
// そのまま再利用し、このウィンドウ側では表示だけを受け持つ。
extension CPYSecureInfoSplitViewController {

    /// TOTP の取り込みシートを開く（既存の取り込み画面を再利用する）
    func presentTOTPImport() {
        guard editor.draft != nil else { NSSound.beep(); return }
        let importViewController = CPYTOTPImportViewController()
        importViewController.onImport = { [weak self] secret in
            guard let self = self else { return }
            self.editor.addField(kind: .totp, label: L10n.totpDefaultFieldLabel, value: secret)
            self.detailViewController.show(item: self.editor.draft)
            self.commitIfNeeded()
        }
        presentAsSheet(importViewController)
    }

    /// パスワード生成シートを開く（既存の生成画面をそのまま再利用する）。
    ///
    /// **生成値を直接フィールドへ入れる導線は設けない。** 生成した値を
    /// 「コピー」でクリップボードへ取り、貼り付けてもらう。入力先をこちらで
    /// 決める作りも試したが、選ばせる UI はこの画面には重く、推測に頼ると
    /// どの欄へ入ったのか利用者から見えなくなる。生成画面を開く頻度は高くないので、
    /// コピー＆ペーストの手数は許容する
    func presentPasswordGenerator() {
        presentAsSheet(CPYPasswordGeneratorViewController())
    }
}
