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

/// LICENSE とは別に、配布物で表示が求められる通知のファイル（Apache-2.0 の NOTICE、同梱コードの一覧など）
let noticeFileNames = ["NOTICE", "NOTICE.txt", "NOTICE.md", "THIRD-PARTY-NOTICES"]

/// パッケージが中に取り込んでいる第三者のコードのうち、上の通知ファイルに載っていないもののライセンス。
/// realm-core は src/external/ のコードもビルドしてアプリに入る（v1.5.1 の SPM 化から、ソースからビルドしている）。
/// Intel の十進数ライブラリ・JSON for Modern C++・MPark.Variant は THIRD-PARTY-NOTICES に載っているが、
/// jsonsl は載っていないので個別に足す（s2・bson は realm-core 本体と同じ Apache-2.0）
let vendoredLicenses: [String: [(title: String, path: String)]] = [
    "realm-core": [("jsonsl", "src/external/jsonsl/LICENSE")],
]

/// 通知ファイルと、取り込まれている第三者コードのライセンスを、LICENSE の後ろに付ける本文にする
func additionalNotices(in directory: URL, packageName: String) -> String {
    var parts: [String] = []
    for name in noticeFileNames {
        let url = directory.appendingPathComponent(name)
        if let text = try? String(contentsOf: url, encoding: .utf8) {
            parts.append("### \(name)\n\n\(text.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
    }
    for vendored in vendoredLicenses[packageName] ?? [] {
        let url = directory.appendingPathComponent(vendored.path)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            fail("\(packageName) に \(vendored.path) が見つかりません（取り込まれているコードが変わった可能性があります）")
        }
        parts.append("### \(vendored.title) (\(vendored.path))\n\n\(text.trimmingCharacters(in: .whitespacesAndNewlines))")
    }
    return parts.map { "\n\n" + $0 }.joined()
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
    let directory = checkoutsURL.appendingPathComponent(pin.name)
    guard let license = licenseText(in: directory) else {
        fail("\(pin.name) のライセンスファイルが見つかりません（\(checkoutsURL.path)/\(pin.name)）")
    }
    sections.append((pin.name, "\(pin.name) \(pin.version)", license + additionalNotices(in: directory, packageName: pin.name)))
}

let localPackages = (try? fileManager.contentsOfDirectory(at: localPackagesURL, includingPropertiesForKeys: nil)) ?? []
for package in localPackages where fileManager.fileExists(atPath: package.appendingPathComponent("Package.swift").path) {
    guard let license = licenseText(in: package) else {
        fail("\(package.path) にライセンスファイルがありません")
    }
    let name = package.lastPathComponent
    sections.append((name, "\(name) (Packages/\(name))", license + additionalNotices(in: package, packageName: name)))
}

sections.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

// Thoth の元になったアプリ（MIT）。MIT はバイナリの配布物にも著作権表示を含めることを求めるので、
// ライブラリより先に載せる（リポジトリの LICENSE・LICENSE_CLIPMENU と同じ本文）
let upstreams: [(heading: String, file: String)] = [
    ("Clipy (the application Thoth is derived from)", "LICENSE"),
    ("ClipMenu (the origin of Clipy)", "LICENSE_CLIPMENU"),
]
var text = "# Acknowledgements\nThis application is derived from the following open-source applications:\n"
for upstream in upstreams {
    guard let license = try? String(contentsOf: root.appendingPathComponent(upstream.file), encoding: .utf8) else {
        fail("\(upstream.file) を読めません")
    }
    text += "\n## \(upstream.heading)\n\n\(license.trimmingCharacters(in: .whitespacesAndNewlines))\n"
}
text += "\nThis application makes use of the following third party libraries:\n"
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
