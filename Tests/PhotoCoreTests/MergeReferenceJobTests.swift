import CoreImage
import Foundation
import ImageIO
import PhotoFixtures
import Testing
@testable import PhotoCore

/// A bracket whose frames are in two folders, imported as two projects:
/// `IMG_0001` (−2 EV) and `IMG_0002` (0 EV) in `A`, `IMG_0003` (+2 EV) in `B`.
struct TwoFolderBracket {
    let root: URL
    let library: MergeLibrary

    var a: URL { root.appending(path: "A", directoryHint: .isDirectory) }
    var b: URL { root.appending(path: "B", directoryHint: .isDirectory) }

    static func make(_ frames: [HDRBracket.Frame] = MemoryHeavy.HDRMergeJobTests.bracket) async throws -> TwoFolderBracket {
        let root = FileManager.default.temporaryDirectory.appending(path: "merge-two-\(UUID().uuidString)",
                                                                     directoryHint: .isDirectory)
        let catalog = try Catalog.makeInMemory()
        for (index, frame) in frames.enumerated() {
            let folder = root.appending(path: index < 2 ? "A" : "B", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let image = HDRBracket.image(frame, width: MergeLibrary.width, height: MergeLibrary.height)
            try HDRBracket.writeDNG(image, frame: frame, to: folder.appending(path: String(format: "IMG_%04d.dng", index + 1)),
                                    date: String(format: "2026:05:01 10:00:%02d", index))
        }
        // One project per folder, as two folder imports make them.
        for name in ["A", "B"] {
            _ = try await Importer(catalog: catalog, metadataReader: ImageIOMetadataReader())
                .importFolder(root.appending(path: name, directoryHint: .isDirectory))
        }
        var versions: [String: Int64] = [:]
        for image in try await catalog.allImages() {
            guard let id = image.id, let version = try await catalog.versions(ofImage: id).first(where: \.isDefault) else {
                continue
            }
            versions[image.fileName] = version.id
        }
        return TwoFolderBracket(root: root, library: MergeLibrary(folder: root, catalog: catalog, versions: versions))
    }

    func remove() {
        for folder in [a, b] {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
        }
        try? FileManager.default.removeItem(at: root)
    }
}

/// Records each progress report's step.
final class PhaseLog: @unchecked Sendable {
    // @unchecked: guarded by the lock.
    private let lock = NSLock()
    private var reports: [MergeProgress] = []

    func add(_ progress: MergeProgress) { lock.withLock { reports.append(progress) } }
    var all: [MergeProgress] { lock.withLock { reports } }
}

extension MemoryHeavy {
    /// The merge job with a chosen reference and the two boxes (issue #150,
    /// revision 2026-11-21).
    @Suite("HDR merge job, reference and options", .serialized)
    struct MergeReferenceJobTests {
        @Test("AC3a: another reference names the result, puts it in its folder and project, and gives it its values")
        func chosenReference() async throws {
            try await offCooperativePool {
                let bracket = try await TwoFolderBracket.make()
                defer { bracket.remove() }
                let catalog = bracket.library.catalog
                let chosen = try #require(bracket.library.versions["IMG_0003.dng"])
                let standard = try #require(bracket.library.versions["IMG_0002.dng"])
                try await catalog.setRating(Rating(clamping: 5), forVersions: [chosen])
                try await catalog.setColorLabel(.blue, forVersions: [chosen])
                try await catalog.setDescriptiveField(.title, to: "From the bright frame", forVersions: [chosen])
                try await catalog.setRating(Rating(clamping: 1), forVersions: [standard])
                try await catalog.setDescriptiveField(.title, to: "From the 0 EV frame", forVersions: [standard])

                let selection = try await bracket.library.selection(["IMG_0001.dng", "IMG_0002.dng", "IMG_0003.dng"])
                #expect(selection.referenceFrame.fileName == "IMG_0002.dng")
                let other = try #require(selection.choosingReference(chosen))
                #expect(other.referenceFrame.fileName == "IMG_0003.dng")
                #expect(other.frames == selection.frames)

                let result = try await bracket.library.job.run(other, format: .tiff)
                #expect(result.url.lastPathComponent == "IMG_0003_HDR.tif")
                #expect(result.url.deletingLastPathComponent().standardizedFileURL.path == bracket.b.standardizedFileURL.path)
                #expect(!FileManager.default.fileExists(atPath: bracket.a.appending(path: "IMG_0002_HDR.tif").path))
                let master = try #require(result.master)
                let details = try #require(try await catalog.details(forVersion: master.versionID))
                let chosenDetails = try #require(try await catalog.details(forVersion: chosen))
                let standardDetails = try #require(try await catalog.details(forVersion: standard))
                #expect(details.image.projectId == chosenDetails.image.projectId)
                #expect(details.image.projectId != standardDetails.image.projectId)
                #expect(details.image.captureDate == chosenDetails.image.captureDate)
                // AC5's fields are the chosen frame's, not the default reference's.
                #expect(try await catalog.libraryValues(forVersion: master.versionID)
                    == catalog.libraryValues(forVersion: chosen))
                let read = try #require(try await ImageIOMetadataReader().metadata(for: [result.url])[result.url])
                #expect(read.title == "From the bright frame")
                #expect(read.rating == 5)
                #expect(read.label == ColorLabel.blue.xmpName)

                // Numbered in the chosen frame's folder, as any result.
                let again = try await bracket.library.job.run(other, format: .dng)
                #expect(again.url.lastPathComponent == "IMG_0003_HDR-2.dng")
            }
        }

        @Test("AC12: a read-only folder refuses only while the reference is in it")
        func readOnlyFollowsTheReference() async throws {
            try await offCooperativePool {
                let bracket = try await TwoFolderBracket.make()
                defer { bracket.remove() }
                try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: bracket.a.path)
                let selection = try await bracket.library.selection(["IMG_0001.dng", "IMG_0002.dng", "IMG_0003.dng"])
                let check = try #require(MergePreflight.disk.check(selection))
                #expect(check.refusal == .unwritableFolder(reference: "IMG_0002", folder: "A"))
                await #expect(throws: HDRMergeJob.Failure.refused(check.refusal)) {
                    try await bracket.library.job.run(selection, format: .tiff)
                }
                let third = try #require(bracket.library.versions["IMG_0003.dng"])
                let first = try #require(bracket.library.versions["IMG_0001.dng"])
                let writable = try #require(selection.choosingReference(third))
                #expect(MergePreflight.disk.check(writable) == nil)
                let result = try await bracket.library.job.run(writable, format: .tiff)
                #expect(result.url.lastPathComponent == "IMG_0003_HDR.tif")
                let back = try #require(writable.choosingReference(first))
                #expect(MergePreflight.disk.check(back)?.refusal == .unwritableFolder(reference: "IMG_0001", folder: "A"))
            }
        }

        @Test("AC7a, design §7.1: with Auto-align off frames of another scene merge, and the job has no Aligning step")
        func unrelatedMergesWithoutAlignment() async throws {
            try await offCooperativePool {
                let bracket = MemoryHeavy.HDRMergeJobTests.bracket
                let library = try await MergeLibrary.make(Array(bracket.prefix(2))) { folder in
                    let other = TestScene.hazyLandscape.image(width: MergeLibrary.width, height: MergeLibrary.height)
                    try HDRBracket.writeDNG(other, frame: HDRBracket.Frame(ev: 2), to: folder.appending(path: "IMG_0003.dng"),
                                            date: "2026:05:01 10:00:05")
                }
                defer { library.remove() }
                let selection = try await library.selection(["IMG_0001.dng", "IMG_0002.dng", "IMG_0003.dng"])
                let phases = PhaseLog()
                let result = try await library.job.run(selection, format: .tiff, options: MergeOptions(align: false)) {
                    phases.add($0)
                }
                #expect(result.url.lastPathComponent == "IMG_0002_HDR.tif")
                #expect(result.master != nil)
                let reports = phases.all
                #expect(!reports.contains { if case .aligning = $0.phase { true } else { false } })
                #expect(reports.contains { $0.phase == .merging })
                // The bar never goes back and ends at 1.
                #expect(zip(reports, reports.dropFirst()).allSatisfy { $0.fraction <= $1.fraction })
                #expect(reports.last?.fraction == 1)

                // With it on, the same frames are refused and Activity's text says how to turn it off (MergeText).
                await #expect(throws: HDRMergeJob.Failure.misaligned(name: "IMG_0003", reference: "IMG_0002")) {
                    try await library.job.run(selection, format: .tiff)
                }
            }
        }

        @Test("AC7b: with Auto-align off the other refusals still apply")
        func refusalsWithoutAlignment() async throws {
            try await offCooperativePool {
                let library = try await MergeLibrary.make(MemoryHeavy.HDRMergeJobTests.bracket) { folder in
                    try Data("not a movie".utf8).write(to: folder.appending(path: "CLIP.mov"))
                }
                defer {
                    try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: library.folder.path)
                    library.remove()
                }
                let off = MergeOptions(align: false, deghost: false)
                let selection = try await library.selection(["IMG_0001.dng", "IMG_0002.dng", "IMG_0003.dng"])
                // A frame of another size, as the catalog has it.
                var frames = selection.frames
                frames[2].pixelSize = CGSize(width: 320, height: 480)
                let sized = MergeSelection(frames: frames)
                #expect(sized.refusal == .differentSize(name: "IMG_0003", reference: "IMG_0002"))
                await #expect(throws: HDRMergeJob.Failure.refused(sized.refusal!)) {
                    try await library.job.run(sized, format: .tiff, options: off)
                }
                // An offline frame.
                frames = selection.frames
                frames[0].isOnline = false
                let offline = MergeSelection(frames: frames)
                await #expect(throws: HDRMergeJob.Failure.refused(.offline(name: "IMG_0001", count: 1))) {
                    try await library.job.run(offline, format: .tiff, options: off)
                }
                // A video among the photos.
                if let clip = library.versions["CLIP.mov"] {
                    let details = try #require(try await library.catalog.details(forVersion: clip))
                    let withVideo = MergeSelection(frames: selection.frames + [MergeFrame(details: details, isOnline: true)])
                    await #expect(throws: HDRMergeJob.Failure.refused(.video(name: "CLIP"))) {
                        try await library.job.run(withVideo, format: .tiff, options: off)
                    }
                }
                // The read-only folder, before any work starts.
                try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: library.folder.path)
                let reads = ProgressLog()
                await #expect(throws: HDRMergeJob.Failure.refused(.unwritableFolder(reference: "IMG_0002",
                                                                                     folder: library.folder.lastPathComponent))) {
                    try await library.job.run(selection, format: .tiff, options: off) { reads.add($0) }
                }
                #expect(reads.count == 0)
            }
        }

        @Test("AC3b, AC8a at the job: de-ghost off and another reference give other pixels; the defaults are deterministic")
        func choicesAreOtherMerges() async throws {
            try await offCooperativePool {
                let walker = [HDRBracket.Frame(ev: -2, object: SIMD2(0.13, 0.42)), HDRBracket.Frame(ev: 0, object: SIMD2(0.27, 0.42)),
                              HDRBracket.Frame(ev: 2, object: SIMD2(0.41, 0.42))]
                let library = try await MergeLibrary.make(walker)
                defer { library.remove() }
                let selection = try await library.selection(["IMG_0001.dng", "IMG_0002.dng", "IMG_0003.dng"])
                let standard = try await library.job.run(selection, format: .tiff)
                let plain = try await library.job.run(selection, format: .tiff, options: MergeOptions(deghost: false))
                let third = try #require(library.versions["IMG_0003.dng"])
                let bright = try await library.job.run(try #require(selection.choosingReference(third)), format: .tiff)
                #expect(standard.url.lastPathComponent == "IMG_0002_HDR.tif")
                #expect(plain.url.lastPathComponent == "IMG_0002_HDR-2.tif")
                #expect(bright.url.lastPathComponent == "IMG_0003_HDR.tif")
                let pixels = try [standard, plain, bright].map { try MemoryHeavy.HDRMergeJobTests.pixels($0.url) }
                #expect(pixels[0] != pixels[1])
                #expect(pixels[0] != pixels[2])
                // R19: the same choices again give the same pixels.
                let again = try await library.job.run(selection, format: .tiff)
                #expect(try MemoryHeavy.HDRMergeJobTests.pixels(again.url) == pixels[0])
            }
        }
    }
}

@Suite("HDR merge progress")
struct MergeProgressScheduleTests {
    @Test("Design §7.1: without alignment its share is left out and the bar still runs from 0 to 1")
    func schedule() {
        let aligned = MergeProgress.Schedule(aligns: true)
        #expect(aligned.readingShare == 0.5 && aligned.aligningShare == 0.3)
        #expect(aligned.merging == 0.8 && abs(aligned.adding - 0.97) < 1e-12)
        let plain = MergeProgress.Schedule(aligns: false)
        #expect(plain.aligningShare == 0)
        #expect(abs(plain.readingShare - 0.5 / 0.7) < 1e-12)
        #expect(plain.merging == plain.readingShare)
        for schedule in [aligned, plain] {
            let steps = [schedule.readingShare, schedule.merging, schedule.toneMapping, schedule.saving, schedule.adding]
            #expect(zip(steps, steps.dropFirst()).allSatisfy { $0 <= $1 })
            #expect(schedule.adding < 1)
        }
    }
}

extension MemoryHeavy.MergeCommandTests {
    /// A library on disk under `root` with `frames` written to `Photos/A` (the
    /// first two) and `Photos/B` (the rest), each folder its own project; and
    /// the default version ids by file name.
    static func twoFolderLibrary(_ frames: [(HDRBracket.Frame, LinearImage?)], root: URL) async throws
        -> (locations: LibraryLocations, ids: [String: Int64]) {
        for (index, (frame, image)) in frames.enumerated() {
            let folder = root.appending(path: index < 2 ? "Photos/A" : "Photos/B", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let pixels = image ?? HDRBracket.image(frame, width: MergeLibrary.width, height: MergeLibrary.height)
            try HDRBracket.writeDNG(pixels, frame: frame, to: folder.appending(path: "IMG_000\(index + 1).dng"),
                                    date: "2026:05:01 10:00:0\(index)")
        }
        let locations = LibraryLocations.rooted(at: root.appending(path: "Library", directoryHint: .isDirectory))
        try locations.createDirectories()
        let catalog = try Catalog.open(at: locations.catalogFileURL)
        for name in ["A", "B"] {
            _ = try await Importer(catalog: catalog, metadataReader: ImageIOMetadataReader())
                .importFolder(root.appending(path: "Photos/\(name)", directoryHint: .isDirectory))
        }
        var ids: [String: Int64] = [:]
        for item in try await catalog.libraryItems(matching: LibraryFilter(groupsPairs: false)) {
            ids[(item.relativePath as NSString).lastPathComponent] = item.versionID
        }
        return (locations, ids)
    }

    @Test("AC14: photocli merge takes a reference and off switches, and says them in its JSON")
    func referenceAndSwitches() async throws {
        try await offCooperativePool {
            try await RepositoryFiles.withTemporaryDirectory { root in
                let frames = MemoryHeavy.HDRMergeJobTests.bracket.map { ($0, LinearImage?.none) }
                let (locations, ids) = try await Self.twoFolderLibrary(frames, root: root)
                let cli = CommandLineInterface(environment: .hermetic(currentDirectory: root))
                let names = ["IMG_0001.dng", "IMG_0002.dng", "IMG_0003.dng"]
                let base = ["merge"] + names.flatMap { ["--version", String(ids[$0]!)] }
                    + ["--library-root", locations.catalogDirectory.deletingLastPathComponent().path]

                // Without the options: the sheet's defaults.
                let standard = await cli.run(base)
                #expect(standard.exitCode == 0, "\(standard.standardError)")
                let json = try JSONValue.parse(standard.standardOutput)
                #expect(json["reference"]?.numberValue == Double(ids["IMG_0002.dng"]!))
                #expect(json["align"] == .bool(true))
                #expect(json["deghost"] == .bool(true))
                #expect(json["path"]?.stringValue?.hasSuffix("Photos/A/IMG_0002_HDR.tif") == true)

                // AC3a: another reference, in another folder.
                let chosen = await cli.run(base + ["--reference", String(ids["IMG_0003.dng"]!), "--no-align", "--no-deghost"])
                #expect(chosen.exitCode == 0, "\(chosen.standardError)")
                let other = try JSONValue.parse(chosen.standardOutput)
                #expect(other["reference"]?.numberValue == Double(ids["IMG_0003.dng"]!))
                #expect(other["align"] == .bool(false))
                #expect(other["deghost"] == .bool(false))
                #expect(other["path"]?.stringValue?.hasSuffix("Photos/B/IMG_0003_HDR.tif") == true)

                // A reference that isn't one of the frames is an error that says so, and writes nothing.
                let before = try FileManager.default.contentsOfDirectory(atPath: root.appending(path: "Photos/A").path)
                let wrong = await cli.run(["merge", "--version", String(ids["IMG_0001.dng"]!), "--version",
                                           String(ids["IMG_0002.dng"]!), "--reference", String(ids["IMG_0003.dng"]!),
                                           "--library-root", locations.catalogDirectory.deletingLastPathComponent().path])
                #expect(wrong.exitCode != 0)
                #expect(wrong.standardError.contains("not one of the --version values"))
                #expect(try FileManager.default.contentsOfDirectory(atPath: root.appending(path: "Photos/A").path) == before)
            }
        }
    }

    @Test("AC14, AC7a: an unrelated frame is refused naming --no-align, and merged as given with it")
    func unrelatedWithSwitch() async throws {
        try await offCooperativePool {
            try await RepositoryFiles.withTemporaryDirectory { root in
                let bracket = MemoryHeavy.HDRMergeJobTests.bracket
                let other = TestScene.hazyLandscape.image(width: MergeLibrary.width, height: MergeLibrary.height)
                let (locations, ids) = try await Self.twoFolderLibrary([(bracket[0], nil), (bracket[1], nil), (bracket[2], other)],
                                                                       root: root)
                let cli = CommandLineInterface(environment: .hermetic(currentDirectory: root))
                let base = ["merge"] + ["IMG_0001.dng", "IMG_0002.dng", "IMG_0003.dng"].flatMap { ["--version", String(ids[$0]!)] }
                    + ["--library-root", locations.catalogDirectory.deletingLastPathComponent().path]
                let refused = await cli.run(base)
                #expect(refused.exitCode != 0)
                #expect(refused.standardError.contains("IMG_0003 doesn't line up with IMG_0002"))
                #expect(refused.standardError.contains("--no-align"))
                let merged = await cli.run(base + ["--no-align"])
                #expect(merged.exitCode == 0, "\(merged.standardError)")
                #expect(try JSONValue.parse(merged.standardOutput)["align"] == .bool(false))
            }
        }
    }
}
