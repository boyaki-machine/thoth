//
//  SecureFieldRowView+Lifecycle.swift
//
//  Thoth
//  GitHub: https://github.com/boyaki-machine/Thoth
//

import Cocoa

// MARK: - Teardown
//
// 行ビューは使い捨てで、`CPYSecureInfoDetailViewController.rebuildRows` が
// アイテムの切り替え・フィールドの追加削除並べ替え・マスク切替のたびに作り直す。
// 「作り直す側」と「捨てられる側の後始末」を 1 箇所に集めておく。
extension SecureFieldRowView {

    /// 行を捨てる前に必ず呼ぶ（`rebuildRows` から）。
    ///
    /// **画面から外すだけでは足りない。** フィールドエディタはウィンドウで 1 つを
    /// 使い回すため、外したあとの行にも編集の変更・終了が届く。届いた行は
    /// 「画面に見えていた文字列」を作業コピーへ書き戻すので、マスク中なら
    /// `••••••••` が、未入力なら空文字が、そのまま値として保存される。
    ///
    /// 実害の例: 行が作り直されたあとに古い行が書き戻すと、**入力した値が
    /// 伏せ字や空に化ける**。ラベルまで空になった場合は `commitOutcome()` の
    /// 「ラベルも値も空なら除去」に掛かってフィールドごと消える
    func prepareForRemoval() {
        // 先に切る。あとの hideRevealedValue() が stringValue を書き換えても
        // 通知が飛ばないようにするため
        labelField.delegate = nil
        valueField.delegate = nil
        noteTextView.delegate = nil
        onLabelEdited = nil
        onValueEdited = nil
        onEditingEnded = nil
        // 捨てる行に平文を残さない
        hideRevealedValue()
    }
}
