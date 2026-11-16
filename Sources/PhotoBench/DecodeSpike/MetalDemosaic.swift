import CoreImage
import Foundation
import Metal

// SPIKE for issue #194 (question 2): throwaway. Demosaic kernels written for
// this spike from published descriptions, not from any project's code:
//
// - bilinear: each missing color is the mean of the same color's sites in the
//   3x3 neighbourhood (5x5 when the 3x3 has none). For Bayer that is the
//   textbook bilinear interpolation; for X-Trans it is the simplest usable one.
// - mhc: Malvar, He and Cutler, "High-quality linear interpolation for
//   demosaicing of Bayer-patterned color images" (ICASSP 2004): the paper's
//   four 5x5 filters, coefficients as printed there.
// - ha: green by the Hamilton–Adams directional estimates (US patent
//   5,629,734: the green neighbours' mean plus a quarter of the color's own
//   second difference, per direction), blended by inverse squared directional
//   gradients (in the manner of Pekkucuksen and Altunbasak's GBTF, ICIP 2010,
//   simplified to two directions) instead of a hard choice; red and blue by
//   bilinear interpolation of the color differences against that green (as in
//   Gunturk et al., "Demosaicking: color filter array interpolation", IEEE
//   Signal Processing Magazine 2005, section on color difference methods).
//
// Borders mirror (reflect-101), which keeps a Bayer site's color.
// `#pragma clang fp contract(off)` and the safe math mode keep the GPU's float
// arithmetic to the same operations, in the same order, as the CPU reference
// (`DemosaicReference`), so the two can be compared with a derived bound.

enum DemosaicAlgorithm: String, CaseIterable {
    case bilinear, mhc, ha
}

final class MetalDemosaicer {
    let device: MTLDevice
    let queue: MTLCommandQueue
    private var pipelines: [String: MTLComputePipelineState] = [:]
    /// Compiling the library and pipelines (the first use in a process), ms.
    let compileMs: Double

    static let epsilon: Float = 1e-3

    static let source = """
    #include <metal_stdlib>
    using namespace metal;
    #pragma clang fp contract(off)

    struct Params { uint width; uint height; uint period; uint bin; };

    inline int mirror(int i, int n) {
        if (i < 0) i = -i;
        if (i >= n) i = 2 * n - 2 - i;
        return clamp(i, 0, n - 1);
    }
    inline int colorAt(constant int *pattern, uint period, int x, int y) {
        return pattern[(uint(y) % period) * period + (uint(x) % period)];
    }
    inline float at(texture2d<float, access::read> t, int x, int y, int w, int h) {
        return t.read(uint2(mirror(x, w), mirror(y, h))).r;
    }

    kernel void normalize(device const ushort *raw [[buffer(0)]], constant Params &p [[buffer(1)]],
                          constant int *pattern [[buffer(2)]], constant float *black [[buffer(3)]],
                          constant float *scale [[buffer(4)]], constant float &span [[buffer(5)]],
                          texture2d<float, access::write> cfa [[texture(0)]], uint2 gid [[thread_position_in_grid]]) {
        if (gid.x >= p.width || gid.y >= p.height) return;
        uint site = (gid.y % p.period) * p.period + gid.x % p.period;
        float v = float(raw[gid.y * p.width + gid.x]) - black[site];
        v = min(max(v, 0.0f), span) * scale[site];
        cfa.write(float4(v, 0, 0, 0), gid);
    }

    kernel void bilinear(texture2d<float, access::read> cfa [[texture(0)]], texture2d<float, access::write> out [[texture(1)]],
                         constant Params &p [[buffer(1)]], constant int *pattern [[buffer(2)]],
                         uint2 gid [[thread_position_in_grid]]) {
        int w = p.width, h = p.height, x = gid.x, y = gid.y;
        if (x >= w || y >= h) return;
        float sum[3] = {0, 0, 0}; float count[3] = {0, 0, 0};
        int own = colorAt(pattern, p.period, x, y);
        for (int dy = -1; dy <= 1; dy++) {
            for (int dx = -1; dx <= 1; dx++) {
                if (dx == 0 && dy == 0) continue;
                int mx = mirror(x + dx, w), my = mirror(y + dy, h);
                int c = colorAt(pattern, p.period, mx, my);
                sum[c] = sum[c] + cfa.read(uint2(mx, my)).r;
                count[c] = count[c] + 1.0f;
            }
        }
        for (int c = 0; c < 3; c++) {
            if (c == own || count[c] > 0) continue;
            for (int dy = -2; dy <= 2; dy++) {
                for (int dx = -2; dx <= 2; dx++) {
                    if (abs(dx) < 2 && abs(dy) < 2) continue;
                    int mx = mirror(x + dx, w), my = mirror(y + dy, h);
                    if (colorAt(pattern, p.period, mx, my) != c) continue;
                    sum[c] = sum[c] + cfa.read(uint2(mx, my)).r;
                    count[c] = count[c] + 1.0f;
                }
            }
        }
        float rgb[3];
        for (int c = 0; c < 3; c++) rgb[c] = c == own ? cfa.read(uint2(x, y)).r : sum[c] / count[c];
        out.write(float4(rgb[0], rgb[1], rgb[2], 1), gid);
    }

    kernel void mhc(texture2d<float, access::read> cfa [[texture(0)]], texture2d<float, access::write> out [[texture(1)]],
                    constant Params &p [[buffer(1)]], constant int *pattern [[buffer(2)]],
                    uint2 gid [[thread_position_in_grid]]) {
        int w = p.width, h = p.height, x = gid.x, y = gid.y;
        if (x >= w || y >= h) return;
        float c0 = at(cfa, x, y, w, h);
        float l1 = at(cfa, x - 1, y, w, h), r1 = at(cfa, x + 1, y, w, h);
        float u1 = at(cfa, x, y - 1, w, h), d1 = at(cfa, x, y + 1, w, h);
        float l2 = at(cfa, x - 2, y, w, h), r2 = at(cfa, x + 2, y, w, h);
        float u2 = at(cfa, x, y - 2, w, h), d2 = at(cfa, x, y + 2, w, h);
        float ul = at(cfa, x - 1, y - 1, w, h), ur = at(cfa, x + 1, y - 1, w, h);
        float dl = at(cfa, x - 1, y + 1, w, h), dr = at(cfa, x + 1, y + 1, w, h);
        float orth1 = ((l1 + r1) + u1) + d1;
        float orth2 = ((l2 + r2) + u2) + d2;
        float diag = ((ul + ur) + dl) + dr;
        int own = colorAt(pattern, p.period, x, y);
        float rgb[3];
        if (own == 1) {
            // Green site: the color left and right of it, and the other one above and below.
            int across = colorAt(pattern, p.period, mirror(x + 1, w), y);
            float rowColor = ((((5.0f * c0 + 4.0f * (l1 + r1)) - (l2 + r2)) - diag) + 0.5f * (u2 + d2)) / 8.0f;
            float columnColor = ((((5.0f * c0 + 4.0f * (u1 + d1)) - (u2 + d2)) - diag) + 0.5f * (l2 + r2)) / 8.0f;
            rgb[1] = c0;
            rgb[across] = rowColor;
            rgb[2 - across] = columnColor;
        } else {
            float green = ((4.0f * c0 + 2.0f * orth1) - orth2) / 8.0f;
            float other = ((6.0f * c0 + 2.0f * diag) - 1.5f * orth2) / 8.0f;
            rgb[own] = c0;
            rgb[1] = green;
            rgb[2 - own] = other;
        }
        out.write(float4(max(rgb[0], 0.0f), max(rgb[1], 0.0f), max(rgb[2], 0.0f), 1), gid);
    }

    kernel void haGreen(texture2d<float, access::read> cfa [[texture(0)]], texture2d<float, access::write> green [[texture(1)]],
                        constant Params &p [[buffer(1)]], constant int *pattern [[buffer(2)]], constant float &eps [[buffer(3)]],
                        uint2 gid [[thread_position_in_grid]]) {
        int w = p.width, h = p.height, x = gid.x, y = gid.y;
        if (x >= w || y >= h) return;
        float c0 = at(cfa, x, y, w, h);
        if (colorAt(pattern, p.period, x, y) == 1) { green.write(float4(c0, 0, 0, 0), gid); return; }
        float gl = at(cfa, x - 1, y, w, h), gr = at(cfa, x + 1, y, w, h);
        float gu = at(cfa, x, y - 1, w, h), gd = at(cfa, x, y + 1, w, h);
        float lapH = (2.0f * c0 - at(cfa, x - 2, y, w, h)) - at(cfa, x + 2, y, w, h);
        float lapV = (2.0f * c0 - at(cfa, x, y - 2, w, h)) - at(cfa, x, y + 2, w, h);
        float gh = (gl + gr) * 0.5f + lapH * 0.25f;
        float gv = (gu + gd) * 0.5f + lapV * 0.25f;
        float dh = eps + (abs(gl - gr) + abs(lapH));
        float dv = eps + (abs(gu - gd) + abs(lapV));
        float wh = 1.0f / (dh * dh), wv = 1.0f / (dv * dv);
        float g = (wh * gh + wv * gv) / (wh + wv);
        green.write(float4(max(g, 0.0f), 0, 0, 0), gid);
    }

    kernel void haColor(texture2d<float, access::read> cfa [[texture(0)]], texture2d<float, access::read> green [[texture(1)]],
                        texture2d<float, access::write> out [[texture(2)]],
                        constant Params &p [[buffer(1)]], constant int *pattern [[buffer(2)]],
                        uint2 gid [[thread_position_in_grid]]) {
        int w = p.width, h = p.height, x = gid.x, y = gid.y;
        if (x >= w || y >= h) return;
        float g = at(green, x, y, w, h);
        int own = colorAt(pattern, p.period, x, y);
        float rgb[3];
        rgb[1] = g;
        if (own == 1) {
            int across = colorAt(pattern, p.period, mirror(x + 1, w), y);
            float horizontal = ((at(cfa, x - 1, y, w, h) - at(green, x - 1, y, w, h)) + (at(cfa, x + 1, y, w, h) - at(green, x + 1, y, w, h))) * 0.5f;
            float vertical = ((at(cfa, x, y - 1, w, h) - at(green, x, y - 1, w, h)) + (at(cfa, x, y + 1, w, h) - at(green, x, y + 1, w, h))) * 0.5f;
            rgb[across] = g + horizontal;
            rgb[2 - across] = g + vertical;
        } else {
            float diagonal = ((((at(cfa, x - 1, y - 1, w, h) - at(green, x - 1, y - 1, w, h))
                              + (at(cfa, x + 1, y - 1, w, h) - at(green, x + 1, y - 1, w, h)))
                              + (at(cfa, x - 1, y + 1, w, h) - at(green, x - 1, y + 1, w, h)))
                              + (at(cfa, x + 1, y + 1, w, h) - at(green, x + 1, y + 1, w, h))) * 0.25f;
            rgb[own] = at(cfa, x, y, w, h);
            rgb[2 - own] = g + diagonal;
        }
        out.write(float4(max(rgb[0], 0.0f), max(rgb[1], 0.0f), max(rgb[2], 0.0f), 1), gid);
    }

    // Each color's mean over a bin x bin block: half size for Bayer (2), a third for X-Trans (3).
    kernel void binned(texture2d<float, access::read> cfa [[texture(0)]], texture2d<float, access::write> out [[texture(1)]],
                       constant Params &p [[buffer(1)]], constant int *pattern [[buffer(2)]],
                       uint2 gid [[thread_position_in_grid]]) {
        uint b = p.bin;
        if (gid.x >= p.width / b || gid.y >= p.height / b) return;
        float sum[3] = {0, 0, 0}; float count[3] = {0, 0, 0};
        for (uint dy = 0; dy < b; dy++) {
            for (uint dx = 0; dx < b; dx++) {
                uint x = gid.x * b + dx, y = gid.y * b + dy;
                int c = colorAt(pattern, p.period, x, y);
                sum[c] = sum[c] + cfa.read(uint2(x, y)).r;
                count[c] = count[c] + 1.0f;
            }
        }
        out.write(float4(sum[0] / count[0], sum[1] / count[1], sum[2] / count[2], 1), gid);
    }
    """

    init() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw BenchError("no Metal device")
        }
        self.device = device
        self.queue = queue
        let start = ContinuousClock.now
        let options = MTLCompileOptions()
        options.mathMode = .safe
        let library = try device.makeLibrary(source: Self.source, options: options)
        for name in ["normalize", "bilinear", "mhc", "haGreen", "haColor", "binned"] {
            guard let function = library.makeFunction(name: name) else { throw BenchError("no kernel \(name)") }
            pipelines[name] = try device.makeComputePipelineState(function: function)
        }
        compileMs = (ContinuousClock.now - start).milliseconds
    }

    struct Run {
        var output: MTLTexture
        /// Copying the mosaic into a Metal buffer (CPU), ms.
        var uploadMs: Double
        /// GPU time of each pass (normalize, demosaic passes), ms.
        var passMs: [String: Double]
        var gpuMs: Double { passMs.values.reduce(0, +) }
        /// Wall time from the start of the upload to the end of the last pass, ms.
        var wallMs: Double
    }

    func texture(_ format: MTLPixelFormat, _ width: Int, _ height: Int) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: width, height: height, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .private
        guard let texture = device.makeTexture(descriptor: descriptor) else { throw BenchError("no texture \(width)x\(height)") }
        return texture
    }

    private func dispatch(_ name: String, _ width: Int, _ height: Int, timing: inout [String: Double], label: String? = nil,
                          _ body: (MTLComputeCommandEncoder) -> Void) throws {
        guard let buffer = queue.makeCommandBuffer(), let encoder = buffer.makeComputeCommandEncoder(),
              let pipeline = pipelines[name] else { throw BenchError("cannot encode \(name)") }
        encoder.setComputePipelineState(pipeline)
        body(encoder)
        encoder.dispatchThreads(MTLSize(width: width, height: height, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
        encoder.endEncoding()
        buffer.commit()
        buffer.waitUntilCompleted()
        if let error = buffer.error { throw error }
        timing[label ?? name, default: 0] += (buffer.gpuEndTime - buffer.gpuStartTime) * 1000
    }

    /// The mosaic demosaiced (or binned, with `bin` > 1) into a texture of
    /// `format`: camera RGB balanced by the mosaic's multipliers, as LibRaw's
    /// own output is (`LibRawDecoder`), with alpha 1.
    func run(_ mosaic: RawMosaic, algorithm: DemosaicAlgorithm, bin: Int = 1,
             format: MTLPixelFormat = .rgba16Float) throws -> Run {
        let start = ContinuousClock.now
        guard let raw = mosaic.values.withUnsafeBytes({ device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) })
        else { throw BenchError("no buffer") }
        let uploadMs = (ContinuousClock.now - start).milliseconds
        var params = [UInt32(mosaic.width), UInt32(mosaic.height), UInt32(mosaic.period), UInt32(bin)]
        var pattern = mosaic.pattern
        var black = mosaic.blackPerSite
        var scale = (0..<mosaic.pattern.count).map { Float(mosaic.multipliers[Int(mosaic.pattern[$0])]) / mosaic.whiteSpan }
        var span = mosaic.whiteSpan
        var eps = Self.epsilon
        let w = mosaic.width, h = mosaic.height
        var timing: [String: Double] = [:]
        let cfa = try texture(.r32Float, w, h)
        try dispatch("normalize", w, h, timing: &timing) { e in
            e.setBuffer(raw, offset: 0, index: 0)
            e.setBytes(&params, length: 16, index: 1)
            e.setBytes(&pattern, length: pattern.count * 4, index: 2)
            e.setBytes(&black, length: black.count * 4, index: 3)
            e.setBytes(&scale, length: scale.count * 4, index: 4)
            e.setBytes(&span, length: 4, index: 5)
            e.setTexture(cfa, index: 0)
        }
        let output: MTLTexture
        if bin > 1 {
            output = try texture(format, w / bin, h / bin)
            try dispatch("binned", w / bin, h / bin, timing: &timing) { e in
                e.setTexture(cfa, index: 0); e.setTexture(output, index: 1)
                e.setBytes(&params, length: 16, index: 1); e.setBytes(&pattern, length: pattern.count * 4, index: 2)
            }
        } else {
            output = try texture(format, w, h)
            switch algorithm {
            case .bilinear, .mhc:
                try dispatch(algorithm.rawValue, w, h, timing: &timing) { e in
                    e.setTexture(cfa, index: 0); e.setTexture(output, index: 1)
                    e.setBytes(&params, length: 16, index: 1); e.setBytes(&pattern, length: pattern.count * 4, index: 2)
                }
            case .ha:
                let green = try texture(.r32Float, w, h)
                try dispatch("haGreen", w, h, timing: &timing) { e in
                    e.setTexture(cfa, index: 0); e.setTexture(green, index: 1)
                    e.setBytes(&params, length: 16, index: 1); e.setBytes(&pattern, length: pattern.count * 4, index: 2)
                    e.setBytes(&eps, length: 4, index: 3)
                }
                try dispatch("haColor", w, h, timing: &timing) { e in
                    e.setTexture(cfa, index: 0); e.setTexture(green, index: 1); e.setTexture(output, index: 2)
                    e.setBytes(&params, length: 16, index: 1); e.setBytes(&pattern, length: pattern.count * 4, index: 2)
                }
            }
        }
        return Run(output: output, uploadMs: uploadMs, passMs: timing, wallMs: (ContinuousClock.now - start).milliseconds)
    }

    /// A private texture's pixels as Float RGBA (any float format), row by row from the top.
    func read(_ texture: MTLTexture) throws -> [Float] {
        let w = texture.width, h = texture.height
        let half = texture.pixelFormat == .rgba16Float
        guard half || texture.pixelFormat == .rgba32Float else { throw BenchError("cannot read \(texture.pixelFormat)") }
        let shared = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: texture.pixelFormat, width: w, height: h, mipmapped: false)
        shared.storageMode = .shared
        guard let target = device.makeTexture(descriptor: shared), let buffer = queue.makeCommandBuffer(),
              let blit = buffer.makeBlitCommandEncoder() else { throw BenchError("no readback texture") }
        blit.copy(from: texture, to: target)
        blit.endEncoding()
        buffer.commit(); buffer.waitUntilCompleted()
        if half {
            var halves = [Float16](repeating: 0, count: w * h * 4)
            halves.withUnsafeMutableBytes {
                target.getBytes($0.baseAddress!, bytesPerRow: w * 8, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
            }
            return halves.map(Float.init)
        }
        var floats = [Float](repeating: 0, count: w * h * 4)
        floats.withUnsafeMutableBytes {
            target.getBytes($0.baseAddress!, bytesPerRow: w * 16, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        }
        return floats
    }
}
