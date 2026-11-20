import Foundation
import Testing
@testable import PhotoCore

/// `photocli render --out` never writes over the file it renders, nor over a
/// master of the library the command reads (issue #166). A file rendered
/// without `--library-root` reads no library (issue #222).
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
        CommandLineInterface(environment: .hermetic(currentDirectory: library.root.deletingLastPathComponent(),
                                                     standardLibrary: root))
    }

    /// The catalog's files, to show nothing was written to them.
    static func catalogBytes(_ library: Library) throws -> [Data?] {
        let file = library.locations.catalogFileURL
        return try ["", "-wal", "-shm"].map { suffix in
            let url = URL(fileURLWithPath: file.path + suffix)
            return FileManager.default.fileExists(atPath: url.path) ? try Data(contentsOf: url) : nil
        }
    }

    /// Renders `arguments` onto `out` and checks it was refused with `outputIsMaster` and `out` kept its bytes.
    static func expectRefused(_ cli: CommandLineInterface, out: URL, _ arguments: [String],
                              sourceLocation: SourceLocation = #_sourceLocation) async throws {
        let before = try Data(contentsOf: out)
        let output = await cli.run(["render"] + arguments + ["--out", out.path, "--long-edge", "64"])
        #expect(output.exitCode == 1, "\(out.lastPathComponent): \(output.standardOutput)", sourceLocation: sourceLocation)
        #expect(output.standardError.contains("outputIsMaster"), "\(output.standardError)", sourceLocation: sourceLocation)
        #expect(try Data(contentsOf: out) == before, "\(out.lastPathComponent) was written", sourceLocation: sourceLocation)
    }

    @Test("A file render with no --library-root reads no library: only the input is refused (#222)")
    func fileRenderAsksNoLibrary() async throws {
        try await CommandTests.withLibrary { library in
            // The standard library holds these masters, but a file render without --library-root doesn't read it
            // (owner's ruling on #222, 2026-11-19, narrowing #166's): they are ordinary files to it.
            let cli = Self.cli(standardLibrary: library.root, in: library)
            let input = library.photos.appending(path: "IMG_0001.jpg").path
            let copy = library.root.deletingLastPathComponent().appending(path: "copy.jpg")
            try FileManager.default.copyItem(at: library.photos.appending(path: "IMG_0003.jpg"), to: copy)
            let catalogBefore = try Self.catalogBytes(library)
            for out in [library.photos.appending(path: "IMG_0002.jpg"), copy] {
                let before = try Data(contentsOf: out)
                let output = await cli.run(["render", input, "--out", out.path, "--long-edge", "64"])
                #expect(output.exitCode == 0, "\(out.lastPathComponent): \(output.standardError)")
                #expect(try Data(contentsOf: out) != before, "\(out.lastPathComponent) was not written")
            }
            try await Self.expectRefused(cli, out: URL(fileURLWithPath: input), [input])
            #expect(try Self.catalogBytes(library) == catalogBefore, "the standard library's catalog was touched")
        }
    }

    @Test("A standard library that can't be read doesn't stop a file render; a --version render still fails")
    func unreadableStandardLibraryIsNotRead() async throws {
        try await CommandTests.withLibrary { library in
            let damaged = library.root.deletingLastPathComponent().appending(path: "Damaged", directoryHint: .isDirectory)
            let locations = LibraryLocations.rooted(at: damaged)
            try locations.createDirectories()
            let garbage = Data("this is not a database, not even a little".utf8)
            try garbage.write(to: locations.catalogFileURL)
            let cli = Self.cli(standardLibrary: damaged, in: library)
            let out = library.root.deletingLastPathComponent().appending(path: "out.png")
            let output = await cli.run(["render", library.photos.appending(path: "IMG_0001.jpg").path,
                                        "--out", out.path, "--long-edge", "64"])
            #expect(output.exitCode == 0, "\(output.standardError)")
            #expect(FileManager.default.fileExists(atPath: out.path))

            // A version lives in a library, so --version still reads the standard one, and fails on this.
            let versionOut = library.root.deletingLastPathComponent().appending(path: "version.png")
            let version = await cli.run(["render", "--version", "1", "--out", versionOut.path])
            #expect(version.exitCode == 1, "\(version.standardOutput)")
            #expect(version.standardError.contains("\"failed\""), "\(version.standardError)")
            #expect(!FileManager.default.fileExists(atPath: versionOut.path))
            #expect(try Data(contentsOf: locations.catalogFileURL) == garbage)
            let files = try FileManager.default.contentsOfDirectory(atPath: locations.catalogDirectory.path)
            #expect(files == [locations.catalogFileURL.lastPathComponent], "\(files)")
        }
    }

    @Test("A library the command reads still protects its masters: --library-root, and --version with or without it")
    func namedLibraryAndVersionRendersStillProtectMasters() async throws {
        try await CommandTests.withLibrary { library in
            let cli = Self.cli(standardLibrary: library.root, in: library)
            let input = library.photos.appending(path: "IMG_0001.jpg").path
            let master = library.photos.appending(path: "IMG_0002.jpg")
            let copy = library.root.deletingLastPathComponent().appending(path: "copy.jpg")
            try FileManager.default.copyItem(at: library.photos.appending(path: "IMG_0003.jpg"), to: copy)
            let version = String(library.versionIDs[0])
            for out in [master, copy] {
                // A file with the library named.
                try await Self.expectRefused(cli, out: out, [input, "--library-root", library.root.path])
                // A version from the standard library (no --library-root) and from a named one.
                try await Self.expectRefused(cli, out: out, ["--version", version])
                try await Self.expectRefused(cli, out: out, ["--version", version, "--library-root", library.root.path])
            }
        }
    }

    @Test("Opening a catalog for reading creates no catalog, migrates nothing and refuses writes")
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
            // A file render without --library-root reads no library (#222); the input alone is refused.
            let cli = CommandLineInterface(environment: .hermetic(
                currentDirectory: library.root.deletingLastPathComponent(),
                standardLibrary: library.root.deletingLastPathComponent().appending(path: "NoLibrary")))
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
            // Another file is written, and nothing is created at the standard location.
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
