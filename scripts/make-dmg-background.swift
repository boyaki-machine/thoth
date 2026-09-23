#!/usr/bin/env swift
//
// 配布用 DMG のウィンドウ背景（Thoth.app → Applications の矢印と案内文）を描く。
// make_dmg.sh から呼ばれる。
//
// 使い方:
//   scripts/make-dmg-background.swift <出力先.png> <倍率: 1 または 2>
//
// 寸法とアイコンの位置は make_dmg.sh の DMG_* と揃えること（ここでは引数にせず定数で持つ）。
//
// 背景は中間の明るさの色にしている。Finder はアイコン名を、ライトモードでは黒、
// ダークモードでは白で描くので、明るい背景だとダークモードで名前が読めなくなる。
// 中間の明るさなら、黒・白のどちらの文字とも 4.5:1 前後のコントラストが取れる。

import AppKit

let windowWidth: CGFloat = 560
let windowHeight: CGFloat = 400      // Finder のウィンドウより少し高く描き、下端の見切れに備える
let iconCenterY: CGFloat = 160       // 上端からの距離（Finder の座標と同じ向き）
let appIconCenterX: CGFloat = 150
let applicationsCenterX: CGFloat = 410
let iconSize: CGFloat = 128

let arguments = CommandLine.arguments
guard arguments.count == 3, let scale = Double(arguments[2]), scale >= 1 else {
    FileHandle.standardError.write(Data("使い方: make-dmg-background.swift <出力先.png> <倍率>\n".utf8))
    exit(1)
}
let outputURL = URL(fileURLWithPath: arguments[1])

guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                 pixelsWide: Int(windowWidth * scale), pixelsHigh: Int(windowHeight * scale),
                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { exit(1) }
// 点の大きさで描き、ファイルには倍率分のピクセルで書く（Retina 用の @2x）
rep.size = NSSize(width: windowWidth, height: windowHeight)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

/// 上端からの距離を、AppKit の座標（下端が 0）に直す
func flipped(_ yFromTop: CGFloat) -> CGFloat { windowHeight - yFromTop }

// 背景: 中間の明るさのスレート色。上をわずかに明るくする
let top = NSColor(srgbRed: 0.50, green: 0.55, blue: 0.62, alpha: 1)
let bottom = NSColor(srgbRed: 0.44, green: 0.48, blue: 0.55, alpha: 1)
NSGradient(starting: top, ending: bottom)?.draw(in: NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight), angle: -90)

// 矢印: 2 つのアイコンの間。アイコンの端から少し離す
let arrowY = flipped(iconCenterY)
let arrowStart = appIconCenterX + iconSize / 2 + 18
let arrowEnd = applicationsCenterX - iconSize / 2 - 18
let headLength: CGFloat = 22
let headHalfHeight: CGFloat = 16
let shaftHalfHeight: CGFloat = 5

let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: arrowStart, y: arrowY + shaftHalfHeight))
arrow.line(to: NSPoint(x: arrowEnd - headLength, y: arrowY + shaftHalfHeight))
arrow.line(to: NSPoint(x: arrowEnd - headLength, y: arrowY + headHalfHeight))
arrow.line(to: NSPoint(x: arrowEnd, y: arrowY))
arrow.line(to: NSPoint(x: arrowEnd - headLength, y: arrowY - headHalfHeight))
arrow.line(to: NSPoint(x: arrowEnd - headLength, y: arrowY - shaftHalfHeight))
arrow.line(to: NSPoint(x: arrowStart, y: arrowY - shaftHalfHeight))
arrow.close()
arrow.lineJoinStyle = .round
NSColor(white: 1, alpha: 0.92).setFill()
arrow.fill()

// 案内文: ウィンドウ下部の中央
let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center
func drawCaption(_ text: String, size: CGFloat, weight: NSFont.Weight, yFromTop: CGFloat) {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: NSColor.white,
        .paragraphStyle: paragraph,
    ]
    let string = NSAttributedString(string: text, attributes: attributes)
    let height = string.size().height
    string.draw(in: NSRect(x: 0, y: flipped(yFromTop) - height / 2, width: windowWidth, height: height))
}
drawCaption("Thoth を Applications フォルダへドラッグしてインストール", size: 14, weight: .semibold, yFromTop: 285)
drawCaption("Drag Thoth to the Applications folder to install", size: 12, weight: .regular, yFromTop: 307)

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
do {
    try png.write(to: outputURL)
} catch {
    FileHandle.standardError.write(Data("書き出せません: \(error)\n".utf8))
    exit(1)
}
