import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import PhotoCore
import UniformTypeIdentifiers

/// The system's RAW decoder against LibRaw (issue #161): decode plus render
/// to 8-bit sRGB at full size, time and memory-free difference at a small
/// size. LibRaw's output is linear with no tone curve, Apple's has its
/// baseline exposure and tone mapping, so the difference is first of all one
/// of look; `meanLuma` and the written PNGs show it.
///
/// Each time is given twice: the first run and the best of `--runs`. The
/// runs share one `CIContext`, so the system decoder's best is a warm run
/// (what it prepared for the file is reused) and far below its first; the
/// first run of the first file also pays for setting the context up, so it
/// is not a cold decode either. LibRaw runs on the CPU and its two figures
/// are close.
///
/// `photobench rawcompare --files a.RAF:b.RW2 [--output DIR] [--runs N]`
enum RawCompareBenchmark {
    static func run(_ arguments: Arguments) async throws -> [String: any Sendable] {
        let files = (arguments.values["files"] ?? "").split(separator: ":")
            .map { URL(fileURLWithPath: (String($0) as NSString).expandingTildeInPath) }
        guard !files.isEmpty else { throw BenchError("rawcompare needs --files a.RAF:b.RW2") }
        let runs = arguments.int("runs", default: 3)
        let output = arguments.values["output"].map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
        if let output { try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true) }
        let context = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearITUR_2020)!])
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

        var rows: [[String: any Sendable]] = []
        for file in files {
            var row: [String: any Sendable] = ["file": file.lastPathComponent]
            func time(_ body: () throws -> CGImage?) rethrows -> (first: Double, best: Double, image: CGImage?) {
                var first = Double.infinity, best = Double.infinity
                var image: CGImage?
                for run in 0..<max(runs, 1) {
                    let start = DispatchTime.now()
                    image = try body()
                    let seconds = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1e9
                    if run == 0 { first = seconds }
                    best = min(best, seconds)
                }
                return (first, best, image)
            }
            func describe(_ timed: (first: Double, best: Double, image: CGImage?)) -> String? {
                timed.image.map { "\($0.width)x\($0.height), first run \(fmt(timed.first)) s, best of \(max(runs, 1)) \(fmt(timed.best)) s" }
            }
            let system = time {
                guard let image = PreviewGenerator.systemRAWImage(file) else { return nil }
                return context.createCGImage(image, from: image.extent, format: .RGBA8, colorSpace: srgb)
            }
            var libError: String?
            let full = time {
                do {
                    let decoded = try LibRawDecoder.decode(file)
                    return context.createCGImage(decoded.image, from: decoded.image.extent, format: .RGBA8, colorSpace: srgb)
                } catch { libError = "\(error)"; return nil }
            }
            let half = time {
                guard let decoded = try? LibRawDecoder.decode(file, halfSize: true) else { return nil }
                return context.createCGImage(decoded.image, from: decoded.image.extent, format: .RGBA8, colorSpace: srgb)
            }
            row["system"] = describe(system) ?? "no image"
            row["libraw"] = describe(full) ?? "no image: \(libError ?? "?")"
            row["librawHalf"] = describe(half) ?? "no image"

            if let a = system.image, let b = full.image {
                let pa = small(a), pb = small(b)
                row["meanLumaSystem"] = fmt(luma(pa)); row["meanLumaLibRaw"] = fmt(luma(pb))
                row["meanAbsDiff(0-255)"] = fmt(meanAbsDiff(pa, pb))
            }
            if let output {
                for (name, image) in [("system", system.image), ("libraw", full.image)] {
                    guard let image, let thumb = scaled(image, longEdge: 1600) else { continue }
                    let url = output.appending(path: "\(file.deletingPathExtension().lastPathComponent)-\(name).png")
                    if let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) {
                        CGImageDestinationAddImage(destination, thumb, nil)
                        CGImageDestinationFinalize(destination)
                    }
                }
            }
            print(row.sorted { $0.key < $1.key }.map { "  \($0.key): \($0.value)" }.joined(separator: "\n"), "\n")
            rows.append(row)
        }
        return ["machine": machineDescription(), "runs": runs, "files": rows]
    }

    private static func fmt(_ value: Double) -> String { String(format: "%.2f", value) }

    private static func scaled(_ image: CGImage, longEdge: Int) -> CGImage? {
        let scale = Double(longEdge) / Double(max(image.width, image.height))
        let width = max(1, Int(Double(image.width) * scale)), height = max(1, Int(Double(image.height) * scale))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    /// 256 x 171 RGBA bytes, a fixed grid so two decodes of one frame line up.
    private static func small(_ image: CGImage) -> [UInt8] {
        let width = 256, height = 171
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return bytes
    }

    private static func luma(_ bytes: [UInt8]) -> Double {
        var sum = 0.0
        for index in stride(from: 0, to: bytes.count, by: 4) {
            sum += 0.2126 * Double(bytes[index]) + 0.7152 * Double(bytes[index + 1]) + 0.0722 * Double(bytes[index + 2])
        }
        return sum / Double(bytes.count / 4)
    }

    private static func meanAbsDiff(_ a: [UInt8], _ b: [UInt8]) -> Double {
        var sum = 0.0, count = 0
        for index in 0..<min(a.count, b.count) where index % 4 != 3 {
            sum += abs(Double(a[index]) - Double(b[index])); count += 1
        }
        return sum / Double(max(count, 1))
    }
}
