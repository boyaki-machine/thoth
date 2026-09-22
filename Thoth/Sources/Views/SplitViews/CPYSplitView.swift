//
//  CPYSplitView.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Econa77 on 2016/06/29.
//
//  Copyright © 2015-2018 Clipy Project.
//

import Cocoa

class CPYSplitView: NSSplitView {

    // MARK: - Properties
    /// 既定値は旧 `NSColor.scrollBarColor`（macOS 11 で非推奨）と同じ固定グレー
    @IBInspectable var separatorColor: NSColor = NSColor(white: 2.0 / 3.0, alpha: 1) {
        didSet {
            needsDisplay = true
        }
    }

    // MARK: - Draw
    override func drawDivider(in rect: NSRect) {
        separatorColor.setFill()
        rect.fill()
    }

}
