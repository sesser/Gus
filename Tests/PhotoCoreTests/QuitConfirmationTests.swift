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

    // The About window and the license windows never carry the
    // confirmation (issue #179, code review Q3).
    @Test func confirmationGoesOnTheKeyWindowUnlessItIsPassedOver() {
        let passedOver: Set<String> = ["about", "license"]
        func host(key: String?, main: String?, visible: [String]) -> String? {
            QuitConfirmation.host(key: key, main: main, visible: visible, isPassedOver: passedOver.contains)
        }
        // As before: the key window, else the main one, else a visible one.
        #expect(host(key: "library", main: "library", visible: ["library", "about"]) == "library")
        #expect(host(key: "import", main: "library", visible: ["library", "import"]) == "import")
        #expect(host(key: nil, main: "library", visible: ["import", "library"]) == "library")
        #expect(host(key: nil, main: nil, visible: ["import", "library"]) == "import")
        // About or a license window key: the app's own window instead.
        #expect(host(key: "about", main: "library", visible: ["library", "about"]) == "library")
        #expect(host(key: "license", main: "license", visible: ["about", "license", "library"]) == "library")
        #expect(host(key: "about", main: "about", visible: ["about", "import"]) == "import")
        // Only such windows left, or none: no window, the alert stands alone.
        #expect(host(key: "about", main: "license", visible: ["about", "license"]) == nil)
        #expect(host(key: nil, main: nil, visible: []) == nil)
    }
}
