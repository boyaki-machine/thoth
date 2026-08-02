//
//  CPYSecureInfoDetailViewController.swift
//
//  Thoth
//  GitHub: https://github.com/boyaki-machine/Thoth
//

import Cocoa

/// セキュア情報確認ウィンドウの右ペイン。
/// 選択中アイテムのタイトルと各フィールドを表示する。
///
/// フィールド行の表示・編集は後続ステップで実装する。現時点ではタイトルと
/// 「選択なし」プレースホルダーの表示までを担当する。
final class CPYSecureInfoDetailViewController: NSViewController {

    // 表示内容をユニットテストから検証できるよう internal にしている
    let titleLabel = NSTextField(labelWithString: "")
    let placeholderLabel = NSTextField(labelWithString: "")

    private enum Layout {
        static let padding: CGFloat = 20
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 520))
        setupUI()
        show(item: nil)
    }

    private func setupUI() {
        titleLabel.font = .systemFont(ofSize: NSFont.systemFontSize + 4, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        // 「アイテムを選択してください」の案内。システムカラーを使い、
        // ライト/ダークどちらの外観にも自動で追従させる
        placeholderLabel.textColor = .secondaryLabelColor
        placeholderLabel.alignment = .center
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(placeholderLabel)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: Layout.padding),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Layout.padding),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Layout.padding),

            placeholderLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            placeholderLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    /// 表示するアイテムを差し替える。nil で「選択なし」表示にする
    func show(item: SecureMenuItem?) {
        guard let item = item else {
            titleLabel.stringValue = ""
            titleLabel.isHidden = true
            placeholderLabel.stringValue = L10n.secureInfoNoSelection
            placeholderLabel.isHidden = false
            return
        }
        titleLabel.stringValue = item.title
        titleLabel.isHidden = false
        placeholderLabel.isHidden = true
    }
}
