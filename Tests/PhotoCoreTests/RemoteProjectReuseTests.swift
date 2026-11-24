import Foundation
import GRDB
import PhotoFixtures
import Testing
@testable import PhotoCore

/// Issue #271, the owner's finding at sign-off (2026-11-24): a server import
/// adds to an existing project of the same name instead of making a second
/// one (`Catalog.projectForImport`, `RemoteProjectName.cleaned`).
@Suite("Immich import project reuse")
struct RemoteProjectReuseTests {
    static func projects(_ catalog: Catalog) async throws -> [ProjectRecord] {
        try await catalog.database.read { db in try ProjectRecord.order(ProjectRecord.Columns.id).fetchAll(db) }
    }

    static func imageProjects(_ catalog: Catalog) async throws -> [Int64] {
        try await catalog.database.read { db in try ImageRecord.fetchAll(db).map(\.projectId) }
    }

    @Test("Importing the same scope again adds to the first project and makes none")
    func secondImportReuses() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let setup = try await RemoteImportTests.setup(assets: try FakeImmichServer.jpegAssets(count: 4))
            let listed = try await RemoteImportTests.listed(setup)
            let options = RemoteImportTests.options(root, setup)
            let first = await RemoteImportTests.importer(setup).run(Array(listed.prefix(2)), options: options)
            #expect(first.imported == 2)
            let second = await RemoteImportTests.importer(setup).run(Array(listed.suffix(2)), options: options)
            #expect(second.imported == 2)
            let projects = try await Self.projects(setup.catalog)
            #expect(projects.map(\.name) == ["Home - All Photos"])
            let id = try #require(projects.first?.id)
            #expect(first.project?.id == id && second.project?.id == id)
            #expect(try await Self.imageProjects(setup.catalog) == [id, id, id, id])
            // Each import is still its own run, both in that project.
            let runs = try await setup.catalog.database.read { db in try ImportRunRecord.fetchAll(db) }
            #expect(runs.count == 2 && runs.allSatisfy { $0.projectId == id })
        }
    }

    @Test("A different name, such as another album's, makes its own project")
    func differentNameCreates() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let setup = try await RemoteImportTests.setup(assets: try FakeImmichServer.jpegAssets(count: 2))
            let listed = try await RemoteImportTests.listed(setup)
            _ = await RemoteImportTests.importer(setup).run([listed[0]], options: RemoteImportTests.options(root, setup))
            let other = RemoteImportTests.options(root, setup, project: "Home - Trip")
            let result = await RemoteImportTests.importer(setup).run([listed[1]], options: other)
            #expect(result.imported == 1)
            let projects = try await Self.projects(setup.catalog)
            #expect(projects.map(\.name) == ["Home - All Photos", "Home - Trip"])
            #expect(result.project?.id == projects.last?.id)
        }
    }

    @Test("Names are compared after cleaning, exactly: case counts, extra spaces and Unicode forms don't")
    func comparison() async throws {
        let catalog = try Catalog.makeInMemory()
        let address = "http://nas.local:2283"
        let first = try await catalog.projectForImport(named: RemoteProjectName.cleaned("Home - All Photos", address: address),
                                                       sourcePath: "/a")
        #expect(first.created)
        // Runs of spaces collapse and the ends are trimmed when the field is
        // cleaned, so this is the same name.
        let spaced = try await catalog.projectForImport(
            named: RemoteProjectName.cleaned("  Home   - All Photos  ", address: address), sourcePath: "/a")
        #expect(!spaced.created && spaced.project.id == first.project.id)
        // Case counts, as it does for every project name.
        let lower = try await catalog.projectForImport(named: RemoteProjectName.cleaned("home - all photos", address: address),
                                                       sourcePath: "/a")
        #expect(lower.created && lower.project.id != first.project.id)
        // A decomposed é finds the precomposed one.
        let composed = try await catalog.projectForImport(named: "Caf\u{E9} - All Photos", sourcePath: "/a")
        let decomposed = try await catalog.projectForImport(named: "Cafe\u{301} - All Photos", sourcePath: "/a")
        #expect(composed.created && !decomposed.created && decomposed.project.id == composed.project.id)
        // A field of separators cleans to "-", not to the address.
        #expect(RemoteProjectName.cleaned(" / ", address: address) == "-")
        // An empty field falls back on the address, and that name is reused too.
        #expect(RemoteProjectName.cleaned("  ", address: address) == address)
        let blank = try await catalog.projectForImport(named: RemoteProjectName.cleaned("  ", address: address),
                                                       sourcePath: "/a")
        let blankAgain = try await catalog.projectForImport(named: RemoteProjectName.cleaned("", address: address),
                                                            sourcePath: "/b")
        #expect(blank.created && blank.project.name == address)
        #expect(!blankAgain.created && blankAgain.project.id == blank.project.id)
        #expect(try await Self.projects(catalog).count == 4)
    }

    @Test("Two imports with an empty Project name both go into the project named by the address")
    func emptyFieldImportsReuse() async throws {
        // Through `RemoteImporter.makeTarget`, so a change in how it cleans the
        // field or which address it falls back on is caught (code review C21).
        try await RepositoryFiles.withTemporaryDirectory { root in
            let setup = try await RemoteImportTests.setup(assets: try FakeImmichServer.jpegAssets(count: 2))
            let listed = try await RemoteImportTests.listed(setup)
            let first = await RemoteImportTests.importer(setup).run([listed[0]],
                                                                    options: RemoteImportTests.options(root, setup, project: "  "))
            let second = await RemoteImportTests.importer(setup).run([listed[1]],
                                                                     options: RemoteImportTests.options(root, setup, project: ""))
            #expect(first.imported == 1 && second.imported == 1)
            let projects = try await Self.projects(setup.catalog)
            #expect(projects.map(\.name) == [setup.link.address])
            #expect(first.project?.id == projects.first?.id && second.project?.id == projects.first?.id)
            // The note's rule agrees with the import for the same field and address.
            #expect(RemoteProjectName.addsToExistingProject(typed: "", address: setup.link.address, existingProjectID: nil,
                                                            projectNames: projects.map(\.name)))
        }
    }

    @Test("Of several projects with the name, the oldest is used, the earliest made on a tie")
    func severalWithTheName() async throws {
        let catalog = try Catalog.makeInMemory()
        let old = Date(timeIntervalSince1970: 1_000)
        // Made in this order: the newer one first, so the oldest has the larger id.
        let newer = try await catalog.createProject(name: "Home - All Photos", createdAt: Date(timeIntervalSince1970: 2_000))
        let oldest = try await catalog.createProject(name: "Home - All Photos", createdAt: old)
        let tie = try await catalog.createProject(name: "Home - All Photos", createdAt: old)
        #expect(try #require(oldest.id) > (newer.id ?? 0) && (tie.id ?? 0) > (oldest.id ?? 0))
        let found = try await catalog.projectForImport(named: "Home - All Photos", sourcePath: "/x")
        #expect(!found.created && found.project.id == oldest.id)
        #expect(try await Self.projects(catalog).count == 3)
    }

    @Test("A reused project keeps its folder when the destination differs")
    func keepsSourcePath() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let setup = try await RemoteImportTests.setup(assets: try FakeImmichServer.jpegAssets(count: 2))
            let listed = try await RemoteImportTests.listed(setup)
            let options = RemoteImportTests.options(root, setup)
            _ = await RemoteImportTests.importer(setup).run([listed[0]], options: options)
            var elsewhere = options
            elsewhere.destination = root.appending(path: "Elsewhere")
            let second = await RemoteImportTests.importer(setup).run([listed[1]], options: elsewhere)
            #expect(second.imported == 1)
            let projects = try await Self.projects(setup.catalog)
            #expect(projects.count == 1)
            #expect(projects.first?.sourcePath == options.destination.path)
            // The photo itself is where this import put it.
            #expect(RemoteImportTests.files(in: elsewhere.destination) == [listed[1].fileName])
        }
    }

    @Test("The note under the field shows exactly when the import would add to an existing project (DQ-13)")
    func reuseNote() {
        let address = "http://nas.local:2283"
        let names = ["Home - All Photos", "Caf\u{E9} - Trip", address]
        func shows(_ typed: String, addTo: Int64? = nil, in projects: [String] = names) -> Bool {
            RemoteProjectName.addsToExistingProject(typed: typed, address: address, existingProjectID: addTo,
                                                    projectNames: projects)
        }
        // A match, also after the field's cleaning.
        #expect(shows("Home - All Photos"))
        #expect(shows("  Home   - All Photos "))
        // Case counts, as the importer compares.
        #expect(!shows("home - all photos"))
        // A decomposed é matches the precomposed one.
        #expect(shows("Cafe\u{301} - Trip"))
        // An empty field is compared as the address it falls back on.
        #expect(shows("   "))
        #expect(!shows("", in: ["Home - All Photos"]))
        // No match, and no projects loaded.
        #expect(!shows("Home - Trip"))
        #expect(!shows("Home - All Photos", in: []))
        // Add to names a project: the field is absent, no note.
        #expect(!shows("Home - All Photos", addTo: 7))
    }

    @Test("Imports that look for the same name at once make one project")
    func concurrentLookups() async throws {
        // Structural: the lookup and the insert are one GRDB write, and writes
        // are serialized, so whichever runs first makes it and the rest find it.
        let catalog = try Catalog.makeInMemory()
        let results = try await withThrowingTaskGroup(of: Bool.self) { group in
            for _ in 0..<16 {
                group.addTask { try await catalog.projectForImport(named: "Home - All Photos", sourcePath: "/a").created }
            }
            return try await group.reduce(into: [Bool]()) { $0.append($1) }
        }
        #expect(results.filter { $0 }.count == 1)
        #expect(try await Self.projects(catalog).count == 1)
    }
}
