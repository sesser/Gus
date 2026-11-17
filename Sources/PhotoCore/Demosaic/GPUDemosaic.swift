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
        /// As if the noise reduction's scratch textures could not be made,
        /// after the demosaic is encoded (code review C1).
        case scratchAllocation
    }

    /// Set by a test, for the work of its own task only.
    @TaskLocal public static var injectedFault: InjectedFault?

    /// The noise reduction decodes use (`LibRawDecoder`): the baseline step;
    /// tests and measurements set another, or none, for their own task.
    @TaskLocal public static var decodeNoiseReduction: ColorNoiseReduction? = .baseline

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
                        ? GPUDemosaic.float(half: row.load(fromByteOffset: i * 2, as: UInt16.self))
                        : row.load(fromByteOffset: i * 4, as: Float.self)
                }
            }
            return out
        }
    }

    /// An IEEE half float's value (Swift's `Float16` is not available on
    /// every Mac the package builds for).
    public static func float(half bits: UInt16) -> Float {
        let sign: Float = bits & 0x8000 != 0 ? -1 : 1
        let exponent = Int((bits >> 10) & 0x1f), fraction = Float(bits & 0x3ff)
        switch exponent {
        case 0: return sign * fraction * 0x1p-24
        case 31: return fraction == 0 ? sign * .infinity : .nan
        default: return sign * (1 + fraction / 1024) * Float(sign: .plus, exponent: exponent - 15, significand: 1)
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

    /// Counts the demosaics run in the work of a task (tests: a white
    /// balance change runs none, AC10; a cancelled decode runs none, AC13).
    public final class RunCounter: Sendable {
        private let count = Mutex(0)
        public init() {}
        public var value: Int { count.withLock { $0 } }
        func increment() { count.withLock { $0 += 1 } }
    }

    @TaskLocal public static var runCounter: RunCounter?

    init(device: any MTLDevice) throws(Failure) {
        guard let queue = device.makeCommandQueue() else { throw .allocation("a command queue") }
        self.device = device
        self.queue = queue
        let options = MTLCompileOptions()
        options.mathMode = .safe
        do {
            let library = try device.makeLibrary(source: DemosaicKernels.source, options: options)
            var made: [String: any MTLComputePipelineState] = [:]
            for name in ["xtransGreen", "xtransColor", "bayerGreen", "bayerColor", "binHalf", "denoise"] {
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
    public func run(_ mosaic: SensorMosaic, halfSize: Bool = false, precision: Precision = .half,
                    noiseReduction: ColorNoiseReduction? = .baseline, bandHeight: Int = 256) throws(Failure) -> Image {
        if Self.injectedFault == .execution { throw .injected }
        let width = halfSize ? mosaic.width / 2 : mosaic.width
        let height = halfSize ? mosaic.height / 2 : mosaic.height
        guard width > 0, height > 0 else { throw .allocation("an image of no size") }
        let format = precision.pixelFormat
        let alignment = device.minimumLinearTextureAlignment(for: format)
        let bytesPerRow = (width * precision.bytesPerPixel + alignment - 1) / alignment * alignment
        guard let storage = PageAlignedStorage(count: bytesPerRow * height) else { throw .allocation("the output") }
        storage.zeroPadding(rows: height, bytesPerRow: bytesPerRow, used: width * precision.bytesPerPixel)
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
        // Every way out of the encoding ends the encoder: Metal aborts the
        // process when one is released without `endEncoding` (code review C1).
        var green: (any MTLTexture)?
        var scratch: [any MTLTexture] = []
        do throws(Failure) {
            if halfSize {
                common("binHalf")
                encoder.setTexture(output, index: 0)
                dispatch("binHalf", width, height)
            } else {
                let greenDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r32Float, width: width,
                                                                               height: height, mipmapped: false)
                greenDescriptor.storageMode = .private
                greenDescriptor.usage = [.shaderRead, .shaderWrite]
                guard let plane = device.makeTexture(descriptor: greenDescriptor) else { throw .allocation("the green plane") }
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
                    guard let tables else { throw .encoding("tables for \(pattern)") }
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
            if let noiseReduction, let channels = noiseReduction.channels(for: mosaic, halfSize: halfSize) {
                scratch = try encodeDenoise(encoder, source: output, destination: output, width: width, height: height,
                                            channels: channels, reduction: noiseReduction, bandHeight: bandHeight)
            }
        } catch {
            encoder.endEncoding()
            throw error
        }
        encoder.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
        withExtendedLifetime((rawStorage, raw, green, outputBuffer, scratch)) {}
        if let error = commands.error { throw .execution(String(describing: error)) }
        guard commands.status == .completed else { throw .execution("command buffer status \(commands.status.rawValue)") }
        Self.runCounter?.increment()
        return Image(width: width, height: height, bytesPerRow: bytesPerRow, precision: precision, storage: storage,
                     gpuSeconds: commands.gpuEndTime - commands.gpuStartTime)
    }

    /// The color noise reduction that follows the demosaic (R9): a fixed
    /// baseline step, no control (PRD Q4). Three levels of an edge-avoiding
    /// à trous smoothing of the color differences R − G and B − G, 1, 2 and
    /// 4 pixels apart, each a 5 x 5 B3-spline window (Dammertz, Sewtz,
    /// Hanika and Lensch, "Edge-avoiding À-Trous wavelet transform for fast
    /// global illumination filtering", HPG 2010) whose weights fall with a
    /// neighbour's luminance and color difference from the center measured
    /// against the noise the file's own model predicts there
    /// (`NoiseModel`); luminance is kept. `colorStrength` halves at each
    /// level, as the color differences get less noisy. Weights are rational
    /// functions, 1 / (1 + d²/(2σ²h²))², not exponentials, so the GPU and
    /// its CPU reference compute them with the same correctly rounded steps
    /// and one division.
    public struct ColorNoiseReduction: Sendable, Hashable {
        /// h for luminance: how many noise deviations a luminance difference may be.
        public var luminanceStrength: Float
        /// h for color, at the first level.
        public var colorStrength: Float
        /// Steps of the levels, pixels.
        public var steps: [Int]
        /// A model to use instead of the one estimated from the mosaic (tests).
        public var model: NoiseModel?

        public init(luminanceStrength: Float, colorStrength: Float, steps: [Int] = [1, 2, 4], model: NoiseModel? = nil) {
            self.luminanceStrength = luminanceStrength
            self.colorStrength = colorStrength
            self.steps = steps
            self.model = model
        }

        /// The app's step. Measured, not tuned to a test: see status.md, "Color noise reduction".
        public static let baseline = ColorNoiseReduction(luminanceStrength: 2, colorStrength: 3)

        /// The B3-spline window, 1 4 6 4 1 over 16 (exact in binary).
        static let taps: [Float] = [0.0625, 0.25, 0.375, 0.25, 0.0625]
        /// No variance is taken as smaller (normalized units): a file with no noise is left as it is.
        static let varianceFloor: Float = 1e-12

        /// Each output channel's variance a·v + b, from the sensor's: a value v = m·x
        /// (multiplier m) has variance m·a·v + m²·b; a half-size value averages about
        /// `n` samples of its color (`binCounts`), so its variance is that over n.
        /// Nil when the mosaic gives no model.
        func channels(for mosaic: SensorMosaic, halfSize: Bool) -> (a: SIMD3<Float>, b: SIMD3<Float>)? {
            let noise = model ?? NoiseModel.estimate(mosaic)
            guard noise != .none else { return nil }
            let m = SIMD3<Double>(mosaic.multipliers)
            var a = m * noise.a, b = m * m * noise.b
            if halfSize {
                let counts = GPUDemosaic.binCounts(mosaic.pattern)
                a /= counts
                b /= counts
            }
            return (SIMD3<Float>(a), SIMD3<Float>(b))
        }
    }

    /// The mean number of each color's sites in a half-size bin's window, over the pattern's phases.
    static func binCounts(_ pattern: CFAPattern) -> SIMD3<Double> {
        let (low, high) = pattern.kind == .xTrans ? (-1, 2) : (0, 1)
        var counts = SIMD3<Double>.zero
        var bins = 0.0
        for oy in stride(from: 0, to: pattern.period, by: 2) {
            for ox in stride(from: 0, to: pattern.period, by: 2) {
                for dy in low...high {
                    for dx in low...high {
                        counts[pattern.color(x: (ox + dx + pattern.period) % pattern.period,
                                             y: (oy + dy + pattern.period) % pattern.period)] += 1
                    }
                }
                bins += 1
            }
        }
        return counts / bins
    }

    struct DenoiseParams {
        var width: UInt32
        var height: UInt32
        var inTop: Int32
        var inRows: Int32
        var outTop: Int32
        var rowBegin: Int32
        var rowEnd: Int32
        var step: Int32
        var hY2: Float
        var hC2: Float
        var floor: Float
        var aR: Float, aG: Float, aB: Float
        var bR: Float, bG: Float, bB: Float
    }

    /// Encodes the noise reduction from `source` into `destination` (the same
    /// texture for the app's in-place step), in bands of rows through small
    /// float scratch textures, so no second full-size image is ever made
    /// (R21). A band's last level writes its rows only after the next band's
    /// first level has read the rows it shares with them; two sets of scratch
    /// textures take turns. Returns the scratch textures, to be kept until
    /// the command buffer completes.
    func encodeDenoise(_ encoder: any MTLComputeCommandEncoder, source: any MTLTexture, destination: any MTLTexture,
                       width: Int, height: Int, channels: (a: SIMD3<Float>, b: SIMD3<Float>),
                       reduction: ColorNoiseReduction, bandHeight: Int) throws(Failure) -> [any MTLTexture] {
        let steps = reduction.steps
        guard !steps.isEmpty else { return [] }
        // One level in place would read what it writes.
        guard steps.count > 1 || source !== destination else { throw .encoding("a one-level noise reduction in place") }
        let radii = steps.map { 2 * $0 }
        // What each level must leave valid around the band: the radii of the levels after it.
        let remaining = radii.indices.map { i in radii[(i + 1)...].reduce(0, +) }
        let band = max(bandHeight, radii.reduce(0, +))
        if Self.injectedFault == .scratchAllocation { throw .allocation("noise reduction scratch") }
        var sets: [[any MTLTexture]] = []
        for _ in 0..<2 {
            var set: [any MTLTexture] = []
            for level in 0..<(steps.count - 1) {
                let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba32Float, width: width,
                                                                          height: min(height, band + 2 * remaining[level]),
                                                                          mipmapped: false)
                descriptor.storageMode = .private
                descriptor.usage = [.shaderRead, .shaderWrite]
                guard let texture = device.makeTexture(descriptor: descriptor) else { throw .allocation("noise reduction scratch") }
                set.append(texture)
            }
            sets.append(set)
        }
        var taps = ColorNoiseReduction.taps
        let pipeline = pipelines["denoise"]!
        func encode(level: Int, bandIndex: Int) {
            let y0 = bandIndex * band, y1 = min(height, y0 + band)
            let set = sets[bandIndex % 2]
            let inTexture = level == 0 ? source : set[level - 1]
            let outTexture = level == steps.count - 1 ? destination : set[level]
            let inTop = level == 0 ? 0 : max(0, y0 - remaining[level - 1])
            let inRows = level == 0 ? height : min(height, y1 + remaining[level - 1]) - inTop
            let rowBegin = max(0, y0 - remaining[level]), rowEnd = min(height, y1 + remaining[level])
            let outTop = level == steps.count - 1 ? 0 : rowBegin
            let colorScale = Float(1 << (2 * level))
            var params = DenoiseParams(width: UInt32(width), height: UInt32(height), inTop: Int32(inTop),
                                       inRows: Int32(inRows), outTop: Int32(outTop), rowBegin: Int32(rowBegin),
                                       rowEnd: Int32(rowEnd), step: Int32(steps[level]),
                                       hY2: reduction.luminanceStrength * reduction.luminanceStrength,
                                       hC2: reduction.colorStrength * reduction.colorStrength / colorScale,
                                       floor: ColorNoiseReduction.varianceFloor,
                                       aR: channels.a.x, aG: channels.a.y, aB: channels.a.z,
                                       bR: channels.b.x, bG: channels.b.y, bB: channels.b.z)
            encoder.setComputePipelineState(pipeline)
            encoder.setTexture(inTexture, index: 0)
            encoder.setTexture(outTexture, index: 1)
            encoder.setBytes(&params, length: MemoryLayout<DenoiseParams>.stride, index: 0)
            encoder.setBytes(&taps, length: taps.count * 4, index: 1)
            let tw = pipeline.threadExecutionWidth, th = max(1, pipeline.maxTotalThreadsPerThreadgroup / tw)
            encoder.dispatchThreadgroups(MTLSize(width: (width + tw - 1) / tw, height: (rowEnd - rowBegin + th - 1) / th, depth: 1),
                                         threadsPerThreadgroup: MTLSize(width: tw, height: th, depth: 1))
        }
        let bands = (height + band - 1) / band
        for index in 0..<bands {
            for level in 0..<(steps.count - 1) { encode(level: level, bandIndex: index) }
            if index > 0 { encode(level: steps.count - 1, bandIndex: index - 1) }
        }
        encode(level: steps.count - 1, bandIndex: bands - 1)
        return sets.flatMap { $0 }
    }

    /// The noise reduction alone, of an image this engine made (tests: the
    /// kernel against its CPU reference on the same input, and the
    /// half-float write rule).
    public func denoise(_ image: Image, channels: (a: SIMD3<Float>, b: SIMD3<Float>), reduction: ColorNoiseReduction,
                        precision: Precision, bandHeight: Int = 256) throws(Failure) -> Image {
        let format = precision.pixelFormat
        let alignment = device.minimumLinearTextureAlignment(for: format)
        let bytesPerRow = (image.width * precision.bytesPerPixel + alignment - 1) / alignment * alignment
        guard let storage = PageAlignedStorage(count: bytesPerRow * image.height).map({
                  $0.zeroPadding(rows: image.height, bytesPerRow: bytesPerRow, used: image.width * precision.bytesPerPixel)
                  return $0
              }),
              let outputBuffer = device.makeBuffer(bytesNoCopy: storage.pointer, length: storage.allocatedCount,
                                                   options: .storageModeShared, deallocator: nil),
              let inputBuffer = device.makeBuffer(bytesNoCopy: image.storage.pointer, length: image.storage.allocatedCount,
                                                  options: .storageModeShared, deallocator: nil) else {
            throw .allocation("the noise reduction's buffers")
        }
        let inDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: image.precision.pixelFormat, width: image.width,
                                                                    height: image.height, mipmapped: false)
        inDescriptor.storageMode = .shared
        inDescriptor.usage = [.shaderRead]
        let outDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: image.width,
                                                                     height: image.height, mipmapped: false)
        outDescriptor.storageMode = .shared
        outDescriptor.usage = [.shaderRead, .shaderWrite]
        guard let input = inputBuffer.makeTexture(descriptor: inDescriptor, offset: 0, bytesPerRow: image.bytesPerRow),
              let output = outputBuffer.makeTexture(descriptor: outDescriptor, offset: 0, bytesPerRow: bytesPerRow),
              let commands = queue.makeCommandBuffer(), let encoder = commands.makeComputeCommandEncoder() else {
            throw .allocation("the noise reduction's textures")
        }
        let scratch: [any MTLTexture]
        do throws(Failure) {
            scratch = try encodeDenoise(encoder, source: input, destination: output, width: image.width, height: image.height,
                                        channels: channels, reduction: reduction, bandHeight: bandHeight)
        } catch {
            encoder.endEncoding()
            throw error
        }
        encoder.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
        withExtendedLifetime((image.storage, inputBuffer, outputBuffer, scratch)) {}
        if let error = commands.error { throw .execution(String(describing: error)) }
        return Image(width: image.width, height: image.height, bytesPerRow: bytesPerRow, precision: precision, storage: storage,
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
