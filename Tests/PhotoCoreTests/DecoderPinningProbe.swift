import CoreImage
import Foundation
import Testing
@testable import PhotoCore

/// Temporary: renders the RAW golden cases with each decoder version this Mac
/// supports pinned (and with none), into `GOLDEN_FAILURES_DIR/pinned/macos-<major>/<version>/`,
/// to compare across the CI runners. Writes only; never fails.
@Suite("Decoder pinning probe (temporary)",
       .enabled(if: ProcessInfo.processInfo.environment["GOLDEN_FAILURES_DIR"] != nil))
struct DecoderPinningProbe {
    @Test("Render the RAW cases with each decoder version pinned")
    func renderPinned() throws {
        let raw = try #require(CIRAWFilter(imageURL: RAWGoldenCase.master))
        let versions = raw.supportedDecoderVersions.map(\.rawValue)
        print("pinning: \(GoldenTests.decoder), supported \(versions)")
        let folder = Goldens.failureDirectory.appending(
            path: "pinned/macos-\(ProcessInfo.processInfo.operatingSystemVersion.majorVersion)",
            directoryHint: .isDirectory)
        for version in [nil] + versions.map(Optional.some) {
            for golden in GoldenTests.rawCases {
                var adjustments = golden.adjustments
                adjustments.decode.decoderVersion = version
                let image = try PreviewGenerator(engine: Goldens.engine).image(
                    source: RAWGoldenCase.master, stack: adjustments.editStack, longEdge: nil)
                try EncodedImage(rendering: image, engine: Goldens.engine).writePNG(
                    to: folder.appending(path: "\(version ?? "default")/\(golden.name).png"))
            }
        }
    }
}
