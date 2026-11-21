import CoreGraphics
import Foundation
import ImageIO
import PhotoFixtures
import Testing
import zlib
@testable import PhotoCore

extension MemoryHeavy {
    /// The merge's bounds against hostile or very large input (issue #150,
    /// security review M1, M2, L1, L7, L8).
    @Suite("HDR merge safety", .serialized)
    struct MergeSafetyTests {
        static func folder() throws -> URL {
            let url = FileManager.default.temporaryDirectory.appending(path: "merge-safety-\(UUID().uuidString)",
                                                                       directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }

        /// A real, flat gray PNG of `width` by `height` pixels: a few hundred
        /// kilobytes on disk for hundreds of megapixels (zlib packs the flat rows
        /// a thousand to one). ImageIO refuses a header whose data is too short,
        /// so the rows are all there.
        static func flatPNG(width: Int, height: Int) throws -> Data {
            func chunk(_ type: String, _ body: Data) -> Data {
                var data = Data()
                withUnsafeBytes(of: UInt32(body.count).bigEndian) { data.append(contentsOf: $0) }
                let typed = Data(type.utf8) + body
                data.append(typed)
                let crc = typed.withUnsafeBytes { UInt32(crc32(0, $0.bindMemory(to: UInt8.self).baseAddress, uInt(typed.count))) }
                withUnsafeBytes(of: crc.bigEndian) { data.append(contentsOf: $0) }
                return data
            }
            var row = [UInt8](repeating: 0x40, count: width * 3 + 1)
            row[0] = 0 // filter: none
            var stream = z_stream()
            guard deflateInit_(&stream, 9, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
                throw CocoaError(.fileWriteUnknown)
            }
            defer { deflateEnd(&stream) }
            var compressed = Data()
            var output = [UInt8](repeating: 0, count: 1 << 16)
            func pump(_ flush: Int32) {
                repeat {
                    output.withUnsafeMutableBufferPointer { buffer in
                        stream.next_out = buffer.baseAddress
                        stream.avail_out = uInt(buffer.count)
                        deflate(&stream, flush)
                        compressed.append(buffer.baseAddress!, count: buffer.count - Int(stream.avail_out))
                    }
                } while stream.avail_out == 0
            }
            for _ in 0..<height {
                row.withUnsafeMutableBufferPointer { buffer in
                    stream.next_in = buffer.baseAddress
                    stream.avail_in = uInt(buffer.count)
                    pump(Z_NO_FLUSH)
                }
            }
            stream.next_in = nil
            stream.avail_in = 0
            pump(Z_FINISH)
            var header = Data()
            withUnsafeBytes(of: UInt32(width).bigEndian) { header.append(contentsOf: $0) }
            withUnsafeBytes(of: UInt32(height).bigEndian) { header.append(contentsOf: $0) }
            header.append(contentsOf: [8, 2, 0, 0, 0])
            return Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) + chunk("IHDR", header)
                + chunk("IDAT", compressed) + chunk("IEND", Data())
        }

        static func frame(_ id: Int64, url: URL, size: CGSize?, second: Double) -> MergeFrame {
            MergeFrame(versionID: id, imageID: id, volumeID: 1, projectID: 1,
                       displayName: url.deletingPathExtension().lastPathComponent, fileName: url.lastPathComponent,
                       relativePath: "shoot/" + url.lastPathComponent, kind: FileKind(pathExtension: url.pathExtension),
                       isCopy: false, isOnline: true, url: url, pixelSize: size,
                       date: Date(timeIntervalSinceReferenceDate: second))
        }

        @Test("M1: frames over the pixel limit, or over the memory budget together, are refused in the sheet")
        func refusedBySize() {
            let huge = CGSize(width: 60000, height: 60000)
            let url = URL(fileURLWithPath: "/shoot/A.png")
            let selection = MergeSelection(frames: [Self.frame(1, url: url, size: huge, second: 1),
                                                    Self.frame(2, url: url.deletingLastPathComponent().appending(path: "B.png"),
                                                               size: huge, second: 2)])
            #expect(selection.refusal == .tooLarge(name: "A", megapixels: MergeLimits.maximumPixels / 1_000_000))
            #expect(selection.flagged == [1, 2])
            let normal = CGSize(width: 6000, height: 4000)
            let tight = MergeSelection(frames: [Self.frame(1, url: url, size: normal, second: 1),
                                                Self.frame(2, url: url, size: normal, second: 2)],
                                       memoryBudget: 6000 * 4000 * 8)
            #expect(tight.refusal == .tooMuchMemory)
            let roomy = MergeSelection(frames: [Self.frame(1, url: url, size: normal, second: 1),
                                                Self.frame(2, url: url, size: normal, second: 2)],
                                       memoryBudget: 2 * 6000 * 4000 * 8)
            #expect(roomy.refusal == nil)
        }

        @Test("M1: a tiny file claiming 180 megapixels is refused from its decoder's size, before any allocation")
        func refusedByHeader() async throws {
            let folder = try Self.folder()
            defer { try? FileManager.default.removeItem(at: folder) }
            let a = folder.appending(path: "A.png"), b = folder.appending(path: "B.png")
            let png = try Self.flatPNG(width: 15000, height: 12000)
            #expect(png.count < 1 << 20)
            try png.write(to: a)
            try png.write(to: b)
            #expect(throws: MergeDecoder.Failure.tooLarge(a)) {
                try MergeDecoder.linearImage(a, source: .imageIO, longEdge: MergeLimits.measureLongEdge)
            }
            // The catalog didn't know the size: the job finds it, writes nothing.
            let selection = MergeSelection(frames: [Self.frame(1, url: a, size: nil, second: 1),
                                                    Self.frame(2, url: b, size: nil, second: 2)])
            #expect(selection.refusal == nil)
            let job = HDRMergeJob(catalog: try Catalog.makeInMemory(), metadataReader: ImageIOMetadataReader())
            await #expect(throws: HDRMergeJob.Failure.tooLarge(name: "A")) {
                try await job.run(selection, format: .tiff)
            }
            #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted() == ["A.png", "B.png"])
        }

        @Test("M1: a frame whose pixels would pass the remaining budget is refused before they are held")
        func budgetBeforeHolding() throws {
            let folder = try Self.folder()
            defer { try? FileManager.default.removeItem(at: folder) }
            let url = folder.appending(path: "a.png")
            let image = HDRBracket.image(HDRBracket.Frame(ev: 0), width: 64, height: 48)
            try SyntheticImages.write(try #require(image.cgImage(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)),
                                      to: url, type: .png)
            let merger = HDRMerger()
            #expect(throws: HDRMerger.Failure.overBudget) {
                try merger.fullFrame(of: url, source: .imageIO, budget: 64 * 48 * 8 - 1)
            }
            #expect(try merger.fullFrame(of: url, source: .imageIO, budget: 64 * 48 * 8).extent.width == 64)
        }

        @Test("M2: a DNG past 4 GiB is refused before its file exists")
        func dngTooLarge() throws {
            let folder = try Self.folder()
            defer { try? FileManager.default.removeItem(at: folder) }
            let url = folder.appending(path: "big.dng")
            #expect(throws: LinearDNGWriter.Failure.tooLarge) {
                _ = try LinearDNGWriter(url: url, width: 40000, height: 30000, metadata: .init())
            }
            #expect(!FileManager.default.fileExists(atPath: url.path))
            #expect(LinearDNGWriter.fits(width: 12000, height: 12500, metadata: .init()))
        }

        @Test("L1: a name that fills the file system's limit is written; the result's stem is shortened to fit")
        func longNames() throws {
            let folder = try Self.folder()
            defer { try? FileManager.default.removeItem(at: folder) }
            // 255 bytes: the old hidden name (name + 46 bytes) could not have been made.
            let name = String(repeating: "a", count: 251) + ".tif"
            let url = folder.appending(path: name)
            try MergeOutput.writeInPlace(url) { try Data("x".utf8).write(to: $0) }
            #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == [name])
            let stem = String(repeating: "é", count: 125) // 250 bytes in UTF-8
            let result = MergeNaming.name(stem: stem, format: .tiff, masters: MasterFiles.none.names(in: folder), files: [])
            #expect(result.utf8.count <= 255)
            #expect(result.hasSuffix("_HDR.tif"))
            #expect(result.hasPrefix("éé"))
        }

        @Test("L7: only a file system without hard links falls back, and the fallback never replaces")
        func linkFallback() throws {
            let folder = try Self.folder()
            defer { try? FileManager.default.removeItem(at: folder) }
            func failing(_ code: Int32) -> (UnsafePointer<CChar>, UnsafePointer<CChar>) -> Int32 {
                { _, _ in code }
            }
            let a = folder.appending(path: "a.tif")
            #expect(throws: MergeOutput.Failure.self) {
                try MergeOutput.writeInPlace(a, linkFile: failing(EACCES)) { try Data("a".utf8).write(to: $0) }
            }
            #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
            try MergeOutput.writeInPlace(a, linkFile: failing(ENOTSUP)) { try Data("a".utf8).write(to: $0) }
            #expect(try String(contentsOf: a, encoding: .utf8) == "a")
            #expect(throws: MergeOutput.Failure.nameTaken) {
                try MergeOutput.writeInPlace(a, linkFile: failing(ENOTSUP)) { try Data("b".utf8).write(to: $0) }
            }
            #expect(try String(contentsOf: a, encoding: .utf8) == "a")
            #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["a.tif"])
            // C6: neither links nor an exclusive rename (FAT32, exFAT): a placeholder reserves the name.
            let b = folder.appending(path: "b.tif")
            try MergeOutput.writeInPlace(b, linkFile: failing(ENOTSUP), renameExclusive: failing(ENOTSUP)) {
                try Data("b".utf8).write(to: $0)
            }
            #expect(try String(contentsOf: b, encoding: .utf8) == "b")
            #expect(throws: MergeOutput.Failure.nameTaken) {
                try MergeOutput.writeInPlace(b, linkFile: failing(ENOTSUP), renameExclusive: failing(ENOTSUP)) {
                    try Data("c".utf8).write(to: $0)
                }
            }
            #expect(try String(contentsOf: b, encoding: .utf8) == "b")
            #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted() == ["a.tif", "b.tif"])
        }

        /// Runs `body` with a fresh FAT32 disk image (64 MB: FAT32 wants more than 32) attached at a folder of its
        /// own (CLAUDE.md: a FAT32 image stands in for a camera card); detached
        /// after. Nil when `hdiutil` can't make or attach one here.
        static func withFAT32(_ body: (URL) throws -> Void) throws -> Bool {
            let folder = try Self.folder()
            defer { try? FileManager.default.removeItem(at: folder) }
            let image = folder.appending(path: "card.dmg"), mount = folder.appending(path: "mount", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
            func hdiutil(_ arguments: [String]) -> Bool {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
                process.arguments = arguments
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice
                guard (try? process.run()) != nil else { return false }
                process.waitUntilExit()
                return process.terminationStatus == 0
            }
            guard hdiutil(["create", "-size", "64m", "-fs", "MS-DOS FAT32", "-volname", "MERGE", image.path]),
                  hdiutil(["attach", "-nobrowse", "-mountpoint", mount.path, image.path])
            else { return false }
            defer { _ = hdiutil(["detach", "-force", mount.path]) }
            try body(mount)
            return true
        }

        /// Whether `hdiutil` can make and attach a FAT32 image here (it can't on
        /// some CI runners): probed once, so the FAT32 test shows as skipped
        /// rather than passing without running (code review C10).
        static let canAttachFAT32: Bool = (try? withFAT32 { _ in }) ?? false

        @Test("C6: on a FAT32 volume the result is written beside the masters, and never replaces a file",
              .enabled(if: MergeSafetyTests.canAttachFAT32, "hdiutil can't make or attach a FAT32 image here"))
        func fat32() throws {
            let ran = try Self.withFAT32 { volume in
                let url = volume.appending(path: "IMG_1_HDR.tif")
                try MergeOutput.writeInPlace(url) { try Data("first".utf8).write(to: $0) }
                #expect(try String(contentsOf: url, encoding: .utf8) == "first")
                #expect(throws: MergeOutput.Failure.nameTaken) {
                    try MergeOutput.writeInPlace(url) { try Data("second".utf8).write(to: $0) }
                }
                #expect(try String(contentsOf: url, encoding: .utf8) == "first")
                let visible = try FileManager.default.contentsOfDirectory(atPath: volume.path).filter { !$0.hasPrefix(".") }
                #expect(visible == ["IMG_1_HDR.tif"])
                #expect(try FileManager.default.contentsOfDirectory(atPath: volume.path).allSatisfy { !$0.hasSuffix(".partial") })
            }
            #expect(ran, "hdiutil attached a probe image but not this one")
        }

        @Test("L8: a reference whose catalog name or path leaves its folder is refused")
        func plainPlaces() async throws {
            #expect(MergeNaming.isPlainPlace(fileName: "IMG_1.dng", relativePath: "Trip/Day 2/IMG_1.dng"))
            #expect(MergeNaming.isPlainPlace(fileName: "IMG_1.dng", relativePath: "IMG_1.dng"))
            #expect(!MergeNaming.isPlainPlace(fileName: "../IMG_1.dng", relativePath: "Trip/../IMG_1.dng"))
            #expect(!MergeNaming.isPlainPlace(fileName: "IMG_1.dng", relativePath: "Trip/../IMG_1.dng"))
            #expect(!MergeNaming.isPlainPlace(fileName: "IMG_1.dng", relativePath: "/Trip/IMG_1.dng"))
            #expect(!MergeNaming.isPlainPlace(fileName: "x/IMG_1.dng", relativePath: "Trip/x/IMG_1.dng"))
            #expect(!MergeNaming.isPlainPlace(fileName: "IMG_1.dng", relativePath: "Trip//IMG_1.dng"))
            var bad = Self.frame(1, url: URL(fileURLWithPath: "/shoot/A.dng"), size: nil, second: 1)
            bad.relativePath = "shoot/../../A.dng"
            let selection = MergeSelection(frames: [bad, Self.frame(2, url: URL(fileURLWithPath: "/shoot/B.dng"), size: nil,
                                                                   second: 2)])
            let job = HDRMergeJob(catalog: try Catalog.makeInMemory(), metadataReader: ImageIOMetadataReader())
            await #expect(throws: HDRMergeJob.Failure.invalidName(name: "A")) {
                _ = try await job.resultURL(for: selection, format: .tiff)
            }
        }

        @Test("C11: the capture date's offset reaches XMP only when it is a real one")
        func captureDateOffset() {
            func date(_ offset: String?) -> String? {
                var exif: [String: any Sendable] = [kCGImagePropertyExifDateTimeOriginal as String: "2016:05:21 08:43:02"]
                exif[kCGImagePropertyExifOffsetTimeOriginal as String] = offset
                return MergeOutput.Metadata(sourceProperties: [kCGImagePropertyExifDictionary as String: exif],
                                            values: SidecarValues()).xmpCaptureDate
            }
            #expect(date("+02:00") == "2016-05-21T08:43:02+02:00")
            #expect(date("-05:30") == "2016-05-21T08:43:02-05:30")
            #expect(date("Z") == "2016-05-21T08:43:02Z")
            #expect(date("   :  ") == "2016-05-21T08:43:02")
            #expect(date("+2:00") == "2016-05-21T08:43:02")
            #expect(date(nil) == "2016-05-21T08:43:02")
            #expect(MergeOutput.Metadata(sourceProperties: [:], values: SidecarValues()).xmpCaptureDate == nil)
        }

        @Test("L3: exposure metadata that isn't finite and positive counts as unknown")
        func absurdExposure() {
            #expect(MergeExposure.metadataExposure(time: .infinity, fNumber: 8, iso: 100) == nil)
            #expect(MergeExposure.metadataExposure(time: 1.0 / 60, fNumber: .nan, iso: 100) != nil)
            #expect(MergeExposure.metadataExposure(time: 0, fNumber: 8, iso: 100) == nil)
            #expect(!MergeExposure.plausible.contains(.infinity))
            #expect(!MergeExposure.plausible.contains(pow(2, 20)))
        }
    }
}
