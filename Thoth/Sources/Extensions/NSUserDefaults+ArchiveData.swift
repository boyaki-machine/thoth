//
//  NSUserDefaults+ArchiveData.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Econa77 on 2016/06/23.
//
//  Copyright © 2015-2018 Clipy Project.
//

import Foundation

extension UserDefaults {
    /// NSKeyedArchiver の形で保存した値を、`allowedClasses` に挙げたクラス
    /// （と、基本のコレクション・文字列・数値）だけで読み戻す。それ以外のクラスを含むときは nil。
    ///
    /// 環境設定の値（`KeyCombo` や除外アプリ）は旧式 NSCoding のため `requiresSecureCoding = false`
    /// でしか読めないが、そのまま読むと、環境設定のファイル（同じユーザーの他のプロセスが
    /// `defaults write` で書き換えられる）に仕込まれた任意のクラスが Thoth の中で生成される
    /// （安全でないデシリアライズ）。Thoth はキーチェーンのセキュア情報やアクセシビリティの
    /// 権限を持つため、アーカイブが参照するクラス名を先に検査してから読む
    func unarchivedObject(forKey key: String, allowedClasses: [AnyClass]) -> Any? {
        guard let data = object(forKey: key) as? Data else { return nil }
        return KeyedArchiveGuard.unarchivedObject(from: data, allowedClassNames: Set(allowedClasses.map(NSStringFromClass)))
    }
}

/// 旧式 NSCoding のアーカイブを、参照するクラスを限定して読み戻す（純粋関数のためユニットテスト可能）
enum KeyedArchiveGuard {
    /// どのアーカイブでも許すクラス。生成しても副作用の無い基本型だけ
    static let baseClassNames: Set<String> = [
        "NSObject",
        "NSArray", "NSMutableArray",
        "NSDictionary", "NSMutableDictionary",
        "NSString", "NSMutableString",
        "NSNumber"
    ]

    /// アーカイブが参照するクラス名がすべて `allowedClassNames`（と `baseClassNames`）に含まれるか。
    ///
    /// NSKeyedUnarchiver は `$objects` にあるクラス記述の `$classname` を生成し、見つからなければ
    /// `$classes`（親クラスの並び）や `$classhints` を代わりに試すため、そのすべてを検査する。
    /// プロパティリストとして読めないデータも false
    static func referencesOnlyAllowedClasses(_ data: Data, allowedClassNames: Set<String>) -> Bool {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let objects = plist["$objects"] as? [Any] else { return false }
        let allowed = allowedClassNames.union(baseClassNames)
        func isAllowedName(_ value: Any) -> Bool {
            guard let name = value as? String else { return false }
            return allowed.contains(name)
        }
        func isAllowedList(_ value: Any) -> Bool {
            guard let names = value as? [Any] else { return false }
            return names.allSatisfy(isAllowedName)
        }
        for case let object as [String: Any] in objects {
            if let name = object["$classname"], !isAllowedName(name) { return false }
            if let names = object["$classes"], !isAllowedList(names) { return false }
            if let hints = object["$classhints"], !isAllowedList(hints) { return false }
        }
        return true
    }

    /// 参照するクラスを検査してから、ルートのオブジェクトを読み戻す。検査に通らなければ nil
    static func unarchivedObject(from data: Data, allowedClassNames: Set<String>) -> Any? {
        guard referencesOnlyAllowedClasses(data, allowedClassNames: allowedClassNames),
              let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        unarchiver.requiresSecureCoding = false
        return unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey)
    }
}
