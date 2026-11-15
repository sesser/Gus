import Foundation
import Testing
@testable import PhotoCore

/// `photocli render --out` never writes over a catalogued master (issue #166),
/// nor, with no library, over the file it renders.
@Suite("Render output protection")
struct RenderOutputProtectionTests {
    typealias Library = CommandTests.TemporaryLibrary

    /// Renders with `--out` and checks the command was refused and the file
    /// at `out` kept its bytes.
    static func expectRefused(_ library: Library, out: URL, _ arguments: String...,
                              sourceLocation: SourceLocation = #_sourceLocation) async throws {
        let before = try Data(contentsOf: out)
        let result = await library.run(["render"] + arguments + ["--out", out.path, "--long-edge", "64"])
        #expect(result.output.exitCode == 1, "\(result.output.standardOutput)", sourceLocation: sourceLocation)
        #expect(result.json["code"] == "outputIsMaster", "\(result.output.standardError)", sourceLocation: sourceLocation)
        #expect(try Data(contentsOf: out) == before, "\(out.lastPathComponent) was written",
                sourceLocation: sourceLocation)
    }

    @Test("A version rendered onto its own master is refused and the master is untouched (the #166 repro)")
    func versionOntoItsOwnMaster() async throws {
        try await CommandTests.withLibrary { library in
            let id = try #require(library.versionIDs.first)
            let master = try #require(try await library.masterURL(of: id))
            try await Self.expectRefused(library, out: master, "--version", String(id))
        }
    }

    @Test("Any catalogued master is refused, by place: another photo's, another case, through a linked folder")
    func anyMasterByPlace() async throws {
        try await CommandTests.withLibrary { library in
            let input = library.photos.appending(path: "IMG_0001.jpg").path
            try await Self.expectRefused(library, out: library.photos.appending(path: "IMG_0002.jpg"), input)
            try await Self.expectRefused(library, out: library.photos.appending(path: "img_0003.JPG"), input)
            let link = library.root.deletingLastPathComponent().appending(path: "PhotosLink")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: library.photos)
            try await Self.expectRefused(library, out: link.appending(path: "IMG_0002.jpg"), input)
            try await Self.expectRefused(library, out: library.photos.appending(path: "IMG_0002.jpg"),
                                         "--version", String(library.versionIDs[0]))
        }
    }

    @Test("A file with a master's bytes is refused wherever it is")
    func masterByContent() async throws {
        try await CommandTests.withLibrary { library in
            let elsewhere = library.root.deletingLastPathComponent().appending(path: "Elsewhere")
            try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
            let copy = elsewhere.appending(path: "copy.jpg")
            try FileManager.default.copyItem(at: library.photos.appending(path: "IMG_0002.jpg"), to: copy)
            try await Self.expectRefused(library, out: copy, library.photos.appending(path: "IMG_0001.jpg").path)
        }
    }

    @Test("Ordinary files are still written and replaced with a library open")
    func ordinaryFilesStillReplaced() async throws {
        try await CommandTests.withLibrary { library in
            let out = library.root.deletingLastPathComponent().appending(path: "ordinary.jpg")
            try Data("not an image".utf8).write(to: out)
            let result = await library.run("render", "--version", String(library.versionIDs[0]),
                                           "--out", out.path, "--long-edge", "64")
            #expect(result.output.exitCode == 0, "\(result.output.standardError)")
            #expect(try Data(contentsOf: out) != Data("not an image".utf8))
        }
    }

    /// A command line whose standard library is `root` (none passes `--library-root`).
    static func cli(standardLibrary root: URL, in library: Library) -> CommandLineInterface {
        CommandLineInterface(environment: CommandEnvironment(currentDirectory: library.root.deletingLastPathComponent(),
                                                             defaultLibraryRoot: root))
    }

    /// The catalog's files, to show nothing was written to them.
    static func catalogBytes(_ library: Library) throws -> [Data?] {
        let file = library.locations.catalogFileURL
        return try ["", "-wal"].map { suffix in
            let url = URL(fileURLWithPath: file.path + suffix)
            return FileManager.default.fileExists(atPath: url.path) ? try Data(contentsOf: url) : nil
        }
    }

    @Test("A file render with no --library-root asks the standard library, read-only, by place and by content")
    func standardLibraryAskedForAFileRender() async throws {
        try await CommandTests.withLibrary { library in
            let cli = Self.cli(standardLibrary: library.root, in: library)
            let input = library.photos.appending(path: "IMG_0001.jpg").path
            let copy = library.root.deletingLastPathComponent().appending(path: "copy.jpg")
            try FileManager.default.copyItem(at: library.photos.appending(path: "IMG_0003.jpg"), to: copy)
            let catalogBefore = try Self.catalogBytes(library)
            for out in [library.photos.appending(path: "IMG_0002.jpg"), copy] {
                let before = try Data(contentsOf: out)
                let output = await cli.run(["render", input, "--out", out.path, "--long-edge", "64"])
                #expect(output.exitCode == 1, "\(out.lastPathComponent): \(output.standardOutput)")
                #expect(output.standardError.contains("outputIsMaster"), "\(output.standardError)")
                #expect(try Data(contentsOf: out) == before)
            }
            let ordinary = library.root.deletingLastPathComponent().appending(path: "ordinary.png")
            let output = await cli.run(["render", input, "--out", ordinary.path, "--long-edge", "64"])
            #expect(output.exitCode == 0, "\(output.standardError)")
            #expect(try Self.catalogBytes(library) == catalogBefore, "the standard library's catalog was written")
        }
    }

    @Test("A standard library that exists but can't be read refuses the render, and nothing is written")
    func unreadableStandardLibraryRefuses() async throws {
        try await CommandTests.withLibrary { library in
            let damaged = library.root.deletingLastPathComponent().appending(path: "Damaged", directoryHint: .isDirectory)
            let locations = LibraryLocations.rooted(at: damaged)
            try locations.createDirectories()
            let garbage = Data("this is not a database, not even a little".utf8)
            try garbage.write(to: locations.catalogFileURL)
            let out = library.root.deletingLastPathComponent().appending(path: "out.png")
            let output = await Self.cli(standardLibrary: damaged, in: library)
                .run(["render", library.photos.appending(path: "IMG_0001.jpg").path, "--out", out.path])
            #expect(output.exitCode == 1, "\(output.standardOutput)")
            #expect(output.standardError.contains("\"failed\""), "\(output.standardError)")
            #expect(!FileManager.default.fileExists(atPath: out.path))
            #expect(try Data(contentsOf: locations.catalogFileURL) == garbage)
        }
    }

    @Test("Opening a catalog for reading creates nothing, migrates nothing and refuses writes")
    func catalogOpenForReading() async throws {
        try await CommandTests.withLibrary { library in
            let missing = library.root.deletingLastPathComponent().appending(path: "Missing/catalog.sqlite")
            #expect(throws: (any Error).self) { try Catalog.openForReading(at: missing) }
            #expect(!FileManager.default.fileExists(atPath: missing.deletingLastPathComponent().path))

            let catalog = try Catalog.openForReading(at: library.locations.catalogFileURL)
            #expect(try await !catalog.masterFiles(mounted: []).isEmpty)
            await #expect(throws: (any Error).self) {
                try await catalog.database.write { db in try db.execute(sql: "DELETE FROM image") }
            }
        }
    }

    @Test("With no library anywhere the input itself is refused (same path, other case, a hard link)")
    func inputItselfWithoutLibrary() async throws {
        try await CommandTests.withLibrary { library in
            // A standard library location with no catalog: nothing is catalogued, so only the input is refused.
            let cli = CommandLineInterface(environment: CommandEnvironment(
                currentDirectory: library.root.deletingLastPathComponent(),
                defaultLibraryRoot: library.root.deletingLastPathComponent().appending(path: "NoLibrary")))
            let input = library.photos.appending(path: "IMG_0001.jpg")
            let hardLink = library.root.deletingLastPathComponent().appending(path: "hard.jpg")
            try FileManager.default.linkItem(at: input, to: hardLink)
            let before = try Data(contentsOf: input)
            for out in [input.path, library.photos.appending(path: "img_0001.JPG").path, hardLink.path] {
                let output = await cli.run(["render", input.path, "--out", out, "--long-edge", "64"])
                #expect(output.exitCode == 1, "\(out): \(output.standardOutput)")
                #expect(output.standardError.contains("outputIsMaster"), "\(out): \(output.standardError)")
                #expect(try Data(contentsOf: input) == before)
            }
            // With no catalog the rule is the input only: another file is written, and nothing is created.
            let other = library.root.deletingLastPathComponent().appending(path: "other.png")
            let output = await cli.run(["render", input.path, "--out", other.path, "--long-edge", "64"])
            #expect(output.exitCode == 0, "\(output.standardError)")
            #expect(FileManager.default.fileExists(atPath: other.path))
            #expect(!FileManager.default.fileExists(atPath: library.root.deletingLastPathComponent()
                .appending(path: "NoLibrary").path))
        }
    }
}

extension CommandTests.TemporaryLibrary {
    /// Runs a command line with this library's root added (array form).
    func run(_ arguments: [String]) async -> (output: CommandLineInterface.Output, json: JSONValue) {
        let output = await cli.run(arguments + ["--library-root", root.path])
        let text = output.exitCode == 0 ? output.standardOutput : output.standardError
        return (output, (try? JSONValue.parse(text)) ?? .null)
    }

    /// A version's master, as the catalog places it.
    func masterURL(of versionID: Int64) async throws -> URL? {
        let catalog = try Catalog.open(at: locations.catalogFileURL)
        guard let details = try await catalog.details(forVersion: versionID) else { return nil }
        return details.volume.url(forRelativePath: details.image.relativePath)
    }
}
