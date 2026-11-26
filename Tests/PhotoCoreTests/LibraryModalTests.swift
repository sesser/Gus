import Foundation
import Testing

/// The library window's sheets, dialogs and alerts are all listed in
/// `LibraryModal` (PhotoApp), which the preset pack import reads so its report
/// never opens over another (#203: F2, C7, C9). PhotoApp has no test target,
/// so this reads the sources: a presenter added to the window's views without
/// a case fails here.
@Suite("Library window modals")
struct LibraryModalTests {
    static let views = ["Sources/PhotoApp/Views/MainView.swift", "Sources/PhotoApp/Views/SidebarView.swift"]
    static let presenters = [".sheet(", ".confirmationDialog(", ".alert(", ".fullScreenCover("]

    static func cases() throws -> [String] {
        let source = try String(contentsOf: RepositoryFiles.url("Sources/PhotoApp/Model/LibraryModal.swift"), encoding: .utf8)
        let line = try #require(source.components(separatedBy: "\n").first {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix("case ") && $0.contains(",")
        })
        return line.trimmingCharacters(in: .whitespaces).dropFirst("case ".count)
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    @Test func everyPresenterOfTheWindowIsListed() throws {
        var presenterLines: [String] = []
        for path in Self.views {
            let source = try String(contentsOf: RepositoryFiles.url(path), encoding: .utf8)
            for line in source.components(separatedBy: "\n") where Self.presenters.contains(where: line.contains) {
                if !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") { presenterLines.append(line) }
            }
        }
        let cases = try Self.cases()
        #expect(cases == ["export", "lookTables", "sidebarSheet", "sidebarDeletion", "removal", "importSummary", "merge",
                          "copyAdjustments", "publish", "publishServer", "publishResults"])
        // Every modal listed, plus the preset manager itself.
        #expect(presenterLines.count == cases.count + 1, """
            The library window presents \(presenterLines.count) sheets, dialogs and alerts but LibraryModal lists \
            \(cases.count) (plus the preset manager). Add the new one to LibraryModal and LibraryModel.isUp(_:).
            """)
        // Sheets other than the preset manager close through `modalDidClose()`.
        let sheets = presenterLines.filter { $0.contains(".sheet(") && !$0.contains("showsPresetSheet") }
        #expect(sheets.count == 8)
        #expect(sheets.allSatisfy { $0.contains("onDismiss: { model.modalDidClose() }") })
        let main = try String(contentsOf: RepositoryFiles.url(Self.views[0]), encoding: .utf8)
        #expect(main.contains(".onChange(of: model.dialogIsUp)"))
    }
}
