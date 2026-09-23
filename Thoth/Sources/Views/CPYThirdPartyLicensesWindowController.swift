//
//  CPYThirdPartyLicensesWindowController.swift
//
//  Thoth
//

import Cocoa

// MARK: - Window Controller

/// サードパーティライブラリのライセンス一覧を表示するウィンドウのコントローラ。
/// アプリ起動中に一度だけ生成されるシングルトン。
final class CPYThirdPartyLicensesWindowController: NSWindowController {

    static let shared: CPYThirdPartyLicensesWindowController = {
        let viewController = CPYThirdPartyLicensesViewController()
        let window = NSWindow(contentViewController: viewController)
        window.title = L10n.thirdPartyLicenses
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.setContentSize(NSSize(width: 560, height: 600))
        window.center()
        return CPYThirdPartyLicensesWindowController(window: window)
    }()

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(self)
    }
}

// MARK: - View Controller

/// サードパーティライセンス表示画面。
/// 表示内容は Acknowledgements.md。`scripts/update-acknowledgements.swift` が
/// Swift Package の解決結果（Package.resolved）と各パッケージの LICENSE から作る。
final class CPYThirdPartyLicensesViewController: NSViewController {

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 600))
        setupUI()
    }
}

// MARK: - Layout
fileprivate extension CPYThirdPartyLicensesViewController {
    func setupUI() {
        let scrollView = NSScrollView(frame: view.bounds)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder

        let textView = NSTextView(frame: scrollView.bounds)
        textView.autoresizingMask = [.width]
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.string = Self.loadAcknowledgements()

        scrollView.documentView = textView
        view.addSubview(scrollView)
    }

    static func loadAcknowledgements() -> String {
        guard let url = Bundle.main.url(forResource: "Acknowledgements", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return L10n.thirdPartyLicensesLoadFailed
        }
        return text
    }
}
