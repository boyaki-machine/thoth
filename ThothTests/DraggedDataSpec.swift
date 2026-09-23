import Foundation
import Quick
import Nimble
@testable import Thoth

/// 復元されたら印を付ける型（安全でない復元で任意のクラスが生成されないことを確かめる）
final class DraggedDataSpecDecodeSpy: NSObject, NSCoding {
    static var decodeCount = 0

    override init() { super.init() }

    required init?(coder: NSCoder) {
        DraggedDataSpecDecodeSpy.decodeCount += 1
        super.init()
    }

    func encode(with coder: NSCoder) {}
}

// スニペットエディタのドラッグ&ドロップで運ぶ `CPYDraggedData` の直列化と並べ替え。
// ペイストボードには NSKeyedArchiver で載せるため、往復して同じ値に戻らないと
// ドロップ先が掴んでいた対象を見失う。
class DraggedDataSpec: QuickSpec {
    override class func spec() {

        describe("ペイストボード用の直列化（NSSecureCoding）") {

            it("アーカイブして復元すると、種別・識別子・並び順が元の値のまま戻る") {
                let draggedData = CPYDraggedData(type: .folder, folderIdentifier: NSUUID().uuidString, snippetIdentifier: nil, index: 10)
                guard let data = draggedData.archivedData() else { fail("archive failed"); return }

                let unarchiveData = CPYDraggedData.unarchived(from: data)
                expect(unarchiveData) != nil
                expect(unarchiveData?.type) == draggedData.type
                expect(unarchiveData?.folderIdentifier) == draggedData.folderIdentifier
                expect(unarchiveData?.snippetIdentifier) == nil
                expect(unarchiveData?.index) == draggedData.index
            }

            it("スニペットの識別子も往復する") {
                let draggedData = CPYDraggedData(type: .snippet, folderIdentifier: "F", snippetIdentifier: "S", index: 2)
                let restored = draggedData.archivedData().flatMap(CPYDraggedData.unarchived(from:))
                expect(restored?.type) == .snippet
                expect(restored?.snippetIdentifier) == "S"
            }

            it("別の型のデータは復元せず、その型のオブジェクトも生成しない（他アプリから差し込まれたデータ）") {
                DraggedDataSpecDecodeSpy.decodeCount = 0
                let crafted = try? NSKeyedArchiver.archivedData(withRootObject: DraggedDataSpecDecodeSpy(), requiringSecureCoding: false)
                expect(crafted) != nil
                expect(CPYDraggedData.unarchived(from: crafted ?? Data())) == nil
                expect(DraggedDataSpecDecodeSpy.decodeCount) == 0
            }

            it("壊れたデータは nil") {
                expect(CPYDraggedData.unarchived(from: Data([0x00, 0x01, 0x02]))) == nil
            }
        }

        describe("並べ替え（NSOutlineView のドロップ位置）") {
            let items = ["A", "B", "C", "D"]

            it("下へ動かす: B を C の後ろ（挿入位置 3）へ") {
                expect(CPYDraggedData.reordered(items, from: 1, to: 3)) == ["A", "C", "B", "D"]
            }

            it("上へ動かす: D を先頭（挿入位置 0）へ") {
                expect(CPYDraggedData.reordered(items, from: 3, to: 0)) == ["D", "A", "B", "C"]
            }

            it("末尾（挿入位置 = 要素数）へ動かす") {
                expect(CPYDraggedData.reordered(items, from: 0, to: 4)) == ["B", "C", "D", "A"]
            }

            it("同じ位置・直後へのドロップは動かさない") {
                expect(CPYDraggedData.reordered(items, from: 1, to: 1)) == nil
                expect(CPYDraggedData.reordered(items, from: 1, to: 2)) == nil
            }

            it("範囲外の位置は受け付けない（ずれた index で別の項目を消さない・落ちない）") {
                expect(CPYDraggedData.reordered(items, from: 7, to: 0)) == nil
                expect(CPYDraggedData.reordered(items, from: -1, to: 0)) == nil
                expect(CPYDraggedData.reordered(items, from: 0, to: 5)) == nil
                expect(CPYDraggedData.reordered(items, from: 0, to: -1)) == nil
            }
        }
    }
}
