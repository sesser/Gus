import Testing
@testable import PhotoCore

@Suite("Quit confirmation")
struct QuitConfirmationTests {
    @Test func importerAsksWhileCopying() {
        for trigger in [QuitConfirmation.Trigger.quit, .closeImportWindow] {
            #expect(QuitConfirmation.needed(app: .importer, trigger: trigger, isCopying: true) == .stopCopy)
            #expect(QuitConfirmation.needed(app: .importer, trigger: trigger, isCopying: false) == nil)
        }
    }

    @Test func libraryAsksOnQuitOnly() {
        #expect(QuitConfirmation.needed(app: .library, trigger: .quit, isCopying: true) == .importing)
        #expect(QuitConfirmation.needed(app: .library, trigger: .quit, isCopying: false, isAddingFolders: true) == .importing)
        #expect(QuitConfirmation.needed(app: .library, trigger: .quit, isCopying: false, isExporting: true) == .exporting)
        #expect(QuitConfirmation.needed(app: .library, trigger: .quit, isCopying: false) == nil)
        // Closing its Import window keeps copying.
        #expect(QuitConfirmation.needed(app: .library, trigger: .closeImportWindow, isCopying: true,
                                        isExporting: true) == nil)
    }

    @Test func importingComesBeforeExporting() {
        #expect(QuitConfirmation.needed(app: .library, trigger: .quit, isCopying: true, isExporting: true) == .importing)
    }
}
