import Foundation
import Testing
@testable import PhotoCore

/// A raw the system's RAW decoder gives no image for is decoded by LibRaw
/// (issue #161). `RAF_SAMPLE=path/to/DSCF5123.RAF swift test --filter LibRawFallbackTests`
/// with a Fujifilm X-E3 file on macOS 27.2.1; fails without the fallback.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["RAF_SAMPLE"] != nil,
                "Set RAF_SAMPLE to a raw the system decoder cannot read and run this suite alone"))
struct LibRawFallbackTests {
    private var url: URL { URL(fileURLWithPath: ProcessInfo.processInfo.environment["RAF_SAMPLE"] ?? "") }

    @Test func decodesAtFullAndSmallSizes() throws {
        let full = try PreviewGenerator.decode(url, longEdge: nil, draft: false)
        #expect(full.image.extent.width > 4000)
        #expect(!full.context.isRaw)
        #expect(full.context.scale == 1)
        let small = try PreviewGenerator.decode(url, longEdge: 800, draft: false)
        #expect(small.image.extent.width < full.image.extent.width)
        #expect(small.context.scale <= 0.5)
    }

    @Test func rendersThroughThePipeline() throws {
        let image = try PreviewGenerator().cgImage(source: url, stack: .identity, longEdge: 1000)
        #expect(max(image.width, image.height) == 1000)
    }
}
