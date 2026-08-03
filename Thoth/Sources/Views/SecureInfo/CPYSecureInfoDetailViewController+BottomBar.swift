//
//  CPYSecureInfoDetailViewController+BottomBar.swift
//
//  Thoth
//  GitHub: https://github.com/boyaki-machine/Thoth
//

import Cocoa

// MARK: - Bottom Bar
//
// 右ペイン下端の操作列。
//
// ```
// [フィールドを追加▾] [TOTP追加...] [パスワード生成...]      [閉じる]
// ```
//
// 左側の 3 つは横並びの `NSStackView` にまとめる。個別に leading 制約で
// 数珠つなぎにすると、ウィンドウを縮めたときに「閉じる」へめり込む。
extension CPYSecureInfoDetailViewController {

    /// フィールド追加メニューとボトムバーを組み立てる
    func setupBottomBar() {
        addFieldButton.pullsDown = true
        let menu = NSMenu()
        // pullsDown のポップアップは先頭項目がボタンの表示名になる
        menu.addItem(NSMenuItem(title: L10n.secureInfoAddField, action: nil, keyEquivalent: ""))
        for template in SecureInfoFieldTemplate.allCases {
            let menuItem = NSMenuItem(title: template.menuTitle,
                                      action: #selector(addFieldSelected(_:)), keyEquivalent: "")
            menuItem.target = self
            menuItem.representedObject = template.rawValue
            menu.addItem(menuItem)
        }
        addFieldButton.menu = menu

        addTOTPButton.title = L10n.addTOTP
        addTOTPButton.bezelStyle = .rounded
        addTOTPButton.target = self
        addTOTPButton.action = #selector(addTOTPSelected)

        // 廃止した管理ウィンドウの編集シートと同じ文言・同じ役割。
        // あちらは生成値を手でコピペさせていたが、こちらは選択中のフィールドへ直接入れる
        generatePasswordButton.title = "\(L10n.passwordGenerator)..."
        generatePasswordButton.bezelStyle = .rounded
        generatePasswordButton.toolTip = "⌘G"
        generatePasswordButton.target = self
        generatePasswordButton.action = #selector(generatePasswordSelected)

        bottomBarStackView.orientation = .horizontal
        bottomBarStackView.spacing = Layout.rowSpacing
        bottomBarStackView.translatesAutoresizingMaskIntoConstraints = false
        [addFieldButton, addTOTPButton, generatePasswordButton].forEach {
            bottomBarStackView.addArrangedSubview($0)
        }
        view.addSubview(bottomBarStackView)

        closeButton.title = L10n.close
        closeButton.bezelStyle = .rounded
        closeButton.target = self
        closeButton.action = #selector(closeWindowSelected)
        // 既定ボタンにはしない。Return は右ペインへフォーカスを移す操作に
        // 割り当て済みで、既定ボタンにすると横取りされる
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(closeButton)
    }

    /// ボトムバーの追加系ボタンをまとめて出し入れする。
    /// `NSStackView` の管理下なので、隠したぶんは並びから畳まれる。
    /// 「閉じる」はスタックの外にあり、選択が無くても押せる
    func setBottomBarButtonsHidden(_ hidden: Bool) {
        addFieldButton.isHidden = hidden
        addTOTPButton.isHidden = hidden
        generatePasswordButton.isHidden = hidden
    }

    // MARK: - Password Generator Target

    /// パスワード生成の入力先になる行（無ければ nil）。
    ///
    /// 1. 直前に編集していた行。覚えた `fieldID` をその場で行へ解決し直す
    ///    （並べ替えやマスク切替で行ビューは作り直されるため、ビュー参照はすぐ古くなる。
    ///    種別が変わって受け取れなくなっていた場合もここで弾かれる）
    /// 2. 覚えが無ければ、**マスク指定のフィールドがちょうど 1 つのときだけ**それを使う
    ///
    /// 2 が要るのは、マスク中の値欄はクリックしても編集が始まらない（`isValueEditable`）
    /// ためで、素直にパスワード欄を触ったユーザーには入力先が記録されない。
    /// ラベルを選ばないと使えない機能になってしまう。
    ///
    /// **候補が複数あるときは推測しない。** どちらのパスワードを潰すかを
    /// 間違えると取り返しがつきにくいので、その場合はラベルを選んでもらう
    var fillTargetRow: SecureFieldRowView? {
        if let fieldID = fillTargetFieldID,
           let remembered = fieldRows.first(where: {
               $0.field.fieldID == fieldID && $0.acceptsGeneratedPassword
           }) {
            return remembered
        }
        let masked = fieldRows.filter { $0.acceptsGeneratedPassword && $0.field.isPassword }
        return masked.count == 1 ? masked.first : nil
    }

    // MARK: - Actions

    @objc func closeWindowSelected() {
        view.window?.performClose(self)
    }

    @objc func addFieldSelected(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let template = SecureInfoFieldTemplate(rawValue: raw) else { return }
        onAddFieldRequested?(template)
    }

    @objc func addTOTPSelected() {
        onAddTOTPRequested?()
    }

    @objc func generatePasswordSelected() {
        onGeneratePasswordRequested?()
    }
}
