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
    // confirmation (issue #179, code review Q3), and a window that shows a
    // sheet hands it to the sheet (C6).
    private static let passedOver: Set<String> = ["about", "license"]

    private func host(key: String?, main: String?, visible: [String], sheets: [String: String] = [:]) -> String? {
        QuitConfirmation.host(key: key, main: main, visible: visible, isPassedOver: Self.passedOver.contains,
                              attachedSheet: { sheets[$0] })
    }

    @Test func confirmationGoesOnTheKeyWindowUnlessItIsPassedOver() {
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

    @Test func confirmationGoesOnTheSheetOfAWindowThatShowsOne() {
        let sheets = ["library": "export sheet"]
        // About key over a library window with a sheet up: the sheet, not
        // the window under it, where a second sheet would wait unseen.
        #expect(host(key: "about", main: "library", visible: ["library", "about"], sheets: sheets) == "export sheet")
        #expect(host(key: "license", main: "license", visible: ["license", "library"], sheets: sheets) == "export sheet")
        #expect(host(key: nil, main: "library", visible: ["library"], sheets: sheets) == "export sheet")
        // The sheet itself key, as it is when ⌘Q comes from the window: unchanged.
        #expect(host(key: "export sheet", main: "library", visible: ["library"], sheets: sheets) == "export sheet")
        // A sheet on a sheet (a panel over the Export sheet): the front one.
        let stacked = ["library": "export sheet", "export sheet": "folder panel"]
        #expect(host(key: "about", main: "library", visible: ["library", "about"], sheets: stacked) == "folder panel")
        // Another window's sheet is not this one's.
        #expect(host(key: "import", main: "library", visible: ["library", "import"], sheets: sheets) == "import")
        // No sheet anywhere: the window.
        #expect(host(key: "about", main: "library", visible: ["library", "about"]) == "library")
    }

    @Test func frontSheetFollowsTheChainAndStops() {
        #expect(QuitConfirmation.frontSheet(of: "a") { _ in nil } == "a")
        #expect(QuitConfirmation.frontSheet(of: "a") { ["a": "b", "b": "c"][$0] } == "c")
        // A chain that came back on itself ends; it does not hang.
        let looped = QuitConfirmation.frontSheet(of: "a") { ["a": "b", "b": "a"][$0] }
        #expect(["a", "b"].contains(looped))
    }
}
