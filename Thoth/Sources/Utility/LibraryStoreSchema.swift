//
//  LibraryStoreSchema.swift
//
//  Thoth
//  GitHub: https://github.com/boyaki-machine/Thoth
//

import Foundation
import SwiftData

// SwiftData 版の保存層のスキーマ。
//
// 平文で置くのは「並べる・引く・構造を保つ」ための列だけにし、表示に使う中身は
// FieldCipher で暗号化した JSON（sealedPayload）にまとめる。中身の項目を増やしても
// SwiftData のスキーマ移行が要らないよう、JSON 側に version を持たせる。
// 将来のスキーマ変更に備え、最初から VersionedSchema / SchemaMigrationPlan を使う。

enum LibraryStoreSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        return [StoredClip.self, StoredFolder.self, StoredSnippet.self, StoreMeta.self]
    }

    /// 履歴 1 件。id は内容キー（HMAC）、中身（タイトル・種別など）は暗号化
    @Model
    final class StoredClip {
        @Attribute(.unique) var id: String
        var updateTime: Int
        /// クリップ実データ（.data）のパス。ファイル名は UUID で、内容の手掛かりを含まない
        var dataPath: String
        /// ClipPayload を暗号化したもの
        var sealedPayload: Data
        /// 縮小したサムネイル（PNG）を暗号化したもの。画像クリップのみ
        @Attribute(.externalStorage) var sealedThumbnail: Data?

        init(id: String, updateTime: Int, dataPath: String, sealedPayload: Data, sealedThumbnail: Data? = nil) {
            self.id = id
            self.updateTime = updateTime
            self.dataPath = dataPath
            self.sealedPayload = sealedPayload
            self.sealedThumbnail = sealedThumbnail
        }
    }

    /// スニペットフォルダ 1 件。名前は暗号化
    @Model
    final class StoredFolder {
        @Attribute(.unique) var id: String
        var index: Int
        var enable: Bool
        /// FolderPayload を暗号化したもの
        var sealedPayload: Data
        /// 並び順は保たれないので、読むときは必ず index で並べ直す
        @Relationship(deleteRule: .cascade, inverse: \StoredSnippet.folder)
        var snippets: [StoredSnippet] = []

        init(id: String, index: Int, enable: Bool, sealedPayload: Data) {
            self.id = id
            self.index = index
            self.enable = enable
            self.sealedPayload = sealedPayload
        }
    }

    /// スニペット 1 件。名前・本文は暗号化
    @Model
    final class StoredSnippet {
        @Attribute(.unique) var id: String
        var index: Int
        var enable: Bool
        /// SnippetPayload を暗号化したもの
        var sealedPayload: Data
        var folder: StoredFolder?

        init(id: String, index: Int, enable: Bool, sealedPayload: Data) {
            self.id = id
            self.index = index
            self.enable = enable
            self.sealedPayload = sealedPayload
        }
    }

    /// 保存層そのものについての記録（Realm からの移行の記録など）
    @Model
    final class StoreMeta {
        @Attribute(.unique) var key: String
        var migratedAt: Date?
        var sourceClipCount: Int
        var sourceFolderCount: Int
        var sourceSnippetCount: Int

        init(key: String, migratedAt: Date?, sourceClipCount: Int, sourceFolderCount: Int, sourceSnippetCount: Int) {
            self.key = key
            self.migratedAt = migratedAt
            self.sourceClipCount = sourceClipCount
            self.sourceFolderCount = sourceFolderCount
            self.sourceSnippetCount = sourceSnippetCount
        }
    }
}

enum LibraryStoreMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        return [LibraryStoreSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        return []
    }
}

typealias StoredClip = LibraryStoreSchemaV1.StoredClip
typealias StoredFolder = LibraryStoreSchemaV1.StoredFolder
typealias StoredSnippet = LibraryStoreSchemaV1.StoredSnippet
typealias StoreMeta = LibraryStoreSchemaV1.StoreMeta

// MARK: - Payloads（暗号化する中身）

/// 履歴の中身。version は中身の形式の版（項目を足したら上げ、古い版も読めるようにする）
struct ClipPayload: Codable, Equatable {
    var version = 1
    var title: String
    var primaryType: String
    var isColorCode: Bool
    /// サムネイルのキャッシュキー（PINCache を廃止するまでの間だけ使う）
    var thumbnailPath: String
}

struct FolderPayload: Codable, Equatable {
    var version = 1
    var title: String
}

struct SnippetPayload: Codable, Equatable {
    var version = 1
    var title: String
    var content: String
}
