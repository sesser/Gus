import CoreGraphics
import CoreVideo
import Foundation
import PhotoFixtures
import Testing
import Vision
@testable import PhotoCore

/// Issue #88, R4, R6, R10, R13: running detections.
@Suite("Detection masks: detection")
struct MaskDetectionTests {
    // MARK: Fixtures

    /// A synthetic scene, sRGB, upright: a plain field (`disc` false) or a
    /// red disc on blue, which Vision's foreground request takes as a subject.
    static func fixture(width: Int, height: Int, disc: Bool, grey: Double = 0.5) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        if disc {
            context.setFillColor(red: 0.2, green: 0.45, blue: 0.75, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.setFillColor(red: 0.9, green: 0.2, blue: 0.1, alpha: 1)
            let d = Double(min(width, height)) * 0.45
            context.fillEllipse(in: CGRect(x: Double(width) / 2 - d / 2, y: Double(height) / 2 - d / 2, width: d, height: d))
        } else {
            context.setFillColor(red: grey, green: grey, blue: grey, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        return context.makeImage()!
    }

    // MARK: R13, AC11

    /// Both requests run without error on synthetic fixtures and give masks of
    /// the sizes the spike measured (status.md §2): Subject 512 × 512 for any
    /// shape of photo, People 512 × 384 for a landscape photo and 384 × 512 for
    /// a portrait one. Availability and sizes only: what a synthetic image
    /// selects says nothing about quality. Part of `swift test`, so CI runs it
    /// on macOS 15 and 26.
    @Test("Both Vision requests run on synthetic fixtures and give masks of the measured sizes (R13, AC11)")
    func requestsRunWithTheMeasuredSizes() throws {
        let detector = VisionMaskDetector()
        var subjects = 0, people = 0
        for (width, height) in [(768, 512), (512, 768)] {
            let landscape = width > height
            for disc in [true, false] {
                let image = Self.fixture(width: width, height: height, disc: disc)
                let subject: MaskRaster
                let person: MaskRaster
                do {
                    subject = try detector.detect(.foreground, in: image)
                    person = try detector.detect(.person, in: image)
                } catch {
                    Issue.record("detection failed on \(width) × \(height) (disc \(disc)): \(error) on \(Self.system)")
                    continue
                }
                if subject.instances > 0 {
                    subjects += 1
                    #expect(subject.width == 512 && subject.height == 512, "Subject \(subject.width) × \(subject.height)")
                }
                if person.instances > 0 {
                    people += 1
                    #expect((person.width, person.height) == (landscape ? (512, 384) : (384, 512)),
                            "People \(person.width) × \(person.height) for \(width) × \(height)")
                }
                for raster in [subject, person] where raster.instances == 0 {
                    #expect(raster == MaskRaster.empty(raster.request, revision: raster.revision))
                }
                // Neither request downloads anything: each reports a revision it already has.
                #expect(subject.revision >= 1 && person.revision >= 1)
            }
        }
        // The size checks are not vacuous: each request found something somewhere.
        #expect(subjects >= 2, "Subject found the disc in \(subjects) of 2 fixtures on \(Self.system)")
        #expect(people >= 1, "People found something in \(people) of 4 fixtures on \(Self.system)")
    }

    static let system = ProcessInfo.processInfo.operatingSystemVersionString

    // MARK: The input (R4, AC3)

    static func writeJPEG(width: Int, height: Int, orientation: Int = 1) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "detection-input-\(UUID().uuidString).jpg", directoryHint: .notDirectory)
        try SyntheticImages.write(Self.fixture(width: width, height: height, disc: true), to: url, type: .jpeg,
                                  exif: SyntheticImages.Exif(orientation: orientation), quality: 0.95)
        return url
    }

    static func pixels(_ image: CGImage) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(data: &bytes, width: image.width, height: image.height, bitsPerComponent: 8,
                                bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return bytes
    }

    @Test("The input is the oriented mask frame at 2560 pixels, whatever edits the photo has; Distortion alone changes it (AC3)")
    func inputIgnoresEdits() throws {
        let url = try Self.writeJPEG(width: 3000, height: 2000, orientation: 6)
        defer { try? FileManager.default.removeItem(at: url) }
        let engine = RenderEngine(contextCount: 1, name: "detection-test")
        let plain = try MaskDetectionRun.input(source: url, adjustments: Adjustments(), engine: engine)
        // Oriented (a quarter turn in the file's tag), at the preview tier's long edge.
        #expect(plain.width == 1707 && plain.height == 2560, "\(plain.width) × \(plain.height)")

        var edited = Adjustments()
        edited.exposure.ev = 1.5
        edited.tone.contrast = 60
        edited.whiteBalance.relativeTemperature = 40
        edited.blackAndWhite.isOn = true
        edited.crop = Crop(rect: CropRect(x: 0.2, y: 0.2, width: 0.5, height: 0.5), quarterTurns: 1, angle: 7)
        edited.local.masks = [Mask(components: [MaskComponent(.radial(RadialGradient(center: MaskPoint(x: 0.5, y: 0.5),
                                                                                       radiusX: 0.2, radiusY: 0.2)))],
                                   adjustments: { var v = LocalValues(); v.exposure = 2; return v }())]
        edited.spots.spots = [Spot(center: MaskPoint(x: 0.5, y: 0.5), size: 0.05, source: MaskPoint(x: 0.2, y: 0.2))]
        let withEdits = try MaskDetectionRun.input(source: url, adjustments: edited, engine: engine)
        #expect(Self.pixels(withEdits) == Self.pixels(plain))

        var distorted = Adjustments()
        distorted.distortion = LensDistortion(isOn: true, source: .manual, amount: 60)
        let corrected = try MaskDetectionRun.input(source: url, adjustments: distorted, engine: engine)
        #expect(corrected.width == plain.width && corrected.height == plain.height)
        #expect(Self.pixels(corrected) != Self.pixels(plain), "the distortion that defines the mask frame applies")
    }

    @Test("A file that can't be rendered is unreadable, not a crash")
    func unreadableInput() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "not-a-photo-\(UUID().uuidString).jpg")
        try Data("nothing".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: MaskDetectionError.unreadable) {
            try MaskDetectionRun.input(source: url, adjustments: Adjustments(), engine: RenderEngine(contextCount: 1, name: "t"))
        }
    }

    // MARK: Running

    struct Stub: MaskDetecting {
        var result: Result<MaskRaster, MaskDetectionError>
        func detect(_ request: MaskRaster.Request, in image: CGImage) throws(MaskDetectionError) -> MaskRaster {
            try result.get()
        }
    }

    @Test("A run renders the input and hands it to the detector; a cancelled run stops before rendering")
    func runAndCancel() async throws {
        let url = try Self.writeJPEG(width: 600, height: 400)
        defer { try? FileManager.default.removeItem(at: url) }
        let engine = RenderEngine(contextCount: 1, name: "detection-test")
        let raster = try MaskRaster(levels: [1, 2, 3, 4], width: 2, height: 2, instances: 3, request: .person)
        let found = try await MaskDetectionRun.run(.people, source: url, adjustments: Adjustments(), engine: engine,
                                                   detector: Stub(result: .success(raster)))
        #expect(found == raster)
        await #expect(throws: MaskDetectionError.unavailable("x")) {
            try await MaskDetectionRun.run(.subject, source: url, adjustments: Adjustments(), engine: engine,
                                           detector: Stub(result: .failure(.unavailable("x"))))
        }
        let task = Task {
            try await MaskDetectionRun.run(.subject, source: url, adjustments: Adjustments(), engine: engine,
                                           detector: Stub(result: .success(raster)))
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test("Vision's can't-run-here errors are Unavailable; any other error is Failed")
    func classification() {
        func error(_ code: VNErrorCode) -> NSError { NSError(domain: VNErrorDomain, code: code.rawValue) }
        for code in [VNErrorCode.unsupportedComputeDevice, .unsupportedComputeStage, .unsupportedRevision,
                     .unsupportedRequest] {
            guard case .unavailable = VisionMaskDetector.classify(error(code)) else {
                Issue.record("\(code.rawValue) should be unavailable")
                continue
            }
        }
        for code in [VNErrorCode.internalError, .outOfMemory, .invalidImage] {
            guard case .failed = VisionMaskDetector.classify(error(code)) else {
                Issue.record("\(code.rawValue) should be failed")
                continue
            }
        }
        guard case .failed = VisionMaskDetector.classify(CocoaError(.fileReadUnknown)) else {
            Issue.record("another domain should be failed")
            return
        }
    }

    @Test("A float soft mask is quantized to 8 bits, rounded and clamped, top row first")
    func quantization() throws {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, 3, 2, kCVPixelFormatType_OneComponent32Float, nil, &buffer)
        let pixelBuffer = try #require(buffer)
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        let base = CVPixelBufferGetBaseAddress(pixelBuffer)!, rowBytes = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let values: [[Float]] = [[0, 0.5, 1], [-0.2, 1.3, .nan]]
        for (y, row) in values.enumerated() {
            for (x, value) in row.enumerated() {
                base.advanced(by: y * rowBytes).assumingMemoryBound(to: Float.self)[x] = value
            }
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        let levels = try #require(VisionMaskDetector.levels(of: pixelBuffer))
        #expect(levels.width == 3 && levels.height == 2)
        #expect(levels.levels == [0, 128, 255, 0, 255, 0])
    }

    @Test("A component's state follows its digest, its row and what this session learned")
    func states() {
        let digest = DetectionMaskModelTests.digestA
        let found = MaskDetection(kind: .subject, raster: digest), failed = MaskDetection(kind: .people)
        let entry = MaskRasterStore.Entry(pixels: .init(width: 1, height: 1, levels: [255]), instances: 2)
        let empty = MaskRasterStore.Entry(pixels: .init(width: 1, height: 1, levels: [0]), instances: 0)
        let states = [MaskDetectionState.of(found, lookup: .stored(entry), unavailable: false),
                      MaskDetectionState.of(found, lookup: .stored(empty), unavailable: true),
                      MaskDetectionState.of(found, lookup: .missing, unavailable: false),
                      MaskDetectionState.of(found, lookup: nil, unavailable: false),
                      MaskDetectionState.of(failed, lookup: nil, unavailable: false),
                      MaskDetectionState.of(failed, lookup: nil, unavailable: true)]
        #expect(states == [.found(instances: 2), .empty, .missing, .loading, .failed, .unavailable])
        let offering = [MaskDetectionState.failed, .unavailable, .missing, .found(instances: 1), .empty, .loading]
            .map { $0.offersUpdate }
        #expect(offering == [true, true, true, false, false, false])
    }

    // MARK: Real photos, opt in

    /// `AI_MASK_SAMPLES=a.JPG:b.ORF swift test --filter MaskDetectionTests`: the
    /// owner's photos, never committed. Direction only (R1's findings): each
    /// request runs or says it is unavailable, and what it finds has the
    /// measured size. Prints instances and coverage to compare by eye.
    @Test("Real photos, opt in: detections run and give results of the measured sizes",
          .enabled(if: ProcessInfo.processInfo.environment["AI_MASK_SAMPLES"] != nil))
    func samples() async throws {
        let files = (ProcessInfo.processInfo.environment["AI_MASK_SAMPLES"] ?? "").split(separator: ":")
            .map { URL(fileURLWithPath: (String($0) as NSString).expandingTildeInPath) }
        let engine = RenderEngine(contextCount: 1, name: "detection-samples")
        for file in files {
            let image = try MaskDetectionRun.input(source: file, adjustments: Adjustments(), engine: engine)
            for request in MaskRaster.Request.allCases {
                do {
                    let raster = try VisionMaskDetector().detect(request, in: image)
                    let pixels = try MaskRaster.pixels(fromPNG: raster.png)
                    let coverage = Double(pixels.levels.reduce(0) { $0 + Int($1) }) / 255 / Double(pixels.levels.count)
                    print("\(file.lastPathComponent) \(request.rawValue): \(raster.instances) instances, "
                          + "\(raster.width) × \(raster.height), coverage \(String(format: "%.1f%%", coverage * 100)), "
                          + "\(raster.png.count) bytes")
                    if raster.instances > 0 {
                        if request == .foreground {
                            #expect(raster.width == 512 && raster.height == 512)
                        } else {
                            #expect(Set([raster.width, raster.height]) == [512, 384])
                            #expect(raster.instances <= 4, "People stops at four (R15)")
                        }
                    }
                } catch MaskDetectionError.unavailable(let detail) {
                    print("\(file.lastPathComponent) \(request.rawValue): unavailable, \(detail)")
                }
            }
        }
    }
}
