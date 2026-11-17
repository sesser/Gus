import CoreImage
import Foundation
import PhotoFixtures
import Testing
@testable import PhotoCore

/// Issue #196's quality criteria on real raws, which are never committed:
///
///     XTRANS_SAMPLES=a.RAF:b.RAF (or a folder) swift test --filter DemosaicXTransSampleTests
///     BAYER_SAMPLES=a.RW2:b.CR2 swift test --filter DemosaicTruthTests
///
/// Each is skipped, saying why, when its variable is not set. The measures
/// are the #194 spike's (`Measure`, in PhotoFixtures, shared with
/// `photobench demosaic`), on the middle 2048 x 2048 of each frame.
enum DemosaicSamples {
    static func files(_ variable: String) -> [URL] {
        guard let value = ProcessInfo.processInfo.environment[variable], !value.isEmpty else { return [] }
        var isFolder: ObjCBool = false
        if !value.contains(":"), FileManager.default.fileExists(atPath: value, isDirectory: &isFolder), isFolder.boolValue {
            let folder = URL(fileURLWithPath: value)
            return ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
                .filter { ["raf", "rw2", "cr2", "orf", "dng", "nef", "arw"].contains($0.pathExtension.lowercased()) }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        }
        return value.split(separator: ":").map { URL(fileURLWithPath: String($0)) }
    }

    /// A decode's image before its color step, as floats.
    static func linear(_ url: URL, _ choice: LibRawDecoder.DemosaicChoice,
                       noiseReduction: GPUDemosaic.ColorNoiseReduction? = .baseline) throws -> (RGBPicture, LibRawDecoder.Output) {
        let output = try GPUDemosaic.$decodeNoiseReduction.withValue(noiseReduction) {
            try LibRawDecoder.decode(url, lensCorrections: false, demosaic: choice)
        }
        return (Measure.render(output.linear), output)
    }
}

@Suite(.enabled(if: !DemosaicSamples.files("XTRANS_SAMPLES").isEmpty,
                "Set XTRANS_SAMPLES to X-Trans raws (a list or a folder) to check AC3, AC4, AC6, AC9 and AC12 on them"),
       .serialized)
struct DemosaicXTransSampleTests {
    struct Row {
        var falseColor: Double, detail: Double, libRawFalseColor: Double, libRawDetail: Double
        var blockMedian: Double, blockP95: Double, edgeMedian: Double
        var falseColorRatio: Double { falseColor / libRawFalseColor }
        var detailRatio: Double { detail / libRawDetail }
    }

    static func measure(_ url: URL, ours: RGBPicture, libRaw: RGBPicture, step: Measure.ColorStep, size: Int = 2048) -> Row {
        let a = ours.middle(size), b = libRaw.middle(size)
        let w = b.width, h = b.height
        let oursLab: [SIMD3<Float>] = a.pixels.map { (c: SIMD3<Float>) -> SIMD3<Float> in Measure.lab(step.apply(c)) }
        let libLab: [SIMD3<Float>] = b.pixels.map { (c: SIMD3<Float>) -> SIMD3<Float> in Measure.lab(step.apply(c)) }
        let libEdges = Measure.edgeMask(libLab, width: w, height: h), ourEdges = Measure.edgeMask(oursLab, width: w, height: h)
        let fcOurs = Measure.falseColor(oursLab, edges: ourEdges, width: w, height: h)
        let fcLib = Measure.falseColor(libLab, edges: libEdges, width: w, height: h)
        let blocks = Measure.Summary(Measure.deltaE(Measure.blockLab(a.map(step.apply)), Measure.blockLab(b.map(step.apply))))
        let pixels = Measure.compare(oursLab, libLab, edges: libEdges, width: w, height: h)
        return Row(falseColor: fcOurs.chroma, detail: fcOurs.detail, libRawFalseColor: fcLib.chroma, libRawDetail: fcLib.detail,
                   blockMedian: blocks.median, blockP95: blocks.p95, edgeMedian: pixels.edges.median)
    }

    /// As the PRD stands after the owner's rulings of 2026-11-16 (rev 2):
    /// AC3 (the kernel alone) is accepted as measured, so it is printed, not
    /// expected. AC4 applies to files at ISO 800 or lower only; high ISO is
    /// judged by AC5 and AC6. AC6 was accepted as a whole: false color at
    /// most LibRaw's is expected on every file, the detail ratio is recorded
    /// (the owner accepted five of 28 files at 0.92x to 0.94x), and the files
    /// under 0.95x are listed at the end. Rev 2 also records three files at
    /// ISO 400 or lower just outside AC4 (an X-E3 at ISO 200 with block p95
    /// 2.08, two X100S files with dense fine detail), accepted with the issue
    /// as a whole: for those three AC4 is recorded and listed, as AC6's detail
    /// is (code review Q3); for every other file at ISO 800 or lower it is
    /// expected.
    /// The three files of the owner's samples PRD rev 2 accepts just outside
    /// AC4, by file name (the sample copies may carry a prefix).
    static let acceptedOutsideAC4 = ["DSCF4179.RAF", "X1009619.RAF", "X1009802.RAF"]

    @Test("Real X-Trans raws against LibRaw's own demosaic: false color, detail, ΔE (AC3, AC4, AC6)")
    func quality() throws {
        var underDetail: [String] = [], acceptedAC4: [String] = []
        for url in DemosaicSamples.files("XTRANS_SAMPLES") {
            let (libRaw, lib) = try DemosaicSamples.linear(url, .libRaw)
            let (kernel, kernelOutput) = try DemosaicSamples.linear(url, .automatic, noiseReduction: nil)
            let (ours, _) = try DemosaicSamples.linear(url, .automatic)
            guard case .gpu(.xTrans) = kernelOutput.demosaic else {
                print("XTRANS_SAMPLES: \(url.lastPathComponent): not demosaiced by the X-Trans kernel (\(kernelOutput.demosaic))")
                continue
            }
            let step = try #require(Measure.ColorStep(lib.step), "\(url.lastPathComponent): no usable color")
            let alone = Self.measure(url, ours: kernel, libRaw: libRaw, step: step)
            let reduced = Self.measure(url, ours: ours, libRaw: libRaw, step: step)
            let decoder = SystemRAWDecoder.reads(url) ? "system decoder reads it" : "LibRaw only"
            print(String(format: "XTRANS_SAMPLES: %@ (%@ %@, ISO %.0f, %@): LibRaw false color %.2f, detail %.2f; "
                         + "kernel alone (AC3, measured) %.2fx at detail %.2fx; with noise reduction %.2fx at %.2fx; "
                         + "blocks ΔE %.2f / %.2f, edge ΔE median %.2f",
                         url.lastPathComponent, lib.cameraMake, lib.cameraModel, lib.iso, decoder, alone.libRawFalseColor,
                         alone.libRawDetail, alone.falseColorRatio, alone.detailRatio, reduced.falseColorRatio,
                         reduced.detailRatio, reduced.blockMedian, reduced.blockP95, reduced.edgeMedian))
            // AC6: with the noise reduction, false color at most LibRaw's; detail recorded.
            #expect(reduced.falseColorRatio <= 1.0, "\(url.lastPathComponent): AC6 false color")
            if reduced.detailRatio < 0.95 {
                underDetail.append(String(format: "%@ %.2fx", url.lastPathComponent, reduced.detailRatio))
            }
            // AC4: at ISO 800 or lower, at block scale and at edges the two agree.
            if lib.iso > 0, lib.iso <= 800 {
                if Self.acceptedOutsideAC4.contains(where: { url.lastPathComponent.hasSuffix($0) }) {
                    acceptedAC4.append(String(format: "%@ blocks %.2f / %.2f, edges %.2f", url.lastPathComponent,
                                              reduced.blockMedian, reduced.blockP95, reduced.edgeMedian))
                } else {
                    #expect(reduced.blockMedian <= 1.0 && reduced.blockP95 <= 2.0, "\(url.lastPathComponent): AC4 blocks")
                    #expect(reduced.edgeMedian <= 5, "\(url.lastPathComponent): AC4 edges")
                }
            }
        }
        print("XTRANS_SAMPLES: AC6 detail under 0.95x with the noise reduction (recorded, accepted in rev 2): "
              + (underDetail.isEmpty ? "none" : underDetail.joined(separator: ", ")))
        print("XTRANS_SAMPLES: AC4 recorded, not expected, for the files rev 2 accepts just outside it: "
              + (acceptedAC4.isEmpty ? "none among these samples" : acceptedAC4.joined(separator: "; ")))
    }

    @Test("An X-E3's frame is the camera's and its lens corrections apply; a GPU failure gives LibRaw's pixels (AC9, AC12)")
    func frameAndFallback() throws {
        for url in DemosaicSamples.files("XTRANS_SAMPLES") {
            let output = try LibRawDecoder.decode(url)
            guard output.cameraModel == "X-E3" else { continue }
            #expect(output.demosaic == .gpu(.xTrans))
            #expect(output.size == CGSize(width: 6000, height: 4000))
            #expect(output.hasLensCorrections)
            let failed = try GPUDemosaic.$injectedFault.withValue(.execution) { try LibRawDecoder.decode(url, longEdge: 1500) }
            let libRaw = try LibRawDecoder.decode(url, longEdge: 1500, demosaic: .libRaw)
            #expect(failed.demosaic == .libRaw(reason: GPUDemosaic.Failure.injected.description))
            #expect(failed.pixels.data == libRaw.pixels.data)
            #expect(try LibRawDecoder.decode(url, longEdge: 1500).demosaic == .gpu(.xTrans))
        }
    }
}

/// AC2 and AC3's synthetic half: a Bayer raw binned 2 x 2 (each color from
/// its own sites, nothing interpolated) is a full-color picture of real
/// detail; sampled through RGGB and X-Trans into DNGs, it is demosaiced by
/// ours and by LibRaw's own (AHD, three-pass X-Trans), each compared with
/// the truth.
@Suite(.enabled(if: !DemosaicSamples.files("BAYER_SAMPLES").isEmpty,
                "Set BAYER_SAMPLES to Bayer raws (a list or a folder) to check AC2 and AC3 against a known truth"),
       .serialized)
struct DemosaicTruthTests {
    /// The owner accepted AC2's edge chroma bound on the E-M5 III's truth as
    /// measured (2026-11-16, PRD Q2: 2.04 against AHD's 1.97, 1.04x; its
    /// CPSNR passes): for it the edge chroma error is recorded and listed, as
    /// AC4's and AC6's accepted files are. Matched by file-name suffix.
    static let acceptedEdgeChroma = ["EM5MarkIII.ORF"]

    @Test("Against a known truth, the Bayer kernel is within 0.1 dB of AHD's CPSNR and at most its edge chroma error (AC2); X-Trans recorded (AC3)")
    func truth() async throws {
        var accepted: [String] = []
        for url in DemosaicSamples.files("BAYER_SAMPLES") {
            let mosaic = try LibRawDecoder.sensorMosaic(url)
            guard mosaic.pattern.kind == .bayer else { continue }
            let binned = try GPUDemosaic.shared().run(mosaic, halfSize: true, precision: .float, noiseReduction: nil)
            let w = binned.width / 6 * 6, h = binned.height / 6 * 6
            let whole = RGBPicture(rgba: binned.floats(), width: binned.width, height: binned.height)
            let truth = whole.cropped(x: 0, y: 0, width: w, height: h)
                .map(Measure.quantized16)
            let truthLab = truth.pixels.map(Measure.labSRGB)
            let edges = Measure.edgeMask(truthLab, width: w, height: h)
            try await RepositoryFiles.withTemporaryDirectory { folder in
                for pattern in [CFAPattern.rggb, .xTransSample] {
                    var values = Data(count: w * h * 2)
                    values.withUnsafeMutableBytes { raw in
                        let out = raw.bindMemory(to: UInt16.self)
                        for y in 0..<h { for x in 0..<w { out[y * w + x] = UInt16(truth[x, y][pattern.color(x: x, y: y)] * 65535).littleEndian } }
                    }
                    let dng = folder.appending(path: "\(url.deletingPathExtension().lastPathComponent)-\(pattern.kind).dng")
                    var options = SyntheticDNG.Options(width: w, height: h, seed: 1)
                    options.cfaPeriod = pattern.period
                    options.cfaColors = pattern.colors.map(UInt8.init)
                    try SyntheticDNG.write(to: dng, options: options, mosaic: values)
                    // The demosaic alone: the truth has no noise model to reduce.
                    var scores: [(cpsnr: Double, chroma: Double)] = []
                    for choice in [LibRawDecoder.DemosaicChoice.automatic, .libRaw] {
                        let (picture, _) = try DemosaicSamples.linear(dng, choice, noiseReduction: nil)
                        let labs = picture.pixels.map(Measure.labSRGB)
                        let comparison = Measure.compare(labs, truthLab, edges: edges, width: w, height: h)
                        scores.append((Measure.cpsnr(picture, truth), comparison.edgeChroma.p95))
                    }
                    print(String(format: "BAYER_SAMPLES: %@ through %@: CPSNR ours %.2f dB, LibRaw %.2f dB; edge chroma error p95 ours %.2f, LibRaw %.2f",
                                 url.lastPathComponent, "\(pattern.kind)", scores[0].cpsnr, scores[1].cpsnr, scores[0].chroma, scores[1].chroma))
                    // AC2 for Bayer. AC3's X-Trans half was accepted as measured (PRD rev 2): printed only.
                    if pattern.kind == .bayer {
                        #expect(scores[0].cpsnr >= scores[1].cpsnr - 0.1, "\(url.lastPathComponent): AC2 CPSNR")
                        if Self.acceptedEdgeChroma.contains(where: { url.lastPathComponent.hasSuffix($0) }) {
                            accepted.append(String(format: "%@ %.2f against %.2f (%.2fx)", url.lastPathComponent,
                                                   scores[0].chroma, scores[1].chroma, scores[0].chroma / scores[1].chroma))
                        } else {
                            #expect(scores[0].chroma <= scores[1].chroma, "\(url.lastPathComponent): AC2 edge chroma error")
                        }
                    }
                }
            }
        }
        print("BAYER_SAMPLES: AC2 edge chroma error recorded, not expected, for the file the owner accepted: "
              + (accepted.isEmpty ? "none among these samples" : accepted.joined(separator: "; ")))
    }
}
