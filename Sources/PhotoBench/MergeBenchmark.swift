import CoreImage
import Foundation
import ImageIO
import PhotoCore

/// HDR merge (issue #150) on real or synthetic brackets, without a library:
/// the time of each step, the plan it measured, the peak memory, and the
/// files it writes (status.md spikes 2 to 4).
enum MergeBenchmark {
    static func run(_ arguments: Arguments) async throws -> [String: any Sendable] {
        guard let list = arguments.values["files"] else { throw BenchError("missing --files") }
        let urls = list.split(separator: ":").map { URL(fileURLWithPath: (String($0) as NSString).expandingTildeInPath) }
        guard urls.count >= 2 else { throw BenchError("--files needs at least two files") }
        let output = try arguments.url("output")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let formats: [MergeFormat] = switch arguments.values["format"] ?? "tiff" {
        case "dng": [.dng]
        case "both": [.tiff, .dng]
        default: [.tiff]
        }
        let properties = urls.map(MergeOutput.Metadata.properties(of:))
        let reference = arguments.values["reference"].flatMap(Int.init) ?? referenceIndex(properties)
        let clock = ContinuousClock()
        var report: [String: any Sendable] = ["frames": urls.map(\.lastPathComponent), "reference": reference]
        func ms(_ duration: Duration) -> Double {
            Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
        }
        let start = footprint()
        print("start footprint \(start.current / 1_000_000) MB")

        let merger = HDRMerger()
        if arguments.flags.contains("experiment") {
            for (index, url) in urls.enumerated() {
                autoreleasepool {
                    let ctx = CIContext(options: [.workingColorSpace: RenderEngine.workingColorSpace,
                                                  .workingFormat: CIFormat.RGBAf, .cacheIntermediates: false])
                    let image = try! MergeDecoder.linearImage(url, source: MergeDecoder.source(of: url), longEdge: 2048)
                    print("decoded \(index): \(footprint().current / 1_000_000) MB")
                    _ = MergeBitmap.render(image, context: arguments.flags.contains("own") ? ctx : merger.context)
                    print("rendered \(index): \(footprint().current / 1_000_000) MB")
                }
                print("released \(index): \(footprint().current / 1_000_000) MB")
            }
            return [:]
        }
        var mark = clock.now
        let sources = urls.map(MergeDecoder.source(of:))
        let copies = try urls.enumerated().map { index, url in
            try merger.measuringCopy(of: url, source: sources[index])
        }
        print("copies rendered: footprint \(footprint().current / 1_000_000) MB peak \(footprint().peak / 1_000_000)")
        report["decoders"] = sources.map(\.rawValue)
        let metadata = properties.map { props -> Double? in
            let exif = props[kCGImagePropertyExifDictionary as String] as? [String: any Sendable] ?? [:]
            return MergeExposure.metadataExposure(time: exif[kCGImagePropertyExifExposureTime as String] as? Double,
                                                  fNumber: exif[kCGImagePropertyExifFNumber as String] as? Double,
                                                  iso: (exif[kCGImagePropertyExifISOSpeedRatings as String] as? [any Sendable])?
                                                      .first.flatMap { $0 as? Int64 }.map(Int.init))
        }
        let options = MergeOptions(align: !arguments.flags.contains("no-align"),
                                   deghost: !arguments.flags.contains("no-deghost"))
        report["align"] = options.align
        report["deghost"] = options.deghost
        let plan = try merger.plan(measuring: copies, reference: reference, metadataExposures: metadata,
                                   options: options)
        let planTime = clock.now - mark
        mark = clock.now
        let full = try urls.enumerated().map { index, url in try merger.fullFrame(of: url, source: sources[index]) }
        report["fullDecodeMilliseconds"] = ms(clock.now - mark)
        report["size"] = "\(Int(full[reference].extent.width))x\(Int(full[reference].extent.height))"
        print("full frames held: \(Int(ms(clock.now - mark))) ms, footprint \(footprint().current / 1_000_000) MB peak \(footprint().peak / 1_000_000)")
        report["planMilliseconds"] = ms(planTime)
        report["exposures"] = plan.frames.map(\.exposure)
        report["metadataExposures"] = metadata.map { m in m.map { $0 / (metadata[reference] ?? 1) } ?? -1 }
        report["clips"] = plan.frames.map(\.clip)
        report["rotations"] = plan.frames.map(\.homography.rotationDegrees)
        report["shiftsOnCopy"] = plan.frames.map { $0.homography.shift(of: plan.measureSize) }
        report["ghostFractions"] = plan.ghosts.map { plane in
            Double(plane.values.reduce(0, +)) / Double(max(1, plane.values.count))
        }
        report["toneMap"] = ["compression": plan.toneMap.compression, "top": plan.toneMap.top]
        print("plan \(Int(ms(planTime))) ms; footprint \(footprint().current / 1_000_000) MB")

        let values = SidecarValues()
        let stem = urls[reference].deletingPathExtension().lastPathComponent
        for format in formats {
            mark = clock.now
            let radiance = try merger.radiance(plan, frames: full)
            let url = output.appending(path: "\(stem)_HDR.\(format.fileExtension)")
            try? FileManager.default.removeItem(at: url)
            let meta = MergeOutput.Metadata(sourceProperties: properties[reference], values: values)
            switch format {
            case .tiff:
                try MergeOutput.writeTIFF(try merger.toneMapped(plan, radiance: radiance), context: merger.context,
                                          metadata: meta, to: url)
            case .dng:
                try MergeOutput.writeDNG(radiance, context: merger.context, metadata: meta, to: url, brightest: plan.brightest)
            }
            let time = clock.now - mark
            print("after \(format): footprint \(footprint().current / 1_000_000) MB peak \(footprint().peak / 1_000_000)")
            report["\(format.rawValue)Milliseconds"] = ms(time)
            print("\(format.rawValue): \(Int(ms(time))) ms -> \(url.path)")
        }
        let end = footprint()
        report["peakFootprintMB"] = Double(end.peak) / 1_000_000
        report["startFootprintMB"] = Double(start.current) / 1_000_000
        for (key, value) in report.sorted(by: { $0.key < $1.key }) { print("\(key): \(value)") }
        return report
    }

    /// The frame at 0 EV compensation, else the earliest.
    static func referenceIndex(_ properties: [[String: any Sendable]]) -> Int {
        for (index, props) in properties.enumerated() {
            let exif = props[kCGImagePropertyExifDictionary as String] as? [String: any Sendable] ?? [:]
            if let bias = exif[kCGImagePropertyExifExposureBiasValue as String] as? Double, bias == 0 { return index }
            if let bias = exif[kCGImagePropertyExifExposureBiasValue as String] as? Int64, bias == 0 { return index }
        }
        return 0
    }

    static func footprint() -> (current: UInt64, peak: UInt64) {
        var info = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(getpid(), RUSAGE_INFO_V4, $0) }
        }
        guard result == 0 else { return (0, 0) }
        return (info.ri_phys_footprint, info.ri_lifetime_max_phys_footprint)
    }
}
