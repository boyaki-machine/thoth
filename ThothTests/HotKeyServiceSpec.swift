import Quick
import Nimble
import Magnet
import Carbon
@testable import Thoth

class HotKeyServiceSpec: QuickSpec {
    override class func spec() {
        migrateHotKeySpecs()
        saveHotKeySpecs()
        keyCombosSpecs()
        clearHistoryHotKeySpecs()
        folderHotKeySpecs()
    }

    private static func migrateHotKeySpecs() {
        describe("Migrate HotKey") {

            beforeEach {
                let defaults = UserDefaults.standard
                defaults.removeObject(forKey: Constants.UserDefaults.hotKeys)
                defaults.removeObject(forKey: Constants.HotKey.migrateNewKeyCombo)
                defaults.removeObject(forKey: Constants.HotKey.mainKeyCombo)
                defaults.removeObject(forKey: Constants.HotKey.historyKeyCombo)
                defaults.removeObject(forKey: Constants.HotKey.snippetKeyCombo)
                defaults.synchronize()
            }

            it("Migrate default settings") {
                let service = HotKeyService()
                expect(service.mainKeyCombo) == nil
                expect(service.historyKeyCombo) == nil
                expect(service.snippetKeyCombo) == nil

                let defaults = UserDefaults.standard

                expect(defaults.bool(forKey: Constants.HotKey.migrateNewKeyCombo)) == false
                service.setupDefaultHotKeys()
                expect(defaults.bool(forKey: Constants.HotKey.migrateNewKeyCombo)) == true

                expect(service.mainKeyCombo) != nil
                expect(service.mainKeyCombo?.QWERTYKeyCode) == 9
                expect(service.mainKeyCombo?.modifiers) == 768
                expect(service.mainKeyCombo?.doubledModifiers) == false
                expect(service.mainKeyCombo?.keyEquivalent.uppercased()) == "V"

                expect(service.historyKeyCombo) != nil
                expect(service.historyKeyCombo?.QWERTYKeyCode) == 9
                expect(service.historyKeyCombo?.modifiers) == 4352
                expect(service.historyKeyCombo?.doubledModifiers) == false
                expect(service.historyKeyCombo?.keyEquivalent.uppercased()) == "V"

                expect(service.snippetKeyCombo) != nil
                expect(service.snippetKeyCombo?.QWERTYKeyCode) == 11
                expect(service.snippetKeyCombo?.modifiers) == 768
                expect(service.snippetKeyCombo?.doubledModifiers) == false
                expect(service.snippetKeyCombo?.keyEquivalent.uppercased()) == "B"
            }

            it("Migrate customize settings") {
                let service = HotKeyService()
                expect(service.mainKeyCombo) == nil
                expect(service.historyKeyCombo) == nil
                expect(service.snippetKeyCombo) == nil

                let defaults = UserDefaults.standard
                let defaultKeyCombos: [String: Any] = [Constants.Menu.clip: ["keyCode": 0, "modifiers": 4352],
                                                       Constants.Menu.history: ["keyCode": 9, "modifiers": 768],
                                                       Constants.Menu.snippet: ["keyCode": 11, "modifiers": 4352]]
                defaults.register(defaults: [Constants.UserDefaults.hotKeys: defaultKeyCombos])
                defaults.synchronize()

                expect(defaults.bool(forKey: Constants.HotKey.migrateNewKeyCombo)) == false
                service.setupDefaultHotKeys()
                expect(defaults.bool(forKey: Constants.HotKey.migrateNewKeyCombo)) == true

                expect(service.mainKeyCombo) != nil
                expect(service.mainKeyCombo?.QWERTYKeyCode) == 0
                expect(service.mainKeyCombo?.modifiers) == 4352
                expect(service.mainKeyCombo?.doubledModifiers) == false
                expect(service.mainKeyCombo?.keyEquivalent.uppercased()) == "A"

                expect(service.historyKeyCombo) != nil
                expect(service.historyKeyCombo?.QWERTYKeyCode) == 9
                expect(service.historyKeyCombo?.modifiers) == 768
                expect(service.historyKeyCombo?.doubledModifiers) == false
                expect(service.historyKeyCombo?.keyEquivalent.uppercased()) == "V"

                expect(service.snippetKeyCombo) != nil
                expect(service.snippetKeyCombo?.QWERTYKeyCode) == 11
                expect(service.snippetKeyCombo?.modifiers) == 4352
                expect(service.snippetKeyCombo?.doubledModifiers) == false
                expect(service.snippetKeyCombo?.keyEquivalent.uppercased()) == "B"
            }

            afterEach {
                let defaults = UserDefaults.standard
                defaults.removeObject(forKey: Constants.UserDefaults.hotKeys)
                defaults.removeObject(forKey: Constants.HotKey.migrateNewKeyCombo)
                defaults.removeObject(forKey: Constants.HotKey.mainKeyCombo)
                defaults.removeObject(forKey: Constants.HotKey.historyKeyCombo)
                defaults.removeObject(forKey: Constants.HotKey.snippetKeyCombo)
                defaults.synchronize()
            }
        }
    }

    private static func saveHotKeySpecs() {
        describe("Save HotKey") {

            beforeEach {
                let defaults = UserDefaults.standard
                defaults.set(true, forKey: Constants.HotKey.migrateNewKeyCombo)
                defaults.removeObject(forKey: Constants.HotKey.mainKeyCombo)
                defaults.removeObject(forKey: Constants.HotKey.historyKeyCombo)
                defaults.removeObject(forKey: Constants.HotKey.snippetKeyCombo)
                defaults.synchronize()
            }

            it("Save key combos") {
                let service = HotKeyService()
                expect(service.mainKeyCombo) == nil
                expect(service.historyKeyCombo) == nil
                expect(service.snippetKeyCombo) == nil

                let defautls = UserDefaults.standard
                expect(defautls.archiveDataForKey(KeyCombo.self, key: Constants.HotKey.mainKeyCombo)) == nil
                expect(defautls.archiveDataForKey(KeyCombo.self, key: Constants.HotKey.historyKeyCombo)) == nil
                expect(defautls.archiveDataForKey(KeyCombo.self, key: Constants.HotKey.snippetKeyCombo)) == nil

                service.setupDefaultHotKeys()
                expect(service.mainKeyCombo) == nil
                expect(service.historyKeyCombo) == nil
                expect(service.snippetKeyCombo) == nil

                let mainKeyCombo = KeyCombo(QWERTYKeyCode: 9, carbonModifiers: 768)
                let historyKeyCombo = KeyCombo(doubledCocoaModifiers: .command)
                let snippetKeyCombo = KeyCombo(QWERTYKeyCode: 0, cocoaModifiers: .shift)

                service.change(with: .main, keyCombo: mainKeyCombo)
                service.change(with: .history, keyCombo: historyKeyCombo)
                service.change(with: .snippet, keyCombo: snippetKeyCombo)

                let savedMainKeyCombo = defautls.archiveDataForKey(KeyCombo.self, key: Constants.HotKey.mainKeyCombo)
                let savedHistoryKeyCombo = defautls.archiveDataForKey(KeyCombo.self, key: Constants.HotKey.historyKeyCombo)
                let savedSnippetKeyCombo = defautls.archiveDataForKey(KeyCombo.self, key: Constants.HotKey.snippetKeyCombo)

                expect(savedMainKeyCombo) != nil
                expect(savedMainKeyCombo?.QWERTYKeyCode) == 9
                expect(savedMainKeyCombo?.modifiers) == 768
                expect(savedMainKeyCombo?.doubledModifiers) == false
                expect(savedMainKeyCombo?.keyEquivalent.uppercased()) == "V"

                expect(savedHistoryKeyCombo) != nil
                expect(savedHistoryKeyCombo?.QWERTYKeyCode) == 0
                expect(savedHistoryKeyCombo?.modifiers) == cmdKey
                expect(savedHistoryKeyCombo?.doubledModifiers) == true
                expect(savedHistoryKeyCombo?.keyEquivalent.uppercased()) == ""

                expect(savedSnippetKeyCombo) != nil
                expect(savedSnippetKeyCombo?.QWERTYKeyCode) == 0
                expect(savedSnippetKeyCombo?.modifiers) == shiftKey
                expect(savedSnippetKeyCombo?.doubledModifiers) == false
                expect(savedSnippetKeyCombo?.keyEquivalent.uppercased()) == "A"

                service.change(with: .main, keyCombo: nil)
                expect(service.mainKeyCombo) == nil
                expect(defautls.archiveDataForKey(KeyCombo.self, key: Constants.HotKey.mainKeyCombo)) == nil
            }

            it("Unarchive saved key combos") {
                let mainKeyCombo = KeyCombo(QWERTYKeyCode: 9, carbonModifiers: 768)
                let historyKeyCombo = KeyCombo(doubledCocoaModifiers: .command)
                let snippetKeyCombo = KeyCombo(QWERTYKeyCode: 0, cocoaModifiers: .shift)

                let defaults = UserDefaults.standard
                defaults.setArchiveData(mainKeyCombo!, forKey: Constants.HotKey.mainKeyCombo)
                defaults.setArchiveData(historyKeyCombo!, forKey: Constants.HotKey.historyKeyCombo)
                defaults.setArchiveData(snippetKeyCombo!, forKey: Constants.HotKey.snippetKeyCombo)

                let service = HotKeyService()
                expect(service.mainKeyCombo) == nil
                expect(service.historyKeyCombo) == nil
                expect(service.snippetKeyCombo) == nil

                service.setupDefaultHotKeys()

                expect(service.mainKeyCombo) != nil
                expect(service.mainKeyCombo?.QWERTYKeyCode) == 9
                expect(service.mainKeyCombo?.modifiers) == 768
                expect(service.mainKeyCombo?.doubledModifiers) == false
                expect(service.mainKeyCombo?.keyEquivalent.uppercased()) == "V"

                expect(service.historyKeyCombo) != nil
                expect(service.historyKeyCombo?.QWERTYKeyCode) == 0
                expect(service.historyKeyCombo?.modifiers) == cmdKey
                expect(service.historyKeyCombo?.doubledModifiers) == true
                expect(service.historyKeyCombo?.keyEquivalent.uppercased()) == ""

                expect(service.snippetKeyCombo) != nil
                expect(service.snippetKeyCombo?.QWERTYKeyCode) == 0
                expect(service.snippetKeyCombo?.modifiers) == shiftKey
                expect(service.snippetKeyCombo?.doubledModifiers) == false
                expect(service.snippetKeyCombo?.keyEquivalent.uppercased()) == "A"
            }

            afterEach {
                let defaults = UserDefaults.standard
                defaults.removeObject(forKey: Constants.UserDefaults.hotKeys)
                defaults.removeObject(forKey: Constants.HotKey.migrateNewKeyCombo)
                defaults.removeObject(forKey: Constants.HotKey.mainKeyCombo)
                defaults.removeObject(forKey: Constants.HotKey.historyKeyCombo)
                defaults.removeObject(forKey: Constants.HotKey.snippetKeyCombo)
                defaults.synchronize()
            }
        }
    }

    private static func keyCombosSpecs() {
        describe("Key comobos") {
            it("Default key combos") {
                let keyCombos = HotKeyService.defaultKeyCombos
                let mainCombos = keyCombos[Constants.Menu.clip] as? [String: Int]
                let historyCombos = keyCombos[Constants.Menu.history] as? [String: Int]
                let snippetCombos = keyCombos[Constants.Menu.snippet] as? [String: Int]

                expect(mainCombos?["keyCode"]) == 9
                expect(mainCombos?["modifiers"]) == 768

                expect(historyCombos?["keyCode"]) == 9
                expect(historyCombos?["modifiers"]) == 4352

                expect(snippetCombos?["keyCode"]) == 11
                expect(snippetCombos?["modifiers"]) == 768
            }
        }
    }

    private static func clearHistoryHotKeySpecs() {
        describe("Clear History HotKey") {
            beforeEach {
                let defaults = UserDefaults.standard
                defaults.removeObject(forKey: Constants.HotKey.clearHistoryKeyCombo)
                defaults.synchronize()
            }

            it("Add and remove clear history hokey") {
                let service = HotKeyService()

                expect(service.clearHistoryKeyCombo) == nil

                let keyCombo = KeyCombo(QWERTYKeyCode: 10, carbonModifiers: cmdKey)
                service.changeClearHistoryKeyCombo(keyCombo)

                expect(service.clearHistoryKeyCombo) != nil
                expect(service.clearHistoryKeyCombo) == keyCombo

                let savedData = UserDefaults.standard.object(forKey: Constants.HotKey.clearHistoryKeyCombo) as? Data
                let savedKeyCombo = NSKeyedUnarchiver.unarchiveObject(with: savedData!) as? KeyCombo
                expect(savedKeyCombo) == keyCombo

                service.changeClearHistoryKeyCombo(nil)
                expect(service.clearHistoryKeyCombo) == nil
            }

            afterEach {
                let defaults = UserDefaults.standard
                defaults.removeObject(forKey: Constants.HotKey.clearHistoryKeyCombo)
                defaults.synchronize()
            }
        }
    }

    private static func folderHotKeySpecs() {
        describe("Folder HotKey") {
            beforeEach {
                let defaults = UserDefaults.standard
                defaults.removeObject(forKey: Constants.HotKey.folderKeyCombos)
                defaults.synchronize()
            }

            it("Add and Remove folder hotkey") {
                let service = HotKeyService()

                let identifier = NSUUID().uuidString
                expect(service.snippetKeyCombo(forIdentifier: identifier)) == nil

                let keyCombo = KeyCombo(QWERTYKeyCode: 0, carbonModifiers: cmdKey)!
                service.registerSnippetHotKey(with: identifier, keyCombo: keyCombo)

                expect(service.snippetKeyCombo(forIdentifier: identifier)) != nil
                expect(service.snippetKeyCombo(forIdentifier: identifier)) == keyCombo

                let changeKeyCombo = KeyCombo(doubledCarbonModifiers: shiftKey)!
                service.registerSnippetHotKey(with: identifier, keyCombo: changeKeyCombo)

                expect(service.snippetKeyCombo(forIdentifier: identifier)) != keyCombo
                expect(service.snippetKeyCombo(forIdentifier: identifier)) == changeKeyCombo

                service.unregisterSnippetHotKey(with: identifier)
                expect(service.snippetKeyCombo(forIdentifier: identifier)) == nil
            }

            afterEach {
                let defaults = UserDefaults.standard
                defaults.removeObject(forKey: Constants.HotKey.folderKeyCombos)
                defaults.synchronize()
            }
        }
    }
}
