// swift-tools-version:6.0
//
// LetsMove 1.25（https://github.com/potionfactory/LetsMove）を Swift Package にしたもの。
// 本家は Swift Package Manager に対応していないため、v1.5.1 で CocoaPods をやめたときに
// リポジトリへ取り込んだ。変更点は README.md を参照。

import PackageDescription

let package = Package(
    name: "LetsMove",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "LetsMove", targets: ["LetsMove"])
    ],
    targets: [
        .target(
            name: "LetsMove",
            resources: [.process("Resources")],
            cSettings: [
                // 本家どおり ARC を使わない（autorelease などを直接呼ぶ実装。Podspec も requires_arc = false）。
                // 取り込んだ他者のコードのため、非推奨 API などの警告は出さない
                .unsafeFlags(["-fno-objc-arc", "-w"])
            ]
        )
    ]
)
