import Foundation
import PhotoFixtures
import Testing
@testable import PhotoCore

/// `photocli render <file>` without `--library-root` leaves the standard
/// library alone (issue #222): nothing in its folder is created, written or
/// touched, the `-shm` file included.
@Suite("Render input and the standard library")
struct RenderInputLibraryTests {
    /// Every file under `root`, by relative path, with its bytes and
    /// modification time: any write, creation or removal changes it.
    struct FolderState: Equatable, CustomStringConvertible {
        var files: [String: Entry]

        struct Entry: Equatable {
            var bytes: Data
            var modified: Date
        }

        init(_ root: URL) throws {
            files = [:]
            let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey]
            let base = root.resolvingSymlinksInPath().path
            for case let url as URL in FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys) ?? .init() {
                let values = try url.resourceValues(forKeys: Set(keys))
                guard values.isRegularFile == true else { continue }
                let path = String(url.resolvingSymlinksInPath().path.dropFirst(base.count))
                files[path] = Entry(bytes: try Data(contentsOf: url), modified: values.contentModificationDate ?? .distantPast)
            }
        }

        var description: String {
            files.keys.sorted().map { "\($0) \(files[$0]!.bytes.count) B \(files[$0]!.modified.timeIntervalSince1970)" }
                .joined(separator: "; ")
        }
    }

    /// A library with one imported photo whose catalog is closed again; its
    /// `-wal` and `-shm` files stay, as they do after the app quits.
    static func closedLibrary(in folder: URL) async throws -> LibraryLocations {
        let photos = folder.appending(path: "LibraryPhotos", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: photos, withIntermediateDirectories: true)
        let master = photos.appending(path: "IMG_0100.jpg")
        try SyntheticImages.writeJPEG(to: master, width: 64, height: 48, seed: 100)
        let locations = LibraryLocations.rooted(at: folder.appending(path: "Standard", directoryHint: .isDirectory))
        try locations.createDirectories()
        let catalog = try Catalog.open(at: locations.catalogFileURL)
        _ = try await Importer(catalog: catalog, metadataReader: ImageIOMetadataReader()).importFolder(photos)
        try catalog.database.close()
        return locations
    }

    @Test("A file rendered with no --library-root creates, writes and touches nothing in the standard library")
    func fileRenderLeavesTheStandardLibraryAlone() async throws {
        try await RepositoryFiles.withTemporaryDirectory { folder in
            let locations = try await Self.closedLibrary(in: folder)
            // As the owner's library was found: closed, with its `-wal` and `-shm` beside it.
            let catalog = locations.catalogFileURL.path
            for suffix in ["", "-wal", "-shm"] {
                try #require(FileManager.default.fileExists(atPath: catalog + suffix), "no catalog\(suffix)")
            }
            let root = locations.catalogDirectory.deletingLastPathComponent()
            let before = try FolderState(root)

            let input = folder.appending(path: "input.jpg")
            try SyntheticImages.writeJPEG(to: input, width: 64, height: 48, seed: 1)
            let out = folder.appending(path: "out.png")
            let cli = CommandLineInterface(environment: .hermetic(currentDirectory: folder, standardLibrary: root))
            let output = await cli.run(["render", input.path, "--out", out.path, "--long-edge", "32"])
            #expect(output.exitCode == 0, "\(output.standardError)")

            let after = try FolderState(root)
            #expect(after == before, "before: \(before)\nafter: \(after)")
            #expect(FileManager.default.fileExists(atPath: out.path), "the file was not rendered")
        }
    }
}
