//
//  SecureInfoUndoStack.swift
//
//  Thoth
//  GitHub: https://github.com/boyaki-machine/Thoth
//

import Foundation

// MARK: - Undo Action

/// 取り消しの対象になった操作の種類。メニューの表示（「"編集" を取り消す」）に使う。
///
/// 文字列ではなく enum で持つのは、スナップショット自体を UI 非依存に保つため
/// （ユニットテストから L10n を経由せずに検証できる）。
enum SecureInfoUndoAction: String, Equatable {
    /// タイトル・ラベル・値・マスク指定の変更、フィールドの追加・削除・並べ替え
    case edit
    /// アイテムの追加
    case addItem
    /// アイテムの削除
    case deleteItem
    /// アイテムの並べ替え
    case reorderItems
    /// ファイルからの取り込み
    case importItems

    var localizedName: String {
        switch self {
        case .edit:          return L10n.secureInfoActionEdit
        case .addItem:       return L10n.secureInfoActionAdd
        case .deleteItem:    return L10n.secureInfoActionDelete
        case .reorderItems:  return L10n.secureInfoActionReorder
        case .importItems:   return L10n.secureInfoActionImport
        }
    }
}

// MARK: - Snapshot

/// ある時点の「Keychain へ保存済みの状態」一式。
///
/// `SecureMenuItem` は値型なので、丸ごと控えておけば取り消しに必要な情報が揃う。
/// 差分ではなく全体を持つのは、フィールドの削除・並べ替え・アイテムの入れ替えといった
/// 種類の違う変更を 1 つの仕組みで戻せるようにするため。
struct SecureInfoSnapshot: Equatable {
    /// 保存済みの全アイテム（displayOrder 順）
    let items: [SecureMenuItem]
    /// 選択中アイテムの保存済みの姿（編集中の作業コピーではない）
    let draft: SecureMenuItem?
    let selectedItemID: String?
    /// この状態のあとに行われた操作。取り消しメニューの表示に使う
    let action: SecureInfoUndoAction

    /// 保持しているデータが同じか（`action` は比較しない）。
    /// 空振りの保存で同じ内容が積み重なるのを防ぐために使う
    func hasSameContent(as other: SecureInfoSnapshot) -> Bool {
        return items == other.items && draft == other.draft && selectedItemID == other.selectedItemID
    }

    /// 操作名だけ差し替えた複製を返す（やり直し側へ積むときに使う）
    func labeled(_ action: SecureInfoUndoAction) -> SecureInfoSnapshot {
        return SecureInfoSnapshot(items: items, draft: draft, selectedItemID: selectedItemID, action: action)
    }
}

// MARK: - Undo Stack

/// セキュア情報確認ウィンドウの取り消し／やり直しスタック。
///
/// 積む単位は **「Keychain へ 1 回書き込むごと」**。打鍵ごとの取り消しは
/// AppKit 標準のテキスト編集 Undo に任せ、こちらは確定した変更だけを扱う
/// （保存が編集の区切りでしか走らない設計と粒度を揃えている）。
///
/// **保持する内容は平文の機微情報**なので、ウィンドウを閉じるとき・データを読み直すとき・
/// 他の画面の変更でスタックが陳腐化したときには必ず `clear()` すること。
final class SecureInfoUndoStack {

    /// 保持する世代数の上限。平文をいつまでも溜め込まないよう頭打ちにする
    static let maxDepth = 20

    /// テストから中身を確認できるよう internal
    private(set) var undoSnapshots: [SecureInfoSnapshot] = []
    private(set) var redoSnapshots: [SecureInfoSnapshot] = []

    var canUndo: Bool { !undoSnapshots.isEmpty }
    var canRedo: Bool { !redoSnapshots.isEmpty }

    /// 次に取り消される操作（メニューの表示に使う）
    var undoAction: SecureInfoUndoAction? { undoSnapshots.last?.action }
    /// 次にやり直される操作
    var redoAction: SecureInfoUndoAction? { redoSnapshots.last?.action }

    /// 変更を加える**直前**の状態を積む。
    ///
    /// 直前に積んだものと内容が同じなら何もしない。20 秒のフォールバック保存などで
    /// 中身の変わらない保存が走っても、取り消しが空振りする世代を作らないため。
    /// - Returns: 実際に積んだ場合 true
    @discardableResult
    func push(_ snapshot: SecureInfoSnapshot) -> Bool {
        if let last = undoSnapshots.last, last.hasSameContent(as: snapshot) { return false }
        undoSnapshots.append(snapshot)
        Self.trim(&undoSnapshots)
        // 新しい変更が入ったらやり直しの分岐は消える（一般的な Undo の作法）
        redoSnapshots.removeAll()
        return true
    }

    /// 1 世代戻す。
    /// - Parameter current: 現在の状態（やり直し用に控える）
    /// - Returns: 復元すべき状態。戻せるものが無ければ nil
    func undo(current: SecureInfoSnapshot) -> SecureInfoSnapshot? {
        guard let snapshot = undoSnapshots.popLast() else { return nil }
        // やり直しの表示名は「取り消した操作の名前」。current 自身の action は
        // さらに前の操作を指しているので、ここで貼り替える
        redoSnapshots.append(current.labeled(snapshot.action))
        Self.trim(&redoSnapshots)
        return snapshot
    }

    /// 1 世代進める
    func redo(current: SecureInfoSnapshot) -> SecureInfoSnapshot? {
        guard let snapshot = redoSnapshots.popLast() else { return nil }
        undoSnapshots.append(current.labeled(snapshot.action))
        Self.trim(&undoSnapshots)
        return snapshot
    }

    /// 保持している状態をすべて捨てる。**平文を保持しているため必ず呼べるようにしておくこと**
    func clear() {
        undoSnapshots.removeAll()
        redoSnapshots.removeAll()
    }

    private static func trim(_ snapshots: inout [SecureInfoSnapshot]) {
        guard snapshots.count > maxDepth else { return }
        snapshots.removeFirst(snapshots.count - maxDepth)
    }
}
