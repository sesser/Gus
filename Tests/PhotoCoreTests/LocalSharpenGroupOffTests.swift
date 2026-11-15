import CoreImage
import Foundation
import PhotoFixtures
import Testing
@testable import PhotoCore

/// Issue #71, owner ruling 2026-11-15 (option B): local Sharpness belongs to
/// the Sharpening group. With the group turned off, a mask's Sharpness
/// sharpens nothing (it used to sharpen with the default Radius 1, Detail 25
/// and Masking 0); its stored amount is kept and applies again when the
/// group is turned back on.
@Suite("Local Sharpness with the Sharpening group off")
struct LocalSharpenGroupOffTests {
    static let gradient = LinearGradient(start: MaskPoint(x: 0.1, y: 0.1), end: MaskPoint(x: 0.6, y: 0.7))

    /// Sharpening set by hand, a mask with `sharpness` (and, with `exposure`,
    /// a second local value, so the mask renders without its Sharpness too).
    static func values(groupOn: Bool, sharpness: Double, exposure: Double? = nil) -> Adjustments {
        var values = Adjustments()
        values.sharpen = Sharpen(amount: 120, radius: 2, detail: 80, masking: 60)
        values.local.masks = [GoldenCase.mask([.linear(gradient)]) {
            $0.sharpen = sharpness
            if let exposure { $0.exposure = exposure }
        }]
        if !groupOn { values.setEnabled(.sharpening, false) }
        return values
    }

    static func render(_ values: Adjustments, _ input: LinearImage) -> [Float] {
        MaskRenderingTests.render(values, input).pixels
    }

    static func largestDifference(_ a: [Float], _ b: [Float]) -> Float {
        zip(a, b).map { abs($0 - $1) }.max() ?? 0
    }

    @Test("With the group off, a mask's Sharpness renders exactly as Sharpness 0")
    func offRendersWithoutLocalSharpness() {
        let input = TestScene.edgeTarget.image()
        for exposure in [nil, -0.3] as [Double?] {
            let off = Self.render(Self.values(groupOn: false, sharpness: 80, exposure: exposure), input)
            let none = Self.render(Self.values(groupOn: false, sharpness: 0, exposure: exposure), input)
            #expect(off == none, "exposure \(String(describing: exposure))")
        }
        // A mask whose only value is Sharpness changes nothing at all: the photo as it comes in.
        let onlySharpness = Self.render(Self.values(groupOn: false, sharpness: 80), input)
        #expect(Self.largestDifference(onlySharpness, input.pixels) == 0)
    }

    @Test("With the group on, the same mask's Sharpness sharpens (the check above is not vacuous)")
    func onSharpens() {
        let input = TestScene.edgeTarget.image()
        var on = Self.values(groupOn: true, sharpness: 80, exposure: -0.3)
        on.sharpen.amount = 0
        var flat = on
        flat.local.masks[0].adjustments.sharpen = 0
        #expect(Self.largestDifference(Self.render(on, input), Self.render(flat, input)) > 0.01)
    }

    @Test("Turning the group off keeps the stored Sharpness; turning it on applies it again")
    func storedValuesAreKept() throws {
        let off = Self.values(groupOn: false, sharpness: 80, exposure: -0.3)
        #expect(off.local.masks[0].adjustments.sharpen == 80)
        #expect(off.effective.local.masks[0].adjustments.sharpen == 0)
        // The stack keeps the amount, and reads back with it.
        let read = Adjustments(stack: try EditStack.decode(from: try off.editStack.jsonString()))
        #expect(read == off && read.local.masks[0].adjustments.sharpen == 80)
        var on = off
        on.setEnabled(.sharpening, true)
        #expect(on.effective.local.masks[0].adjustments.sharpen == 80)
        // Other groups turned off leave local Sharpness alone.
        var lightOff = Self.values(groupOn: true, sharpness: 80, exposure: -0.3)
        lightOff.exposure.ev = 0.5
        lightOff.setEnabled(.light, false)
        #expect(lightOff.effective.local.masks[0].adjustments.sharpen == 80)
    }

    /// A plain bump: previews cached under version 9 may hold the old local
    /// sharpening, and a key cannot say which stacks have it, so all of
    /// version 9's previews go at launch and are made again on demand.
    @Test("Previews cached before the fix are not used")
    func pipelineVersionBumped() async throws {
        #expect(PreviewCacheKey.currentPipelineVersion == 10)
        let edits = EditStack.identity.renderHash
        let hash = String(repeating: "ab", count: 32)
        let old = try #require(PreviewCacheKey(contentHash: hash, editStackHash: edits, tier: .preview, pipelineVersion: 9))
        let current = try #require(PreviewCacheKey(contentHash: hash, editStackHash: edits, tier: .preview))
        try await RepositoryFiles.withTemporaryDirectory { folder in
            let cache = PreviewDiskCache(root: folder)
            try cache.store(Data([1, 2, 3]), for: old)
            #expect(!cache.contains(current))
            cache.removeObsoletePipelineVersions()
            #expect(!cache.contains(old) && !FileManager.default.fileExists(atPath: folder.appending(path: "v9").path))
        }
    }

    @Test("Live frames follow the rule: the staged path renders Sharpness 0 with the group off")
    func liveFrames() async throws {
        try await RepositoryFiles.withTemporaryDirectory { folder in
            let url = folder.appending(path: "photo.jpg")
            try SyntheticImages.writeJPEG(to: url, width: 1200, height: 900, seed: 71)
            let generator = PreviewGenerator(engine: RenderEngine(contextCount: 1, name: "local-sharpen-test"))
            let session = LiveRenderSession(source: url, generator: generator, longEdge: 800, colorSpace: nil)
            let off = LiveSessionTests.bytes(try await session.render(Self.values(groupOn: false, sharpness: 80,
                                                                                  exposure: -0.3)))
            let none = LiveSessionTests.bytes(try await session.render(Self.values(groupOn: false, sharpness: 0,
                                                                                   exposure: -0.3)))
            #expect(!off.isEmpty && off == none)
            var on = Self.values(groupOn: true, sharpness: 80, exposure: -0.3)
            on.sharpen.amount = 0
            var flat = on
            flat.local.masks[0].adjustments.sharpen = 0
            let sharpened = LiveSessionTests.bytes(try await session.render(on))
            let unsharpened = LiveSessionTests.bytes(try await session.render(flat))
            #expect(sharpened != unsharpened)
        }
    }
}
