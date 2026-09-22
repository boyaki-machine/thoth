#!/usr/bin/env swift
//
// サードパーティライセンス一覧（Thoth/Resources/Acknowledgements.md と NOTICE）を、
// Swift Package の解決結果（Package.resolved）から作り直す。
//
// 使い方（リポジトリのどこからでもよい）:
//   scripts/update-acknowledgements.swift [SourcePackages のフォルダ]
//
// フォルダを省略すると、build/SourcePackages へパッケージを取得してから作る。
// パッケージを足したり版を変えたりしたら実行して、結果をコミットする。
// 実行し忘れると AcknowledgementsSpec が落ちる（末尾の指紋が Package.resolved と合わなくなる）。
//
// v1.5.1 で CocoaPods をやめるまでは、`pod install` が同じ一覧を自動で作っていた。

import CryptoKit
import Foundation

/// テストだけで使うパッケージ。アプリに入らないので一覧に載せない
let testOnlyPackages: Set<String> = [
    "quick", "nimble", "cwlcatchexception", "cwlpreconditiontesting",
    "swift-algorithms", "swift-argument-parser", "swift-numerics",
]

let fileManager = FileManager.default
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL
let resolvedURL = root.appendingPathComponent("Thoth.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved")
let localPackagesURL = root.appendingPathComponent("Packages")
let outputs = [root.appendingPathComponent("Thoth/Resources/Acknowledgements.md"), root.appendingPathComponent("NOTICE")]

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

struct Pin {
    let identity: String
    let name: String
    let version: String
}

/// Package.resolved の固定版を読む。名前は取得先のフォルダ名（URL の最後の要素）と同じ
func readPins() -> [Pin] {
    guard let data = try? Data(contentsOf: resolvedURL),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let pins = json["pins"] as? [[String: Any]] else {
        fail("\(resolvedURL.path) を読めません")
    }
    return pins.map { pin in
        guard let identity = pin["identity"] as? String,
              let location = pin["location"] as? String,
              let state = pin["state"] as? [String: Any],
              let version = (state["version"] as? String) ?? (state["revision"] as? String) else {
            fail("Package.resolved の形式が想定と違います: \(pin)")
        }
        var name = URL(string: location)?.lastPathComponent ?? identity
        if name.hasSuffix(".git") { name.removeLast(4) }
        return Pin(identity: identity, name: name, version: version)
    }
}

/// 一覧の末尾に書く指紋。AcknowledgementsSpec が同じ計算で照合する
func fingerprint(of pins: [Pin]) -> String {
    let canonical = pins.map { "\($0.identity) \($0.version)" }.sorted().joined(separator: "\n")
    return SHA256.hash(data: Data(canonical.utf8)).map { String(format: "%02x", $0) }.joined()
}

func licenseText(in directory: URL) -> String? {
    let candidates = ["LICENSE", "LICENSE.md", "LICENSE.txt", "LICENCE", "LICENCE.md", "COPYING"]
    for candidate in candidates {
        let url = directory.appendingPathComponent(candidate)
        if let text = try? String(contentsOf: url, encoding: .utf8) {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
    return nil
}

func run(_ arguments: [String]) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    process.arguments = arguments
    process.currentDirectoryURL = root
    do {
        try process.run()
    } catch {
        fail("\(arguments.joined(separator: " ")) を実行できません: \(error)")
    }
    process.waitUntilExit()
    if process.terminationStatus != 0 {
        fail("\(arguments.joined(separator: " ")) が失敗しました（終了コード \(process.terminationStatus)）")
    }
}

// MARK: - 取得

let sourcePackagesURL: URL
if CommandLine.arguments.count > 1 {
    sourcePackagesURL = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
} else {
    sourcePackagesURL = root.appendingPathComponent("build/SourcePackages")
    print("==> パッケージを取得します: \(sourcePackagesURL.path)")
    fflush(stdout)  // xcodebuild の出力より先に出す
    run(["xcodebuild", "-resolvePackageDependencies", "-project", "Thoth.xcodeproj", "-scheme", "Thoth",
         "-clonedSourcePackagesDirPath", sourcePackagesURL.path])
}
let checkoutsURL = sourcePackagesURL.appendingPathComponent("checkouts")

// MARK: - 一覧を作る

let pins = readPins()
var sections: [(name: String, heading: String, license: String)] = []

for pin in pins where !testOnlyPackages.contains(pin.identity) {
    guard let license = licenseText(in: checkoutsURL.appendingPathComponent(pin.name)) else {
        fail("\(pin.name) のライセンスファイルが見つかりません（\(checkoutsURL.path)/\(pin.name)）")
    }
    sections.append((pin.name, "\(pin.name) \(pin.version)", license))
}

let localPackages = (try? fileManager.contentsOfDirectory(at: localPackagesURL, includingPropertiesForKeys: nil)) ?? []
for package in localPackages where fileManager.fileExists(atPath: package.appendingPathComponent("Package.swift").path) {
    guard let license = licenseText(in: package) else {
        fail("\(package.path) にライセンスファイルがありません")
    }
    let name = package.lastPathComponent
    sections.append((name, "\(name) (Packages/\(name))", license))
}

sections.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

var text = "# Acknowledgements\nThis application makes use of the following third party libraries:\n"
for section in sections {
    text += "\n## \(section.heading)\n\n\(section.license)\n"
}
text += "\nGenerated by scripts/update-acknowledgements.swift from Package.resolved (pins SHA-256: \(fingerprint(of: pins)))\n"

for output in outputs {
    do {
        try text.write(to: output, atomically: true, encoding: .utf8)
    } catch {
        fail("\(output.path) に書けません: \(error)")
    }
}
print("==> \(sections.count) 件のライセンスを書き出しました: \(outputs.map { $0.path.replacingOccurrences(of: root.path + "/", with: "") }.joined(separator: ", "))")
