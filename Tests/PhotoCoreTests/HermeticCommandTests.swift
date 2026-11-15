import Foundation
import Testing
@testable import PhotoCore

/// Tests never read the owner's library (`docs/WORKFLOW.md`, Build). A
/// command environment built directly falls back on the real standard library
/// for any command run without `--library-root` (#166's code review, C1), so
/// every one in the tests goes through `CommandEnvironment.hermetic`.
@Suite("Hermetic command tests")
struct HermeticCommandTests {
    static let helper = "Tests/PhotoCoreTests/Support/HermeticCommands.swift"
    /// Split so this file does not match itself.
    static let construction = "CommandEnvironment" + "("

    @Test("Only the hermetic helper builds a command environment in the tests")
    func onlyTheHelperBuildsEnvironments() throws {
        let files = RepositoryFiles.files(under: "Tests").filter { $0.hasSuffix(".swift") }
        #expect(files.contains(Self.helper), "the scan found no helper: it is looking in the wrong place")
        var offenders: [String] = []
        for file in files where file != Self.helper {
            let text = try String(contentsOf: RepositoryFiles.url(file), encoding: .utf8)
            for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
            where line.contains(Self.construction) {
                offenders.append("\(file):\(index + 1)")
            }
        }
        #expect(offenders.isEmpty, "use CommandEnvironment.hermetic(currentDirectory:standardLibrary:): \(offenders)")
        let helperText = try String(contentsOf: RepositoryFiles.url(Self.helper), encoding: .utf8)
        #expect(helperText.contains(Self.construction), "the scanner is vacuous")
    }

    @Test("The hermetic environment's standard library is a folder that does not exist")
    func defaultStandardLibraryIsAbsent() throws {
        let environment = CommandEnvironment.hermetic(currentDirectory: URL(fileURLWithPath: "/"))
        let locations = try environment.libraryLocations(CommandArguments(values: [:]))
        #expect(locations != (try? LibraryLocations.standard()))
        #expect(!FileManager.default.fileExists(atPath: locations.catalogFileURL.path))
    }
}
