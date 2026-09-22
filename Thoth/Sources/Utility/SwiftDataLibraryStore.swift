//
//  SwiftDataLibraryStore.swift
//
//  Thoth
//  GitHub: https://github.com/boyaki-machine/Thoth
//

import Foundation
import SwiftData

/// SwiftData 版の保存層の本体（コンテナ・暗号化・直列キューを持つ）。
/// 履歴・スニペットの保存層（SwiftDataHistoryStore / SwiftDataSnippetStore）がこれを共有して使う。
///
/// ## スレッド
/// ModelContext はスレッドをまたげないため、専用の直列キューの中でだけ使う。
/// 保存層のメソッドはどのスレッドから呼んでもよく、中で直列キューへ同期的に入る
/// （同じキューの中から呼ばれたときはそのまま実行する）。戻り値は値型なのでスレッドをまたげる。
///
/// ## 暗号化
/// 表示に使う中身はすべて FieldCipher で暗号化してから保存し、読むときに復号する。
/// 復号できない行（改ざん・鍵違い）は読み飛ばし、記録を残す。
final class SwiftDataLibrary {

    /// 暗号化の付加データに入れるモデル名。**変えると保存済みのデータが読めなくなる**
    enum Entity {
        static let clip = "StoredClip"
        static let folder = "StoredFolder"
        static let snippet = "StoredSnippet"
    }

    // MARK: - Properties

    let container: ModelContainer
    let cipher: FieldCipher
    private let queue = DispatchQueue(label: "io.github.boyaki-machine.Thoth.LibraryStore")
    private let queueKey = DispatchSpecificKey<Void>()
    /// 直列キューの中でだけ触る
    private var context: ModelContext?

    // MARK: - Initialize

    init(container: ModelContainer, cipher: FieldCipher) {
        self.container = container
        self.cipher = cipher
        queue.setSpecific(key: queueKey, value: ())
    }

    /// ファイルに保存する保存層を開く
    static func open(at url: URL, cipher: FieldCipher) throws -> SwiftDataLibrary {
        let schema = Schema(versionedSchema: LibraryStoreSchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, url: url)
        let container = try ModelContainer(for: schema, migrationPlan: LibraryStoreMigrationPlan.self,
                                           configurations: configuration)
        return SwiftDataLibrary(container: container, cipher: cipher)
    }

    /// メモリ上だけの保存層を作る（テスト・鍵が使えない起動用）
    static func inMemory(cipher: FieldCipher) throws -> SwiftDataLibrary {
        let schema = Schema(versionedSchema: LibraryStoreSchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, migrationPlan: LibraryStoreMigrationPlan.self,
                                           configurations: configuration)
        return SwiftDataLibrary(container: container, cipher: cipher)
    }

    // MARK: - Context

    /// 直列キューの中で ModelContext を使う
    func perform<T>(_ block: (ModelContext) throws -> T) rethrows -> T {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            return try block(currentContext())
        }
        return try queue.sync { try block(currentContext()) }
    }

    /// 書き込んで保存し、変更を通知する
    func write(notifying store: AnyObject, _ block: (ModelContext) throws -> Void) {
        perform { context in
            do {
                try block(context)
                try context.save()
            } catch {
                context.rollback()
                NSLog("[SwiftDataLibrary] write failed: \(error)")
                return
            }
            // 通知の処理で保存層を掴み続けない（メインキューが空くまでコンテナが解放されなくなる）
            DispatchQueue.main.async { [weak store] in
                NotificationCenter.default.post(name: .thothLibraryDidChange, object: store)
            }
        }
    }

    private func currentContext() -> ModelContext {
        if let context = context { return context }
        let created = ModelContext(container)
        created.autosaveEnabled = false
        context = created
        return created
    }

    /// 保存済みのデータを今の鍵で復号できるか（空なら true）。
    /// キーチェーンがリセットされて別の鍵が作られたときなどに false になる
    var isReadable: Bool {
        return perform { context in
            func first<T: PersistentModel>(_ type: T.Type) -> T? {
                var descriptor = FetchDescriptor<T>()
                descriptor.fetchLimit = 1
                return (try? context.fetch(descriptor))?.first
            }
            func canOpen(_ sealed: Data, _ entity: String, _ id: String) -> Bool {
                return cipher.open(sealed, context: FieldCipher.Context(entity: entity, id: id, field: "payload")) != nil
            }
            if let clip = first(StoredClip.self), !canOpen(clip.sealedPayload, Entity.clip, clip.id) { return false }
            if let folder = first(StoredFolder.self), !canOpen(folder.sealedPayload, Entity.folder, folder.id) { return false }
            if let snippet = first(StoredSnippet.self), !canOpen(snippet.sealedPayload, Entity.snippet, snippet.id) { return false }
            return true
        }
    }

    // MARK: - Seal / Open

    func seal<T: Encodable>(_ payload: T, entity: String, id: String, field: String = "payload") throws -> Data {
        return try cipher.sealJSON(payload, context: FieldCipher.Context(entity: entity, id: id, field: field))
    }

    func open<T: Decodable>(_ type: T.Type, from sealed: Data, entity: String, id: String, field: String = "payload") -> T? {
        guard let payload = cipher.openJSON(type, from: sealed, context: FieldCipher.Context(entity: entity, id: id, field: field)) else {
            NSLog("[SwiftDataLibrary] could not open \(entity) \(field); the row is skipped")
            return nil
        }
        return payload
    }
}

// MARK: - History

final class SwiftDataHistoryStore: HistoryStore {

    private let library: SwiftDataLibrary
    private static let entity = SwiftDataLibrary.Entity.clip

    init(library: SwiftDataLibrary) {
        self.library = library
    }

    func clipID(forContentHash hash: String) -> String {
        return library.cipher.contentID(for: hash)
    }

    func clips(ascending: Bool) -> [ClipRecord] {
        return library.perform { context in
            let descriptor = FetchDescriptor<StoredClip>(sortBy: [SortDescriptor(\.updateTime, order: ascending ? .forward : .reverse)])
            return ((try? context.fetch(descriptor)) ?? []).compactMap(record)
        }
    }

    func clip(id: String) -> ClipRecord? {
        return library.perform { context in
            find(id, in: context).flatMap(record)
        }
    }

    var isEmpty: Bool {
        return library.perform { context in
            ((try? context.fetchCount(FetchDescriptor<StoredClip>())) ?? 0) == 0
        }
    }

    func upsert(_ clip: ClipRecord, thumbnail: Data?) {
        library.write(notifying: self) { context in
            let payload = ClipPayload(title: clip.title, primaryType: clip.primaryType, isColorCode: clip.isColorCode)
            let sealed = try library.seal(payload, entity: Self.entity, id: clip.id)
            let sealedThumbnail = try thumbnail.map { try library.cipher.seal($0, context: thumbnailContext(clip.id)) }
            if let existing = find(clip.id, in: context) {
                existing.updateTime = clip.updateTime
                existing.dataPath = clip.dataPath
                existing.sealedPayload = sealed
                existing.hasThumbnail = sealedThumbnail != nil
                existing.sealedThumbnail = sealedThumbnail
            } else {
                context.insert(StoredClip(id: clip.id, updateTime: clip.updateTime, dataPath: clip.dataPath,
                                          sealedPayload: sealed, sealedThumbnail: sealedThumbnail))
            }
        }
    }

    func thumbnail(forClipID id: String) -> Data? {
        return library.perform { context in
            guard let sealed = find(id, in: context)?.sealedThumbnail else { return nil }
            return library.cipher.open(sealed, context: thumbnailContext(id))
        }
    }

    /// 履歴をまとめて追加する（移行用。1 回の保存で書き込む）
    func importClips(_ clips: [ClipRecord]) {
        library.write(notifying: self) { context in
            for clip in clips {
                let payload = ClipPayload(title: clip.title, primaryType: clip.primaryType, isColorCode: clip.isColorCode)
                context.insert(StoredClip(id: clip.id, updateTime: clip.updateTime, dataPath: clip.dataPath,
                                          sealedPayload: try library.seal(payload, entity: Self.entity, id: clip.id)))
            }
        }
    }

    @discardableResult
    func deleteClip(id: String) -> ClipRecord? {
        var removed: ClipRecord?
        library.write(notifying: self) { context in
            guard let existing = find(id, in: context) else { return }
            removed = record(existing)
            context.delete(existing)
        }
        return removed
    }

    @discardableResult
    func deleteAllClips() -> [ClipRecord] {
        return delete(matching: nil)
    }

    @discardableResult
    func deleteClips(olderThan updateTime: Int) -> [ClipRecord] {
        return delete(matching: #Predicate<StoredClip> { $0.updateTime < updateTime })
    }

    // MARK: - Private

    private func delete(matching predicate: Predicate<StoredClip>?) -> [ClipRecord] {
        var removed = [ClipRecord]()
        library.write(notifying: self) { context in
            let targets = try context.fetch(FetchDescriptor<StoredClip>(predicate: predicate))
            removed = targets.compactMap(record)
            targets.forEach { context.delete($0) }
        }
        return removed
    }

    private func thumbnailContext(_ id: String) -> FieldCipher.Context {
        return FieldCipher.Context(entity: Self.entity, id: id, field: "thumbnail")
    }

    private func find(_ id: String, in context: ModelContext) -> StoredClip? {
        var descriptor = FetchDescriptor<StoredClip>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    private func record(_ stored: StoredClip) -> ClipRecord? {
        guard let payload = library.open(ClipPayload.self, from: stored.sealedPayload, entity: Self.entity, id: stored.id) else { return nil }
        return ClipRecord(id: stored.id, dataPath: stored.dataPath, title: payload.title,
                          primaryType: payload.primaryType, updateTime: stored.updateTime,
                          hasThumbnail: stored.hasThumbnail, isColorCode: payload.isColorCode)
    }
}

// MARK: - Snippets

final class SwiftDataSnippetStore: SnippetStore {

    private let library: SwiftDataLibrary
    private static let folderEntity = SwiftDataLibrary.Entity.folder
    private static let snippetEntity = SwiftDataLibrary.Entity.snippet

    init(library: SwiftDataLibrary) {
        self.library = library
    }

    func folders() -> [SnippetFolderRecord] {
        return library.perform { context in
            let descriptor = FetchDescriptor<StoredFolder>(sortBy: [SortDescriptor(\.index)])
            return ((try? context.fetch(descriptor)) ?? []).compactMap(record)
        }
    }

    func folder(id: String) -> SnippetFolderRecord? {
        return library.perform { context in
            findFolder(id, in: context).flatMap(record)
        }
    }

    func snippet(id: String) -> SnippetRecord? {
        return library.perform { context in
            findSnippet(id, in: context).flatMap(record)
        }
    }

    func saveFolder(_ folder: SnippetFolderRecord) {
        library.write(notifying: self) { context in
            let sealed = try library.seal(FolderPayload(title: folder.title), entity: Self.folderEntity, id: folder.id)
            if let existing = findFolder(folder.id, in: context) {
                existing.index = folder.index
                existing.enable = folder.enable
                existing.sealedPayload = sealed
            } else {
                context.insert(StoredFolder(id: folder.id, index: folder.index, enable: folder.enable, sealedPayload: sealed))
            }
        }
    }

    func deleteFolder(id: String) {
        library.write(notifying: self) { context in
            guard let existing = findFolder(id, in: context) else { return }
            // 中のスニペットは関連の削除規則（.cascade）で一緒に消える
            context.delete(existing)
        }
    }

    func saveSnippet(_ snippet: SnippetRecord, folderID: String) {
        library.write(notifying: self) { context in
            let sealed = try sealPayload(of: snippet)
            if let existing = findSnippet(snippet.id, in: context) {
                existing.index = snippet.index
                existing.enable = snippet.enable
                existing.sealedPayload = sealed
            } else {
                // どのフォルダにも属さないスニペットは作らない（メニューにも編集画面にも出ないため）
                guard let folder = findFolder(folderID, in: context) else { return }
                let stored = StoredSnippet(id: snippet.id, index: snippet.index, enable: snippet.enable, sealedPayload: sealed)
                context.insert(stored)
                stored.folder = folder
            }
        }
    }

    func deleteSnippet(id: String) {
        library.write(notifying: self) { context in
            guard let existing = findSnippet(id, in: context) else { return }
            context.delete(existing)
        }
    }

    func reorderFolders(_ ids: [String]) {
        library.write(notifying: self) { context in
            for (index, id) in ids.enumerated() {
                findFolder(id, in: context)?.index = index
            }
        }
    }

    func reorderSnippets(_ ids: [String], inFolder folderID: String) {
        library.write(notifying: self) { context in
            guard let folder = findFolder(folderID, in: context) else { return }
            for (index, id) in ids.enumerated() {
                guard let snippet = findSnippet(id, in: context) else { continue }
                // 他のフォルダにあるスニペットはこのフォルダへ移す
                if snippet.folder?.id != folderID {
                    snippet.folder = folder
                }
                snippet.index = index
            }
        }
    }

    func importFolders(_ folders: [SnippetFolderRecord]) {
        library.write(notifying: self) { context in
            for record in folders {
                let sealedFolder = try library.seal(FolderPayload(title: record.title), entity: Self.folderEntity, id: record.id)
                let folder = StoredFolder(id: record.id, index: record.index, enable: record.enable, sealedPayload: sealedFolder)
                context.insert(folder)
                for snippetRecord in record.snippets {
                    let stored = StoredSnippet(id: snippetRecord.id, index: snippetRecord.index, enable: snippetRecord.enable,
                                               sealedPayload: try sealPayload(of: snippetRecord))
                    context.insert(stored)
                    stored.folder = folder
                }
            }
        }
    }

    // MARK: - Private

    private func sealPayload(of snippet: SnippetRecord) throws -> Data {
        return try library.seal(SnippetPayload(title: snippet.title, content: snippet.content),
                                entity: Self.snippetEntity, id: snippet.id)
    }

    private func findFolder(_ id: String, in context: ModelContext) -> StoredFolder? {
        var descriptor = FetchDescriptor<StoredFolder>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    private func findSnippet(_ id: String, in context: ModelContext) -> StoredSnippet? {
        var descriptor = FetchDescriptor<StoredSnippet>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    private func record(_ stored: StoredFolder) -> SnippetFolderRecord? {
        guard let payload = library.open(FolderPayload.self, from: stored.sealedPayload, entity: Self.folderEntity, id: stored.id) else { return nil }
        let snippets = stored.snippets.sorted { $0.index < $1.index }.compactMap(record)
        return SnippetFolderRecord(id: stored.id, index: stored.index, enable: stored.enable, title: payload.title, snippets: snippets)
    }

    private func record(_ stored: StoredSnippet) -> SnippetRecord? {
        guard let payload = library.open(SnippetPayload.self, from: stored.sealedPayload, entity: Self.snippetEntity, id: stored.id) else { return nil }
        return SnippetRecord(id: stored.id, index: stored.index, enable: stored.enable, title: payload.title, content: payload.content)
    }
}
