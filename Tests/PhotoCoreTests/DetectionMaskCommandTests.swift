import CoreGraphics
import Foundation
import Testing
@testable import PhotoCore

/// Issue #88, R9, AC9: `photocli mask add --shape subject|people|background`
/// and `mask list`, with a detector that answers the same everywhere.
@Suite("Detection masks: command line")
struct DetectionMaskCommandTests {
    struct Fixed: MaskDetecting {
        var answer: Result<MaskRaster, MaskDetectionError>
        func detect(_ request: MaskRaster.Request, in image: CGImage) throws(MaskDetectionError) -> MaskRaster {
            // The input is the mask frame at the preview tier's long edge, or less (R4).
            guard max(image.width, image.height) <= MaskDetectionRun.inputLongEdge else { throw .failed("too large") }
            return try answer.get()
        }
    }

    static let found = try! MaskRaster(levels: (0..<(16 * 12)).map { $0 % 16 < 8 ? 255 : 0 }, width: 16, height: 12,
                                       instances: 2, request: .person)

    /// Runs a command line on `library` with `detector`.
    static func run(_ library: CommandTests.TemporaryLibrary, _ detector: any MaskDetecting,
                    _ arguments: String...) async -> (output: CommandLineInterface.Output, json: JSONValue) {
        let cli = CommandLineInterface(environment: .hermetic(currentDirectory: library.root, maskDetector: detector))
        let output = await cli.run(arguments + ["--library-root", library.root.path])
        let text = output.exitCode == 0 ? output.standardOutput : output.standardError
        return (output, (try? JSONValue.parse(text)) ?? .null)
    }

    @Test("--dry-run reports what it found and stores nothing; a real run writes the component and its result (AC9)")
    func addPeople() async throws {
        try await CommandTests.withLibrary { library in
            let id = String(library.versionIDs[0])
            let detector = Fixed(answer: .success(Self.found))
            let dry = await Self.run(library, detector, "mask", "add", "--version", id, "--shape", "people",
                                     "--set", "exposure=-0.5", "--dry-run")
            #expect(dry.output.exitCode == 0, "\(dry.output.standardError)")
            #expect(dry.json["dryRun"] == true && dry.json["written"] == false)
            #expect(dry.json["detection"]?["state"] == "found" && dry.json["detection"]?["instances"] == 2)
            #expect(dry.json["detection"]?["raster"] == .string(Self.found.digest))
            let catalog = try Catalog.open(at: library.locations.catalogFileURL)
            #expect(try await catalog.maskRasterDigests().isEmpty, "a dry run stores no result")

            let real = await Self.run(library, detector, "mask", "add", "--version", id, "--shape", "people",
                                      "--set", "exposure=-0.5")
            #expect(real.json["written"] == true)
            let component = real.json["masks"]?.arrayValue?.first?["components"]?.arrayValue?.first
            #expect(component?["shape"] == "people" && component?["raster"] == .string(Self.found.digest))
            #expect(component?["state"] == "found")
            #expect(try await catalog.maskRasterDigests() == [Self.found.digest])

            // Background added to the same mask, and listed with its kind and state.
            let subject = Fixed(answer: .success(MaskRaster.empty(.foreground)))
            _ = await Self.run(library, subject, "mask", "add", "--version", id, "--mask", "0", "--shape", "background",
                               "--operation", "subtract")
            let listed = await Self.run(library, subject, "mask", "list", "--version", id)
            let components = listed.json["masks"]?.arrayValue?.first?["components"]?.arrayValue ?? []
            #expect(components.map { $0["shape"] } == ["people", "background"])
            #expect(components.map { $0["state"] } == ["found", "empty"])

            // The renderer export and the loupe share reads the stored result: without its row it renders otherwise.
            let out = library.root.appending(path: "people.png"), without = library.root.appending(path: "without.png")
            let render = await Self.run(library, detector, "render", "--version", id, "--out", out.path, "--long-edge", "160")
            #expect(render.output.exitCode == 0, "\(render.output.standardError)")
            try await catalog.deleteMaskRasterForChecks(digest: Self.found.digest)
            _ = await Self.run(library, detector, "render", "--version", id, "--out", without.path, "--long-edge", "160")
            #expect(try Data(contentsOf: out) != Data(contentsOf: without))
        }
    }

    @Test("A failed or unavailable detection is still added, with no result, and says why (R6)")
    func failedDetections() async throws {
        try await CommandTests.withLibrary { library in
            let id = String(library.versionIDs[1])
            for (failure, state) in [(MaskDetectionError.unavailable("unsupported device"), "unavailable"),
                                     (MaskDetectionError.failed("boom"), "failed")] {
                let added = await Self.run(library, Fixed(answer: .failure(failure)), "mask", "add", "--version", id,
                                           "--shape", "subject")
                #expect(added.json["written"] == true)
                #expect(added.json["detection"]?["state"] == .string(state))
                #expect(added.json["detection"]?["reason"] == .string(failure.detail))
                #expect(added.json["masks"]?.arrayValue?.last?["components"]?.arrayValue?.first?["state"] == "failed")
            }
        }
    }

    @Test("Detections take no --params; a missing original is an error and writes nothing")
    func refusals() async throws {
        try await CommandTests.withLibrary { library in
            let id = String(library.versionIDs[2])
            let detector = Fixed(answer: .success(Self.found))
            let params = await Self.run(library, detector, "mask", "add", "--version", id, "--shape", "subject",
                                        "--params", #"{"raster": "\#(Self.found.digest)"}"#)
            #expect(params.json["code"] == "invalidValue")
            try FileManager.default.removeItem(at: library.photos.appending(path: "IMG_0003.jpg"))
            let missing = await Self.run(library, detector, "mask", "add", "--version", id, "--shape", "subject")
            #expect(missing.json["code"] == "fileNotFound")
            let listed = await Self.run(library, detector, "mask", "list", "--version", id)
            #expect(listed.json["masks"]?.arrayValue?.isEmpty == true)
        }
    }

    @Test("mask list says a result whose row is gone is missing (AC13)")
    func missingRow() async throws {
        try await CommandTests.withLibrary { library in
            let id = String(library.versionIDs[0])
            let detector = Fixed(answer: .success(Self.found))
            _ = await Self.run(library, detector, "mask", "add", "--version", id, "--shape", "people")
            let catalog = try Catalog.open(at: library.locations.catalogFileURL)
            try await catalog.deleteMaskRasterForChecks(digest: Self.found.digest)
            let listed = await Self.run(library, detector, "mask", "list", "--version", id)
            #expect(listed.json["masks"]?.arrayValue?.first?["components"]?.arrayValue?.first?["state"] == "missing")
        }
    }
}
