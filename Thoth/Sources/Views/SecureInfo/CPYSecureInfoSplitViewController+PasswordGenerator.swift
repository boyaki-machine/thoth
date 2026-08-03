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
// **入力先はシート上の「入力先」ポップアップで選ばせる。** 直前のフォーカスから
// 推測する作りにしていたが、マスク中の値欄はクリックしても編集が始まらないため
// フォーカスが記録されず、結局どの欄に入るのか利用者から見えなかった
// （詳しくは `CPYSecureInfoDetailViewController.fillCandidates`）。
extension CPYSecureInfoSplitViewController {

    /// パスワード生成シートを開く（既存の生成画面を再利用する）
    func presentPasswordGenerator() {
        guard editor.draft != nil else { NSSound.beep(); return }
        // 打ちかけの内容を先に確定させる。シート表示でフォーカスが外れる際の
        // 保存と、生成値の反映が前後して取り違えるのを防ぐ
        view.window?.makeFirstResponder(nil)
        let generator = CPYPasswordGeneratorViewController()
        // 候補が無ければ渡さない。生成シートは従来どおりコピー専用で開く
        generator.fillDestinations = detailViewController.fillCandidates.map {
            CPYPasswordGeneratorViewController.FillDestination(
                fieldID: $0.field.fieldID,
                title: Self.destinationTitle(for: $0.field))
        }
        generator.preferredDestinationID = detailViewController.preferredFillFieldID
        generator.onUse = { [weak self] password, fieldID in
            self?.applyGeneratedPassword(password, toFieldID: fieldID)
        }
        presentAsSheet(generator)
    }

    /// 入力先ポップアップに出す名前（純粋関数のためユニットテスト可能）。
    /// ラベルが空のフィールドでも選べるよう、空なら種別の既定名で代替する
    static func destinationTitle(for field: SecureMenuItem.Field) -> String {
        let label = field.label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard label.isEmpty else { return label }
        return field.isPassword ? L10n.secureFieldDefaultLabelPassword : L10n.secureFieldDefaultLabelText
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
