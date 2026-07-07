//
//  CPYShortcutsPreferenceViewController.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Econa77 on 2016/02/26.
//
//  Copyright © 2015-2018 Clipy Project.
//

import Cocoa
import KeyHolder
import Magnet

class CPYShortcutsPreferenceViewController: NSViewController {

    // MARK: - Properties
    @IBOutlet private weak var mainShortcutRecordView: RecordView!
    @IBOutlet private weak var historyShortcutRecordView: RecordView!
    @IBOutlet private weak var snippetShortcutRecordView: RecordView!
    @IBOutlet private weak var clearHistoryShortcutRecordView: RecordView!
    @IBOutlet private weak var secureShortcutRecordView: RecordView!

    // MARK: - Initialize
    override func loadView() {
        super.loadView()
        mainShortcutRecordView.delegate = self
        historyShortcutRecordView.delegate = self
        snippetShortcutRecordView.delegate = self
        clearHistoryShortcutRecordView.delegate = self
        secureShortcutRecordView.delegate = self
        prepareHotKeys()
    }

}

// MARK: - Shortcut
private extension CPYShortcutsPreferenceViewController {
    func prepareHotKeys() {
        mainShortcutRecordView.keyCombo = AppEnvironment.current.hotKeyService.mainKeyCombo
        historyShortcutRecordView.keyCombo = AppEnvironment.current.hotKeyService.historyKeyCombo
        snippetShortcutRecordView.keyCombo = AppEnvironment.current.hotKeyService.snippetKeyCombo
        clearHistoryShortcutRecordView.keyCombo = AppEnvironment.current.hotKeyService.clearHistoryKeyCombo
        secureShortcutRecordView.keyCombo = AppEnvironment.current.hotKeyService.secureKeyCombo
    }
}

// MARK: - RecordView Delegate
extension CPYShortcutsPreferenceViewController: RecordViewDelegate {
    func recordViewShouldBeginRecording(_ recordView: RecordView) -> Bool {
        return true
    }

    func recordView(_ recordView: RecordView, canRecordKeyCombo keyCombo: KeyCombo) -> Bool {
        return true
    }

    func recordView(_ recordView: RecordView, didChangeKeyCombo keyCombo: KeyCombo?) {
        switch recordView {
        case mainShortcutRecordView:
            AppEnvironment.current.hotKeyService.change(with: .main, keyCombo: keyCombo)
        case historyShortcutRecordView:
            AppEnvironment.current.hotKeyService.change(with: .history, keyCombo: keyCombo)
        case snippetShortcutRecordView:
            AppEnvironment.current.hotKeyService.change(with: .snippet, keyCombo: keyCombo)
        case clearHistoryShortcutRecordView:
            AppEnvironment.current.hotKeyService.changeClearHistoryKeyCombo(keyCombo)
        case secureShortcutRecordView:
            AppEnvironment.current.hotKeyService.change(with: .secure, keyCombo: keyCombo)
        default: break
        }
    }

    func recordViewDidEndRecording(_ recordView: RecordView) {}
}
