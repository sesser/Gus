import CoreGraphics
import CoreImage
import CoreVideo
import Foundation
import Vision

/// Finds a mask component's result in a photo (issue #88, R4): renders the
/// mask frame at `inputLongEdge` and runs a Vision request on it, on the Mac.
/// Neither request downloads a model or uses the network (R10).
public protocol MaskDetecting: Sendable {
    /// The result of `request` on `image` (upright, sRGB). An empty result
    /// (nothing found) is a result; throws `MaskDetectionError` otherwise.
    /// Cancelling the calling task cancels the request.
    func detect(_ request: MaskRaster.Request, in image: CGImage) async throws(MaskDetectionError) -> MaskRaster
}

/// Why a detection gave no result (design §4: Failed and Unavailable).
public enum MaskDetectionError: Error, Equatable, Sendable {
    /// The request reports it can't run on this Mac (an unsupported compute
    /// device or revision): Vision's foreground request refuses the CPU, so a
    /// Mac with no usable GPU or Neural Engine gets this. The system's words.
    case unavailable(String)
    /// The request, or reading its result, failed. The system's words.
    case failed(String)
    /// The photo could not be rendered for detection.
    case unreadable
    /// Vision gave a mask this build can't read or store.
    case unusableMask

    /// For `photocli`, in plain English (it has no String Catalog); the app
    /// words the last two itself (`MaskDetectionText.detail`).
    public var detail: String {
        switch self {
        case .unavailable(let detail), .failed(let detail): detail
        case .unreadable: "The photo could not be rendered for detection."
        case .unusableMask: "Vision gave a mask this build can't read."
        }
    }
}

/// Vision's instance mask requests: `VNGenerateForegroundInstanceMaskRequest`
/// for Subject and Background, `VNGeneratePersonInstanceMaskRequest` for
/// People (at most four people, R15). Every instance is used (R11), as
/// Vision's soft all-instances mask quantized to 8 bits.
public struct VisionMaskDetector: MaskDetecting {
    public init() {}

    public func detect(_ request: MaskRaster.Request, in image: CGImage) async throws(MaskDetectionError) -> MaskRaster {
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        let vision: VNImageBasedRequest = switch request {
        case .foreground: VNGenerateForegroundInstanceMaskRequest()
        case .person: VNGeneratePersonInstanceMaskRequest()
        }
        let cancel = RequestCancel(vision)
        do {
            // Cancel reaches the request itself (code review C8), which then throws.
            try await withTaskCancellationHandler {
                guard !Task.isCancelled else { throw CancellationError() }
                try handler.perform([vision])
            } onCancel: {
                cancel.cancel()
            }
        } catch {
            throw Self.classify(error)
        }
        let results: [VNInstanceMaskObservation]? = (vision as? VNGenerateForegroundInstanceMaskRequest)?.results
            ?? (vision as? VNGeneratePersonInstanceMaskRequest)?.results
        // No observation, or one with no instance: nothing found (R6).
        guard let observation = results?.first, !observation.allInstances.isEmpty else {
            return .empty(request, revision: vision.revision)
        }
        let buffer: CVPixelBuffer
        do {
            buffer = try observation.generateMask(forInstances: observation.allInstances)
        } catch {
            throw Self.classify(error)
        }
        guard let (levels, width, height) = Self.levels(of: buffer) else { throw .unusableMask }
        do {
            return try MaskRaster(levels: levels, width: width, height: height,
                                  instances: observation.allInstances.count, request: request, revision: vision.revision)
        } catch {
            throw .unusableMask
        }
    }

    /// Cancels a Vision request from the task's cancellation handler, which
    /// runs on another thread. `@unchecked`: `VNRequest` is not `Sendable`,
    /// but `cancel()` is its documented way to stop a request in flight from
    /// elsewhere, and nothing else of the request is touched through this.
    private final class RequestCancel: @unchecked Sendable {
        private let request: VNRequest
        init(_ request: VNRequest) { self.request = request }
        func cancel() { request.cancel() }
    }

    /// Unavailable for errors that say the request can't run here, failed otherwise.
    static func classify(_ error: any Error) -> MaskDetectionError {
        let nsError = error as NSError
        let detail = "\(nsError.domain) \(nsError.code): \(nsError.localizedDescription)"
        guard nsError.domain == VNErrorDomain else { return .failed(detail) }
        var unavailable: Set<Int> = [VNErrorCode.unsupportedRevision.rawValue, VNErrorCode.unsupportedRequest.rawValue,
                                     VNErrorCode.unsupportedComputeStage.rawValue,
                                     VNErrorCode.unsupportedComputeDevice.rawValue]
        if #available(macOS 27, *) { unavailable.insert(VNErrorCode.resourceUnavailable.rawValue) }
        return unavailable.contains(nsError.code) ? .unavailable(detail) : .failed(detail)
    }

    /// A one-channel mask (32-bit float, 16-bit half or 8-bit), 0 … 1, as
    /// levels, top row first.
    static func levels(of buffer: CVPixelBuffer) -> (levels: [UInt8], width: Int, height: Int)? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        let format = CVPixelBufferGetPixelFormatType(buffer)
        let read: (UnsafeRawPointer, Int) -> Float
        let bytesPerPixel: Int
        switch format {
        case kCVPixelFormatType_OneComponent32Float:
            (read, bytesPerPixel) = ({ $0.assumingMemoryBound(to: Float.self)[$1] }, 4)
        case kCVPixelFormatType_OneComponent16Half:
            (read, bytesPerPixel) = ({ Float($0.assumingMemoryBound(to: Float16.self)[$1]) }, 2)
        case kCVPixelFormatType_OneComponent8:
            (read, bytesPerPixel) = ({ Float($0.assumingMemoryBound(to: UInt8.self)[$1]) / 255 }, 1)
        default: return nil
        }
        // Checked before anything is allocated or read (security review N1).
        let sides = 1...MaskRaster.maximumSide
        guard sides.contains(width), sides.contains(height), !CVPixelBufferIsPlanar(buffer),
              rowBytes >= width * bytesPerPixel, CVPixelBufferGetDataSize(buffer) >= rowBytes * height,
              let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        var levels = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            let row = UnsafeRawPointer(base.advanced(by: y * rowBytes))
            for x in 0..<width {
                let value = read(row, x)
                levels[y * width + x] = value.isFinite ? UInt8((min(max(value, 0), 1) * 255).rounded()) : 0
            }
        }
        return (levels, width, height)
    }
}

/// Running a detection for a photo (R4).
public enum MaskDetectionRun {
    /// The long edge of the detection input: the preview tier's. Any input
    /// from 1024 pixels up gave the same mask (status.md §2).
    public static let inputLongEdge = PreviewTier.preview.longEdge

    /// The result of `kind`'s request on the master at `source`: rendered
    /// (`input`), then detected. Cancellable before and after the render,
    /// and during the request.
    public static func run(_ kind: MaskDetectionKind, source: URL, adjustments: Adjustments, engine: RenderEngine,
                           detector: any MaskDetecting) async throws -> MaskRaster {
        try Task.checkCancellation()
        let image = try input(source: source, adjustments: adjustments, engine: engine)
        try Task.checkCancellation()
        return try await detector.detect(kind.request, in: image)
    }

    /// Each of `requests` on one render of the input (code review C7): an
    /// Update of Subject and People renders once. A failed render fails them
    /// all. Throws only `CancellationError`.
    public static func run(_ requests: [MaskRaster.Request], source: URL, adjustments: Adjustments,
                           engine: RenderEngine, detector: any MaskDetecting) async throws
        -> [MaskRaster.Request: Result<MaskRaster, MaskDetectionError>] {
        try Task.checkCancellation()
        let image: CGImage
        do {
            image = try input(source: source, adjustments: adjustments, engine: engine)
        } catch {
            return Dictionary(requests.map { ($0, .failure(error)) }, uniquingKeysWith: { first, _ in first })
        }
        var results: [MaskRaster.Request: Result<MaskRaster, MaskDetectionError>] = [:]
        for request in requests where results[request] == nil {
            try Task.checkCancellation()
            do {
                results[request] = .success(try await detector.detect(request, in: image))
            } catch {
                results[request] = .failure(error)
            }
        }
        try Task.checkCancellation()
        return results
    }

    /// The mask frame of the master at `source` (the oriented decode before
    /// any crop; a raw's whole sensor) with no adjustments but the Distortion
    /// group that defines that frame (R4, R7), at most `inputLongEdge`
    /// pixels, in sRGB, so the result does not depend on edits made before.
    public static func input(source: URL, adjustments: Adjustments, engine: RenderEngine) throws(MaskDetectionError)
        -> CGImage {
        let isRaw = SystemRAWDecoder.reads(source)
        var settings = SystemRAWDecoder.settings(RAWDecodeSettings(), reaching: source, systemReads: isRaw)
        settings.fullFrame = isRaw
        let decoded: PreviewGenerator.Decoded
        do {
            decoded = try PreviewGenerator.decode(source, longEdge: inputLongEdge, draft: false, settings: settings)
        } catch {
            throw .unreadable
        }
        let image = maskFrame(adjustments, decoded.image, context: decoded.context).scaledToFit(longEdge: inputLongEdge)
        let extent = image.extent
        guard !extent.isInfinite, !extent.isEmpty, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let rendered = engine.makeCGImage(image, colorSpace: space) else { throw .unreadable }
        return rendered
    }

    /// The decode with the Distortion group alone applied (`AdjustmentRenderer.lensCorrected`).
    static func maskFrame(_ adjustments: Adjustments, _ decoded: CIImage, context: RenderContext) -> CIImage {
        var distortion = Adjustments()
        distortion.distortion = adjustments.effective.distortion
        return AdjustmentRenderer.lensCorrected(distortion, decoded, context: context)
    }
}

/// What a detection component shows (design §4), from its stored kind and
/// digest and what is known about the result.
public enum MaskDetectionState: Equatable, Sendable {
    case found(instances: Int)
    /// An Update of a found result failed on this visit: the earlier result
    /// still applies (design DR-1).
    case failedUpdate(instances: Int)
    case empty
    /// Detection failed, or a result was never stored (no digest).
    case failed
    /// This session learned the request can't run on this Mac.
    case unavailable
    /// The digest names no row, or the row's bytes can't be read.
    case missing
    /// The result is not known yet (its row is being read).
    case loading

    /// The component selects nothing, so Update is the remedy (design §4).
    public var offersUpdate: Bool {
        switch self {
        case .failed, .failedUpdate, .unavailable, .missing: true
        case .found, .empty, .loading: false
        }
    }

    /// The state of `detection` given its row's lookup (nil while not read)
    /// and whether this session found its request unavailable.
    public static func of(_ detection: MaskDetection, lookup: MaskRasterStore.Lookup?, unavailable: Bool)
        -> MaskDetectionState {
        guard detection.raster != nil else { return unavailable ? .unavailable : .failed }
        switch lookup {
        case nil: return .loading
        case .missing: return .missing
        case .stored(let entry): return entry.instances > 0 ? .found(instances: entry.instances) : .empty
        }
    }
}

/// Where an Update's components are when its result lands (code review C1):
/// each component the Update started on is found again by its kind, the
/// result it named, its operation and Invert, at its old place if it is still there, else at the first
/// unclaimed place that matches. Nil for one that is gone (removed, or
/// changed by an undo), so a result never lands on another component.
public enum MaskDetectionUpdate {
    public struct Started: Equatable, Sendable {
        public var index: Int
        public var kind: MaskDetectionKind
        public var raster: String?
        public var operation: MaskOperation
        public var invert: Bool

        public init(index: Int, kind: MaskDetectionKind, raster: String?, operation: MaskOperation = .add,
                    invert: Bool = false) {
            self.index = index
            self.kind = kind
            self.raster = raster
            self.operation = operation
            self.invert = invert
        }
    }

    public static func positions(of started: [Started], in components: [MaskComponent]) -> [Int?] {
        var claimed = Set<Int>()
        return started.map { wanted in
            // Its operation and Invert too: twins that differ only there stay apart (code review C10).
            func matches(_ position: Int) -> Bool {
                let component = components[position]
                guard !claimed.contains(position), let detection = component.shape.detection else { return false }
                return detection.kind == wanted.kind && detection.raster == wanted.raster
                    && component.operation == wanted.operation && component.invert == wanted.invert
            }
            let position = components.indices.contains(wanted.index) && matches(wanted.index)
                ? wanted.index : components.indices.first(where: matches)
            if let position { claimed.insert(position) }
            return position
        }
    }

    /// Every component an Update covers is still in `mask` as it was (kind,
    /// result, operation, Invert), wherever it now sits. False when one was
    /// changed or removed, or the mask is gone: the Update is then cancelled
    /// whole (design DR-5). Adding a component, reordering, or changing
    /// anything else keeps it intact.
    public static func isIntact(_ started: [Started], in mask: Mask?) -> Bool {
        guard let mask else { return false }
        return !positions(of: started, in: mask.components).contains(nil)
    }
}

