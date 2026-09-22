//
//  RealmLibraryStore.swift
//
//  Thoth
//  GitHub: https://github.com/boyaki-machine/Thoth
//

import Foundation
import RealmSwift

// Realm を保存先とする保存層。
//
// v1.5 からは本番では使わない（保存先は SwiftData 版）。保存層の契約テストで
// SwiftData 版と挙動を揃えるための比較対象として残し、v1.6.x で Realm と合わせて削除する。
//
// Realm の構成（暗号鍵・スキーマ移行・テスト時のインメモリ差し替え）は
// RealmProvider の defaultConfiguration に従う。Realm はスレッドごとに
// インスタンスを持つため、呼び出しのたびに RealmProvider.defaultRealm() で取り直す。

/// 書き込みのあとにメインスレッドで変更を通知する
private func notifyLibraryDidChange(_ store: AnyObject) {
    DispatchQueue.main.async {
        NotificationCenter.default.post(name: .thothLibraryDidChange, object: store)
    }
}

// MARK: - History

final class RealmHistoryStore: HistoryStore {

    /// 暗号化された Realm の中に置くので、内容ハッシュをそのまま使う（従来どおり）
    func clipID(forContentHash hash: String) -> String {
        return hash
    }

    func clips(ascending: Bool) -> [ClipRecord] {
        return RealmProvider.defaultRealm().objects(CPYClip.self)
            .sorted(byKeyPath: #keyPath(CPYClip.updateTime), ascending: ascending)
            .map(ClipRecord.init)
    }

    func clip(id: String) -> ClipRecord? {
        return RealmProvider.defaultRealm().object(ofType: CPYClip.self, forPrimaryKey: id).map(ClipRecord.init)
    }

    var isEmpty: Bool {
        return RealmProvider.defaultRealm().objects(CPYClip.self).isEmpty
    }

    func upsert(_ clip: ClipRecord) {
        let realm = RealmProvider.defaultRealm()
        let object = CPYClip()
        object.dataHash = clip.id
        object.dataPath = clip.dataPath
        object.title = clip.title
        object.primaryType = clip.primaryType
        object.updateTime = clip.updateTime
        object.thumbnailPath = clip.thumbnailPath
        object.isColorCode = clip.isColorCode
        realm.transaction { realm.add(object, update: .all) }
        notifyLibraryDidChange(self)
    }

    @discardableResult
    func deleteClip(id: String) -> ClipRecord? {
        let realm = RealmProvider.defaultRealm()
        guard let object = realm.object(ofType: CPYClip.self, forPrimaryKey: id) else { return nil }
        let removed = ClipRecord(object)
        realm.transaction { realm.delete(object) }
        notifyLibraryDidChange(self)
        return removed
    }

    @discardableResult
    func deleteAllClips() -> [ClipRecord] {
        let realm = RealmProvider.defaultRealm()
        let objects = realm.objects(CPYClip.self)
        // Results.map は遅延評価なので、削除する前に値型へ確定させる
        let removed = Array(objects.map(ClipRecord.init))
        realm.transaction { realm.delete(objects) }
        notifyLibraryDidChange(self)
        return removed
    }

    @discardableResult
    func deleteClips(olderThan updateTime: Int) -> [ClipRecord] {
        let realm = RealmProvider.defaultRealm()
        let objects = realm.objects(CPYClip.self).filter("updateTime < %d", updateTime)
        // Results.map は遅延評価なので、削除する前に値型へ確定させる
        let removed = Array(objects.map(ClipRecord.init))
        guard !removed.isEmpty else { return [] }
        realm.transaction { realm.delete(objects) }
        notifyLibraryDidChange(self)
        return removed
    }
}

// MARK: - Snippets

final class RealmSnippetStore: SnippetStore {

    func folders() -> [SnippetFolderRecord] {
        return RealmProvider.defaultRealm().objects(CPYFolder.self)
            .sorted(byKeyPath: #keyPath(CPYFolder.index), ascending: true)
            .map(SnippetFolderRecord.init)
    }

    func folder(id: String) -> SnippetFolderRecord? {
        return RealmProvider.defaultRealm().object(ofType: CPYFolder.self, forPrimaryKey: id).map(SnippetFolderRecord.init)
    }

    func snippet(id: String) -> SnippetRecord? {
        return RealmProvider.defaultRealm().object(ofType: CPYSnippet.self, forPrimaryKey: id).map(SnippetRecord.init)
    }

    func saveFolder(_ folder: SnippetFolderRecord) {
        let realm = RealmProvider.defaultRealm()
        realm.transaction {
            let object = realm.object(ofType: CPYFolder.self, forPrimaryKey: folder.id) ?? {
                let created = CPYFolder()
                created.identifier = folder.id
                realm.add(created)
                return created
            }()
            object.index = folder.index
            object.enable = folder.enable
            object.title = folder.title
        }
        notifyLibraryDidChange(self)
    }

    func deleteFolder(id: String) {
        let realm = RealmProvider.defaultRealm()
        guard let object = realm.object(ofType: CPYFolder.self, forPrimaryKey: id) else { return }
        realm.transaction {
            realm.delete(object.snippets)
            realm.delete(object)
        }
        notifyLibraryDidChange(self)
    }

    func saveSnippet(_ snippet: SnippetRecord, folderID: String) {
        let realm = RealmProvider.defaultRealm()
        if let object = realm.object(ofType: CPYSnippet.self, forPrimaryKey: snippet.id) {
            realm.transaction { Self.apply(snippet, to: object) }
        } else {
            // どのフォルダにも属さないスニペットは作らない（メニューにも編集画面にも出ないため）
            guard let folder = realm.object(ofType: CPYFolder.self, forPrimaryKey: folderID) else { return }
            let object = CPYSnippet()
            object.identifier = snippet.id
            Self.apply(snippet, to: object)
            realm.transaction { folder.snippets.append(object) }
        }
        notifyLibraryDidChange(self)
    }

    func deleteSnippet(id: String) {
        let realm = RealmProvider.defaultRealm()
        guard let object = realm.object(ofType: CPYSnippet.self, forPrimaryKey: id) else { return }
        realm.transaction { realm.delete(object) }
        notifyLibraryDidChange(self)
    }

    func reorderFolders(_ ids: [String]) {
        let realm = RealmProvider.defaultRealm()
        realm.transaction {
            for (index, id) in ids.enumerated() {
                realm.object(ofType: CPYFolder.self, forPrimaryKey: id)?.index = index
            }
        }
        notifyLibraryDidChange(self)
    }

    func reorderSnippets(_ ids: [String], inFolder folderID: String) {
        let realm = RealmProvider.defaultRealm()
        guard let folder = realm.object(ofType: CPYFolder.self, forPrimaryKey: folderID) else { return }
        realm.transaction {
            for (index, id) in ids.enumerated() {
                guard let snippet = realm.object(ofType: CPYSnippet.self, forPrimaryKey: id) else { continue }
                // 他のフォルダにあるスニペットは、元のフォルダから外してこのフォルダへ移す
                if let source = snippet.folder, source.identifier != folderID {
                    if let position = source.snippets.index(of: snippet) {
                        source.snippets.remove(at: position)
                    }
                    folder.snippets.append(snippet)
                }
                snippet.index = index
            }
        }
        notifyLibraryDidChange(self)
    }

    func importFolders(_ folders: [SnippetFolderRecord]) {
        let realm = RealmProvider.defaultRealm()
        realm.transaction {
            for record in folders {
                let folder = CPYFolder()
                folder.identifier = record.id
                folder.index = record.index
                folder.enable = record.enable
                folder.title = record.title
                for snippetRecord in record.snippets {
                    let snippet = CPYSnippet()
                    snippet.identifier = snippetRecord.id
                    Self.apply(snippetRecord, to: snippet)
                    folder.snippets.append(snippet)
                }
                realm.add(folder)
            }
        }
        notifyLibraryDidChange(self)
    }

    private static func apply(_ record: SnippetRecord, to object: CPYSnippet) {
        object.index = record.index
        object.enable = record.enable
        object.title = record.title
        object.content = record.content
    }
}

// MARK: - Record Conversion

extension ClipRecord {
    init(_ clip: CPYClip) {
        self.init(id: clip.dataHash,
                  dataPath: clip.dataPath,
                  title: clip.title,
                  primaryType: clip.primaryType,
                  updateTime: clip.updateTime,
                  thumbnailPath: clip.thumbnailPath,
                  isColorCode: clip.isColorCode)
    }
}

extension SnippetRecord {
    init(_ snippet: CPYSnippet) {
        self.init(id: snippet.identifier,
                  index: snippet.index,
                  enable: snippet.enable,
                  title: snippet.title,
                  content: snippet.content)
    }
}

extension SnippetFolderRecord {
    init(_ folder: CPYFolder) {
        self.init(id: folder.identifier,
                  index: folder.index,
                  enable: folder.enable,
                  title: folder.title,
                  snippets: folder.snippets
                    .sorted(byKeyPath: #keyPath(CPYSnippet.index), ascending: true)
                    .map(SnippetRecord.init))
    }
}
