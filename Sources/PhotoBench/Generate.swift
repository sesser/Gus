import Foundation
import PhotoFixtures
import UniformTypeIdentifiers

/// Writes a synthetic shoot: JPEGs, Bayer DNGs and HEICs spread over folders,
/// with increasing capture times and unique pixels per file, plus optional
/// RAW+JPEG pairs (a DNG and a JPEG with the same name and capture time).
enum Generate {
    static func run(_ arguments: Arguments) async throws -> [String: any Sendable] {
        let output = try arguments.url("output")
        let jpegCount = arguments.int("jpeg", default: 9_800)
        let dngCount = arguments.int("dng", default: 100)
        let heicCount = arguments.int("heic", default: 100)
        let pairCount = arguments.int("pairs", default: 0)
        let videoCount = arguments.int("videos", default: 0)
        let videoSeconds = Double(arguments.int("video-seconds", default: 10))
        let perFolder = max(1, arguments.int("per-folder", default: 500))
        let jpegSize = arguments.size("jpeg-size", default: (2048, 1365))
        let dngSize = arguments.size("dng-size", default: (6000, 4000))
        let heicSize = arguments.size("heic-size", default: (4032, 3024))

        enum Kind { case jpeg, dng, heic, pair }
        var plan: [(Kind, Int)] = []
        plan += (0..<jpegCount).map { (.jpeg, $0) }
        plan += (0..<dngCount).map { (.dng, $0) }
        plan += (0..<heicCount).map { (.heic, $0) }
        plan += (0..<pairCount).map { (.pair, $0) }
        let jobs = plan

        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        let dates = (0..<jobs.count).map { formatter.string(from: base.addingTimeInterval(Double($0) * 7)) }

        let failures = Counter()
        let (_, elapsed) = await measure {
            DispatchQueue.concurrentPerform(iterations: jobs.count) { index in
                let (kind, number) = jobs[index]
                let folder = output.appending(path: String(format: "Shoot-%03d", index / perFolder + 1))
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let seed = UInt64(index) &* 2_654_435_761 &+ 17
                do {
                    switch kind {
                    case .jpeg:
                        let url = folder.appending(path: String(format: "IMG_%05d.JPG", index + 1))
                        // Every fifth photo is portrait, with the orientation in EXIF.
                        let orientation = number % 5 == 0 ? 6 : 1
                        try SyntheticImages.writeJPEG(to: url, width: jpegSize.0, height: jpegSize.1, seed: seed,
                                                      exif: .init(dateTimeOriginal: dates[index], orientation: orientation),
                                                      quality: 0.85)
                    case .dng:
                        let url = folder.appending(path: String(format: "RAW_%05d.DNG", index + 1))
                        try SyntheticDNG.write(to: url, options: .init(width: dngSize.0, height: dngSize.1, seed: seed,
                                                                       dateTimeOriginal: dates[index]))
                    case .heic:
                        let url = folder.appending(path: String(format: "IMG_%05d.HEIC", index + 1))
                        guard let image = SyntheticImages.makeImage(width: heicSize.0, height: heicSize.1, seed: seed) else {
                            throw BenchError("could not render HEIC source")
                        }
                        try SyntheticImages.write(image, to: url, type: .heic,
                                                  exif: .init(dateTimeOriginal: dates[index]), quality: 0.8)
                    case .pair:
                        let stem = String(format: "PAIR_%05d", index + 1)
                        try SyntheticDNG.write(to: folder.appending(path: stem + ".DNG"),
                                               options: .init(width: dngSize.0, height: dngSize.1, seed: seed,
                                                              dateTimeOriginal: dates[index]))
                        try SyntheticImages.writeJPEG(to: folder.appending(path: stem + ".JPG"),
                                                      width: jpegSize.0, height: jpegSize.1, seed: seed,
                                                      exif: .init(dateTimeOriginal: dates[index]), quality: 0.85)
                    }
                } catch {
                    failures.increment()
                }
            }
        }
        // Videos are written one after another (AVAssetWriter is asynchronous).
        for index in 0..<videoCount {
            let folder = output.appending(path: String(format: "Shoot-%03d", (jobs.count + index) / perFolder + 1))
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let created = ISO8601DateFormatter().string(from: base.addingTimeInterval(Double(jobs.count + index) * 7))
            do {
                try await SyntheticVideo.write(to: folder.appending(path: String(format: "MVI_%05d.MOV", jobs.count + index + 1)),
                                               options: .init(width: 1280, height: 720, seconds: videoSeconds, framesPerSecond: 5,
                                                              seed: UInt64(index) &* 7919, creationDate: created))
            } catch {
                failures.increment()
            }
        }
        let bytes = folderSize(output)
        print("Generated \(jobs.count - failures.value) jobs (\(jpegCount) JPEG, \(dngCount) DNG, \(heicCount) HEIC, \(pairCount) RAW+JPEG pairs) in \(String(format: "%.1f", elapsed.seconds)) s, \(formatBytes(bytes))")
        if failures.value > 0 { print("  \(failures.value) files failed") }
        return ["files": jobs.count - failures.value + pairCount, "jpeg": jpegCount, "dng": dngCount, "heic": heicCount,
                "pairs": pairCount,
                "seconds": elapsed.seconds, "bytes": bytes]
    }

    static func folderSize(_ url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            total += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}
