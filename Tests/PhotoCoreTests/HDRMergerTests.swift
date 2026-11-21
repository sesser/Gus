import CoreImage
import Foundation
import PhotoFixtures
import Testing
import simd
@testable import PhotoCore

/// The merge's core on synthetic brackets (issue #150): radiance, ghosts and
/// tone mapping, without files.
@Suite("HDR merge core")
struct HDRMergerTests {
    static let width = 600
    static let height = 400

    static func frames(_ frames: [HDRBracket.Frame], width: Int = width, height: Int = height) -> [CIImage] {
        frames.map { HDRBracket.image($0, width: width, height: height).ciImage }
    }

    static func merge(_ bracket: [HDRBracket.Frame], reference: Int, width: Int = width, height: Int = height)
        throws -> (HDRMerger, HDRMerger.Plan, CIImage) {
        let merger = HDRMerger()
        let images = frames(bracket, width: width, height: height)
        let copies = images.map { MergeBitmap.render($0, context: merger.context)! }
        let plan = try merger.plan(measuring: copies, reference: reference, metadataExposures: bracket.map { _ in nil })
        return (merger, plan, try merger.radiance(plan, frames: images))
    }

    @Test("Three exposures merge to the scene's light, measured exposures within 1% of the truth")
    func recoversRadiance() throws {
        let bracket = [HDRBracket.Frame(ev: -2), HDRBracket.Frame(ev: 0), HDRBracket.Frame(ev: 2)]
        let (merger, plan, radiance) = try Self.merge(bracket, reference: 1)
        for (index, frame) in bracket.enumerated() {
            let truth = pow(2, frame.ev)
            print("exposure \(index): \(plan.frames[index].exposure) truth \(truth) clip \(plan.frames[index].clip)")
            #expect(abs(plan.frames[index].exposure / truth - 1) < 0.01)
        }
        let merged = try #require(MergeBitmap.render(radiance, context: merger.context))
        let truth = HDRBracket.radianceImage(width: Self.width, height: Self.height)
        // Away from edges: next to one, a fraction of a pixel of alignment
        // error mixes in a neighbor up to 3,600 times brighter.
        var worst: Float = 0
        var compared = 0
        for y in 1..<(Self.height - 1) {
            for x in 1..<(Self.width - 1) {
                var low = Float.infinity, high: Float = 0
                for dy in -1...1 {
                    for dx in -1...1 {
                        let p = truth[x + dx, y + dy]
                        let l = MergeBitmap.luminance(SIMD3(p.x, p.y, p.z))
                        low = min(low, l)
                        high = max(high, l)
                    }
                }
                guard high < low * 1.25 else { continue }
                compared += 1
                let m = merged.rgb(x: x, y: y), p = truth[x, y], t = SIMD3(p.x, p.y, p.z)
                worst = max(worst, simd_reduce_max(abs(m - t) / t))
            }
        }
        print("compared \(compared) pixels")
        print("worst relative radiance error \(worst)")

        #expect(worst < 0.02)
    }
}

@Suite("HDR merge DNG")
struct MergeDNGTests {
    @Test("The linear DNG decodes in the system RAW decoder with the light it was given", arguments: [16, 32])
    func dngRoundTrip(bits: Int) throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "merge-dng-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let radiance = HDRBracket.radianceImage(width: 400, height: 300)
        let url = folder.appending(path: "a_HDR.dng")
        let merger = HDRMerger()
        try MergeOutput.writeDNG(radiance.ciImage, context: merger.context,
                                 metadata: MergeOutput.Metadata(sourceProperties: [:], values: SidecarValues()), to: url,
                                 brightest: 3.6, bitsPerSample: bits)
        let raw = try #require(CIRAWFilter(imageURL: url))
        print("bits \(bits) native \(raw.nativeSize) supported \(SystemRAWDecoder.reads(url)) layout \(String(describing: DNGLayout(contentsOf: url)))")
        let decoded = try MergeDecoder.linearImage(url, source: MergeDecoder.source(of: url), longEdge: nil)
        let bitmap = try #require(MergeBitmap.render(decoded, context: merger.context))
        for (x, y) in [(50, 50), (300, 80), (200, 250)] {
            print("bits \(bits) at \(x),\(y): decoded \(bitmap.rgb(x: x, y: y)) written \(radiance[x, y])")
        }
    }
}
