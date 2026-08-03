//
//  CPYSecureInfoDetailViewController+Row.swift
//
//  Thoth
//  GitHub: https://github.com/boyaki-machine/Thoth
//

import Cocoa

// MARK: - Periodic refresh
//
// TOTP のコード更新と、平文表示の期限切れ確認を 1 本のタイマーで兼ねる。
extension CPYSecureInfoDetailViewController {

    /// TOTP 行があるか、平文表示中の行があるときだけタイマーを動かす
    func startRefreshTimerIfNeeded() {
        stopTOTPTimer()
        guard fieldRows.contains(where: { $0.field.isTOTP || $0.isRevealed }) else { return }
        // NSWindow は通常の RunLoop で動くため .common モードに追加すれば安定して発火する
        let timer = Timer(timeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            self?.refreshPeriodically()
        }
        RunLoop.main.add(timer, forMode: .common)
        totpTimer = timer
    }

    func stopTOTPTimer() {
        totpTimer?.invalidate()
        totpTimer = nil
    }

    private func refreshPeriodically() {
        refreshTOTPRows()
        expireRevealedValues()
    }

    /// 期限を過ぎた平文表示を伏せ字へ戻す
    /// - Returns: 戻した行の数
    @discardableResult
    func expireRevealedValues(now: Date = Date()) -> Int {
        let expired = fieldRows.filter { $0.hideRevealedValueIfExpired(now: now) }.count
        if expired > 0 { startRefreshTimerIfNeeded() }
        return expired
    }

    /// TOTP 行のコードと残り秒数を現在時刻で描き直す
    func refreshTOTPRows() {
        for row in fieldRows where row.field.isTOTP {
            guard let params = TOTPService.parse(row.field.value) else {
                row.updateTOTPDisplay(code: nil, remainingSeconds: 0)
                continue
            }
            row.updateTOTPDisplay(code: totpService.code(for: params),
                                  remainingSeconds: totpService.remainingSeconds(for: params))
        }
    }

    // MARK: - Actions

    /// 値をコピーする。履歴に残さないよう必ず秘匿マーカー付きで書き込み、
    /// 一定時間後（その間に別のコピーが無ければ）自動でクリアする
    func copyValue(of field: SecureMenuItem.Field) {
        guard let value = copyableValue(of: field) else {
            NSSound.beep()
            return
        }
        AppEnvironment.current.pasteService.copyConcealedToPasteboard(with: value)
        AppEnvironment.current.pasteService.scheduleConcealedClear()
    }

    /// コピー対象の文字列。TOTP は secret ではなくその時点のコードを返す
    func copyableValue(of field: SecureMenuItem.Field) -> String? {
        guard field.isTOTP else { return field.value }
        guard let params = TOTPService.parse(field.value) else { return nil }
        return totpService.code(for: params)
    }

    func openURL(of field: SecureMenuItem.Field) {
        guard let url = Self.openableURL(from: field.value) else {
            NSSound.beep()
            return
        }
        NSWorkspace.shared.open(url)
    }

    /// ブラウザで開いてよい URL かを判定する（純粋関数のためユニットテスト可能）。
    ///
    /// **http / https だけを許可する。** インポートしたデータや打ち間違いに
    /// `file://` や独自スキームが入っていると、ボタン 1 つで意図しないファイルや
    /// アプリを開いてしまうため。ホスト名の無い URL も弾く
    static func openableURL(from value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty else { return nil }
        return url
    }
}
