import Foundation
import Metal
import os
import Synchronization

/// Our own demosaic on the GPU, for raws LibRaw unpacks (issue #196):
/// LibRaw's sensor values in, linear camera RGB out, balanced by the
/// mosaic's multipliers exactly as LibRaw's own demosaic would leave it
/// (`LibRawDecoder`), so the color step that follows takes it unchanged.
///
/// One engine per process (`shared`): the device, its queue, the compiled
/// kernels and each pattern's tables. Any number of decodes may run at once;
/// each has its own buffers and command buffer.
///
/// `@unchecked Sendable`: the device, queue and pipeline states are
/// documented as safe to use from any thread, and are not changed after
/// `init`; the tables cache is guarded by its mutex.
public final class GPUDemosaic: @unchecked Sendable {
    public enum Failure: Error, CustomStringConvertible, Equatable {
        case noDevice
        case compile(String)
        case allocation(String)
        case encoding(String)
        case execution(String)
        case injected

        public var description: String {
            switch self {
            case .noDevice: "no Metal device"
            case .compile(let reason): "the demosaic kernels did not compile: \(reason)"
            case .allocation(let what): "could not allocate \(what)"
            case .encoding(let what): "could not encode \(what)"
            case .execution(let reason): "the GPU work failed: \(reason)"
            case .injected: "a failure injected for a test"
            }
        }
    }

    /// A failure a test makes the next demosaics of its task meet (AC12).
    public enum InjectedFault: Sendable {
        /// As if the kernels had failed on the GPU.
        case execution
        /// As if there were no Metal device.
        case noDevice
    }

    /// Set by a test, for the work of its own task only.
    @TaskLocal public static var injectedFault: InjectedFault?

    /// The output format: half float for the app; 32-bit float for tests
    /// that compare the kernels with their CPU reference.
    public enum Precision: Sendable {
        case half, float
        var pixelFormat: MTLPixelFormat { self == .half ? .rgba16Float : .rgba32Float }
        var bytesPerPixel: Int { self == .half ? 8 : 16 }
    }

    /// The demosaiced image, red, green, blue and alpha, rows from the top.
    public struct Image: Sendable {
        public var width: Int
        public var height: Int
        public var bytesPerRow: Int
        public var precision: Precision
        let storage: PageAlignedStorage
        /// GPU time of the work, seconds (from the command buffer's timestamps).
        public var gpuSeconds: Double

        /// The pixels as data, without a copy; the storage lives as long as the data.
        public var data: Data {
            let storage = storage
            return Data(bytesNoCopy: storage.pointer, count: bytesPerRow * height, deallocator: .custom { _, _ in
                withExtendedLifetime(storage) {}
            })
        }

        /// Each pixel's channel values as Float, four to a pixel (tests, measurement).
        public func floats() -> [Float] {
            var out = [Float](repeating: 0, count: width * height * 4)
            for y in 0..<height {
                let row = storage.pointer.advanced(by: y * bytesPerRow)
                for i in 0..<(width * 4) {
                    out[y * width * 4 + i] = precision == .half
                        ? Float(row.load(fromByteOffset: i * 2, as: Float16.self))
                        : row.load(fromByteOffset: i * 4, as: Float.self)
                }
            }
            return out
        }
    }

    /// Kernels whose test for a flat area adds this to a variation, so a
    /// division never meets zero (`DemosaicTables`, the Bayer blend).
    public static let epsilon: Float = 1e-3

    private static let log = Logger(subsystem: AppBranding.bundleIdentifier, category: "decode")

    let device: any MTLDevice
    private let queue: any MTLCommandQueue
    private let pipelines: [String: any MTLComputePipelineState]
    private let tables = Mutex<[CFAPattern: TableBuffers]>([:])

    private struct TableBuffers: @unchecked Sendable {
        // @unchecked: MTLBuffer contents are written once, before the struct is shared.
        var border: Int
        var tapCounts: any MTLBuffer
        var taps: any MTLBuffer
        var pairCounts: any MTLBuffer
        var pairs: any MTLBuffer
        var neighbourCounts: any MTLBuffer
        var neighbours: any MTLBuffer
    }

    /// Demosaics run, for tests that check a white balance change runs none (AC10).
    public static var runCount: Int { counter.withLock { $0 } }
    private static let counter = Mutex(0)

    init(device: any MTLDevice) throws(Failure) {
        guard let queue = device.makeCommandQueue() else { throw .allocation("a command queue") }
        self.device = device
        self.queue = queue
        let options = MTLCompileOptions()
        options.mathMode = .safe
        do {
            let library = try device.makeLibrary(source: DemosaicKernels.source, options: options)
            var made: [String: any MTLComputePipelineState] = [:]
            for name in ["xtransGreen", "xtransColor", "bayerGreen", "bayerColor", "binHalf"] {
                guard let function = library.makeFunction(name: name) else { throw Failure.compile("no kernel \(name)") }
                made[name] = try device.makeComputePipelineState(function: function)
            }
            pipelines = made
        } catch let failure as Failure {
            throw failure
        } catch {
            throw .compile(String(describing: error))
        }
    }

    /// The engine, made on first use. A device that is missing stays
    /// missing for the process; a compile failure is tried again next time.
    public static func shared() throws(Failure) -> GPUDemosaic {
        if injectedFault == .noDevice { throw .noDevice }
        return try made.withLock { (made: inout GPUDemosaic?) throws(Failure) -> GPUDemosaic in
            if let made { return made }
            guard let device = systemDevice else { throw .noDevice }
            let engine = try GPUDemosaic(device: device)
            made = engine
            return engine
        }
    }

    private static let made = Mutex<GPUDemosaic?>(nil)
    private static let systemDevice: (any MTLDevice)? = MTLCreateSystemDefaultDevice()

    // MARK: Running

    /// Demosaics `mosaic` at full size, or bins it to half size.
    public func run(_ mosaic: SensorMosaic, halfSize: Bool = false, precision: Precision = .half) throws(Failure) -> Image {
        if Self.injectedFault == .execution { throw .injected }
        let width = halfSize ? mosaic.width / 2 : mosaic.width
        let height = halfSize ? mosaic.height / 2 : mosaic.height
        guard width > 0, height > 0 else { throw .allocation("an image of no size") }
        let format = precision.pixelFormat
        let alignment = device.minimumLinearTextureAlignment(for: format)
        let bytesPerRow = (width * precision.bytesPerPixel + alignment - 1) / alignment * alignment
        guard let storage = PageAlignedStorage(count: bytesPerRow * height) else { throw .allocation("the output") }
        guard let outputBuffer = device.makeBuffer(bytesNoCopy: storage.pointer, length: storage.allocatedCount,
                                                   options: .storageModeShared, deallocator: nil) else {
            throw .allocation("the output buffer")
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: width, height: height,
                                                                  mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = [.shaderRead, .shaderWrite]
        guard let output = outputBuffer.makeTexture(descriptor: descriptor, offset: 0, bytesPerRow: bytesPerRow) else {
            throw .allocation("the output texture")
        }
        let rawStorage = mosaic.storage
        guard let raw = device.makeBuffer(bytesNoCopy: rawStorage.pointer, length: rawStorage.allocatedCount,
                                          options: .storageModeShared, deallocator: nil) else {
            throw .allocation("the sensor buffer")
        }
        let tables = try tableBuffers(for: mosaic.pattern)
        let pattern = mosaic.pattern
        var params = Params(width: UInt32(mosaic.width), height: UInt32(mosaic.height), period: UInt32(pattern.period),
                            border: UInt32(tables?.border ?? 0), epsilon: Self.epsilon, span: mosaic.whiteSpan,
                            binLow: 0, binHigh: 1)
        if halfSize, pattern.kind == .xTrans { (params.binLow, params.binHigh) = (-1, 2) }
        var colors = pattern.colors
        var black = mosaic.blackPerSite
        var scale = mosaic.scalePerSite

        guard let commands = queue.makeCommandBuffer(), let encoder = commands.makeComputeCommandEncoder() else {
            throw .encoding("a command buffer")
        }
        func common(_ name: String) {
            encoder.setComputePipelineState(pipelines[name]!)
            encoder.setBuffer(raw, offset: 0, index: 0)
            encoder.setBytes(&params, length: MemoryLayout<Params>.stride, index: 1)
            encoder.setBytes(&colors, length: colors.count * 4, index: 2)
            encoder.setBytes(&black, length: black.count * 4, index: 3)
            encoder.setBytes(&scale, length: scale.count * 4, index: 4)
        }
        func dispatch(_ name: String, _ w: Int, _ h: Int) {
            let pipeline = pipelines[name]!
            let tw = pipeline.threadExecutionWidth, th = max(1, pipeline.maxTotalThreadsPerThreadgroup / tw)
            encoder.dispatchThreadgroups(MTLSize(width: (w + tw - 1) / tw, height: (h + th - 1) / th, depth: 1),
                                         threadsPerThreadgroup: MTLSize(width: tw, height: th, depth: 1))
        }
        var green: (any MTLTexture)?
        if halfSize {
            common("binHalf")
            encoder.setTexture(output, index: 0)
            dispatch("binHalf", width, height)
        } else {
            let greenDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r32Float, width: width,
                                                                           height: height, mipmapped: false)
            greenDescriptor.storageMode = .private
            greenDescriptor.usage = [.shaderRead, .shaderWrite]
            guard let plane = device.makeTexture(descriptor: greenDescriptor) else {
                encoder.endEncoding()
                throw .allocation("the green plane")
            }
            green = plane
            switch pattern.kind {
            case .bayer:
                common("bayerGreen")
                encoder.setTexture(plane, index: 0)
                dispatch("bayerGreen", width, height)
                common("bayerColor")
                encoder.setTexture(plane, index: 0)
                encoder.setTexture(output, index: 1)
                dispatch("bayerColor", width, height)
            case .xTrans:
                guard let tables else { encoder.endEncoding(); throw .encoding("tables for \(pattern)") }
                common("xtransGreen")
                encoder.setBuffer(tables.tapCounts, offset: 0, index: 5)
                encoder.setBuffer(tables.taps, offset: 0, index: 6)
                encoder.setBuffer(tables.pairCounts, offset: 0, index: 7)
                encoder.setBuffer(tables.pairs, offset: 0, index: 8)
                encoder.setTexture(plane, index: 0)
                dispatch("xtransGreen", width, height)
                common("xtransColor")
                encoder.setBuffer(tables.neighbourCounts, offset: 0, index: 5)
                encoder.setBuffer(tables.neighbours, offset: 0, index: 6)
                encoder.setTexture(plane, index: 0)
                encoder.setTexture(output, index: 1)
                dispatch("xtransColor", width, height)
            }
        }
        encoder.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
        withExtendedLifetime((rawStorage, raw, green, outputBuffer)) {}
        if let error = commands.error { throw .execution(String(describing: error)) }
        guard commands.status == .completed else { throw .execution("command buffer status \(commands.status.rawValue)") }
        Self.counter.withLock { $0 += 1 }
        return Image(width: width, height: height, bytesPerRow: bytesPerRow, precision: precision, storage: storage,
                     gpuSeconds: commands.gpuEndTime - commands.gpuStartTime)
    }

    struct Params {
        var width: UInt32
        var height: UInt32
        var period: UInt32
        var border: UInt32
        var epsilon: Float
        var span: Float
        var binLow: Int32
        var binHigh: Int32
    }

    /// The X-Trans tables of a pattern as GPU buffers, made once (nil for Bayer, which needs none).
    private func tableBuffers(for pattern: CFAPattern) throws(Failure) -> TableBuffers? {
        guard pattern.kind == .xTrans else { return nil }
        if let known = tables.withLock({ $0[pattern] }) { return known }
        guard let made = DemosaicTables(pattern) else { throw .encoding("tables for \(pattern)") }
        let sites = pattern.period * pattern.period
        var tapCounts = [UInt32](repeating: 0, count: sites * 4)
        var taps = [DemosaicTables.Tap](repeating: .init(dx: 0, dy: 0, weight: 0), count: sites * 4 * DemosaicTables.maximumTaps)
        var pairCounts = [UInt32](repeating: 0, count: sites * 4)
        var pairs = [DemosaicTables.Pair](repeating: .init(ax: 0, ay: 0, bx: 0, by: 0, weight: 0),
                                          count: sites * 4 * DemosaicTables.maximumPairs)
        var neighbourCounts = [UInt32](repeating: 0, count: sites * 3)
        var neighbours = [DemosaicTables.Tap](repeating: .init(dx: 0, dy: 0, weight: 0),
                                              count: sites * 3 * DemosaicTables.maximumNeighbours)
        for site in 0..<sites {
            for d in 0..<4 {
                tapCounts[site * 4 + d] = UInt32(made.greenTaps[site][d].count)
                for (i, tap) in made.greenTaps[site][d].enumerated() {
                    taps[(site * 4 + d) * DemosaicTables.maximumTaps + i] = tap
                }
                pairCounts[site * 4 + d] = UInt32(made.variationPairs[site][d].count)
                for (i, pair) in made.variationPairs[site][d].enumerated() {
                    pairs[(site * 4 + d) * DemosaicTables.maximumPairs + i] = pair
                }
            }
            for c in 0..<3 {
                neighbourCounts[site * 3 + c] = UInt32(made.neighbours[site][c].count)
                for (i, tap) in made.neighbours[site][c].enumerated() {
                    neighbours[(site * 3 + c) * DemosaicTables.maximumNeighbours + i] = tap
                }
            }
        }
        func buffer<T>(_ array: [T]) throws(Failure) -> any MTLBuffer {
            guard let buffer = array.withUnsafeBytes({ device.makeBuffer(bytes: $0.baseAddress!, length: $0.count) }) else {
                throw .allocation("the demosaic tables")
            }
            return buffer
        }
        let result = TableBuffers(border: Self.border(of: made), tapCounts: try buffer(tapCounts), taps: try buffer(taps),
                                  pairCounts: try buffer(pairCounts), pairs: try buffer(pairs),
                                  neighbourCounts: try buffer(neighbourCounts), neighbours: try buffer(neighbours))
        tables.withLock { $0[pattern] = result }
        return result
    }

    /// How far from an edge the X-Trans kernels use their tables (nearer, the window means).
    public static func border(of tables: DemosaicTables) -> Int {
        var reach = 2
        for site in tables.greenTaps {
            for taps in site { for tap in taps { reach = max(reach, Int(abs(tap.dx)), Int(abs(tap.dy))) } }
        }
        for site in tables.variationPairs {
            for pairs in site {
                for pair in pairs { reach = max(reach, Int(abs(pair.ax)), Int(abs(pair.ay)), Int(abs(pair.bx)), Int(abs(pair.by))) }
            }
        }
        return reach
    }
}
