import CoreImage
import Foundation
import ImageIO
import PhotoFixtures
import Synchronization
import Testing
@testable import PhotoCore

/// A scratch library of brackets for the merge job's tests (issue #150).
struct MergeLibrary {
    let folder: URL
    let catalog: Catalog
    /// Default version ids by file name.
    let versions: [String: Int64]

    enum Kind { case dng, jpeg }

    static let width = 480
    static let height = 320

    /// Writes `frames` as `IMG_0001…` in `folder` (a new temporary one unless
    /// given), dated a second apart in `order` (indices of `frames`), and
    /// imports them.
    static func make(_ frames: [HDRBracket.Frame], kind: Kind = .dng, order: [Int]? = nil, writesBias: Bool = true,
                     extra: (URL) throws -> Void = { _ in }) async throws -> MergeLibrary {
        let folder = FileManager.default.temporaryDirectory.appending(path: "merge-\(UUID().uuidString)",
                                                                       directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let order = order ?? Array(frames.indices)
        for (position, index) in order.enumerated() {
            let frame = frames[index]
            let image = HDRBracket.image(frame, width: width, height: height)
            let name = String(format: "IMG_%04d", index + 1)
            let date = String(format: "2026:05:01 10:00:%02d", position)
            switch kind {
            case .dng:
                try HDRBracket.writeDNG(image, frame: frame, to: folder.appending(path: name + ".dng"), date: date,
                                        writesBias: writesBias)
            case .jpeg:
                try HDRBracket.writeJPEG(image, frame: frame, to: folder.appending(path: name + ".jpg"), date: date,
                                         writesBias: writesBias)
            }
        }
        try extra(folder)
        let catalog = try Catalog.makeInMemory()
        _ = try await Importer(catalog: catalog, metadataReader: ImageIOMetadataReader()).importFolder(folder)
        var versions: [String: Int64] = [:]
        for image in try await catalog.allImages() {
            guard let id = image.id, let version = try await catalog.versions(ofImage: id).first(where: \.isDefault) else {
                continue
            }
            versions[image.fileName] = version.id
        }
        return MergeLibrary(folder: folder, catalog: catalog, versions: versions)
    }

    func selection(_ names: [String]) async throws -> MergeSelection {
        var frames: [MergeFrame] = []
        for name in names {
            let id = try #require(versions[name], "\(name)")
            let details = try #require(try await catalog.details(forVersion: id))
            frames.append(MergeFrame(details: details, isOnline: true))
        }
        return MergeSelection(frames: frames)
    }

    var job: HDRMergeJob {
        var job = HDRMergeJob(catalog: catalog, metadataReader: ImageIOMetadataReader())
        job.mountedVolumes = { [] }
        return job
    }

    /// The folder's file names, hidden ones included.
    func files() throws -> Set<String> {
        Set(try FileManager.default.contentsOfDirectory(atPath: folder.path))
    }

    func hashes() async throws -> [String: String] {
        var result: [String: String] = [:]
        for name in try files() where !name.hasPrefix(".") {
            result[name] = try await SHA256ContentHasher().contentHash(of: folder.appending(path: name))
        }
        return result
    }

    func remove() { try? FileManager.default.removeItem(at: folder) }
}

extension MemoryHeavy {
    @Suite("HDR merge job", .serialized)
    struct HDRMergeJobTests {
        static let bracket = [HDRBracket.Frame(ev: -2, shift: SIMD2(2, -1.5), rotationDegrees: 0.2), HDRBracket.Frame(ev: 0),
                              HDRBracket.Frame(ev: 2, shift: SIMD2(-1.5, 1))]

        @Test("AC2, AC3, AC5: the 0 EV frame (not first in time) names a TIFF beside it; masters unchanged; values carried")
        func mergesToTIFF() async throws {
            try await offCooperativePool {
                // IMG_0002 (0 EV) is shot second; IMG_0003 first.
                let library = try await MergeLibrary.make(Self.bracket, order: [2, 1, 0])
                defer { library.remove() }
                let catalog = library.catalog
                let reference = try #require(library.versions["IMG_0002.dng"])
                try await catalog.setRating(Rating(clamping: 4), forVersions: [reference])
                try await catalog.setFlag(.picked, forVersions: [reference])
                try await catalog.setColorLabel(.red, forVersions: [reference])
                for name in ["harbor", "dusk"] {
                    let keyword = try await catalog.keyword(named: name)
                    try await catalog.assignKeyword(try #require(keyword.id), toVersions: [reference])
                }
                try await catalog.setDescriptiveField(.title, to: "Harbor at dusk", forVersions: [reference])
                try await catalog.setDescriptiveField(.caption, to: "Three frames", forVersions: [reference])
                try await catalog.setDescriptiveField(.creator, to: "A. Photographer", forVersions: [reference])

                let before = try await library.hashes()
                let selection = try await library.selection(["IMG_0001.dng", "IMG_0002.dng", "IMG_0003.dng"])
                #expect(selection.frames.map(\.fileName) == ["IMG_0003.dng", "IMG_0002.dng", "IMG_0001.dng"])
                #expect(selection.referenceFrame.fileName == "IMG_0002.dng")
                let result = try await library.job.run(selection, format: .tiff)
                #expect(result.url.lastPathComponent == "IMG_0002_HDR.tif")
                #expect(result.url.deletingLastPathComponent().standardizedFileURL.path
                    == library.folder.standardizedFileURL.path)
                // AC2: every master as it was, no partial file.
                let after = try await library.hashes()
                for (name, hash) in before { #expect(after[name] == hash, "\(name)") }
                #expect(try library.files().allSatisfy { !$0.hasSuffix(".partial") })

                // AC4: a new master in the reference's project, with its hash.
                let master = try #require(result.master)
                let details = try #require(try await catalog.details(forVersion: master.versionID))
                let referenceDetails = try #require(try await catalog.details(forVersion: reference))
                #expect(details.image.projectId == referenceDetails.image.projectId)
                #expect(details.image.contentHash == after["IMG_0002_HDR.tif"])
                #expect(details.image.fileName == "IMG_0002_HDR.tif")

                // AC5: the reference's values, in the library and in the file.
                let values = try await catalog.libraryValues(forVersion: master.versionID)
                let expected = try await catalog.libraryValues(forVersion: reference)
                #expect(values == expected)
                #expect(details.image.captureDate == referenceDetails.image.captureDate)
                let read = try #require(try await ImageIOMetadataReader().metadata(for: [result.url])[result.url])
                #expect(read.title == "Harbor at dusk")
                #expect(read.caption == "Three frames")
                #expect(Set(read.keywords) == ["harbor", "dusk"])
                #expect(read.rating == 4)
                #expect(read.label == ColorLabel.red.xmpName)
                #expect(read.cameraModel == referenceDetails.image.cameraModel)

                // QA Q4: every date is the reference's capture date, not the merge's time.
                #expect(Self.dates(result.url) == ["2026:05:01 10:00:01", "2026:05:01 10:00:01", "2026-05-01T10:00:01"])

                // The file: 16 bits, three samples, Display P3.
                let source = try #require(CGImageSourceCreateWithURL(result.url as CFURL, nil))
                let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
                #expect(image.bitsPerComponent == 16)
                #expect(image.alphaInfo == .none || image.alphaInfo == .noneSkipLast)
                #expect(image.colorSpace?.name == CGColorSpace.displayP3)

                // AC2: again gives -2, and the first file stays as it was.
                let again = try await library.job.run(selection, format: .tiff)
                #expect(again.url.lastPathComponent == "IMG_0002_HDR-2.tif")
                #expect(try await library.hashes()["IMG_0002_HDR.tif"] == after["IMG_0002_HDR.tif"])
                // C1, AC15: a photo of its own, with a row of its own, and a file of its own
                // content, whose pixels are the first merge's.
                let second = try #require(again.master)
                #expect(second.imageID != master.imageID)
                #expect(try await library.hashes()["IMG_0002_HDR-2.tif"] != after["IMG_0002_HDR.tif"])
                #expect(try Self.pixels(result.url) == Self.pixels(again.url))
                // C3: a DNG of the same bracket gets a stem of its own.
                let dng = try await library.job.run(selection, format: .dng)
                #expect(dng.url.lastPathComponent == "IMG_0002_HDR-3.dng")
                #expect(dng.master != nil)
            }
        }

        /// EXIF DateTimeOriginal and DateTimeDigitized, and XMP CreateDate, as
        /// ImageIO reads them.
        static func dates(_ url: URL) -> [String?] {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return [] }
            let exif = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])?[kCGImagePropertyExifDictionary]
                as? [CFString: Any] ?? [:]
            let xmp = CGImageSourceCopyMetadataAtIndex(source, 0, nil)
                .flatMap { CGImageMetadataCopyStringValueWithPath($0, nil, "xmp:CreateDate" as CFString) } as String?
            return [exif[kCGImagePropertyExifDateTimeOriginal] as? String, exif[kCGImagePropertyExifDateTimeDigitized] as? String,
                    xmp.map { String($0.prefix(19)) }]
        }

        /// A TIFF's decoded pixels, 16 bits a channel.
        static func pixels(_ url: URL) throws -> Data {
            let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
            let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
            return try #require(image.dataProvider?.data as Data?)
        }

        @Test("AC15: merging again after the first photo was removed from the library is a new photo")
        func againAfterRemoval() async throws {
            try await offCooperativePool {
                let library = try await MergeLibrary.make(Self.bracket)
                defer { library.remove() }
                let selection = try await library.selection(["IMG_0001.dng", "IMG_0002.dng", "IMG_0003.dng"])
                let first = try await library.job.run(selection, format: .tiff)
                _ = try await library.catalog.removeMergedMaster(imageID: try #require(first.master).imageID)
                let again = try await library.job.run(selection, format: .tiff)
                #expect(again.url.lastPathComponent == "IMG_0002_HDR-2.tif")
                #expect(again.master != nil)
                #expect(FileManager.default.fileExists(atPath: first.url.path))
            }
        }

        @Test("AC2a: a TIFF and a DNG of one bracket each keep their own sidecar")
        func ownSidecars() async throws {
            try await offCooperativePool {
                let library = try await MergeLibrary.make(Self.bracket)
                defer { library.remove() }
                let catalog = library.catalog
                let reference = try #require(library.versions["IMG_0002.dng"])
                let sync = SidecarSync(catalog: catalog, metadataReader: ImageIOMetadataReader())
                let selection = try await library.selection(["IMG_0001.dng", "IMG_0002.dng", "IMG_0003.dng"])
                try await catalog.setRating(Rating(clamping: 4), forVersions: [reference])
                let tiff = try #require(try await library.job.run(selection, format: .tiff).master)
                let volume = try #require(try await catalog.details(forVersion: tiff.versionID)).image.volumeId
                _ = try await sync.writeSidecars(forImages: [tiff.imageID], mountedVolumes: [volume])
                try await catalog.setRating(Rating(clamping: 2), forVersions: [reference])
                let dngResult = try await library.job.run(selection, format: .dng)
                #expect(dngResult.url.lastPathComponent == "IMG_0002_HDR-2.dng")
                let dng = try #require(dngResult.master)
                _ = try await sync.writeSidecars(forImages: [dng.imageID], mountedVolumes: [volume])
                let first = try SidecarFiles.read(library.folder.appending(path: "IMG_0002_HDR.xmp"))
                let second = try SidecarFiles.read(library.folder.appending(path: "IMG_0002_HDR-2.xmp"))
                #expect(first.values.rating == Rating(clamping: 4))
                #expect(second.values.rating == Rating(clamping: 2))
                #expect(try await catalog.libraryValues(forVersion: tiff.versionID).rating == Rating(clamping: 4))
            }
        }

        @Test("AC2: an existing file with the result's name is left alone")
        func existingFileUntouched() async throws {
            try await offCooperativePool {
                let library = try await MergeLibrary.make(Self.bracket) { folder in
                    try Data("not a photo".utf8).write(to: folder.appending(path: "IMG_0002_HDR.tif"))
                }
                defer { library.remove() }
                let selection = try await library.selection(["IMG_0001.dng", "IMG_0002.dng", "IMG_0003.dng"])
                let result = try await library.job.run(selection, format: .tiff)
                #expect(result.url.lastPathComponent == "IMG_0002_HDR-2.tif")
                #expect(try Data(contentsOf: library.folder.appending(path: "IMG_0002_HDR.tif")) == Data("not a photo".utf8))
            }
        }

        @Test("AC3: with no compensation recorded, the first frame by capture time names the result")
        func firstByTimeNames() async throws {
            try await offCooperativePool {
                let library = try await MergeLibrary.make(Self.bracket, order: [2, 0, 1], writesBias: false)
                defer { library.remove() }
                let selection = try await library.selection(["IMG_0001.dng", "IMG_0002.dng", "IMG_0003.dng"])
                #expect(selection.referenceFrame.fileName == "IMG_0003.dng")
                let result = try await library.job.run(selection, format: .tiff)
                #expect(result.url.lastPathComponent == "IMG_0003_HDR.tif")
            }
        }

        @Test("AC4: DNG writes a linear floating-point DNG the system's RAW decoder reads, catalogued")
        func mergesToDNG() async throws {
            try await offCooperativePool {
                let library = try await MergeLibrary.make(Self.bracket)
                defer { library.remove() }
                let selection = try await library.selection(["IMG_0001.dng", "IMG_0002.dng", "IMG_0003.dng"])
                let result = try await library.job.run(selection, format: .dng)
                #expect(result.url.lastPathComponent == "IMG_0002_HDR.dng")
                let layout = try #require(DNGLayout(contentsOf: result.url))
                #expect(layout.hasFloatingPointRaw)
                #expect(layout.hasLinearRaw)
                #expect(SystemRAWDecoder.reads(result.url))
                #expect(result.master != nil)
                // QA Q4: the DNG's dates are the reference's capture date too (the
                // fixture's IMG_0002 is the second frame, a second after the first).
                #expect(Self.dates(result.url) == ["2026:05:01 10:00:01", "2026:05:01 10:00:01", "2026-05-01T10:00:01"])
            }
        }

        @Test("AC4: a sidecar is written for the merged photo when sidecars are, and only then")
        func sidecarWhenEnabled() async throws {
            try await offCooperativePool {
                let library = try await MergeLibrary.make(Self.bracket)
                defer { library.remove() }
                // A sidecar holds the library's values; a photo with none gets none,
                // as any new master (status.md RI-E2).
                try await library.catalog.setRating(Rating(clamping: 3), forVersions: [try #require(library.versions["IMG_0002.dng"])])
                let selection = try await library.selection(["IMG_0001.dng", "IMG_0002.dng", "IMG_0003.dng"])
                let result = try await library.job.run(selection, format: .tiff)
                // The job itself writes no sidecar (sidecars off).
                #expect(try !library.files().contains("IMG_0002_HDR.xmp"))
                let master = try #require(result.master)
                let details = try #require(try await library.catalog.details(forVersion: master.versionID))
                let report = try await SidecarSync(catalog: library.catalog, metadataReader: ImageIOMetadataReader())
                    .writeSidecars(forImages: [master.imageID], mountedVolumes: [details.image.volumeId])
                #expect(report.written == 1)
                #expect(try library.files().contains("IMG_0002_HDR.xmp"))
            }
        }

        @Test("AC6: three JPEGs merge")
        func mergesJPEGs() async throws {
            try await offCooperativePool {
                let library = try await MergeLibrary.make(Self.bracket, kind: .jpeg)
                defer { library.remove() }
                let selection = try await library.selection(["IMG_0001.jpg", "IMG_0002.jpg", "IMG_0003.jpg"])
                #expect(selection.refusal == nil)
                let result = try await library.job.run(selection, format: .tiff)
                #expect(result.url.lastPathComponent == "IMG_0002_HDR.tif")
                #expect(result.master != nil)
            }
        }

        @Test("AC6: a raw with two JPEGs is refused and writes nothing")
        func mixedRefused() async throws {
            try await offCooperativePool {
                let library = try await MergeLibrary.make(Self.bracket, kind: .jpeg) { folder in
                    let image = HDRBracket.image(Self.bracket[1], width: MergeLibrary.width, height: MergeLibrary.height)
                    try HDRBracket.writeDNG(image, frame: Self.bracket[1], to: folder.appending(path: "RAW_0001.dng"),
                                            date: "2026:05:01 10:00:09")
                }
                defer { library.remove() }
                let before = try library.files()
                let count = try await library.catalog.allImages().count
                let selection = try await library.selection(["RAW_0001.dng", "IMG_0001.jpg", "IMG_0003.jpg"])
                #expect(selection.refusal == .mixedKinds)
                #expect(selection.flagged == [try #require(library.versions["RAW_0001.dng"])])
                await #expect(throws: HDRMergeJob.Failure.refused(.mixedKinds)) {
                    try await library.job.run(selection, format: .tiff)
                }
                #expect(try library.files() == before)
                #expect(try await library.catalog.allImages().count == count)
            }
        }

        @Test("AC6: a RAW+JPEG pair selected as its JPEG counts once, as its raw")
        func pairCountsOnce() async throws {
            try await offCooperativePool {
                let library = try await MergeLibrary.make(Self.bracket) { folder in
                    let image = HDRBracket.image(Self.bracket[1], width: MergeLibrary.width, height: MergeLibrary.height)
                    try HDRBracket.writeJPEG(image, frame: Self.bracket[1], to: folder.appending(path: "IMG_0002.jpg"),
                                             date: "2026:05:01 10:00:01")
                }
                defer { library.remove() }
                let raw = try #require(library.versions["IMG_0002.dng"]), jpeg = try #require(library.versions["IMG_0002.jpg"])
                var items = try await library.catalog.libraryItems(versionIDs: [jpeg, library.versions["IMG_0001.dng"]!])
                // The grid's query links the halves of a pair (`libraryItems` doesn't).
                let index = try #require(items.firstIndex { $0.versionID == jpeg })
                items[index].partnerVersionID = raw
                items[index].partnerKind = .raw
                let ids = MergeSelection.versionIDs(for: items)
                #expect(ids.count == 2)
                #expect(ids.contains(raw))
                #expect(!ids.contains(jpeg))
            }
        }

        @Test("AC7: a frame of another scene is refused, named, and nothing is written")
        func unrelatedSceneRefused() async throws {
            try await offCooperativePool {
                let library = try await MergeLibrary.make(Array(Self.bracket.prefix(2))) { folder in
                    let other = TestScene.hazyLandscape.image(width: MergeLibrary.width, height: MergeLibrary.height)
                    try HDRBracket.writeDNG(other, frame: HDRBracket.Frame(ev: 2), to: folder.appending(path: "IMG_0003.dng"),
                                            date: "2026:05:01 10:00:05")
                }
                defer { library.remove() }
                let before = try library.files()
                let selection = try await library.selection(["IMG_0001.dng", "IMG_0002.dng", "IMG_0003.dng"])
                await #expect(throws: HDRMergeJob.Failure.misaligned(name: "IMG_0003", reference: "IMG_0002")) {
                    try await library.job.run(selection, format: .tiff)
                }
                #expect(try library.files() == before)
            }
        }

        @Test("AC9: stopping mid-merge leaves no file, no partial file and no catalog row")
        func cancelLeavesNothing() async throws {
            try await offCooperativePool {
                let library = try await MergeLibrary.make(Self.bracket)
                defer { library.remove() }
                let before = try library.files()
                let count = try await library.catalog.allImages().count
                let selection = try await library.selection(["IMG_0001.dng", "IMG_0002.dng", "IMG_0003.dng"])
                let job = library.job
                let started = AsyncStream<Void>.makeStream()
                let task = Task {
                    try await job.run(selection, format: .tiff) { progress in
                        if case .aligning = progress.phase { started.continuation.yield() }
                    }
                }
                for await _ in started.stream { task.cancel(); break }
                await #expect(throws: CancellationError.self) { try await task.value }
                #expect(try library.files() == before)
                #expect(try await library.catalog.allImages().count == count)
            }
        }

        @Test("AC12: a read-only folder is refused before any work starts")
        func readOnlyFolderRefused() async throws {
            try await offCooperativePool {
                let library = try await MergeLibrary.make(Self.bracket)
                defer {
                    try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: library.folder.path)
                    library.remove()
                }
                try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: library.folder.path)
                let selection = try await library.selection(["IMG_0001.dng", "IMG_0002.dng", "IMG_0003.dng"])
                let check = try #require(MergePreflight.disk.check(selection))
                #expect(check.refusal == .unwritableFolder(reference: "IMG_0002", folder: library.folder.lastPathComponent))
                let reads = ProgressLog()
                await #expect(throws: HDRMergeJob.Failure.refused(check.refusal)) {
                    try await library.job.run(selection, format: .tiff) { reads.add($0) }
                }
                #expect(reads.count == 0)
            }
        }

        @Test("C8: a file the catalog refuses is removed, but only while its name still holds it")
        func refusedFileRemoved() async throws {
            try await offCooperativePool {
                let library = try await MergeLibrary.make(Self.bracket)
                defer { library.remove() }
                let selection = try await library.selection(["IMG_0001.dng", "IMG_0002.dng", "IMG_0003.dng"])
                let before = try library.files()
                await #expect(throws: HDRMergeJob.Failure.sameContent) {
                    try await library.job.run(selection, format: .tiff, catalogue: { _ in throw MergeCatalogFailure.sameContent })
                }
                #expect(try library.files() == before)
                // Another file put under the name meanwhile is not the merge's: it stays.
                let url = library.folder.appending(path: "IMG_0002_HDR.tif")
                await #expect(throws: HDRMergeJob.Failure.sameContent) {
                    try await library.job.run(selection, format: .tiff, catalogue: { _ in
                        try FileManager.default.removeItem(at: url)
                        try Data("someone else's".utf8).write(to: url)
                        throw MergeCatalogFailure.sameContent
                    })
                }
                #expect(try Data(contentsOf: url) == Data("someone else's".utf8))
            }
        }

        @Test("The catalog write runs through a given catalogue, once, or directly without one (CI on PR #258)")
        func catalogueOptional() async throws {
            // `catalogue` has no default closure (Swift 6.2 and 6.3 crashed calling
            // one); nil runs the insert directly, as every other job test does.
            try await offCooperativePool {
                let library = try await MergeLibrary.make(Self.bracket)
                defer { library.remove() }
                let selection = try await library.selection(["IMG_0001.dng", "IMG_0002.dng", "IMG_0003.dng"])
                // Given: called once, around the insert, and its result is the job's.
                let calls = Mutex(0)
                let given = try await library.job.run(selection, format: .tiff, catalogue: { insert in
                    calls.withLock { $0 += 1 }
                    return try await insert()
                })
                #expect(calls.withLock { $0 } == 1)
                let master = try #require(given.master)
                let details = try #require(try await library.catalog.details(forVersion: master.versionID))
                #expect(details.image.fileName == given.url.lastPathComponent)
                // Its error is handled as before: a path already in the library is
                // that version, not a failure.
                let existing = try await library.job.run(selection, format: .tiff, catalogue: { _ in
                    throw MergeCatalogFailure.alreadyInLibrary(versionID: master.versionID)
                })
                #expect(existing.master == nil)
                #expect(existing.existingVersionID == master.versionID)
                // Without one: catalogued directly, a photo of its own.
                let direct = try await library.job.run(selection, format: .tiff)
                let directMaster = try #require(direct.master)
                #expect(directMaster.versionID != master.versionID)
                #expect(try await library.catalog.details(forVersion: directMaster.versionID) != nil)
            }
        }

        @Test("C1: the catalog refusing a second master of the same content says so")
        func sameContentRefused() async throws {
            try await offCooperativePool {
                let library = try await MergeLibrary.make(Self.bracket)
                defer { library.remove() }
                let images = try await library.catalog.allImages()
                let image = try #require(images.first)
                let copy = NewMaster(relativePath: "elsewhere/" + image.fileName, fileSize: image.fileSize,
                                     modifiedAt: image.modifiedAt, contentHash: image.contentHash, metadata: .empty)
                await #expect(throws: MergeCatalogFailure.sameContent) {
                    try await library.catalog.insertMergedMaster(copy, volumeID: image.volumeId, projectID: image.projectId,
                                                                 values: SidecarValues())
                }
                #expect(try await library.catalog.allImages().count == images.count)
            }
        }

        @Test("AC13: Undo takes the photo out of the library and leaves the file; Redo brings it back unless the file changed")
        func undoAndRedo() async throws {
            try await offCooperativePool {
                let library = try await MergeLibrary.make(Self.bracket)
                defer { library.remove() }
                let catalog = library.catalog
                let selection = try await library.selection(["IMG_0001.dng", "IMG_0002.dng", "IMG_0003.dng"])
                let result = try await library.job.run(selection, format: .tiff)
                let master = try #require(result.master)
                let removed = try #require(try await catalog.removeMergedMaster(imageID: master.imageID))
                #expect(try await catalog.details(forVersion: master.versionID) == nil)
                #expect(FileManager.default.fileExists(atPath: result.url.path))
                #expect(try await catalog.restoreMergedMaster(removed, fileAt: result.url))
                let back = try #require(try await catalog.details(forVersion: master.versionID))
                #expect(back.image.id == master.imageID)
                // Undo again, change the file: Redo refuses and adds nothing.
                let again = try #require(try await catalog.removeMergedMaster(imageID: master.imageID))
                try Data("changed".utf8).write(to: result.url)
                #expect(try await !catalog.restoreMergedMaster(again, fileAt: result.url))
                #expect(try await catalog.details(forVersion: master.versionID) == nil)
            }
        }

        @Test("AC13: Undo and Redo keep the stored detection results an edit-history entry names (#88)")
        func undoAndRedoKeepMaskRasters() async throws {
            try await offCooperativePool {
                let library = try await MergeLibrary.make(Self.bracket)
                defer { library.remove() }
                let catalog = library.catalog
                let selection = try await library.selection(["IMG_0001.dng", "IMG_0002.dng", "IMG_0003.dng"])
                let result = try await library.job.run(selection, format: .tiff)
                let master = try #require(result.master)
                var adjustments = Adjustments()
                adjustments.exposure.ev = 0.5
                try await catalog.setEditStack(adjustments.editStack, forVersion: master.versionID, historyLabel: "Exposure")
                #expect(try await catalog.editHistory(forVersion: master.versionID).count == 1)
                let digests = "[\"abc123\"]"
                try await catalog.database.write { db in
                    try db.execute(sql: "UPDATE editHistory SET maskRasters = ? WHERE versionId = ?",
                                   arguments: [digests, master.versionID])
                }
                let removed = try #require(try await catalog.removeMergedMaster(imageID: master.imageID))
                #expect(try await catalog.restoreMergedMaster(removed, fileAt: result.url))
                let stored: [String?] = try await catalog.database.read { db in
                    try String?.fetchAll(db, sql: "SELECT maskRasters FROM editHistory WHERE versionId = ?",
                                         arguments: [master.versionID])
                }
                #expect(stored == [digests])
            }
        }

        @Test("AC11: the merged photo renders, takes an edit with history, and exports")
        func resultIsAPhoto() async throws {
            try await offCooperativePool {
                let library = try await MergeLibrary.make(Self.bracket)
                defer { library.remove() }
                let catalog = library.catalog
                let selection = try await library.selection(["IMG_0001.dng", "IMG_0002.dng", "IMG_0003.dng"])
                let result = try await library.job.run(selection, format: .tiff)
                let master = try #require(result.master)
                let rendered = try PreviewGenerator().cgImage(source: result.url, stack: EditStack(), longEdge: 256)
                #expect(rendered.width == 256)
                var adjustments = Adjustments()
                adjustments.exposure.ev = 0.5
                try await catalog.setEditStack(adjustments.editStack, forVersion: master.versionID, historyLabel: "Exposure")
                #expect(try await catalog.editHistory(forVersion: master.versionID).count == 1)
                let out = library.folder.appending(path: "export", directoryHint: .isDirectory)
                var job = ExportJob(catalog: catalog, renderer: ExportRenderer())
                job.mountedVolumes = { [] }
                let summary = await job.run(ExportRequest(versionIDs: [master.versionID], settings: ExportSettings(),
                                                          destination: out))
                #expect(summary.written.count == 1)
                #expect(summary.failures.isEmpty)
            }
        }

        @Test("Spike 5: an import into the same catalog while a merge catalogues its file leaves both complete")
        func importBesideMerge() async throws {
            try await offCooperativePool {
                let library = try await MergeLibrary.make(Self.bracket)
                defer { library.remove() }
                let other = FileManager.default.temporaryDirectory.appending(path: "merge-other-\(UUID().uuidString)")
                try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: other) }
                for seed in 0..<40 {
                    try SyntheticImages.writeJPEG(to: other.appending(path: "other-\(seed).jpg"), width: 64, height: 48,
                                                  seed: UInt64(1000 + seed))
                }
                let before = try await library.catalog.allImages().count
                let selection = try await library.selection(["IMG_0001.dng", "IMG_0002.dng", "IMG_0003.dng"])
                let catalog = library.catalog
                async let imported = Importer(catalog: catalog, metadataReader: ImageIOMetadataReader(),)
                    .importFolder(other, options: ImportOptions(chunkSize: 4))
                async let merged = library.job.run(selection, format: .tiff)
                let (summary, result) = try await (imported, merged)
                #expect(summary.progress.imported == 40)
                #expect(result.master != nil)
                #expect(try await catalog.allImages().count == before + 41)
            }
        }
    }
}

/// Counts progress reports from a `@Sendable` closure.
final class ProgressLog: @unchecked Sendable {
    // @unchecked: guarded by the lock.
    private let lock = NSLock()
    private var reports: [MergeProgress] = []

    func add(_ progress: MergeProgress) { lock.withLock { reports.append(progress) } }
    var count: Int { lock.withLock { reports.count } }
}

extension MemoryHeavy {
    @Suite("photocli merge", .serialized)
    struct MergeCommandTests {
        @Test("AC14: photocli merge writes a fixture series and prints the path; refuses while the library is locked")
        func mergesFromTheCommandLine() async throws {
            try await offCooperativePool {
                try await RepositoryFiles.withTemporaryDirectory { root in
                    let photos = root.appending(path: "Photos", directoryHint: .isDirectory)
                    try FileManager.default.createDirectory(at: photos, withIntermediateDirectories: true)
                    for (index, frame) in HDRMergeJobTests.bracket.enumerated() {
                        let image = HDRBracket.image(frame, width: MergeLibrary.width, height: MergeLibrary.height)
                        try HDRBracket.writeDNG(image, frame: frame, to: photos.appending(path: "IMG_000\(index + 1).dng"),
                                                date: "2026:05:01 10:00:0\(index)")
                    }
                    let locations = LibraryLocations.rooted(at: root.appending(path: "Library", directoryHint: .isDirectory))
                    try locations.createDirectories()
                    let catalog = try Catalog.open(at: locations.catalogFileURL)
                    _ = try await Importer(catalog: catalog, metadataReader: ImageIOMetadataReader()).importFolder(photos)
                    let ids = try await catalog.libraryItems(matching: LibraryFilter(groupsPairs: false)).map(\.versionID)
                    let cli = CommandLineInterface(environment: .hermetic(currentDirectory: root))
                    let arguments = ["merge"] + ids.flatMap { ["--version", String($0)] }
                        + ["--library-root", locations.catalogDirectory.deletingLastPathComponent().path]

                    let lock = try LibraryLock.acquire(locations)
                    let refused = await cli.run(arguments)
                    #expect(refused.exitCode == 1 && refused.standardError.contains("libraryLocked"))
                    #expect(!FileManager.default.fileExists(atPath: photos.appending(path: "IMG_0002_HDR.tif").path))
                    lock.release()

                    let output = await cli.run(arguments)
                    #expect(output.exitCode == 0, "\(output.standardError)")
                    let json = try JSONValue.parse(output.standardOutput)
                    let path = try #require(json["path"]?.stringValue)
                    #expect(URL(fileURLWithPath: path).lastPathComponent == "IMG_0002_HDR.tif")
                    #expect(FileManager.default.fileExists(atPath: path))
                    #expect(json["format"] == "tiff")
                    #expect(json["frames"]?.arrayValue?.count == 3)
                    #expect(json["versionID"]?.numberValue != nil)

                    let mixed = await cli.run(["merge", "--version", String(ids[0]), "--library-root",
                                               locations.catalogDirectory.deletingLastPathComponent().path])
                    #expect(mixed.exitCode != 0 && mixed.standardError.contains("tooFew"))
                }
            }
        }
    }
}

@Suite("HDR merge rules")
struct MergeRuleTests {
    @Test("Quitting asks while a merge runs, after imports and exports")
    func quitAsks() {
        #expect(QuitConfirmation.needed(app: .library, trigger: .quit, isCopying: false, isMerging: true) == .merging)
        #expect(QuitConfirmation.needed(app: .library, trigger: .quit, isCopying: false, isExporting: true,
                                        isMerging: true) == .exporting)
        #expect(QuitConfirmation.needed(app: .library, trigger: .closeImportWindow, isCopying: false,
                                        isMerging: true) == nil)
    }

    @Test("No removal starts while a merge runs")
    func removalWaits() {
        #expect(!RemovalAvailability.canStart(isRemoving: false, isAddingFolders: false, isCopying: false,
                                              isMerging: true))
        #expect(RemovalAvailability.canStart(isRemoving: false, isAddingFolders: false, isCopying: false))
    }

    @Test("The merged photo takes the selection only when nothing was touched (design §8.3)")
    func landing() {
        #expect(MergeLanding.selects(started: [1, 2, 3], now: [3, 2, 1], showsGrid: true, shown: true))
        #expect(!MergeLanding.selects(started: [1, 2, 3], now: [4], showsGrid: true, shown: true))
        #expect(!MergeLanding.selects(started: [1, 2, 3], now: [1, 2, 3], showsGrid: false, shown: true))
        #expect(!MergeLanding.selects(started: [1, 2, 3], now: [1, 2, 3], showsGrid: true, shown: false))
    }
}

@Suite("Waiting with a deadline")
struct MainActorWaitTests {
    /// Time that passes only when the wait sleeps.
    @MainActor
    final class FakeTime {
        var now: Duration = .zero
        var sleeps = 0
        func sleep(_ duration: Duration) { now += duration; sleeps += 1 }
    }

    @Test("C7: the wait ends at its deadline while the condition still holds, and as soon as it stops")
    @MainActor
    func deadline() async {
        let time = FakeTime()
        let ended = await MainActorWait.whileTrue({ true }, timeout: .seconds(10), interval: .milliseconds(100),
                                                  elapsed: { time.now }, sleep: { time.sleep($0) })
        #expect(!ended)
        #expect(time.now == .seconds(10))
        #expect(time.sleeps == 100)

        let later = FakeTime()
        var asked = 0
        let stopped = await MainActorWait.whileTrue({ asked += 1; return asked < 4 }, timeout: .seconds(10),
                                                    interval: .milliseconds(100), elapsed: { later.now },
                                                    sleep: { later.sleep($0) })
        #expect(stopped)
        #expect(later.now == .milliseconds(300))
    }

    @Test("C7: with the real clock, a wait on a condition that never ends returns")
    @MainActor
    func realClockReturns() async {
        #expect(await !MainActorWait.whileTrue({ true }, timeout: .milliseconds(50)))
    }
}
