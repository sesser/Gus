import CoreImage
import Foundation
import Metal
import PhotoCore

// SPIKE for issue #194 (question 3): throwaway. What owning the decode gives
// in color and white balance.
//
// 1. The #89 spike's option (c), LibRaw's camera colors through a profile's
//    matrices, hue/sat map, look table and tone curve, against Lightroom's
//    Adobe Standard export, with our Metal demosaic in place of LibRaw's: does
//    the hybrid reach (c)'s accuracy? The method, measure and alignment are
//    the #89 spike's (`Look`, `measure`, `fitGain`, `align` below are copied
//    from Sources/PhotoBench/DCPSpike/DCPSpike.swift on feature/dcp-profiles,
//    our own code); the `.dcp` files are read from Lightroom's install, never copied.
// 2. White balance: the as-shot Kelvin each decoder reports against
//    Lightroom's, and how far the same Kelvin number renders apart between
//    the system decoder and ours.
enum ColorSpike {
    struct Case {
        var raw: String
        var dcp: String
        /// Lightroom's as-shot white balance in the export (Temperature, Tint in its XMP).
        var lightroom: (kelvin: Double, tint: Double)
    }

    static let cases: [Case] = [
        Case(raw: "GX85.RW2", dcp: "Adobe Standard/Panasonic DMC-GX85 Adobe Standard.dcp", lightroom: (4700, 12)),
        Case(raw: "Canon5DMkII.CR2", dcp: "Adobe Standard/Canon EOS 5D Mark II Adobe Standard.dcp", lightroom: (5350, 10)),
        Case(raw: "EM5MarkIII.ORF", dcp: "Adobe Standard/Olympus E-M5 Mark III Adobe Standard.dcp", lightroom: (5400, 15)),
    ]

    // MARK: Copied from the #89 spike

    struct Look {
        var hueSat: ProfileHSVTable?
        var lookTable: ProfileHSVTable?
        var curve: [Float]?
        var curveMethod: ProfileColor.CurveMethod = .huePreserving

        func apply(_ working: ProfileImage, gain: Float) -> ProfileImage {
            let (a, b, c) = ProfileColor.float(ProfileColor.workingToProPhoto)
            let (d, e, f) = ProfileColor.float(ProfileColor.proPhotoToWorking)
            return working.map { pixel in
                var p = SIMD3((pixel * a).sum(), (pixel * b).sum(), (pixel * c).sum())
                if let hueSat { p = ProfileColor.applyTable(hueSat, to: p, hdr: false) }
                p *= gain
                if let lookTable { p = ProfileColor.applyTable(lookTable, to: p, hdr: false) }
                if let curve { p = ProfileColor.applyCurve(curve, p, curveMethod) }
                return SIMD3((p * d).sum(), (p * e).sum(), (p * f).sum())
            }
        }
    }

    static func measure(_ working: ProfileImage, box: Int) -> [SIMD3<Double>] {
        let srgb = ProfileColor.apply(ProfileColor.workingToSRGB, working).map { pointwiseMin(pointwiseMax($0, .zero), SIMD3(repeating: 1)) }
        return ProfileColor.blockLab(srgb.boxed(box))
    }

    static func fitGain(_ evaluate: (Double) -> ProfileColor.Difference) -> (ev: Double, difference: ProfileColor.Difference) {
        var best = (ev: 0.0, difference: evaluate(0))
        for step in stride(from: -2.5, through: 2.5, by: 0.1) {
            let d = evaluate(step)
            if d.median < best.difference.median { best = (step, d) }
        }
        let center = best.ev
        for step in stride(from: center - 0.1, through: center + 0.1, by: 0.01) {
            let d = evaluate(step)
            if d.median < best.difference.median { best = (step, d) }
        }
        return best
    }

    struct Warp {
        var scale = 1.0, k1 = 0.0, dx = 0.0, dy = 0.0, ncc = 0.0
        func apply(_ image: ProfileImage) -> ProfileImage { image.warped(scale: scale, k1: k1, dx: dx, dy: dy) }
        var text: String { String(format: "scale %.4f, radial %+.3f, shift %.1f, %.1f px, ncc %.4f", scale, k1, dx, dy, ncc) }
    }

    static func align(fixed: ProfileImage, moving: ProfileImage) -> Warp {
        func luma(_ image: ProfileImage) -> ProfileImage {
            let (_, g, _) = ProfileColor.float(WorkingSpace.toXYZ)
            return image.map { SIMD3(repeating: ProfileColor.srgbEncode(min(max(($0 * g).sum(), 0), 1))) }
        }
        func search(_ factor: Int, scales: [Double], radials: [Double], shifts: [Double], around: Warp) -> Warp {
            let a = luma(fixed).boxed(factor), b = luma(moving).boxed(factor)
            let f = Double(factor)
            func ncc(_ w: Warp) -> Double {
                let moved = b.warped(scale: w.scale, k1: w.k1, dx: w.dx / f, dy: w.dy / f)
                let margin = 48 / factor
                var sa = 0.0, sb = 0.0, saa = 0.0, sbb = 0.0, sab = 0.0, n = 0.0
                for y in margin..<(a.height - margin) {
                    for x in margin..<(a.width - margin) {
                        let p = Double(a.pixels[y * a.width + x].x), q = Double(moved.pixels[y * a.width + x].x)
                        sa += p; sb += q; saa += p * p; sbb += q * q; sab += p * q; n += 1
                    }
                }
                let cov = sab / n - sa / n * sb / n
                return cov / ((saa / n - sa * sa / n / n).squareRoot() * (sbb / n - sb * sb / n / n).squareRoot())
            }
            var best = around
            best.ncc = ncc(best)
            for s in scales { for k in radials { for dy in shifts { for dx in shifts {
                var w = Warp(scale: around.scale + s, k1: around.k1 + k, dx: around.dx + dx, dy: around.dy + dy)
                w.ncc = ncc(w)
                if w.ncc > best.ncc { best = w }
            } } } }
            return best
        }
        let coarse = search(4, scales: Array(stride(from: -0.04, through: 0.04, by: 0.005)),
                            radials: Array(stride(from: -0.06, through: 0.06, by: 0.01)),
                            shifts: Array(stride(from: -12.0, through: 12, by: 4)), around: Warp())
        return search(2, scales: Array(stride(from: -0.004, through: 0.004, by: 0.001)),
                      radials: Array(stride(from: -0.008, through: 0.008, by: 0.002)),
                      shifts: Array(stride(from: -3.0, through: 3, by: 1)), around: coarse)
    }

    static func hueSat(_ dcp: ProfileDCP, kelvin: Double) -> ProfileHSVTable? {
        let maps = dcp.hueSatMaps
        guard let first = maps.first else { return nil }
        guard maps.count == 2 else { return first }
        let weight = CameraProfile(name: "", calibrations: dcp.calibrations).weightOfFirst(at: kelvin)
        let lights = dcp.illuminants.compactMap { CameraProfile.kelvin(ofLightSource: $0) }
        let firstIsCooler = lights.count < 2 || lights[0] <= lights[1]
        return firstIsCooler ? ProfileHSVTable.blend(maps[0], maps[1], weight: weight) : ProfileHSVTable.blend(maps[1], maps[0], weight: weight)
    }

    // MARK: Run

    static func run(_ arguments: Arguments) throws -> [String: any Sendable] {
        let samples = try arguments.url("samples"), profiles = try arguments.url("profiles")
        let longEdge = 1280, box = 4
        let demosaicer = try MetalDemosaicer()
        let curve = BaselineLook.toneCurve.map { points in (0..<4096).map { Float(CameraColorTransform.toneValue(points, at: Double($0) / 4095)) } }
        // The GX85's lens: lensfun's 12-32 mm at 12 mm with the measured radius (question 4), when given.
        let lensfun = arguments.values["lensfun"].map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
        for item in cases where arguments.values["only"].map({ item.raw.hasPrefix($0) }) ?? true {
            let rawURL = samples.appending(path: item.raw)
            let prefix = rawURL.deletingPathExtension().lastPathComponent
            guard let lrImage = CIImage(contentsOf: samples.appending(path: "\(prefix)-adobe-standard.tif")) else { continue }
            let e = lrImage.extent
            var width = e.width >= e.height ? longEdge : Int((Double(longEdge) * e.width / e.height).rounded())
            var height = e.width >= e.height ? Int((Double(longEdge) * e.height / e.width).rounded()) : longEdge
            width -= width % box; height -= height % box
            let lightroom = ProfileRender.render(lrImage, width: width, height: height)
            let lightroomLab = measure(lightroom, box: box)
            let dcp = try ProfileDCP(data: Data(contentsOf: profiles.appending(path: item.dcp)))
            let mosaic = try RawMosaic(rawURL)
            guard let color = mosaic.color else { continue }
            let adobe = color.with(profile: CameraProfile(name: "Adobe Standard", calibrations: dcp.calibrations))
            print("\n=== \(item.raw): Lightroom Adobe Standard export at \(width)x\(height), blocks of 16 at 320")

            // White balance numbers.
            let system = RawDefaults(source: rawURL)
            print(String(format: "as shot: Lightroom %.0f K %+.0f; ours (built-in LibRaw matrix) %.0f K %+.1f; ours (Adobe Standard's matrices) %.0f K %+.1f; system decoder %@",
                         item.lightroom.kelvin, item.lightroom.tint, color.asShot?.kelvin ?? .nan, color.asShot?.tint ?? .nan,
                         adobe.asShot?.kelvin ?? .nan, adobe.asShot?.tint ?? .nan,
                         system.map { String(format: "%.0f K %+.1f", $0.temperature, $0.tint) } ?? "none"))

            // The linear camera colors through Adobe Standard's matrices, as shot: LibRaw's demosaic and ours.
            guard var transform = adobe.transform(for: nil, channelScale: mosaic.channelScale), let asShot = adobe.asShot else { continue }
            transform.exposure = 1
            transform.toneCurve = nil
            var sources: [(String, CIImage)] = []
            let libraw = try LibRawDecoder.decode(rawURL, longEdge: longEdge * 2)
            sources.append(("(c) LibRaw AHD + Adobe Standard matrices + look", transform.apply(to: libraw.linear)))
            for algorithm in DemosaicAlgorithm.allCases {
                let run = try demosaicer.run(mosaic, algorithm: algorithm)
                sources.append(("hybrid \(algorithm.rawValue) + Adobe Standard matrices + look", transform.apply(to: HybridTiming.image(run.output, flip: mosaic.flip))))
            }
            if let lensfun, item.raw.hasPrefix("GX85") {
                let db = try LensfunDatabase(folder: lensfun)
                if let lens = db.candidates(for: mosaic.lens, maker: mosaic.make, mount: "Micro 4/3 System").first?.lens {
                    let correction = LensCorrection(lens: lens, focal: mosaic.focalLength, aperture: mosaic.aperture)
                    let corrector = try LensSpike.Corrector(demosaicer)
                    var q = LensSpike.parameters(correction, width: mosaic.width, height: mosaic.height, cameraCropFactor: 2, vignetting: false)
                    q[2] *= 0.69
                    // Zoomed to the camera's own corrected frame (the scale measured against Lightroom at this radius, question 4).
                    q[4] *= 0.927
                    let run = try demosaicer.run(mosaic, algorithm: .ha)
                    let corrected = try corrector.apply(run.output, q, cubic: true).0
                    sources.append(("hybrid ha + lensfun (radius × 0.69, TCA) + Adobe Standard + look", transform.apply(to: HybridTiming.image(corrected, flip: mosaic.flip))))
                }
            }
            let look = Look(hueSat: hueSat(dcp, kelvin: asShot.kelvin), lookTable: dcp.lookTable, curve: curve, curveMethod: .huePreserving)
            print("variant                                                              ΔE76 median   p95   gain EV   alignment")
            var aligned: [String: ProfileImage] = [:]
            for (name, image) in sources {
                let picture = ProfileRender.render(image, width: width, height: height)
                let warp = align(fixed: lightroom, moving: picture)
                let moved = warp.apply(picture)
                aligned[name] = moved
                let fit = fitGain { ProfileColor.difference(measure(look.apply(moved, gain: Float(pow(2, $0))), box: box), lightroomLab) }
                print(String(format: "%-68@ %6.2f %6.2f %+7.2f   %@", name as NSString, fit.difference.median, fit.difference.p95, fit.ev, warp.text as NSString))
            }

            // The same Kelvin number through the system decoder and through ours (built-in look, both), as rendered.
            print("same white balance numbers, system decoder against ours (built-in matrix and look; blocks of 16 at 320, gain fitted):")
            let builtIn = CameraColorStep(color: color, channelScale: mosaic.channelScale)
            let ours = try demosaicer.run(mosaic, algorithm: .ha)
            let oursImage = HybridTiming.image(ours.output, flip: mosaic.flip)
            for kelvin in [2800.0, 4000, 5500, 7500] {
                var adjustments = Adjustments()
                adjustments.whiteBalance = WhiteBalance(preset: .custom, temperature: kelvin, tint: 0)
                guard let systemImage = try? PreviewGenerator().image(source: rawURL, stack: adjustments.editStack, longEdge: longEdge * 2) else { continue }
                let s = ProfileRender.render(systemImage, width: width, height: height)
                let o = ProfileRender.render(builtIn.apply(to: oursImage, temperature: kelvin, tint: 0), width: width, height: height)
                let warp = align(fixed: s, moving: o)
                let moved = warp.apply(o)
                let sLab = measure(s, box: box)
                let fit = fitGain { ProfileColor.difference(measure(moved.scaled(by: Float(pow(2, $0))), box: box), sLab) }
                // The mean chroma of each (how warm or cold the whole picture is).
                func meanAB(_ labs: [SIMD3<Double>]) -> SIMD2<Double> { labs.reduce(SIMD2(0, 0)) { $0 + SIMD2($1.y, $1.z) } / Double(labs.count) }
                let ms = meanAB(sLab), mo = meanAB(measure(moved.scaled(by: Float(pow(2, fit.ev))), box: box))
                print(String(format: "  %5.0f K: ΔE median %.2f, p95 %.2f, gain %+.2f EV; mean a*, b*: system %+.1f %+.1f, ours %+.1f %+.1f",
                             kelvin, fit.difference.median, fit.difference.p95, fit.ev, ms.x, ms.y, mo.x, mo.y))
            }
        }
        return [:]
    }
}
