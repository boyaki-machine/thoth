import Foundation
import Quick
import Nimble
@testable import Thoth

// スニペットエディタのドラッグ&ドロップで運ぶ `CPYDraggedData` の直列化。
// ペイストボードには NSKeyedArchiver で載せるため、往復して同じ値に戻らないと
// ドロップ先が掴んでいた対象を見失う。
class DraggedDataSpec: QuickSpec {
    override class func spec() {

        describe("ペイストボード用の直列化（NSCoding）") {

            it("アーカイブして復元すると、種別・識別子・並び順が元の値のまま戻る") {
                let draggedData = CPYDraggedData(type: .folder, folderIdentifier: NSUUID().uuidString, snippetIdentifier: nil, index: 10)
                let data = NSKeyedArchiver.archivedData(withRootObject: draggedData)

                let unarchiveData = NSKeyedUnarchiver.unarchiveObject(with: data) as? CPYDraggedData
                expect(unarchiveData) != nil
                expect(unarchiveData?.type) == draggedData.type
                expect(unarchiveData?.folderIdentifier) == draggedData.folderIdentifier
                expect(unarchiveData?.snippetIdentifier) == nil
                expect(unarchiveData?.index) == draggedData.index
            }

        }

    }
}
