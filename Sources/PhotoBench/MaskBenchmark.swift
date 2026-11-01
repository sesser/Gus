import CoreImage
import Darwin
import Foundation
import PhotoCore
import PhotoFixtures

/// Local adjustments on a 24-megapixel RAW file (docs/PHASE6_PLAN.md,
/// "Performance"): live frames at the loupe's size with zero to three masks,
/// what each mask's modules cost, brush rasterization alone, memory, and the
/// stack's encoded size and hashing time while a brush stroke is painted.
enum MaskBenchmark {
    static func run(_ arguments: Arguments) async throws -> [String: any Sendable] {
        let (width, height) = arguments.size("size", default: (6000, 4000))
        let frames = arguments.int("frames", default: 20)
        let folder = FileManager.default.temporaryDirectory.appending(path: "mask-bench-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "bench.dng")
        try SyntheticDNG.write(to: url, options: .init(width: width, height: height, seed: 5))
        print("Source: synthetic DNG \(width) × \(height); live frames at \(PreviewTier.preview.longEdge) px, "
              + "\(frames) frames each")
        let generator = PreviewGenerator(engine: RenderEngine(contextCount: 2, name: "mask-bench"))

        var global = Adjustments()
        global.exposure.ev = 0.3
        global.tone = Tone(contrast: 15, highlights: -30, shadows: 25)
        global.presence = Presence(clarity: 15, vibrance: 20)
        global.sharpen = Sharpen(amount: 40)

        let shapes: [MaskShape] = [
            .linear(LinearGradient(start: MaskPoint(x: 0.5, y: 0), end: MaskPoint(x: 0.5, y: 0.5))),
            .radial(RadialGradient(center: MaskPoint(x: 0.4, y: 0.6), radiusX: 0.25, radiusY: 0.18, rotation: 20)),
            .brush(brush(strokes: 20)),
        ]
        func masked(_ count: Int, _ values: (inout LocalValues) -> Void) -> Adjustments {
            var adjustments = global
            var local = LocalValues()
            values(&local)
            adjustments.local.masks = shapes.prefix(count).map { Mask(components: [MaskComponent($0)], adjustments: local) }
            return adjustments
        }
        let typical: (inout LocalValues) -> Void = {
            $0.exposure = 0.5
            $0.contrast = 20
            $0.clarity = 30
        }

        var report: [String: any Sendable] = ["machine": machineDescription(), "width": width, "height": height]
        var live: [String: any Sendable] = [:]
        /// Frames while one local slider moves. `caches` keeps the session's
        /// stages; `adaptive` lets it draft (interactive frames); otherwise every
        /// frame is full size. `mask` is the one whose slider moves.
        func time(_ name: String, _ adjustments: Adjustments, longEdge: Int = PreviewTier.preview.longEdge,
                  caches: Bool = true, adaptive: Bool = false, mask: Int = 0) async throws {
            let session = LiveRenderSession(source: url, generator: generator, longEdge: longEdge, colorSpace: nil,
                                            cachesStages: caches)
            let first = try await measure { _ = try await session.render(adjustments) }.1.milliseconds
            var values = adjustments
            var samples: [Double] = []
            var scales: [Double: Int] = [:]
            for frame in 0..<frames {
                if values.local.masks.indices.contains(mask) {
                    values.local.masks[mask].adjustments.exposure = 0.5 + Double(frame) * 0.02
                } else {
                    values.exposure.ev = 0.3 + Double(frame) * 0.01
                }
                let (rendered, duration) = try await measure { try await session.render(values, interactive: adaptive) }
                samples.append(duration.milliseconds)
                scales[rendered.scale, default: 0] += 1
            }
            let stats = Stats(samples)
            let scaleText = scales.keys.sorted(by: >).map { "\($0 == 1 ? "full" : $0 == 0.5 ? "½" : "¼") ×\(scales[$0]!)" }
                .joined(separator: ", ")
            print("  \(name.padding(toLength: 44, withPad: " ", startingAt: 0)) first \(String(format: "%6.1f", first)) ms  "
                  + "\(stats.line)  [\(scaleText)]")
            var entry = stats.dictionary
            entry["first_ms"] = first
            entry["scales"] = scales.map { ["scale": $0.key, "frames": $0.value] as [String: any Sendable] }
            live[name] = entry
        }
        print("\nLive frames at \(PreviewTier.preview.longEdge) px (a local slider moves each frame; masks: linear, "
              + "radial, brush of 20 strokes; times include the GPU, read-back and histogram):")
        try await time("global only", global, caches: false)
        for count in 1...3 {
            try await time("\(count) mask(s), whole", masked(count, typical), caches: false)
        }
        print("  Three masks with exposure, contrast and clarity:")
        try await time("whole, first mask moves", masked(3, typical), caches: false, mask: 0)
        try await time("whole, last mask moves", masked(3, typical), caches: false, mask: 2)
        try await time("cached, first mask moves", masked(3, typical), mask: 0)
        try await time("cached, last mask moves", masked(3, typical), mask: 2)
        try await time("cached + adaptive drafts, first mask moves", masked(3, typical), adaptive: true, mask: 0)
        try await time("cached + adaptive drafts, last mask moves", masked(3, typical), adaptive: true, mask: 2)
        try await time("cached, forced ½ (1280 px), first mask moves", masked(3, typical), longEdge: 1280, mask: 0)
        // Where the time goes: three masks with one kind of local value each, cached, last mask moving.
        print("  Three masks, one kind of local value each (cached, last mask moves):")
        for (name, values) in [
            ("exposure only", { (v: inout LocalValues) in v.exposure = 0.5 }),
            ("contrast only", { (v: inout LocalValues) in v.contrast = 20 }),
            ("clarity only", { (v: inout LocalValues) in v.clarity = 30 }),
            ("shadows only (local tone)", { (v: inout LocalValues) in v.shadows = 30 }),
            ("dehaze only", { (v: inout LocalValues) in v.dehaze = 30 }),
        ] as [(String, (inout LocalValues) -> Void)] {
            try await time(name, masked(3, values), mask: 2)
        }
        report["live"] = live

        // Does a frame's time include the GPU's work? `createCGImage` returns a
        // bitmap already filled: reading its bytes afterwards costs a copy, not a render.
        let check = LiveRenderSession(source: url, generator: generator, colorSpace: nil, cachesStages: false)
        _ = try await check.render(masked(3, typical))
        var probe = masked(3, typical)
        probe.local.masks[2].adjustments.exposure = 0.9
        let (frame, total) = try await measure { try await check.render(probe) }
        let (_, read) = await measure {
            if let data = frame.image.cgImage.dataProvider?.data, let bytes = CFDataGetBytePtr(data) {
                var sum = 0
                for i in stride(from: 0, to: CFDataGetLength(data), by: 4096) { sum &+= Int(bytes[i]) }
                _ = sum
            }
        }
        print("\nCompletion: a whole frame took \(String(format: "%.1f", total.milliseconds)) ms (its own measure "
              + "\(String(format: "%.1f", frame.seconds * 1000)) ms); touching its pixels afterwards "
              + "\(String(format: "%.2f", read.milliseconds)) ms")
        report["completion"] = ["frame_ms": total.milliseconds, "read_ms": read.milliseconds]

        // Brush rasterization alone, uncached, at the loupe's size and in full.
        print("\nBrush rasterization (20 strokes, CPU, parallel):")
        let previewHeight = Int((Double(height) * 2560 / Double(max(width, height))).rounded())
        var raster: [String: any Sendable] = [:]
        for (name, size) in [("preview", (2560, previewHeight)), ("full", (width, height))] {
            var samples: [Double] = []
            for run in 0..<5 {
                let strokes = brush(strokes: 20, seed: UInt64(run))
                samples.append(await measure { _ = BrushRasterizer.rasterize(strokes, width: size.0, height: size.1) }.1.milliseconds)
            }
            let stats = Stats(samples)
            print("  \(name) \(size.0) × \(size.1): \(stats.line)")
            raster[name] = stats.dictionary
        }
        report["rasterize"] = raster

        // A full-size render with three masks, for memory.
        let before = footprint()
        let (_, exportTime) = try await measure {
            _ = try generator.cgImage(source: url, stack: masked(3, typical).editStack, longEdge: nil)
        }
        let after = footprint()
        print("\nFull-size render with three masks: \(String(format: "%.0f", exportTime.milliseconds)) ms; "
              + "physical footprint \(formatBytes(before)) before, \(formatBytes(after)) after; "
              + "brush cache \(formatBytes(Int64(BrushRasterizer.cachedBytes)))")
        report["export_ms"] = exportTime.milliseconds
        report["footprint_before"] = before
        report["footprint_after"] = after

        // Painting: the stack's size and the time to encode and hash it as a stroke grows.
        print("\nPainting (points thinned at a tenth of the radius; encode = JSON for the catalog, hash = render hash):")
        var painting: [[String: any Sendable]] = []
        var adjustments = global
        adjustments.local.masks = [Mask(components: [MaskComponent(.brush(Brush()))], adjustments: {
            var v = LocalValues()
            v.exposure = 0.5
            return v
        }())]
        var stroke = BrushStroke(size: 0.02)
        var random = SplitMix64(seed: 3)
        var position = (x: 0.5, y: 0.5)
        var offered = 0
        for target in [100, 1_000, 10_000, 50_000] {
            while stroke.points.count < target {
                // A wandering pointer, a few pixels per event at the loupe's size.
                position.x = min(max(position.x + (Double(random.next() % 2001) / 1000 - 1) * 0.002, 0), 1)
                position.y = min(max(position.y + (Double(random.next() % 2001) / 1000 - 1) * 0.002, 0), 1)
                stroke.record(MaskPoint(x: position.x, y: position.y), aspect: Double(width) / Double(height))
                offered += 1
            }
            adjustments.local.masks[0].components[0] = MaskComponent(.brush(Brush(strokes: [stroke])))
            let stack = adjustments.editStack
            var encodes: [Double] = [], hashes: [Double] = []
            var bytes = 0
            for _ in 0..<5 {
                encodes.append(try await measure { bytes = try stack.jsonData().count }.1.milliseconds)
                hashes.append(await measure { _ = stack.renderHash }.1.milliseconds)
            }
            let line = "  \(target) points (of \(offered) samples): \(formatBytes(Int64(bytes))), encode "
                + String(format: "%.2f", Stats(encodes).percentile(0.5)) + " ms, hash "
                + String(format: "%.2f", Stats(hashes).percentile(0.5)) + " ms"
            print(line)
            painting.append(["points": target, "samples": offered, "bytes": bytes,
                             "encode_ms": Stats(encodes).percentile(0.5), "hash_ms": Stats(hashes).percentile(0.5)])
        }
        report["painting"] = painting
        return report
    }

    /// `strokes` soft strokes of 12 samples each across the frame.
    static func brush(strokes: Int, seed: UInt64 = 1) -> Brush {
        var random = SplitMix64(seed: seed)
        func unit() -> Double { Double(random.next() % 10_000) / 10_000 }
        return Brush(strokes: (0..<strokes).map { _ in
            var x = unit(), y = unit()
            let points = (0..<12).map { _ in
                x = min(max(x + (unit() - 0.5) * 0.08, 0), 1)
                y = min(max(y + (unit() - 0.5) * 0.08, 0), 1)
                return MaskPoint(x: x, y: y)
            }
            return BrushStroke(points: points, size: 0.02 + unit() * 0.04, feather: 60, flow: 70)
        })
    }

    /// The process's physical footprint, as Activity Monitor's Memory column.
    static func footprint() -> Int64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Int64(info.phys_footprint) : 0
    }
}
