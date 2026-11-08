import Foundation
import Quick
import Nimble
import Magnet
@testable import Thoth

/// 復元されたら数える型（許可していないクラスが生成されないことを確かめる）
final class KeyedArchiveGuardSpecDecodeSpy: NSObject, NSCoding {
    static var decodeCount = 0

    override init() { super.init() }

    required init?(coder: NSCoder) {
        KeyedArchiveGuardSpecDecodeSpy.decodeCount += 1
        super.init()
    }

    func encode(with coder: NSCoder) {}
}

// 環境設定（UserDefaults）に旧式 NSCoding で保存した値の読み戻し。
// 環境設定のファイルは同じユーザーの他のプロセスから書き換えられるため、
// アーカイブが参照するクラスを許可した型に限ってから復元する。
class KeyedArchiveGuardSpec: QuickSpec {
    private typealias Guard = KeyedArchiveGuard

    private static func archive(_ object: Any) -> Data {
        return (try? NSKeyedArchiver.archivedData(withRootObject: object, requiringSecureCoding: false)) ?? Data()
    }

    /// アーカイブのプロパティリストを書き換えて作り直す（細工されたアーカイブの再現）
    private static func tampered(_ data: Data, _ transform: (inout [Any]) -> Void) -> Data {
        guard var plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              var objects = plist["$objects"] as? [Any] else { return Data() }
        transform(&objects)
        plist["$objects"] = objects
        return (try? PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)) ?? Data()
    }

    private static let keyComboNames: Set<String> = [NSStringFromClass(KeyCombo.self)]

    // BDD スペックの spec() は多数の it ブロックを含み長くなるため関数長ルールを緩める
    // swiftlint:disable:next function_body_length
    override class func spec() {

        describe("許可したクラスだけのアーカイブ") {

            it("KeyCombo を読み戻せる") {
                let keyCombo = KeyCombo(QWERTYKeyCode: 9, carbonModifiers: 768)
                let decoded = Guard.unarchivedObject(from: archive(keyCombo!), allowedClassNames: keyComboNames) as? KeyCombo
                expect(decoded) == keyCombo
            }

            it("フォルダごとの [String: KeyCombo] を読み戻せる") {
                let combos = ["folder": KeyCombo(doubledCocoaModifiers: .command)!]
                let decoded = Guard.unarchivedObject(from: archive(combos), allowedClassNames: keyComboNames)
                expect((decoded as? [String: KeyCombo])?["folder"]) == combos["folder"]
            }

            it("除外アプリの [CPYAppInfo] を読み戻せる") {
                let info = ["CFBundleIdentifier": "com.example.app", "CFBundleName": "Example"] as [String: AnyObject]
                let apps = [CPYAppInfo(info: info)!]
                let decoded = Guard.unarchivedObject(from: archive(apps),
                                                     allowedClassNames: [NSStringFromClass(CPYAppInfo.self)])
                expect(decoded as? [CPYAppInfo]) == apps
            }

            it("空の配列も読み戻せる") {
                let decoded = Guard.unarchivedObject(from: archive([CPYAppInfo]()),
                                                     allowedClassNames: [NSStringFromClass(CPYAppInfo.self)])
                expect((decoded as? [CPYAppInfo])?.isEmpty) == true
            }
        }

        describe("許可していないクラスを含むアーカイブ") {

            beforeEach {
                KeyedArchiveGuardSpecDecodeSpy.decodeCount = 0
            }

            it("許可していないクラスは生成せずに nil を返す") {
                let data = archive(KeyedArchiveGuardSpecDecodeSpy())
                expect(Guard.unarchivedObject(from: data, allowedClassNames: keyComboNames) == nil) == true
                expect(KeyedArchiveGuardSpecDecodeSpy.decodeCount) == 0
            }

            it("コレクションの中に紛れていても生成しない") {
                let data = archive(["folder": KeyedArchiveGuardSpecDecodeSpy()])
                expect(Guard.unarchivedObject(from: data, allowedClassNames: keyComboNames) == nil) == true
                expect(KeyedArchiveGuardSpecDecodeSpy.decodeCount) == 0
            }

            it("別の用途で許可した型（KeyCombo の読み出しに CPYAppInfo）も拒む") {
                let info = ["CFBundleIdentifier": "com.example.app", "CFBundleName": "Example"] as [String: AnyObject]
                let data = archive([CPYAppInfo(info: info)!])
                expect(Guard.referencesOnlyAllowedClasses(data, allowedClassNames: keyComboNames)) == false
            }

            it("基本型でも一覧に無いもの（NSURL・NSDate）は拒む") {
                expect(Guard.referencesOnlyAllowedClasses(archive(NSURL(string: "https://example.com")!),
                                                          allowedClassNames: [])) == false
                expect(Guard.referencesOnlyAllowedClasses(archive(NSDate()), allowedClassNames: [])) == false
            }

            // $classname が見つからないとき、NSKeyedUnarchiver は $classes の親クラスを代わりに試す
            it("$classes に許可していないクラスが入っていれば拒む") {
                let data = tampered(archive(KeyCombo(QWERTYKeyCode: 9, carbonModifiers: 768)!)) { objects in
                    for index in objects.indices {
                        guard var object = objects[index] as? [String: Any], object["$classname"] != nil else { continue }
                        object["$classes"] = [NSStringFromClass(KeyCombo.self), NSStringFromClass(KeyedArchiveGuardSpecDecodeSpy.self)]
                        objects[index] = object
                    }
                }
                expect(Guard.referencesOnlyAllowedClasses(data, allowedClassNames: keyComboNames)) == false
            }

            it("$classhints に許可していないクラスが入っていれば拒む") {
                let data = tampered(archive(KeyCombo(QWERTYKeyCode: 9, carbonModifiers: 768)!)) { objects in
                    for index in objects.indices {
                        guard var object = objects[index] as? [String: Any], object["$classname"] != nil else { continue }
                        object["$classhints"] = [NSStringFromClass(KeyedArchiveGuardSpecDecodeSpy.self)]
                        objects[index] = object
                    }
                }
                expect(Guard.referencesOnlyAllowedClasses(data, allowedClassNames: keyComboNames)) == false
            }

            it("クラス名が文字列でなければ拒む") {
                let data = tampered(archive(KeyCombo(QWERTYKeyCode: 9, carbonModifiers: 768)!)) { objects in
                    for index in objects.indices {
                        guard var object = objects[index] as? [String: Any], object["$classname"] != nil else { continue }
                        object["$classname"] = 42
                        objects[index] = object
                    }
                }
                expect(Guard.referencesOnlyAllowedClasses(data, allowedClassNames: keyComboNames)) == false
            }
        }

        describe("壊れたデータ") {

            it("プロパティリストでないデータ・空のデータは nil（落ちない）") {
                expect(Guard.unarchivedObject(from: Data("not a plist".utf8), allowedClassNames: keyComboNames) == nil) == true
                expect(Guard.unarchivedObject(from: Data(), allowedClassNames: keyComboNames) == nil) == true
            }

            it("$objects の無いプロパティリストは拒む") {
                let data = (try? PropertyListSerialization.data(fromPropertyList: ["a": 1], format: .binary, options: 0)) ?? Data()
                expect(Guard.referencesOnlyAllowedClasses(data, allowedClassNames: keyComboNames)) == false
            }
        }

        describe("UserDefaults からの読み出し") {
            let suiteName = "io.github.boyaki-machine.ThothTests.KeyedArchiveGuard"
            var defaults: UserDefaults!

            beforeEach {
                defaults = UserDefaults(suiteName: suiteName)
                defaults.removePersistentDomain(forName: suiteName)
                KeyedArchiveGuardSpecDecodeSpy.decodeCount = 0
            }
            afterEach {
                defaults.removePersistentDomain(forName: suiteName)
            }

            it("許可したクラスなら読み戻せる") {
                let keyCombo = KeyCombo(QWERTYKeyCode: 0, cocoaModifiers: .shift)!
                defaults.set(archive(keyCombo), forKey: "combo")
                expect(defaults.unarchivedObject(forKey: "combo", allowedClasses: [KeyCombo.self]) as? KeyCombo) == keyCombo
            }

            it("書き換えられた値は生成せずに nil を返す") {
                defaults.set(archive(KeyedArchiveGuardSpecDecodeSpy()), forKey: "combo")
                expect(defaults.unarchivedObject(forKey: "combo", allowedClasses: [KeyCombo.self]) == nil) == true
                expect(KeyedArchiveGuardSpecDecodeSpy.decodeCount) == 0
            }

            it("値が無い・Data でなければ nil") {
                expect(defaults.unarchivedObject(forKey: "missing", allowedClasses: [KeyCombo.self]) == nil) == true
                defaults.set("text", forKey: "combo")
                expect(defaults.unarchivedObject(forKey: "combo", allowedClasses: [KeyCombo.self]) == nil) == true
            }
        }
    }
}
