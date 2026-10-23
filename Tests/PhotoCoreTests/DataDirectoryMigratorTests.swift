import Foundation
import Testing
@testable import PhotoCore

@Suite("Data directory migration")
struct DataDirectoryMigratorTests {
    private func makeDirectory(_ url: URL, marker: String) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try Data(marker.utf8).write(to: url.appending(path: "marker"))
    }

    private func marker(in url: URL) -> String? {
        (try? Data(contentsOf: url.appending(path: "marker"))).map { String(decoding: $0, as: UTF8.self) }
    }

    @Test func movesPreviousDirectoryToCurrentName() async throws {
        try await RepositoryFiles.withTemporaryDirectory { parent in
            try makeDirectory(parent.appending(path: "OldName"), marker: "catalog")
            let outcome = try DataDirectoryMigrator.migrateDirectory(
                in: parent, currentName: "NewName", previousNames: ["OldName"])
            let current = parent.appending(path: "NewName", directoryHint: .isDirectory)
            #expect(outcome == .moved(from: parent.appending(path: "OldName", directoryHint: .isDirectory), to: current))
            #expect(marker(in: current) == "catalog")
            #expect(!FileManager.default.fileExists(atPath: parent.appending(path: "OldName").path))
        }
    }

    @Test func picksTheFirstExistingPreviousName() async throws {
        try await RepositoryFiles.withTemporaryDirectory { parent in
            try makeDirectory(parent.appending(path: "Oldest"), marker: "oldest")
            try makeDirectory(parent.appending(path: "Older"), marker: "older")
            _ = try DataDirectoryMigrator.migrateDirectory(
                in: parent, currentName: "Current", previousNames: ["Older", "Oldest"])
            #expect(marker(in: parent.appending(path: "Current")) == "older")
            #expect(marker(in: parent.appending(path: "Oldest")) == "oldest")
        }
    }

    @Test func leavesBothDirectoriesAloneOnConflict() async throws {
        try await RepositoryFiles.withTemporaryDirectory { parent in
            try makeDirectory(parent.appending(path: "Current"), marker: "new")
            try makeDirectory(parent.appending(path: "Old"), marker: "old")
            let outcome = try DataDirectoryMigrator.migrateDirectory(
                in: parent, currentName: "Current", previousNames: ["Old"])
            guard case .conflict = outcome else {
                Issue.record("expected a conflict, got \(outcome)")
                return
            }
            #expect(marker(in: parent.appending(path: "Current")) == "new")
            #expect(marker(in: parent.appending(path: "Old")) == "old")
        }
    }

    @Test func doesNothingWithoutPreviousNames() async throws {
        try await RepositoryFiles.withTemporaryDirectory { parent in
            let outcome = try DataDirectoryMigrator.migrateDirectory(
                in: parent, currentName: "Current", previousNames: [])
            #expect(outcome == .nothingToDo)
        }
    }

    @Test func removesObsoleteCachesOnly() async throws {
        try await RepositoryFiles.withTemporaryDirectory { parent in
            try makeDirectory(parent.appending(path: "old.cache"), marker: "x")
            try makeDirectory(parent.appending(path: "new.cache"), marker: "y")
            DataDirectoryMigrator.removeObsoleteCaches(
                in: parent, previousNames: ["old.cache", "new.cache"], currentName: "new.cache")
            #expect(!FileManager.default.fileExists(atPath: parent.appending(path: "old.cache").path))
            #expect(marker(in: parent.appending(path: "new.cache")) == "y")
        }
    }
}
