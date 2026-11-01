import CoreImage
import Foundation
import PhotoFixtures
import Testing
@testable import PhotoCore

/// Checks of the golden-image harness itself: scenes, encoding and comparison.
@Suite("Golden harness")
struct GoldenHarnessTests {
    @Test("Scenes are deterministic and the default size")
    func scenesAreDeterministic() {
        for scene in TestScene.allCases {
            let first = scene.image()
            #expect(first.width == 256 && first.height == 192, "\(scene)")
            #expect(first == scene.image(), "\(scene) differs between two calls")
            #expect(first.pixels.allSatisfy { $0.isFinite }, "\(scene)")
        }
    }

    @Test("A written golden reads back unchanged")
    func pngRoundTripIsExact() async throws {
        try await RepositoryFiles.withTemporaryDirectory { folder in
            for scene in TestScene.allCases {
                let encoded = try EncodedImage(rendering: scene.image().ciImage, engine: Goldens.engine)
                let url = folder.appending(path: "\(scene.rawValue).png")
                try encoded.writePNG(to: url)
                let read = try #require(EncodedImage(contentsOf: url))
                #expect(read == encoded, "\(scene)")
            }
        }
    }

    @Test("Every golden case renders the same bytes twice")
    func rendersAreRepeatable() throws {
        let engine = RenderEngine(contextCount: 1, name: "repeat")
        for golden in GoldenTests.cases {
            let image = golden.render()
            #expect(try EncodedImage(rendering: image, engine: engine) == EncodedImage(rendering: image, engine: engine),
                    "\(golden.name)")
        }
        for golden in GoldenTests.rawCases {
            let image = try golden.render()
            #expect(try EncodedImage(rendering: image, engine: engine) == EncodedImage(rendering: image, engine: engine),
                    "\(golden.name)")
        }
    }

    /// A module that silently did nothing would pin its scene under another name.
    @Test("Every golden case changes its scene")
    func casesChangeTheirScene() throws {
        for golden in GoldenTests.cases {
            let scene = try EncodedImage(rendering: golden.scene.image().ciImage, engine: Goldens.engine)
            let rendered = try EncodedImage(rendering: golden.render(), engine: Goldens.engine)
            if golden.adjustments.presence.clarity < 0 {
                // CIUnsharpMask clamps its intensity at 0 (attribute minimum 0),
                // so `AdjustmentRenderer.clarity` does nothing for negative amounts.
                withKnownIssue("Negative clarity renders nothing: CIUnsharpMask clamps intensity at 0") {
                    #expect(rendered != scene, "\(golden.name)")
                }
                continue
            }
            #expect(rendered != scene, "\(golden.name)")
        }
    }

    @Test("Core Image's software renderer is reported missing on Apple silicon")
    func softwareRendererAvailability() {
        // Without OpenCL the option is ignored and the context is a Metal one.
        #if arch(arm64)
        #expect(!RenderEngine.softwareRendererIsAvailable)
        #endif
    }

    @Test("Identity renders the scene; the difference finds a one-step change")
    func comparisonMeasuresDifferences() throws {
        let scene = try EncodedImage(rendering: TestScene.patchChart.image().ciImage, engine: Goldens.engine)
        let same = ImageDifference(expected: scene, actual: scene)
        #expect(same.psnr == .infinity && same.maxDeltaE == 0 && same.maxChannel == .zero)

        var changed = scene
        changed.samples[(10 * scene.width + 20) * 4 + 1] &+= 257
        let difference = ImageDifference(expected: scene, actual: changed)
        #expect(abs(difference.maxChannel.y - 1.0 / 255) < 1e-9)
        #expect(difference.maxChannel.x == 0 && difference.maxChannel.z == 0)
        #expect(difference.maxDeltaE > 0 && difference.maxDeltaE < 0.01)
        // One 8-bit step is more than the goldens allow.
        #expect(!GoldenTests.tolerance.accepts(difference))
    }

    @Test("The failure image puts expected, actual and the difference side by side")
    func sideBySideLayout() {
        let a = EncodedImage(width: 2, height: 1, samples: [0, 0, 0, 0, 65535, 65535, 65535, 0])
        let b = EncodedImage(width: 2, height: 1, samples: [8191, 0, 0, 0, 65535, 65535, 65535, 0])
        let joined = EncodedImage.sideBySide(expected: a, actual: b)
        #expect(joined.width == 6 && joined.height == 1)
        #expect(joined.samples[0] == 0 && joined.samples[8] == 8191)
        // 8191 / 65535 × 8 ≈ 1.0: the first difference pixel is (almost) full red.
        #expect(joined.samples[16] > 65000 && joined.samples[20] == 0)
    }
}
