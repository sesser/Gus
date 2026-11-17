import CoreImage
import Foundation
import OSLog
import PhotoFixtures
import Testing
@testable import PhotoCore

/// How decodes use the GPU demosaic (issue #196): which files get it
/// (AC1), what a white balance change runs (AC10), the fallback to LibRaw's
/// own demosaic (AC12), cancellation (AC13) and the preview cache (AC14).
/// On synthetic DNGs, so they run in every `swift test`; the system decoder
/// gives no image for the small ones on macOS 27.2, and the tests that need
/// that say so.
@Suite("GPU demosaic in decodes")
struct GPUDemosaicDecodeTests {
    /// A synthetic DNG LibRaw decodes, sampled through `pattern`.
    /// LibRaw's own X-Trans demosaic fails with an input/output error on
    /// small frames (the #194 spike: 450 rows or fewer), so X-Trans files here are 516 x 516.
    static func dng(in folder: URL, _ name: String, pattern: CFAPattern = .rggb, width: Int? = nil, height: Int? = nil,
                    linearRaw: Bool = false) throws -> URL {
        let width = width ?? (pattern.kind == .xTrans ? 516 : 252), height = height ?? (pattern.kind == .xTrans ? 516 : 192)
        let url = folder.appending(path: "\(name).dng")
        var options = SyntheticDNG.Options(width: width, height: height, seed: 11, scene: .pattern, linearRaw: linearRaw)
        options.cfaPeriod = pattern.period
        options.cfaColors = pattern.colors.map(UInt8.init)
        try SyntheticDNG.write(to: url, options: options)
        return url
    }


    // MARK: AC1

    @Test("A raw whose pattern the kernels demosaic gets ours; one they don't keeps LibRaw's, pixel for pixel (AC1)",
          .enabled(if: hasMetalDevice, "No Metal device: the demosaic kernels need one"))
    func whichDemosaic() async throws {
        try await RepositoryFiles.withTemporaryDirectory { folder in
            let bayer = try Self.dng(in: folder, "bayer")
            let xTrans = try Self.dng(in: folder, "xtrans", pattern: .xTransSample)
            #expect(try LibRawDecoder.decode(bayer).demosaic == .gpu(.bayer))
            #expect(try LibRawDecoder.decode(xTrans).demosaic == .gpu(.xTrans))
            // A linear raw is no mosaic: LibRaw's own decode, the same as with the switch.
            let linear = try Self.dng(in: folder, "linear", linearRaw: true)
            let automatic = try LibRawDecoder.decode(linear)
            guard case .libRaw(let reason) = automatic.demosaic else {
                Issue.record("a linear raw went to the GPU: \(automatic.demosaic)")
                return
            }
            #expect(reason == SensorMosaic.Unsupported.notAThreeColorMosaic.description)
            let forced = try LibRawDecoder.decode(linear, demosaic: .libRaw)
            #expect(automatic.pixels.data == forced.pixels.data)
            // The switch keeps LibRaw's demosaic for a file ours would take.
            #expect(try LibRawDecoder.decode(bayer, demosaic: .libRaw).demosaic == .libRaw(reason: "chosen"))
            #expect(try LibRawDecoder.$demosaicOverride.withValue(.libRaw) { try LibRawDecoder.decode(xTrans) }.demosaic
                    == .libRaw(reason: "chosen"))
        }
    }

    @Test("Which decoder a raw gets is still SystemRAWDecoder.reads alone (AC1)")
    func systemDecoderStillDecides() async throws {
        try await RepositoryFiles.withTemporaryDirectory { folder in
            // The system decoder reads this larger DNG; the small one it gives no image for (macOS 27.2).
            let read = try LibRawDecoderTests.dng(in: folder, "system", width: 1536, height: 1152)
            let small = try Self.dng(in: folder, "small", pattern: .xTransSample, width: 252, height: 192)
            for url in [read, small] {
                print("AC1: \(url.lastPathComponent): the system decoder \(SystemRAWDecoder.reads(url) ? "reads it" : "gives no image")")
                let decoded = try PreviewGenerator.decode(url, longEdge: nil, draft: false)
                if SystemRAWDecoder.reads(url) {
                    #expect(decoded.decoder == .systemRAW)
                    #expect(decoded.demosaic == nil)
                } else {
                    #expect(decoded.decoder == .libRaw)
                    #expect(decoded.demosaic == (hasMetalDevice ? .gpu(.xTrans) : decoded.demosaic))
                }
            }
        }
    }

    /// R20 (code review C6): `photocli render` names the decoder and, for
    /// LibRaw's decodes, which demosaic ran; `--demosaic` takes automatic or
    /// libraw and refuses anything else.
    @Test("photocli render reports the decoder and the demosaic, and takes --demosaic (R20)",
          .enabled(if: hasMetalDevice, "No Metal device: the demosaic kernels need one"))
    func renderReportsTheDemosaic() async throws {
        try await CommandTests.withLibrary { library in
            let url = try Self.dng(in: library.photos, "render", pattern: .xTransSample, width: 252, height: 192)
            if SystemRAWDecoder.reads(url) {
                try Test.cancel("The system decoder reads the small X-Trans DNG on this macOS: no LibRaw decode to report")
            }
            let out = library.photos.appending(path: "render.png").path
            let ours = await library.run("render", url.path, "--out", out, "--long-edge", "100")
            #expect(ours.output.exitCode == 0)
            #expect(ours.json["decoder"] == "libRaw")
            #expect(ours.json["demosaic"]?["method"] == "gpu")
            #expect(ours.json["demosaic"]?["pattern"] == "xTrans")
            let libRaw = await library.run("render", url.path, "--out", out, "--long-edge", "100", "--demosaic", "libraw")
            #expect(libRaw.json["demosaic"]?["method"] == "libraw")
            #expect(libRaw.json["demosaic"]?["reason"] == "chosen")
            let automatic = await library.run("render", url.path, "--out", out, "--long-edge", "100", "--demosaic", "Automatic")
            #expect(automatic.json["demosaic"]?["method"] == "gpu")
            let refused = await library.run("render", url.path, "--out", out, "--demosaic", "ahd")
            #expect(refused.output.exitCode != 0)
            #expect(refused.json["code"] == "invalidValue")
            // A JPEG has no demosaic.
            let jpeg = await library.run("render", library.photos.appending(path: "IMG_0001.jpg").path, "--out", out)
            #expect(jpeg.json["decoder"] == "imageIO")
            #expect(jpeg.json["demosaic"] == nil)
        }
    }

    // MARK: AC10

    @Test("A white balance change runs no new unpack or demosaic, and renders as a fresh decode would (AC10)")
    func whiteBalanceRunsNoDemosaic() async throws {
        try await RepositoryFiles.withTemporaryDirectory { folder in
            // Small enough that the system decoder gives no image for it (macOS 27.2), as for the X-E3's files.
            let url = try Self.dng(in: folder, "balance", pattern: .xTransSample, width: 252, height: 192)
            if SystemRAWDecoder.reads(url) {
                try Test.cancel("The system decoder reads the small X-Trans DNG on this macOS: AC10 needs a raw only LibRaw decodes")
            }
            let generator = PreviewGenerator(engine: ReferenceTests.engine)
            let counter = GPUDemosaic.RunCounter()
            try await GPUDemosaic.$runCounter.withValue(counter) {
                for longEdge in [100, 400] {
                    // At fit (a half-size decode) and at full size.
                    let session = LiveRenderSession(source: url, generator: generator, longEdge: longEdge, colorSpace: nil,
                                                    systemDecodesRaw: false)
                    var values = Adjustments()
                    _ = try await session.render(values)
                    var runs = counter.value
                    #expect(runs >= (hasMetalDevice ? 1 : 0))
                    for balance in [WhiteBalance(preset: .custom, temperature: 3200, tint: 0),
                                    WhiteBalance(preset: .custom, temperature: 3200, tint: 30),
                                    WhiteBalance(preset: .daylight)] {
                        values.whiteBalance = balance
                        let kept = try await session.linearFrame(values)
                        #expect(counter.value == runs)
                        #expect(await session.decodeCount == 1)
                        // A fresh session decodes the file again for this balance: the same frame.
                        let fresh = LiveRenderSession(source: url, generator: generator, longEdge: longEdge, colorSpace: nil,
                                                      systemDecodesRaw: false)
                        let again = try await fresh.linearFrame(values)
                        #expect(kept.dataProvider?.data as Data? == again.dataProvider?.data as Data?, "\(balance) at \(longEdge)")
                        // The fresh session's own decode is not the kept one's.
                        runs = counter.value
                    }
                }
            }
        }
    }

    // MARK: AC12

    /// The decode's log lines from this process, with the reason.
    static func fallbackLogged(since date: Date, containing text: String) -> Bool {
        guard let store = try? OSLogStore(scope: .currentProcessIdentifier),
              let entries = try? store.getEntries(at: store.position(date: date),
                                                  matching: NSPredicate(format: "subsystem == %@ AND category == %@",
                                                                        AppBranding.bundleIdentifier, "decode"))
        else { return false }
        return entries.contains { $0.composedMessage.contains("demosaiced by LibRaw") && $0.composedMessage.contains(text) }
    }

    @Test("When the GPU fails, or there is no device, a decode is LibRaw's own, logged, and the next one is ours again (AC12)",
          .enabled(if: hasMetalDevice, "No Metal device: the demosaic kernels need one"), arguments: [GPUDemosaic.InjectedFault.execution, .noDevice])
    func fallbackOnFailure(fault: GPUDemosaic.InjectedFault) async throws {
        try await RepositoryFiles.withTemporaryDirectory { folder in
            for pattern in [CFAPattern.rggb, .xTransSample] {
                let url = try Self.dng(in: folder, "fault-\(pattern.kind)", pattern: pattern)
                let started = Date()
                let failed = try GPUDemosaic.$injectedFault.withValue(fault) { try LibRawDecoder.decode(url) }
                let expected = fault == .noDevice ? GPUDemosaic.Failure.noDevice : .injected
                #expect(failed.demosaic == .libRaw(reason: expected.description))
                // Pixel for pixel what LibRaw's own demosaic gives.
                let libRaw = try LibRawDecoder.decode(url, demosaic: .libRaw)
                #expect(failed.pixels.data == libRaw.pixels.data)
                #expect(LibRawDecoderTests.samples(failed) == LibRawDecoderTests.samples(libRaw))
                #expect(Self.fallbackLogged(since: started.addingTimeInterval(-1), containing: expected.description))
                // The next decode uses the GPU again.
                #expect(try LibRawDecoder.decode(url).demosaic == .gpu(pattern.kind))
            }
        }
    }

    /// Code review C1: the noise reduction's scratch textures failing after
    /// the demosaic is encoded must end the encoder (Metal aborts the process
    /// otherwise) and fall back to LibRaw's demosaic like any GPU failure.
    @Test("When the noise reduction's scratch can't be made, the decode is LibRaw's own and the process lives (R19)",
          .enabled(if: hasMetalDevice, "No Metal device: the demosaic kernels need one"))
    func scratchAllocationFallsBack() async throws {
        // A model given, so the noise reduction runs whatever the picture's own noise.
        let reduction = GPUDemosaic.ColorNoiseReduction(luminanceStrength: 2, colorStrength: 3,
                                                        model: NoiseModel(a: 1e-3, b: 1e-6))
        try await RepositoryFiles.withTemporaryDirectory { folder in
            for pattern in [CFAPattern.rggb, .xTransSample] {
                let url = try Self.dng(in: folder, "scratch-\(pattern.kind)", pattern: pattern)
                let failed = try GPUDemosaic.$decodeNoiseReduction.withValue(reduction) {
                    try GPUDemosaic.$injectedFault.withValue(.scratchAllocation) { try LibRawDecoder.decode(url) }
                }
                #expect(failed.demosaic == .libRaw(reason: GPUDemosaic.Failure.allocation("noise reduction scratch").description))
                let libRaw = try LibRawDecoder.decode(url, demosaic: .libRaw)
                #expect(failed.pixels.data == libRaw.pixels.data)
                // The engine still works: the next decode, with its noise reduction, is ours.
                let next = try GPUDemosaic.$decodeNoiseReduction.withValue(reduction) { try LibRawDecoder.decode(url) }
                #expect(next.demosaic == .gpu(pattern.kind))
            }
            // The noise reduction alone, the other encoder that can meet it.
            let truth = DemosaicScene.truth(width: 48, height: 48, noise: 0.02)
            let engine = try GPUDemosaic.shared()
            let image = try engine.run(DemosaicScene.mosaic(truth, width: 48, height: 48, pattern: .rggb), precision: .float,
                                       noiseReduction: nil)
            #expect(throws: GPUDemosaic.Failure.allocation("noise reduction scratch")) {
                try GPUDemosaic.$injectedFault.withValue(.scratchAllocation) {
                    _ = try engine.denoise(image, channels: (SIMD3(repeating: 1e-3), SIMD3(repeating: 1e-6)),
                                           reduction: reduction, precision: .float)
                }
            }
        }
    }

    // MARK: AC13

    @Test("A decode cancelled after its unpack throws CancellationError and runs no demosaic (AC13)")
    func cancellation() async throws {
        try await RepositoryFiles.withTemporaryDirectory { folder in
            let url = try Self.dng(in: folder, "cancel", pattern: .xTransSample)
            let counter = GPUDemosaic.RunCounter()
            /// Runs `body` in a task that is cancelled before it starts (the
            /// stream ends when its task is cancelled), so it runs cancelled.
            func cancelled<T: Sendable>(_ body: @escaping @Sendable () throws -> T) async -> Result<T, any Error> {
                let gate = AsyncStream<Void>.makeStream()
                let task = Task {
                    for await _ in gate.stream {}
                    return try GPUDemosaic.$runCounter.withValue(counter) { try body() }
                }
                task.cancel()
                return await task.result
            }
            let direct = await cancelled { try LibRawDecoder.decode(url).size }
            #expect(throws: CancellationError.self) { try direct.get() }
            #expect(counter.value == 0)
            // Through the preview pipeline it is a cancellation too, never "undecodable".
            if !SystemRAWDecoder.reads(url) {
                let pipeline = await cancelled { try PreviewGenerator.decode(url, longEdge: nil, draft: false).image.extent }
                #expect(throws: CancellationError.self) { try pipeline.get() }
                #expect(counter.value == 0)
            }
        }
    }

    /// Code review C2: an export stopped while a raw LibRaw decodes is
    /// rendering gets `CancellationError` from the decode; that photo is
    /// neither written nor failed, and the export reads as stopped.
    @Test("A raw stopped while it renders for an export is not a failure, and the export reads as stopped")
    func stoppedExportIsNotAFailure() async throws {
        try await RepositoryFiles.withTemporaryDirectory { folder in
            // The tally: a stopped photo is not done and adds no failure; the others count.
            var summary = ExportSummary(destination: folder)
            #expect(!ExportJob.tally(.cancelled, into: &summary))
            #expect(summary.failures.isEmpty && summary.written.isEmpty && summary.skippedExisting == 0)
            #expect(ExportJob.tally(.skipped, into: &summary))
            #expect(summary.skippedExisting == 1)
            guard case .failed(let failure) = ExportJob.outcome(of: CocoaError(.fileWriteNoPermission), name: "b.RAF") else {
                Issue.record("a write error is a failure")
                return
            }
            #expect(failure.fileName == "b.RAF")

            let url = try Self.dng(in: folder, "export", pattern: .xTransSample, width: 252, height: 192)
            if SystemRAWDecoder.reads(url) {
                try Test.cancel("The system decoder reads the small X-Trans DNG on this macOS, and it does not stop: nothing here is LibRaw's")
            }
            let output = folder.appending(path: "out.jpg")
            // The render, in a task stopped before it starts (its stream ends when the task is cancelled).
            let gate = AsyncStream<Void>.makeStream()
            let task = Task { () -> String in
                for await _ in gate.stream {}
                do {
                    _ = try ExportRenderer().export(source: url, stack: .identity, values: SidecarValues(),
                                                    settings: ExportSettings(), to: output, replacing: false)
                    return "written"
                } catch {
                    switch ExportJob.outcome(of: error, name: "export.dng") {
                    case .cancelled: return "cancelled"
                    case .failed(let failure): return "failed: \(failure.reason)"
                    default: return "other"
                    }
                }
            }
            task.cancel()
            #expect(await task.value == "cancelled")
            #expect(!FileManager.default.fileExists(atPath: output.path))
        }
    }

    // MARK: AC14

    @Test("The pipeline version is 12 and nothing cached under 11 is found (AC14)")
    func pipelineVersion() async throws {
        #expect(PreviewCacheKey.currentPipelineVersion == 12)
        try await RepositoryFiles.withTemporaryDirectory { folder in
            let cache = PreviewDiskCache(root: folder)
            let hash = String(repeating: "ab", count: 32), stack = String(repeating: "cd", count: 32)
            for tier in PreviewTier.allCases {
                let old = try #require(PreviewCacheKey(contentHash: hash, editStackHash: stack, tier: tier, pipelineVersion: 11))
                try cache.store(Data([1, 2, 3]), for: old)
                #expect(cache.contains(old))
                let current = try #require(PreviewCacheKey(contentHash: hash, editStackHash: stack, tier: tier))
                #expect(!cache.contains(current))
            }
        }
    }
}
