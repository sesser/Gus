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

    /// Both requests run on synthetic fixtures and give masks of the sizes the
    /// spike measured (status.md §2): Subject 512 × 512 for any shape of
    /// photo, People 512 × 384 for a landscape photo and 384 × 512 for a
    /// portrait one. Availability and sizes only. Part of `swift test`, so CI
    /// runs it on macOS 15 and 26.
    ///
    /// As ruled in AC11 (#88, RI-E1, Q2):
    /// - Only Vision's "unsupported compute device" error (code 22, a virtual
    ///   machine with no Neural Engine whose GPU Vision won't use) passes, with
    ///   the error printed. Any other error fails, an unsupported revision
    ///   included (code review C9), and so does a wrong size.
    /// - Subject must return the red disc at its measured size wherever it
    ///   runs. Any People mask returned must have its measured size; the
    ///   fixtures hold no person, so an empty People result passes (code
    ///   review C5). The opt-in samples check People on real photos of people.
    @Test("Both Vision requests run on synthetic fixtures and give masks of the measured sizes (R13, AC11)")
    func requestsRunWithTheMeasuredSizes() async throws {
        let detector = VisionMaskDetector()
        var found: [MaskRaster.Request: Int] = [:]
        var unavailable: [MaskRaster.Request: String] = [:]
        for request in MaskRaster.Request.allCases {
            for (width, height) in [(768, 512), (512, 768)] {
                let landscape = width > height
                for disc in [true, false] {
                    let image = Self.fixture(width: width, height: height, disc: disc)
                    let raster: MaskRaster
                    do {
                        raster = try await detector.detect(request, in: image)
                    } catch .unavailable(let detail) where detail.hasPrefix(Self.unsupportedComputeDevice) {
                        unavailable[request] = detail
                        continue
                    } catch {
                        Issue.record("\(request.rawValue) failed on \(width) × \(height) (disc \(disc)): \(error) on \(Self.system)")
                        continue
                    }
                    #expect(raster.revision >= 1, "a revision the request already has: nothing was downloaded")
                    guard raster.instances > 0 else {
                        #expect(raster == MaskRaster.empty(request, revision: raster.revision))
                        continue
                    }
                    found[request, default: 0] += 1
                    switch request {
                    case .foreground:
                        #expect(raster.width == 512 && raster.height == 512, "Subject \(raster.width) × \(raster.height)")
                    case .person:
                        #expect((raster.width, raster.height) == (landscape ? (512, 384) : (384, 512)),
                                "People \(raster.width) × \(raster.height) for \(width) × \(height)")
                    }
                }
            }
        }
        for (request, detail) in unavailable.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            print("AC11: \(request.rawValue) can't run on this Mac (\(Self.system)): \(detail)")
        }
        if unavailable[.foreground] == nil {
            #expect(found[.foreground, default: 0] >= 2, "Subject found the disc in \(found[.foreground, default: 0]) of 2 fixtures")
        }
        if unavailable[.person] == nil, found[.person, default: 0] == 0 {
            print("AC11: People found nothing in the person-less fixtures on \(Self.system); its sizes were not seen here")
        }
    }

    static let system = ProcessInfo.processInfo.operatingSystemVersionString
    /// How `VisionMaskDetector.classify` begins the detail of Vision's code 22.
    static let unsupportedComputeDevice = "\(VNErrorDomain) \(VNErrorCode.unsupportedComputeDevice.rawValue):"

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
        func detect(_ request: MaskRaster.Request, in image: CGImage) async throws(MaskDetectionError) -> MaskRaster {
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

    /// Records the image each request was given.
    final class Recording: MaskDetecting, @unchecked Sendable {
        // @unchecked: the test reads `images` only after the run has finished.
        private(set) var images: [MaskRaster.Request: ObjectIdentifier] = [:]
        private let lock = NSLock()
        let failing: MaskRaster.Request?
        init(failing: MaskRaster.Request? = nil) { self.failing = failing }

        func detect(_ request: MaskRaster.Request, in image: CGImage) async throws(MaskDetectionError) -> MaskRaster {
            lock.withLock { images[request] = ObjectIdentifier(image) }
            if request == failing { throw .unavailable("not here") }
            return .empty(request)
        }
    }

    @Test("An Update of Subject and People renders the input once and keeps each request's own outcome (code review C3, C7)")
    func severalRequestsOneRender() async throws {
        let url = try Self.writeJPEG(width: 600, height: 400)
        defer { try? FileManager.default.removeItem(at: url) }
        let detector = Recording(failing: .person)
        let results = try await MaskDetectionRun.run([.foreground, .person], source: url, adjustments: Adjustments(),
                                                     engine: RenderEngine(contextCount: 1, name: "detection-test"),
                                                     detector: detector)
        #expect(Set(detector.images.values).count == 1, "one rendered input for both")
        #expect(try results[.foreground]?.get() == MaskRaster.empty(.foreground))
        #expect(results[.person].map { if case .failure(.unavailable) = $0 { true } else { false } } == true)

        let missing = FileManager.default.temporaryDirectory.appending(path: "absent-\(UUID().uuidString).jpg")
        let unreadable = try await MaskDetectionRun.run([.foreground, .person], source: missing, adjustments: Adjustments(),
                                                        engine: RenderEngine(contextCount: 1, name: "detection-test"),
                                                        detector: detector)
        #expect(unreadable.count == 2 && unreadable.values.allSatisfy {
            if case .failure(.unreadable) = $0 { true } else { false }
        })
    }

    @Test("An Update's result lands on the components it started on, found by kind and result (code review C1)")
    func updatePositions() {
        let a = DetectionMaskModelTests.digestA, b = DetectionMaskModelTests.digestB
        func detection(_ kind: MaskDetectionKind, _ raster: String?) -> MaskComponent {
            MaskComponent(.detection(MaskDetection(kind: kind, raster: raster)))
        }
        let linear = MaskComponent(.linear(LinearGradient(start: MaskPoint(x: 0, y: 0), end: MaskPoint(x: 1, y: 1))))
        // The review's case: [People, Subject], People removed, Update on [Subject] (index 0), then ⌘Z.
        let started = [MaskDetectionUpdate.Started(index: 0, kind: .subject, raster: a)]
        #expect(MaskDetectionUpdate.positions(of: started, in: [detection(.people, b), detection(.subject, a)]) == [1])
        // A shape in its old place: never the target.
        #expect(MaskDetectionUpdate.positions(of: started, in: [linear, detection(.subject, a)]) == [1])
        // Gone (undone, or its result changed meanwhile): nothing lands.
        #expect(MaskDetectionUpdate.positions(of: started, in: [linear]) == [nil])
        #expect(MaskDetectionUpdate.positions(of: started, in: [detection(.subject, b)]) == [nil])
        // Twins that differ in operation stay apart; a removed one gets nothing (C10).
        let add = MaskComponent(.detection(MaskDetection(kind: .subject, raster: nil)))
        let subtract = MaskComponent(.detection(MaskDetection(kind: .subject, raster: nil)), operation: .subtract)
        let second = [MaskDetectionUpdate.Started(index: 1, kind: .subject, raster: nil, operation: .subtract)]
        #expect(MaskDetectionUpdate.positions(of: second, in: [add, subtract]) == [1])
        #expect(MaskDetectionUpdate.positions(of: second, in: [add]) == [nil])
        let inverted = [MaskDetectionUpdate.Started(index: 0, kind: .subject, raster: nil, invert: true)]
        #expect(MaskDetectionUpdate.positions(of: inverted, in: [add]) == [nil])
        // Two alike each find their own place.
        let twins = [MaskDetectionUpdate.Started(index: 0, kind: .subject, raster: a),
                     MaskDetectionUpdate.Started(index: 1, kind: .subject, raster: a)]
        #expect(MaskDetectionUpdate.positions(of: twins, in: [linear, detection(.subject, a), detection(.subject, a)])
                == [1, 2])
        // Unchanged: in place.
        #expect(MaskDetectionUpdate.positions(of: twins, in: [detection(.subject, a), detection(.subject, a)]) == [0, 1])
    }

    @Test("A change to a component an Update covers, or its removal, cancels the Update; other changes don't (DR-5)")
    func updateIntact() {
        let a = DetectionMaskModelTests.digestA, b = DetectionMaskModelTests.digestB
        let subject = MaskComponent(.detection(MaskDetection(kind: .subject, raster: a)))
        let people = MaskComponent(.detection(MaskDetection(kind: .people, raster: b)))
        let linear = MaskComponent(.linear(LinearGradient(start: MaskPoint(x: 0, y: 0), end: MaskPoint(x: 1, y: 1))))
        var mask = Mask(components: [subject, people])
        let both = [MaskDetectionUpdate.Started(index: 0, kind: .subject, raster: a),
                    MaskDetectionUpdate.Started(index: 1, kind: .people, raster: b)]
        let one = [both[0]]
        #expect(MaskDetectionUpdate.isIntact(both, in: mask))
        // Not covered: the other component (a one-component Update), values, an added component, a reorder.
        var changed = mask
        changed.components[1].invert = true
        #expect(MaskDetectionUpdate.isIntact(one, in: changed))
        #expect(!MaskDetectionUpdate.isIntact(both, in: changed), "two covered, one changed: the whole Update")
        changed = mask
        changed.adjustments.exposure = 1
        changed.amount = 40
        changed.components.append(linear)
        changed.components.swapAt(0, 1)
        #expect(MaskDetectionUpdate.isIntact(both, in: changed))
        // Covered: Invert, operation, removal, the mask deleted.
        changed = mask
        changed.components[0].invert = true
        #expect(!MaskDetectionUpdate.isIntact(one, in: changed))
        changed = mask
        changed.components[0].operation = .intersect
        #expect(!MaskDetectionUpdate.isIntact(one, in: changed))
        mask.components.remove(at: 0)
        #expect(!MaskDetectionUpdate.isIntact(one, in: mask))
        #expect(!MaskDetectionUpdate.isIntact(one, in: nil))
    }

    @Test("Vision's can't-run-here errors are Unavailable; any other error is Failed")
    func classification() {
        func error(_ code: VNErrorCode) -> NSError { NSError(domain: VNErrorDomain, code: code.rawValue) }
        // The detail AC11's test reads to pass only on code 22.
        guard case .unavailable(let detail) = VisionMaskDetector.classify(error(.unsupportedComputeDevice)),
              detail.hasPrefix(Self.unsupportedComputeDevice) else {
            Issue.record("code 22's detail must begin \(Self.unsupportedComputeDevice)")
            return
        }
        for code in [VNErrorCode.unsupportedComputeDevice, .unsupportedComputeStage, .unsupportedRevision,
                     .unsupportedRequest] {
            guard case .unavailable = VisionMaskDetector.classify(error(code)) else {
                Issue.record("\(code.rawValue) should be unavailable")
                continue
            }
        }
        // Resource unavailable (macOS 27) by its raw value, which every SDK
        // compiles: VNError.h declares it right after unsupported compute
        // device with no explicit value. Unavailable on every system, and not
        // code 22, so AC11's test still fails on it (code review C9).
        #expect(VisionMaskDetector.resourceUnavailableCode == VNErrorCode.unsupportedComputeDevice.rawValue + 1)
        let resource = NSError(domain: VNErrorDomain, code: VisionMaskDetector.resourceUnavailableCode)
        if case .unavailable(let detail) = VisionMaskDetector.classify(resource) {
            #expect(detail.hasPrefix("\(VNErrorDomain) 23:"))
            #expect(!detail.hasPrefix(Self.unsupportedComputeDevice))
        } else {
            Issue.record("resource unavailable (23) should be unavailable")
        }
        // Resource corrupted (24, macOS 27) is a failure, as is anything past it.
        for code in [VNErrorCode.internalError.rawValue, VNErrorCode.outOfMemory.rawValue,
                     VNErrorCode.invalidImage.rawValue, VisionMaskDetector.resourceUnavailableCode + 1] {
            guard case .failed = VisionMaskDetector.classify(NSError(domain: VNErrorDomain, code: code)) else {
                Issue.record("\(code) should be failed")
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
        let offering = [MaskDetectionState.failed, .failedUpdate(instances: 1), .unavailable, .missing,
                        .found(instances: 1), .empty, .loading].map { $0.offersUpdate }
        #expect(offering == [true, true, true, true, false, false, false])
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
                    let raster = try await VisionMaskDetector().detect(request, in: image)
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
