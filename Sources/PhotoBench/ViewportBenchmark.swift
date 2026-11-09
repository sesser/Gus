import CoreGraphics
import Foundation
import PhotoCore
import PhotoFixtures

/// Live frames at 100% (docs/features/viewport-render-1to1): the region of a
/// full-resolution render the loupe shows, on a synthetic raw (default
/// 6000 × 4000), typical stack and three masks, against the whole frames the
/// loupe uses below 100%, for the canvases given with `--windows`. Times
/// include the GPU and reading the pixels back.
enum ViewportBenchmark {
    static func run(_ arguments: Arguments) async throws -> [String: any Sendable] {
        let (width, height) = arguments.size("size", default: (6000, 4000))
        let frames = arguments.int("frames", default: 60)
        let folder = FileManager.default.temporaryDirectory.appending(path: "viewport-bench-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "bench.dng")
        try SyntheticDNG.write(to: url, options: .init(width: width, height: height, seed: 5))
        print("Source: synthetic DNG \(width) × \(height), \(frames) frames per case.")
        let generator = PreviewGenerator().withEngine(.interactive())
        var report: [String: any Sendable] = ["machine": machineDescription(), "width": width, "height": height]

        // The regions to measure: `--windows WxH[,WxH…]` (the loupe's canvas in
        // pixels), or the two kept for comparison. Capped by the photo, as at 100%.
        let requested = arguments.values["windows"]?.split(separator: ",").compactMap { spec -> (String, Int, Int)? in
            let parts = spec.split(separator: "x").compactMap { Int($0) }
            return parts.count == 2 ? ("\(spec) canvas", parts[0], parts[1]) : nil
        }
        let windows = (requested ?? [("3024x1800, built-in display", 3024, 1800), ("3872x2592, about 10 MP", 3872, 2592)])
            .map { (name: $0.0, width: min($0.1, width), height: min($0.2, height)) }

        func unit(_ w: Int, _ h: Int) -> CGRect {
            CGRect(x: Double(width - w) / 2 / Double(width), y: Double(height - h) / 2 / Double(height),
                   width: Double(w) / Double(width), height: Double(h) / Double(height))
        }

        print("\nPrepare (decode at full resolution and render to the GPU texture):")
        var prepared: [Double] = []
        var heldBytes = 0
        for _ in 0..<3 {
            let renderer = LiveRegionRenderer(source: url, generator: generator, colorSpace: nil)
            let duration = try await measure { try await renderer.prepare(EditBenchmark.typical) }.1
            prepared.append(duration.milliseconds)
            heldBytes = await renderer.baseByteCount
            await renderer.purge()
        }
        print("  \(Stats(prepared).line); holds \(formatBytes(Int64(heldBytes)))")
        report["prepare"] = Stats(prepared).dictionary
        report["texture_bytes"] = heldBytes

        for window in windows {
            let label = "\(window.name), \(window.width) × \(window.height) (\(String(format: "%.1f", Double(window.width * window.height) / 1_000_000)) MP)"
            print("\nRegion: \(label)")
            let before = MaskBenchmark.footprint()
            let renderer = LiveRegionRenderer(source: url, generator: generator, colorSpace: nil)
            try await renderer.prepare(EditBenchmark.typical)
            let region = unit(window.width, window.height)
            let cases: [(String, Adjustments, @Sendable (Int, inout Adjustments) -> Void)] = [
                ("typical stack, Exposure moves", EditBenchmark.typical, { f, v in v.exposure.ev = 0.4 + Double(f) * 0.02 }),
                ("typical stack, Amount moves", EditBenchmark.typical, { f, v in v.sharpen.amount = 40 + Double(f) }),
                ("typical stack, Saturation moves", EditBenchmark.typical, { f, v in v.presence.saturation = 5 + Double(f) }),
                ("typical stack, Shadows moves", EditBenchmark.typical, { f, v in v.tone.shadows = 25 + Double(f) * 0.5 }),
                ("three masks, first mask's Exposure moves", maskStack(width: width, height: height), { f, v in
                    v.local.masks[0].adjustments.exposure = 0.5 + Double(f) * 0.02
                }),
                ("three masks, last mask's Exposure moves", maskStack(width: width, height: height), { f, v in
                    v.local.masks[2].adjustments.exposure = 0.5 + Double(f) * 0.02
                }),
            ]
            var entry: [String: any Sendable] = [:]
            for (name, start, change) in cases {
                var values = start
                try await renderer.prepare(values)
                let first = try await measure { () -> Void in
                    let frame = try await renderer.render(values, unit: region)
                    touch(frame.image.cgImage)
                }.1
                var samples: [Double] = []
                for frame in 0..<frames {
                    change(frame, &values)
                    let (_, duration) = try await measure { () -> Void in
                        let rendered = try await renderer.render(values, unit: region)
                        touch(rendered.image.cgImage)
                    }
                    samples.append(duration.milliseconds)
                }
                let stats = Stats(samples)
                print("  \(name.padding(toLength: 42, withPad: " ", startingAt: 0)) first \(String(format: "%6.1f", first.milliseconds)) ms  \(stats.line)")
                var caseEntry = stats.dictionary
                caseEntry["first_ms"] = first.milliseconds
                entry[name] = caseEntry
            }
            let after = MaskBenchmark.footprint()
            print("  physical footprint \(formatBytes(before)) → \(formatBytes(after))")
            entry["footprint_before"] = before
            entry["footprint_after"] = after
            report[window.name] = entry
            await renderer.purge()
        }

        // R4: a new RAW decode setting at full resolution (a white balance change, once input pauses).
        print("\nRaw white balance, new value at full resolution (decode + texture, then one frame of the largest region):")
        let renderer = LiveRegionRenderer(source: url, generator: generator, colorSpace: nil)
        var decodes: [Double] = [], framesAfter: [Double] = []
        for step in 0..<5 {
            var values = EditBenchmark.typical
            values.whiteBalance = WhiteBalance(preset: .custom, temperature: 4000 + Double(step) * 500, tint: 0)
            decodes.append(try await measure { try await renderer.prepare(values) }.1.milliseconds)
            let region = windows.first.map { unit($0.width, $0.height) } ?? CGRect(x: 0, y: 0, width: 1, height: 1)
            framesAfter.append(try await measure { () -> Void in
                touch(try await renderer.render(values, unit: region).image.cgImage)
            }.1.milliseconds)
        }
        print("  decode \(Stats(decodes).line)")
        print("  frame  \(Stats(framesAfter).line)")
        report["white_balance_decode"] = Stats(decodes).dictionary
        report["white_balance_frame"] = Stats(framesAfter).dictionary
        await renderer.purge()

        // E4: letting go, today. The loupe's sharp render after a save: a
        // whole 24 MP frame through the generator, then its first read
        // (Core Animation pays for the deferred render when it draws it).
        print("\nToday's full-resolution render of the whole photo, with its pixels read (E4's baseline):")
        var fulls: [Double] = []
        for _ in 0..<5 {
            let duration = try await measure { () -> Void in
                let image = try generator.cgImage(source: url, stack: EditBenchmark.typical.editStack)
                touch(image)
            }.1
            fulls.append(duration.milliseconds)
        }
        print("  \(Stats(fulls).line)")
        report["full_render_ms"] = Stats(fulls).dictionary
        return report
    }

    /// `photobench masks`'s three masks with exposure, contrast and clarity.
    static func maskStack(width: Int, height: Int) -> Adjustments {
        var values = Adjustments()
        values.exposure.ev = 0.3
        values.tone = Tone(contrast: 15, highlights: -30, shadows: 25)
        values.presence = Presence(clarity: 15, vibrance: 20)
        values.sharpen = Sharpen(amount: 40)
        var local = LocalValues()
        local.exposure = 0.5
        local.contrast = 20
        local.clarity = 30
        let shapes: [MaskShape] = [
            .linear(LinearGradient(start: MaskPoint(x: 0.5, y: 0), end: MaskPoint(x: 0.5, y: 0.5))),
            .radial(RadialGradient(center: MaskPoint(x: 0.4, y: 0.6), radiusX: 0.25, radiusY: 0.18, rotation: 20)),
            .brush(MaskBenchmark.brush(strokes: 20)),
        ]
        values.local.masks = shapes.map { Mask(components: [MaskComponent($0)], adjustments: local) }
        return values
    }

    /// Reads every row, so a bitmap is paid for inside the measurement.
    static func touch(_ image: CGImage) {
        guard let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return }
        var sum: UInt64 = 0
        for offset in stride(from: 0, to: CFDataGetLength(data), by: max(1, image.bytesPerRow / 16)) {
            sum &+= UInt64(bytes[offset])
        }
        guard sum != 0 else { return }
    }
}
