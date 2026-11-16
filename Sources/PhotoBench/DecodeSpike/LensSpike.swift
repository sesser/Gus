import CoreImage
import Foundation
import Metal
import PhotoCore

// SPIKE for issue #194 (question 4): throwaway. Lens corrections from
// lensfun's published models (lensfun manual: "How the corrections work" and
// the model formulas of lfDistortionModel, lfTCAModel, lfVignettingModel),
// applied by our own kernel to the demosaiced image, in one resampling pass:
// each output pixel finds where its green came from through the distortion
// model (undistorted radius to distorted), then its red and blue through the
// TCA model from there, and reads each channel at its own place, divided by
// the vignetting gain at that place (devignetting comes first, on the
// pristine image, as the manual orders it).
//
// Coordinates: distortion and TCA radii are normalized so that 1 is half the
// shorter side of the calibration camera's frame (the PTLens convention the
// panotools wiki states, "radius=1.0 is half the smaller side of the image";
// lensfun's poly3 is a subset of PTLens), scaled by the ratio of crop factors
// (the manual: the library computes correction factors for a camera of
// another crop factor). Vignetting's radius: no published source we found
// states it; 1 at the corner (half diagonal) is the only reading under which
// the 12-32 mm's coefficients stay positive over the frame (see spike.md).
enum LensSpike {
    static let source = """
    #include <metal_stdlib>
    using namespace metal;

    // q: 0 cx, 1 cy, 2 normScale, 3 vigScale, 4 outScale, 5 model (0 none, 1 ptlens, 2 poly3, 3 poly5),
    // 6 a|k1, 7 b|k2, 8 c, 9 tca (0/1), 10 vr, 11 cr, 12 br, 13 vb, 14 cb, 15 bb, 16 vig (0/1), 17 v1, 18 v2, 19 v3
    inline float ratio(constant float *q, float r) {
        int model = int(q[5]);
        if (model == 1) return ((q[6] * r + q[7]) * r + q[8]) * r + (1.0f - q[6] - q[7] - q[8]);
        if (model == 2) return 1.0f - q[6] + q[6] * r * r;
        if (model == 3) return 1.0f + q[6] * r * r + q[7] * r * r * r * r;
        return 1.0f;
    }
    inline float vignette(constant float *q, float2 pos) {
        if (q[16] == 0.0f) return 1.0f;
        float r2 = length_squared((pos - float2(q[0], q[1])) * q[3]);
        return 1.0f + r2 * (q[17] + r2 * (q[18] + r2 * q[19]));
    }
    // Where the three channels of an output pixel come from, in input pixels.
    inline void sources(constant float *q, float2 out, thread float2 &pr, thread float2 &pg, thread float2 &pb) {
        float2 c = float2(q[0], q[1]);
        float2 u = (out - c) * q[4] * q[2];
        float2 d = u * ratio(q, length(u));
        float rd = length(d);
        float2 dr = d, db = d;
        if (q[9] != 0.0f) {
            dr = d * ((q[12] * rd + q[11]) * rd + q[10]);
            db = d * ((q[15] * rd + q[14]) * rd + q[13]);
        }
        pr = c + dr / q[2]; pg = c + d / q[2]; pb = c + db / q[2];
    }

    kernel void lensBilinear(texture2d<float, access::sample> input [[texture(0)]], texture2d<float, access::write> out [[texture(1)]],
                             constant float *q [[buffer(0)]], uint2 gid [[thread_position_in_grid]]) {
        if (gid.x >= out.get_width() || gid.y >= out.get_height()) return;
        constexpr sampler s(coord::pixel, filter::linear, address::clamp_to_zero);
        float2 pr, pg, pb;
        sources(q, float2(gid) + 0.5f, pr, pg, pb);
        float r = input.sample(s, pr).r / vignette(q, pr);
        float g = input.sample(s, pg).g / vignette(q, pg);
        float b = input.sample(s, pb).b / vignette(q, pb);
        out.write(float4(r, g, b, 1), gid);
    }

    // Catmull-Rom weights for a fraction t.
    inline float4 cubicWeights(float t) {
        float t2 = t * t, t3 = t2 * t;
        return float4(-0.5f * t3 + t2 - 0.5f * t, 1.5f * t3 - 2.5f * t2 + 1.0f, -1.5f * t3 + 2.0f * t2 + 0.5f * t, 0.5f * t3 - 0.5f * t2);
    }
    inline float bicubic(texture2d<float, access::sample> t, float2 pos, int channel) {
        float2 p = pos - 0.5f;
        float2 f = floor(p), frac = p - f;
        float4 wx = cubicWeights(frac.x), wy = cubicWeights(frac.y);
        int w = t.get_width(), h = t.get_height();
        float sum = 0.0f;
        for (int j = 0; j < 4; j++) {
            int y = clamp(int(f.y) - 1 + j, 0, h - 1);
            float row = 0.0f;
            for (int i = 0; i < 4; i++) {
                int x = clamp(int(f.x) - 1 + i, 0, w - 1);
                row += wx[i] * t.read(uint2(x, y))[channel];
            }
            sum += wy[j] * row;
        }
        return sum;
    }
    kernel void lensBicubic(texture2d<float, access::sample> input [[texture(0)]], texture2d<float, access::write> out [[texture(1)]],
                            constant float *q [[buffer(0)]], uint2 gid [[thread_position_in_grid]]) {
        if (gid.x >= out.get_width() || gid.y >= out.get_height()) return;
        float2 pr, pg, pb;
        sources(q, float2(gid) + 0.5f, pr, pg, pb);
        out.write(float4(max(bicubic(input, pr, 0), 0.0f) / vignette(q, pr), max(bicubic(input, pg, 1), 0.0f) / vignette(q, pg),
                         max(bicubic(input, pb, 2), 0.0f) / vignette(q, pb), 1), gid);
    }

    // The bilinear demosaic and the correction in one pass: each channel's
    // four source pixels are demosaiced where they are read.
    struct Params { uint width; uint height; uint period; uint bin; };
    inline int mirror(int i, int n) { if (i < 0) i = -i; if (i >= n) i = 2 * n - 2 - i; return clamp(i, 0, n - 1); }
    inline float demosaiced(texture2d<float, access::read> cfa, constant Params &p, constant int *pattern, int x, int y, int channel) {
        int w = p.width, h = p.height;
        x = mirror(x, w); y = mirror(y, h);
        if (pattern[(uint(y) % p.period) * p.period + uint(x) % p.period] == channel) return cfa.read(uint2(x, y)).r;
        float sum = 0.0f, count = 0.0f;
        for (int dy = -1; dy <= 1; dy++) for (int dx = -1; dx <= 1; dx++) {
            int mx = mirror(x + dx, w), my = mirror(y + dy, h);
            if (pattern[(uint(my) % p.period) * p.period + uint(mx) % p.period] != channel) continue;
            sum += cfa.read(uint2(mx, my)).r; count += 1.0f;
        }
        return count > 0.0f ? sum / count : 0.0f;
    }
    inline float bilinearAt(texture2d<float, access::read> cfa, constant Params &p, constant int *pattern, float2 pos, int channel) {
        float2 a = pos - 0.5f, f = floor(a), t = a - f;
        int x = int(f.x), y = int(f.y);
        float v00 = demosaiced(cfa, p, pattern, x, y, channel), v10 = demosaiced(cfa, p, pattern, x + 1, y, channel);
        float v01 = demosaiced(cfa, p, pattern, x, y + 1, channel), v11 = demosaiced(cfa, p, pattern, x + 1, y + 1, channel);
        return mix(mix(v00, v10, t.x), mix(v01, v11, t.x), t.y);
    }
    kernel void fusedBilinear(texture2d<float, access::read> cfa [[texture(0)]], texture2d<float, access::write> out [[texture(1)]],
                              constant float *q [[buffer(0)]], constant Params &p [[buffer(1)]], constant int *pattern [[buffer(2)]],
                              uint2 gid [[thread_position_in_grid]]) {
        if (gid.x >= p.width || gid.y >= p.height) return;
        float2 pr, pg, pb;
        sources(q, float2(gid) + 0.5f, pr, pg, pb);
        out.write(float4(bilinearAt(cfa, p, pattern, pr, 0) / vignette(q, pr), bilinearAt(cfa, p, pattern, pg, 1) / vignette(q, pg),
                         bilinearAt(cfa, p, pattern, pb, 2) / vignette(q, pb), 1), gid);
    }
    """

    final class Corrector {
        let demosaicer: MetalDemosaicer
        var pipelines: [String: MTLComputePipelineState] = [:]
        init(_ demosaicer: MetalDemosaicer) throws {
            self.demosaicer = demosaicer
            let library = try demosaicer.device.makeLibrary(source: LensSpike.source, options: nil)
            for name in ["lensBilinear", "lensBicubic", "fusedBilinear"] {
                pipelines[name] = try demosaicer.device.makeComputePipelineState(function: library.makeFunction(name: name)!)
            }
        }

        /// The corrected texture and the pass's GPU time.
        func apply(_ input: MTLTexture, _ q: [Float], cubic: Bool) throws -> (MTLTexture, Double) {
            let output = try demosaicer.texture(.rgba16Float, input.width, input.height)
            guard let buffer = demosaicer.queue.makeCommandBuffer(), let e = buffer.makeComputeCommandEncoder() else { throw BenchError("encode") }
            e.setComputePipelineState(pipelines[cubic ? "lensBicubic" : "lensBilinear"]!)
            e.setTexture(input, index: 0); e.setTexture(output, index: 1)
            var params = q
            e.setBytes(&params, length: params.count * 4, index: 0)
            e.dispatchThreads(MTLSize(width: input.width, height: input.height, depth: 1), threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
            e.endEncoding(); buffer.commit(); buffer.waitUntilCompleted()
            return (output, (buffer.gpuEndTime - buffer.gpuStartTime) * 1000)
        }

        /// The bilinear demosaic and the correction in one pass, from the mosaic; GPU time of the normalize and this pass.
        func fused(_ mosaic: RawMosaic, _ q: [Float]) throws -> (MTLTexture, Double) {
            // The normalized mosaic from the demosaicer's first pass.
            let device = demosaicer.device
            let w = mosaic.width, h = mosaic.height
            guard let raw = mosaic.values.withUnsafeBytes({ device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) }),
                  let buffer = demosaicer.queue.makeCommandBuffer() else { throw BenchError("buffer") }
            let cfa = try demosaicer.texture(.r32Float, w, h)
            let output = try demosaicer.texture(.rgba16Float, w, h)
            var params = [UInt32(w), UInt32(h), UInt32(mosaic.period), 1]
            var pattern = mosaic.pattern
            var black = mosaic.blackPerSite
            var scale = (0..<mosaic.pattern.count).map { Float(mosaic.multipliers[Int(mosaic.pattern[$0])]) / mosaic.whiteSpan }
            var span = mosaic.whiteSpan
            var qq = q
            let normalize = try demosaicer.device.makeComputePipelineState(function: try demosaicer.device.makeLibrary(source: MetalDemosaicer.source, options: nil).makeFunction(name: "normalize")!)
            guard let e = buffer.makeComputeCommandEncoder() else { throw BenchError("encode") }
            e.setComputePipelineState(normalize)
            e.setBuffer(raw, offset: 0, index: 0); e.setBytes(&params, length: 16, index: 1)
            e.setBytes(&pattern, length: pattern.count * 4, index: 2); e.setBytes(&black, length: black.count * 4, index: 3)
            e.setBytes(&scale, length: scale.count * 4, index: 4); e.setBytes(&span, length: 4, index: 5)
            e.setTexture(cfa, index: 0)
            e.dispatchThreads(MTLSize(width: w, height: h, depth: 1), threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
            e.setComputePipelineState(pipelines["fusedBilinear"]!)
            e.setTexture(cfa, index: 0); e.setTexture(output, index: 1)
            e.setBytes(&qq, length: qq.count * 4, index: 0)
            e.dispatchThreads(MTLSize(width: w, height: h, depth: 1), threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
            e.endEncoding(); buffer.commit(); buffer.waitUntilCompleted()
            return (output, (buffer.gpuEndTime - buffer.gpuStartTime) * 1000)
        }
    }

    /// The kernel's numbers for a frame of `width` x `height` sensor pixels
    /// whose diagonal is `cameraCropFactor`'s, with the lens's calibration.
    static func parameters(_ c: LensCorrection, width: Int, height: Int, cameraCropFactor: Double,
                           distortion: Bool = true, tca: Bool = true, vignetting: Bool = true,
                           vignettingAtCorner: Bool = true, outputScale: Double = 1) -> [Float] {
        let diagonalPixels = hypot(Double(width), Double(height))
        let millimetresPerPixel = (43.27 / cameraCropFactor) / diagonalPixels
        // Half the shorter side of the calibration frame, in millimetres, then in our pixels.
        let calibrationHalfDiagonal = 43.27 / c.lensCropFactor / 2
        let calibrationHalfShort = calibrationHalfDiagonal / (1 + c.aspectRatio * c.aspectRatio).squareRoot()
        let normScale = millimetresPerPixel / calibrationHalfShort
        let vigScale = vignettingAtCorner ? millimetresPerPixel / calibrationHalfDiagonal : normScale
        // The center's offset: the shorter dimension is 2 in the manual's units.
        let shortHalf = Double(min(width, height)) / 2
        let cx = Double(width) / 2 + c.centerX * shortHalf, cy = Double(height) / 2 + c.centerY * shortHalf
        let model: Float = !distortion ? 0 : ["ptlens": 1, "poly3": 2, "poly5": 3][c.distortionModel] ?? 0
        let first = c.distortionModel == "ptlens" ? c.a : c.k1, second = c.distortionModel == "ptlens" ? c.b : c.k2
        return [Float(cx), Float(cy), Float(normScale), Float(vigScale), Float(outputScale), model,
                Float(first), Float(second), Float(c.distortionModel == "ptlens" ? c.c : 0),
                tca && c.tcaModel != "none" ? 1 : 0, Float(c.vr), Float(c.cr), Float(c.br), Float(c.vb), Float(c.cb), Float(c.bb),
                vignetting && c.vignettingModel == "pa" ? 1 : 0, Float(c.v1), Float(c.v2), Float(c.v3)]
    }

    // MARK: Run

    static func run(_ arguments: Arguments, files: [URL]) throws -> [String: any Sendable] {
        guard let folder = arguments.values["lensfun"].map({ URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }) else {
            throw BenchError("lens needs --lensfun <lensfun clone>/data/db")
        }
        let start = ContinuousClock.now
        let db = try LensfunDatabase(folder: folder)
        print(String(format: "lensfun database: %d files, %d cameras, %d lenses, read in %.0f ms", db.files, db.cameras.count, db.lenses.count,
                     (ContinuousClock.now - start).milliseconds))
        let demosaicer = try MetalDemosaicer()
        let corrector = try Corrector(demosaicer)
        let lightroom = arguments.values["lightroom"].map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
        for url in files {
            let mosaic = try RawMosaic(url)
            print("\n\(url.lastPathComponent): EXIF-side names from LibRaw: make \"\(mosaic.make)\", model \"\(mosaic.model)\", lens \"\(mosaic.lens)\", "
                  + String(format: "%.1f mm f/%.1f", mosaic.focalLength, mosaic.aperture))
            let camera = db.camera(maker: mosaic.make, model: mosaic.model)
            print("  camera in lensfun: \(camera.map { "\($0.maker) \($0.model), \($0.mount), crop \($0.cropFactor)" } ?? "none under this model name")")
            // Without the camera, its mount comes from the maker's system (spike: Micro Four Thirds makers only).
            let mount = camera?.mount ?? (["panasonic", "olympus", "om digital solutions"].contains(mosaic.make.lowercased()) ? "Micro 4/3 System" : nil)
            let candidates = db.candidates(for: mosaic.lens, maker: mosaic.make, mount: mount)
            for (lens, score) in candidates.prefix(3) {
                print("  lens candidate (score \(score)): \(lens.maker) \(lens.models.first ?? "") [\(lens.mounts.joined(separator: ", "))] in \(lens.file): "
                      + "\(lens.distortion.count) distortion, \(lens.tca.count) TCA, \(lens.vignetting.count) vignetting entries")
            }
            let named = arguments.values["lens"].flatMap { name in db.lenses.first { $0.models.contains { $0.contains(name) } } }
            if let named { print("  lens named on the command line: \(named.models.first ?? "")") }
            guard let lens = named ?? candidates.first?.lens else { print("  no lens to correct with"); continue }
            let correction = LensCorrection(lens: lens, focal: mosaic.focalLength, aperture: mosaic.aperture)
            print("  at \(mosaic.focalLength) mm f/\(mosaic.aperture): \(correction.description)")
            // The camera's crop factor: lensfun's, else the file's 35 mm equivalent.
            let fileCropFactor = mosaic.focalLength35 > 0 && mosaic.focalLength > 0 ? mosaic.focalLength35 / mosaic.focalLength : nil
            let cropFactor = camera?.cropFactor ?? fileCropFactor ?? 1
            print("  camera crop factor used: \(cropFactor) (\(camera != nil ? "lensfun's camera" : fileCropFactor != nil ? "from the file's 35 mm equivalent focal length" : "unknown, 1 assumed"))")
            let w = mosaic.width, h = mosaic.height

            // Cost at this size and at 24 MP.
            let demosaiced = try demosaicer.run(mosaic, algorithm: .ha)
            var costs: [String: [Double]] = [:]
            for _ in 0..<6 {
                costs["bilinear sampler", default: []].append(try corrector.apply(demosaiced.output, parameters(correction, width: w, height: h, cameraCropFactor: cropFactor), cubic: false).1)
                costs["bicubic (Catmull-Rom)", default: []].append(try corrector.apply(demosaiced.output, parameters(correction, width: w, height: h, cameraCropFactor: cropFactor), cubic: true).1)
                costs["fused bilinear demosaic + correction", default: []].append(try corrector.fused(mosaic, parameters(correction, width: w, height: h, cameraCropFactor: cropFactor)).1)
                let separate = try demosaicer.run(mosaic, algorithm: .bilinear)
                costs["separate: normalize + bilinear demosaic + bilinear correction", default: []].append(
                    separate.gpuMs + (try corrector.apply(separate.output, parameters(correction, width: w, height: h, cameraCropFactor: cropFactor), cubic: false).1))
            }
            print(String(format: "  GPU cost at %dx%d (%.1f MP), median of the last 5 of 6:", w, h, Double(w * h) / 1e6))
            for (name, values) in costs.sorted(by: { $0.key < $1.key }) {
                print(String(format: "    %-62@ %.2f ms", name as NSString, LibRawStages.median(Array(values.dropFirst()))))
            }

            // Accuracy: renders as shown, against Lightroom's export and the system decoder (both corrected by the camera's own data).
            guard url.lastPathComponent.hasPrefix("GX85") || arguments.flags.contains("compare") else { continue }
            let step = CameraColorStep(color: mosaic.color, channelScale: mosaic.channelScale)
            func shown(_ texture: MTLTexture, linear: Bool = false) -> RGBPicture {
                var transform = step.transform(temperature: nil, tint: nil)
                if linear { transform.toneCurve = nil; transform.exposure = 1 }
                return Measure.render(transform.apply(to: HybridTiming.image(texture, flip: mosaic.flip)))
            }
            let variants: [(String, [Float]?)] = [
                ("ours, no correction", nil),
                ("ours, lensfun distortion", parameters(correction, width: w, height: h, cameraCropFactor: cropFactor, tca: false, vignetting: false)),
                ("ours, lensfun distortion (radius 1 = half diagonal)", parameters(correction, width: w, height: h, cameraCropFactor: cropFactor, tca: false, vignetting: false)
                    .enumerated().map { $0.offset == 2 ? $0.element / Float((1 + correction.aspectRatio * correction.aspectRatio).squareRoot()) : $0.element }),
                ("ours, lensfun distortion + TCA", parameters(correction, width: w, height: h, cameraCropFactor: cropFactor, vignetting: false)),
            ]
            var sweep: [(String, [Float]?)] = []
            if arguments.flags.contains("sweep") {
                // The radius normalization measured: distortion only, the normalizing length times 1/α.
                for alpha in [0.5, 0.6, 0.65, 0.68, 0.7, 0.72, 0.75, 0.8, 0.9, 1.0] {
                    sweep.append((String(format: "sweep: normalized radius × %.2f", alpha),
                                  parameters(correction, width: w, height: h, cameraCropFactor: cropFactor, tca: false, vignetting: false)
                                      .enumerated().map { $0.offset == 2 ? $0.element * Float(alpha) : $0.element }))
                }
            }
            var references: [(String, RGBPicture)] = []
            if let lightroom, let image = CIImage(contentsOf: lightroom.appending(path: "\(url.deletingPathExtension().lastPathComponent)-adobe-standard.tif")) {
                references.append(("Lightroom (camera's own correction)", Measure.render(image)))
            }
            if let system = PreviewGenerator.systemRAWImage(url) { references.append(("system decoder (default, its correction)", Measure.render(system))) }
            // Each variant is rendered twice: once to find its scale against the first reference, then zoomed by
            // that scale (the kernel's output scale) so that every patch lines up at the same size.
            var pictures: [(String, RGBPicture)] = []
            let identity = parameters(correction, width: w, height: h, cameraCropFactor: cropFactor, distortion: false, tca: false, vignetting: false)
            for (name, q) in variants + sweep {
                var params = q ?? identity
                if let reference = references.first?.1 {
                    let first = Geometry.field(fixed: reference, moving: shown(try corrector.apply(demosaiced.output, params, cubic: true).0))
                    params[4] *= Float(first.scale)
                }
                pictures.append((name, shown(try corrector.apply(demosaiced.output, params, cubic: true).0)))
            }
            for (refName, reference) in references {
                print("  geometry against \(refName) \(reference.width)x\(reference.height): displacement of 64 px patches (px at full size), "
                      + "after the best scale and shift; radial residual by radius (0 center, 1 corner)")
                for (name, picture) in pictures + references.filter({ $0.0 != refName }) {
                    let field = Geometry.field(fixed: reference, moving: picture)
                    print("    \(name): \(field.summary)")
                }
            }
            // Lateral color: red and blue against green, outer part of the frame.
            print("  lateral color (red and blue against green, patches beyond 0.6 of the half diagonal): median radial shift in px, outward positive")
            for (name, picture) in pictures + references {
                print("    \(name): \(Geometry.lateralColor(picture))")
            }
            // Vignetting: the system decoder's flat render over ours uncorrected, both linear, by radius.
            var flat = Adjustments()
            flat.decode.look = .flat
            if let system = try? PreviewGenerator().image(source: url, stack: flat.editStack, longEdge: nil) {
                let ours = shown(demosaiced.output, linear: true)
                let systemLinear = Measure.render(system)
                let profile = Geometry.radialRatio(systemLinear, over: ours)
                let gainCorner = parameters(correction, width: w, height: h, cameraCropFactor: cropFactor)
                print("  vignetting: system decoder (flat) over ours uncorrected, linear luminance by radius (normalized to the center):")
                print("    measured  " + profile.map { String(format: "%.3f", $0) }.joined(separator: " "))
                for (label, scale) in [("lensfun 1/V, radius 1 = corner", Double(gainCorner[3])), ("lensfun 1/V, radius 1 = half short side", Double(gainCorner[2]))] {
                    let halfDiagonal = hypot(Double(w), Double(h)) / 2
                    let predicted = (0..<10).map { bin -> Double in
                        let r = (Double(bin) + 0.5) / 10 * halfDiagonal * scale
                        let v = 1 + correction.v1 * r * r + correction.v2 * pow(r, 4) + correction.v3 * pow(r, 6)
                        return 1 / v
                    }
                    print("    \(label): " + predicted.map { String(format: "%.3f", $0) }.joined(separator: " "))
                }
            }
        }
        return [:]
    }
}

/// Displacement fields by patch matching (normalized cross-correlation of luminance).
enum Geometry {
    static func luma(_ p: RGBPicture) -> [Float] {
        p.pixels.map { c in
            let y = 0.2627 * c.x + 0.6780 * c.y + 0.0593 * c.z
            return y <= 0 ? 0 : pow(min(y, 1), 1 / 2.2)
        }
    }

    struct Plane {
        var width: Int, height: Int, values: [Float]
        func boxed(_ f: Int) -> Plane {
            let w = width / f, h = height / f
            var out = [Float](repeating: 0, count: w * h)
            for y in 0..<h { for x in 0..<w {
                var s: Float = 0
                for dy in 0..<f { for dx in 0..<f { s += values[(y * f + dy) * width + x * f + dx] } }
                out[y * w + x] = s / Float(f * f)
            } }
            return Plane(width: w, height: h, values: out)
        }
    }

    /// NCC of `moving` at (x+dx, y+dy) against `fixed` at (x, y) over a square patch of half size `r`.
    static func ncc(_ a: Plane, _ b: Plane, x: Int, y: Int, dx: Int, dy: Int, r: Int) -> Float {
        var sa: Float = 0, sb: Float = 0, saa: Float = 0, sbb: Float = 0, sab: Float = 0
        for j in -r..<r {
            let ra = (y + j) * a.width + x, rb = (y + j + dy) * b.width + x + dx
            for i in -r..<r {
                let p = a.values[ra + i], q = b.values[rb + i]
                sa += p; sb += q; saa += p * p; sbb += q * q; sab += p * q
            }
        }
        let n = Float(4 * r * r)
        let cov = sab / n - sa / n * sb / n
        let va = saa / n - sa * sa / n / n, vb = sbb / n - sb * sb / n / n
        return va > 1e-7 && vb > 1e-7 ? cov / (va * vb).squareRoot() : -1
    }

    /// Best integer shift in ±`search`, refined by a parabola in x and y.
    static func match(_ a: Plane, _ b: Plane, x: Int, y: Int, around: (Int, Int), search: Int, r: Int) -> (Double, Double, Float)? {
        var best: (Int, Int, Float) = (0, 0, -2)
        for dy in (around.1 - search)...(around.1 + search) {
            for dx in (around.0 - search)...(around.0 + search) {
                guard x - r + dx >= 1, x + r + dx < b.width - 1, y - r + dy >= 1, y + r + dy < b.height - 1 else { continue }
                let c = ncc(a, b, x: x, y: y, dx: dx, dy: dy, r: r)
                if c > best.2 { best = (dx, dy, c) }
            }
        }
        guard best.2 > -2 else { return nil }
        func parabola(_ m: Float, _ c: Float, _ p: Float) -> Double {
            let d = m - 2 * c + p
            return d < 0 ? Double(0.5 * (m - p) / d) : 0
        }
        let (dx, dy) = (best.0, best.1)
        guard x - r + dx - 1 >= 0, x + r + dx + 1 < b.width, y - r + dy - 1 >= 0, y + r + dy + 1 < b.height else { return (Double(dx), Double(dy), best.2) }
        let fx = parabola(ncc(a, b, x: x, y: y, dx: dx - 1, dy: dy, r: r), best.2, ncc(a, b, x: x, y: y, dx: dx + 1, dy: dy, r: r))
        let fy = parabola(ncc(a, b, x: x, y: y, dx: dx, dy: dy - 1, r: r), best.2, ncc(a, b, x: x, y: y, dx: dx, dy: dy + 1, r: r))
        return (Double(dx) + fx, Double(dy) + fy, best.2)
    }

    struct Field {
        var scale = 1.0, tx = 0.0, ty = 0.0
        var residuals: [Double] = []
        var radial: [Double] = []
        var count = 0
        var summary: String {
            let s = residuals.sorted()
            func q(_ p: Double) -> Double { s.isEmpty ? .nan : s[min(s.count - 1, Int(Double(s.count) * p))] }
            return String(format: "scale %.5f, shift %.1f, %.1f; residual median %.2f, p95 %.2f, max %.2f px (%d patches); radial by radius: %@",
                          scale, tx, ty, q(0.5), q(0.95), s.last ?? .nan, count,
                          radial.map { String(format: "%+.2f", $0) }.joined(separator: " ") as NSString)
        }
    }

    /// Where `fixed`'s patches are found in `moving`, both at their own size
    /// (the smaller frame decides the grid; centers lined up), with the best
    /// scale about the center and shift taken out.
    static func field(fixed: RGBPicture, moving: RGBPicture) -> Field {
        let a = Plane(width: fixed.width, height: fixed.height, values: luma(fixed))
        // The moving picture cropped (or padded) about its center to the fixed one's size.
        let ox = (moving.width - fixed.width) / 2, oy = (moving.height - fixed.height) / 2
        var cropped = [Float](repeating: 0, count: fixed.width * fixed.height)
        let mv = luma(moving)
        for y in 0..<fixed.height { for x in 0..<fixed.width {
            let sx = x + ox, sy = y + oy
            if sx >= 0, sy >= 0, sx < moving.width, sy < moving.height { cropped[y * fixed.width + x] = mv[sy * moving.width + sx] }
        } }
        let b = Plane(width: fixed.width, height: fixed.height, values: cropped)
        // Coarse to fine: an eighth of the size (±160 px), a half (±6 px around it), full size (±2 px around that).
        let a8 = a.boxed(8), b8 = b.boxed(8), a2 = a.boxed(2), b2 = b.boxed(2)
        let cx = Double(fixed.width) / 2, cy = Double(fixed.height) / 2
        let halfDiagonal = hypot(cx, cy)
        // Two passes: the second searches around where the first pass's scale and shift put each patch,
        // so that patches far from the center, displaced by a scale difference, are found too.
        var samples: [(x: Double, y: Double, dx: Double, dy: Double)] = []
        var predicted: (k: Double, tx: Double, ty: Double) = (0, 0, 0)
        for pass in 0..<2 {
            samples = []
            for y in stride(from: 96, to: fixed.height - 96, by: 128) {
                for x in stride(from: 96, to: fixed.width - 96, by: 128) {
                    let px = Double(x) - cx, py = Double(y) - cy
                    let guess = ((predicted.k * px + predicted.tx) / 8, (predicted.k * py + predicted.ty) / 8)
                    guard let coarse = match(a8, b8, x: x / 8, y: y / 8, around: (Int(guess.0.rounded()), Int(guess.1.rounded())),
                                             search: pass == 0 ? 20 : 10, r: 6), coarse.2 > 0.5,
                          let middle = match(a2, b2, x: x / 2, y: y / 2, around: (Int((coarse.0 * 4).rounded()), Int((coarse.1 * 4).rounded())), search: 6, r: 16),
                          middle.2 > 0.6,
                          let fine = match(a, b, x: x, y: y, around: (Int((middle.0 * 2).rounded()), Int((middle.1 * 2).rounded())), search: 2, r: 32),
                          fine.2 > 0.8 else { continue }
                    samples.append((Double(x), Double(y), fine.0, fine.1))
                }
            }
            let first = fit(samples, cx: cx, cy: cy, halfDiagonal: halfDiagonal)
            predicted = (first.scale - 1, first.tx, first.ty)
        }
        return fit(samples, cx: cx, cy: cy, halfDiagonal: halfDiagonal)
    }

    static func fit(_ samples: [(x: Double, y: Double, dx: Double, dy: Double)], cx: Double, cy: Double, halfDiagonal: Double) -> Field {
        var field = Field()
        field.count = samples.count
        guard samples.count > 10 else { return field }
        // Least squares: d = (s − 1)(p − c) + t.
        var sxx = 0.0, sxd = 0.0, n = Double(samples.count), sx = 0.0, sy = 0.0, sdx = 0.0, sdy = 0.0
        for s in samples {
            let px = s.x - cx, py = s.y - cy
            sxx += px * px + py * py; sxd += px * s.dx + py * s.dy
            sx += px; sy += py; sdx += s.dx; sdy += s.dy
        }
        // Solve jointly for k = s − 1 and t (3 unknowns), normal equations.
        let mx = sx / n, my = sy / n
        let k = (sxd - (mx * sdx + my * sdy)) / (sxx - n * (mx * mx + my * my))
        let tx = sdx / n - k * mx, ty = sdy / n - k * my
        field.scale = 1 + k; field.tx = tx; field.ty = ty
        var bins = [[Double]](repeating: [], count: 5)
        for s in samples {
            let px = s.x - cx, py = s.y - cy
            let rx = s.dx - (k * px + tx), ry = s.dy - (k * py + ty)
            field.residuals.append(hypot(rx, ry))
            let r = hypot(px, py)
            let radial = r > 0 ? (rx * px + ry * py) / r : 0
            bins[min(4, Int(r / halfDiagonal * 5))].append(radial)
        }
        field.radial = bins.map { $0.isEmpty ? .nan : $0.sorted()[$0.count / 2] }
        return field
    }

    /// Median radial shift of red and of blue against green in the outer frame.
    static func lateralColor(_ p: RGBPicture) -> String {
        func channel(_ c: Int) -> Plane {
            Plane(width: p.width, height: p.height, values: p.pixels.map { pow(max(min($0[c], 1), 0), 1 / 2.2) })
        }
        let g = channel(1), r = channel(0), b = channel(2)
        let cx = Double(p.width) / 2, cy = Double(p.height) / 2, half = hypot(cx, cy)
        var red: [Double] = [], blue: [Double] = []
        for y in stride(from: 48, to: p.height - 48, by: 64) {
            for x in stride(from: 48, to: p.width - 48, by: 64) {
                let px = Double(x) - cx, py = Double(y) - cy, rr = hypot(px, py)
                guard rr / half > 0.6 else { continue }
                if let m = match(g, r, x: x, y: y, around: (0, 0), search: 3, r: 24), m.2 > 0.9 { red.append((m.0 * px + m.1 * py) / rr) }
                if let m = match(g, b, x: x, y: y, around: (0, 0), search: 3, r: 24), m.2 > 0.9 { blue.append((m.0 * px + m.1 * py) / rr) }
            }
        }
        func median(_ v: [Double]) -> Double { v.isEmpty ? .nan : v.sorted()[v.count / 2] }
        return String(format: "red %+.2f (n %d), blue %+.2f (n %d)", median(red), red.count, median(blue), blue.count)
    }

    /// Mean luminance of `a` over `b` in ten rings (center to corner), each over the first ring.
    static func radialRatio(_ a: RGBPicture, over b: RGBPicture) -> [Double] {
        let w = min(a.width, b.width), h = min(a.height, b.height)
        let half = hypot(Double(w) / 2, Double(h) / 2)
        var sa = [Double](repeating: 0, count: 10), sb = [Double](repeating: 0, count: 10)
        for y in stride(from: 0, to: h, by: 2) {
            for x in stride(from: 0, to: w, by: 2) {
                let pa = a[x + (a.width - w) / 2, y + (a.height - h) / 2], pb = b[x + (b.width - w) / 2, y + (b.height - h) / 2]
                let la = Double(0.2627 * pa.x + 0.678 * pa.y + 0.0593 * pa.z), lb = Double(0.2627 * pb.x + 0.678 * pb.y + 0.0593 * pb.z)
                guard la < 0.9, lb < 0.9 else { continue }
                let bin = min(9, Int(hypot(Double(x) - Double(w) / 2, Double(y) - Double(h) / 2) / half * 10))
                sa[bin] += la; sb[bin] += lb
            }
        }
        let ratios = (0..<10).map { sb[$0] > 0 ? sa[$0] / sb[$0] : .nan }
        return ratios.map { $0 / ratios[0] }
    }
}
