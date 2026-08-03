//
//  SecureFieldRowView+History.swift
//
//  Thoth
//  GitHub: https://github.com/boyaki-machine/Thoth
//

import Cocoa

// MARK: - Value History
//
// 過去の値（`Field.history`、上限 10 件）を行の下へ展開して見せる。
//
// **メニューではなく行の中に展開する。** 用途が「新しいパスワードを決める前に
// 過去の値を目視で見比べる」ことなので値は画面に出る。そのうえで
// `NSWindow.sharingType = .none`（画面共有・収録からの除外）に守られる場所は
// ウィンドウの中だけで、NSMenu や NSPopover は別ウィンドウに描かれるため守られない。
//
// 履歴はここでは**読み取り専用**。削除も「この値に戻す」も設けない。
// 認証システムのロールバック時に過去の値が退避経路になるため、
// この画面から失う手段を作らない（値を戻したいときは現在値を書き換えれば、
// その操作で現在値が自動的に履歴へ入る）。
extension SecureFieldRowView {

    /// 🕘 を見せるか（純粋関数のためユニットテスト可能）。
    ///
    /// - 履歴を残さない種別（TOTP / メモ）では出さない
    ///   （TOTP の secret は「極めて機微なため履歴を残さない」設計で、
    ///   旧データに残っていたとしても見せない）
    /// - **履歴が 1 件も無ければ出さない。** 押しても何も出ないボタンを見せない
    /// - 削除ボタンと同じくホバー中か編集中だけ出す。ただし読み取り専用でも
    ///   閲覧はできる（破壊的な操作ではないため、削除ボタンとは条件が違う）
    static func showsHistoryButton(kind: SecureMenuItem.Field.Kind, historyCount: Int,
                                   isHovered: Bool, hasFocus: Bool) -> Bool {
        guard kind.retainsValueHistory, historyCount > 0 else { return false }
        return isHovered || hasFocus
    }

    /// 履歴を新しい順に並べる（純粋関数）。
    /// 保存時は末尾に追記されるが、見たいのはたいてい直近の値
    static func sortedHistory(_ history: [SecureMenuItem.FieldHistoryEntry])
        -> [SecureMenuItem.FieldHistoryEntry] {
        return history.sorted { $0.replacedAt > $1.replacedAt }
    }

    /// この行が履歴を持っているか（右クリックメニューの有効判定にも使う）
    var hasValueHistory: Bool {
        return field.kind.retainsValueHistory && !field.history.isEmpty
    }

    /// 🕘 の出し入れ。スタックの中ほどに居るので `isHidden` は使わない
    /// （幅が畳まれてコピー ⧉ が横へ動いてしまう）。透明にしつつ押せなくする
    func updateHistoryButtonVisibility() {
        let shows = Self.showsHistoryButton(kind: field.kind,
                                            historyCount: field.history.count,
                                            isHovered: isHovered,
                                            hasFocus: hasEditingFocus)
        // 展開中は畳む導線を残しておく必要があるので出したままにする
        let visible = shows || isHistoryExpanded
        historyButton.alphaValue = visible ? 1 : 0
        historyButton.isEnabled = visible
    }

    // MARK: - Expansion

    /// 履歴の展開を切り替える。
    /// 畳むときは平文表示も戻す（開いたまま畳んで、次に開いたら平文、を避ける）
    func toggleHistory() {
        guard hasValueHistory else { NSSound.beep(); return }
        setHistoryExpanded(!isHistoryExpanded)
    }

    func setHistoryExpanded(_ expanded: Bool) {
        guard expanded != isHistoryExpanded else { return }
        isHistoryExpanded = expanded
        if expanded {
            buildHistoryPanel()
        } else {
            hideRevealedHistoryValues()
            historyPanel?.removeFromSuperview()
            historyPanel = nil
        }
        applyHistoryHeightConstraints()
        historyButton.image = NSImage(systemSymbolName: expanded ? "clock.fill" : "clock.arrow.circlepath",
                                      accessibilityDescription: nil)
        onHistoryToggled?(self)
    }

    /// 行の高さの基準を切り替える。
    /// 折りたたみ時は値エリアの下端、展開時は履歴パネルの下端が行の下端になる
    private func applyHistoryHeightConstraints() {
        collapsedBottomConstraint?.isActive = !isHistoryExpanded
        expandedBottomConstraint?.isActive = isHistoryExpanded
    }

    private func buildHistoryPanel() {
        let panel = NSStackView()
        panel.orientation = .vertical
        panel.alignment = .leading
        panel.spacing = 2
        panel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(panel)

        for entry in Self.sortedHistory(field.history) {
            let entryView = SecureHistoryEntryView(entry: entry, isPassword: field.isPassword)
            entryView.onCopy = { [weak self] view in
                guard let self = self else { return }
                self.onCopyHistoryValue?(self, view.entry)
            }
            // 平文表示が始まったら、期限切れを見張るためタイマーを動かしてもらう
            entryView.onRevealToggled = { [weak self] _ in
                guard let self = self else { return }
                self.onHistoryRevealToggled?(self)
            }
            panel.addArrangedSubview(entryView)
            entryView.widthAnchor.constraint(equalTo: panel.widthAnchor).isActive = true
        }

        // 値エリアの真下に、値の左端をそろえて差し込む
        NSLayoutConstraint.activate([
            panel.topAnchor.constraint(equalTo: valueContainerForHistory.bottomAnchor,
                                       constant: Layout.historyGap),
            panel.leadingAnchor.constraint(equalTo: valueContainerForHistory.leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
        historyPanel = panel
        expandedBottomConstraint = panel.bottomAnchor.constraint(equalTo: bottomAnchor)
    }

    // MARK: - Reveal discipline

    /// 展開中の履歴ビュー（無ければ空）
    var historyEntryViews: [SecureHistoryEntryView] {
        return historyPanel?.arrangedSubviews.compactMap { $0 as? SecureHistoryEntryView } ?? []
    }

    /// 履歴の平文表示をすべて伏せ字へ戻す
    func hideRevealedHistoryValues() {
        historyEntryViews.forEach { $0.hideRevealedValue() }
    }

    /// 期限を過ぎた履歴の平文表示を伏せ字へ戻す
    /// - Returns: 戻した件数
    @discardableResult
    func hideExpiredHistoryValues(now: Date = Date()) -> Int {
        return historyEntryViews.filter { $0.hideRevealedValueIfExpired(now: now) }.count
    }

    /// 履歴のどれかを平文表示中か（失効タイマーを回すかの判定に使う）
    var hasRevealedHistoryValue: Bool {
        return historyEntryViews.contains { $0.isRevealed }
    }
}
