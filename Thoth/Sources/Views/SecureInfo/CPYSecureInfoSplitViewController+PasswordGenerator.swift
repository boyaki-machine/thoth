//
//  CPYSecureInfoSplitViewController+PasswordGenerator.swift
//
//  Thoth
//  GitHub: https://github.com/boyaki-machine/Thoth
//

import Cocoa

// MARK: - Password Generator
//
// パスワード生成シート（`CPYPasswordGeneratorViewController`）との連携。
//
// **生成値はクリップボードを経由させない。** 廃止した管理ウィンドウの編集シートは
// 生成画面を開くだけで、ユーザーが手でコピーして値欄へ貼り付ける作りだった。
// その間パスワードがクリップボードに乗り続けるうえ、貼り付け先を取り違える事故も
// 起こりうる。ここではモデル（作業コピー）を通して直接入れる。
//
// 入力先は「直前にフォーカスが入っていたフィールド」。ボタンを押した時点では
// すでに編集が終わっているため、押されてから探しに行っても間に合わない
// （記録は `CPYSecureInfoDetailViewController.fillTargetFieldID`）。
extension CPYSecureInfoSplitViewController {

    /// パスワード生成シートを開く（既存の生成画面を再利用する）
    func presentPasswordGenerator() {
        guard editor.draft != nil else { NSSound.beep(); return }
        // 打ちかけの内容を先に確定させる。シート表示でフォーカスが外れる際の
        // 保存と、生成値の反映が前後して取り違えるのを防ぐ
        view.window?.makeFirstResponder(nil)
        let generator = CPYPasswordGeneratorViewController()
        // 入力先が無ければ設定しない。生成シートは従来どおりコピー専用で開く
        if let fieldID = detailViewController.fillTargetRow?.field.fieldID {
            generator.onUse = { [weak self] password in
                self?.applyGeneratedPassword(password, toFieldID: fieldID)
            }
        }
        presentAsSheet(generator)
    }

    /// 生成したパスワードをフィールドへ反映する。
    ///
    /// シート表示と切り離してあるので、ユニットテストはこちらを直接呼ぶ
    /// （`deleteItem(_:)` を確認シートと分けてあるのと同じ理由）。
    /// 取り消しの控えは `commitIfNeeded()` が積むため ⌘Z で戻せる
    func applyGeneratedPassword(_ password: String, toFieldID fieldID: String) {
        guard editor.draft?.fields.contains(where: { $0.fieldID == fieldID }) == true else {
            NSSound.beep()
            return
        }
        editor.updateField(fieldID: fieldID, value: password)
        // マスク中でも入る。伏せ字が値として保存される事故は起きない
        // （画面の文字列ではなくモデルを書き換えているため）。
        // 表示を新しい値に合わせるため行を作り直す
        detailViewController.show(item: editor.draft)
        commitIfNeeded()
    }
}
