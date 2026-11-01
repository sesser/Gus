import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import PhotoFixtures
import Synchronization
import Testing
import UniformTypeIdentifiers
@testable import PhotoCore

@Suite("Export naming")
struct ExportNamingTests {
    func context(_ name: String = "IMG_0412.NEF", sequence: Int = 3) -> TemplateContext {
        let capture = ExifDate.parse("2024:05:01 23:30:15", offset: "+02:00")!
        return TemplateContext(captureDate: capture.date, captureOffsetSeconds: capture.offsetSeconds,
                               fileDate: Date(timeIntervalSince1970: 0), importDate: Date(timeIntervalSince1970: 0),
                               make: "Nikon", model: "Z 6", serial: nil, lens: nil, originalName: name,
                               sequence: sequence, counter: sequence, jobCode: "",
                               exportDate: Date(timeIntervalSince1970: 1_717_243_200)) // 2024-06-01 12:00 UTC
    }

    @Test func originalNamesTakeTheOutputExtension() {
        var settings = ExportSettings()
        #expect(ExportNaming.fileName(for: context(), settings: settings) == "IMG_0412.jpg")
        settings.format = .tiff
        #expect(ExportNaming.fileName(for: context(), settings: settings) == "IMG_0412.tif")
    }

    @Test func templatesExpandWithTheExportDateAndSequence() {
        var settings = ExportSettings()
        settings.naming = .template
        settings.fileNameTemplate = "{capture:yyyyMMdd}-{model}-{seq:3}"
        #expect(ExportNaming.fileName(for: context(), settings: settings) == "20240501-Z 6-003.jpg")
        settings.fileNameTemplate = "{export:yyyy-MM-dd} {name}"
        #expect(ExportNaming.fileName(for: context(), settings: settings) == "2024-06-01 IMG_0412.jpg")
        // An empty result falls back to the original name.
        settings.fileNameTemplate = "{job}"
        #expect(ExportNaming.fileName(for: context(), settings: settings) == "IMG_0412.jpg")
    }

    @Test func namesInABatchNeverCollide() {
        let folder = URL(fileURLWithPath: "/out")
        let plan = ExportNaming.plan([context("a.NEF"), context("A.jpg"), context("a.heic"), context("b.NEF")],
                                     settings: ExportSettings(), in: folder, policy: .keepBoth) { _ in false }
        #expect(plan.map(\.url.lastPathComponent) == ["a.jpg", "A-2.jpg", "a-3.jpg", "b.jpg"])
    }

    @Test func existingFilesFollowThePolicy() {
        let folder = URL(fileURLWithPath: "/out")
        let existing: Set<String> = ["a.jpg", "a-2.jpg"]
        let exists = { (url: URL) in existing.contains(url.lastPathComponent) }
        let contexts = [context("a.NEF"), context("b.NEF")]
        let settings = ExportSettings()
        #expect(ExportNaming.existingCount(contexts, settings: settings, in: folder, fileExists: exists) == 1)
        #expect(ExportNaming.plan(contexts, settings: settings, in: folder, policy: .skip, fileExists: exists)
            == [.skip(folder.appending(path: "a.jpg")), .write(folder.appending(path: "b.jpg"), replacing: false)])
        #expect(ExportNaming.plan(contexts, settings: settings, in: folder, policy: .overwrite, fileExists: exists)
            .first == .write(folder.appending(path: "a.jpg"), replacing: true))
        #expect(ExportNaming.plan(contexts, settings: settings, in: folder, policy: .keepBoth, fileExists: exists)
            .first == .write(folder.appending(path: "a-3.jpg"), replacing: false))
    }
}

@Suite("Export geometry")
struct ExportGeometryTests {
    func size(_ sizing: ExportSettings.Sizing, _ source: CGSize = CGSize(width: 6000, height: 4000),
              edge: Int = 2048, box: (Int, Int) = (1000, 1000), percent: Double = 25) -> CGSize {
        var settings = ExportSettings()
        settings.sizing = sizing
        settings.edgeLength = edge
        (settings.boxWidth, settings.boxHeight) = box
        settings.percent = percent
        return ExportSizing.outputSize(for: source, settings: settings)
    }

    @Test func everySizingModeKeepsTheAspectRatio() {
        #expect(size(.full) == CGSize(width: 6000, height: 4000))
        #expect(size(.longEdge) == CGSize(width: 2048, height: 1365))
        #expect(size(.longEdge, CGSize(width: 4000, height: 6000)) == CGSize(width: 1365, height: 2048))
        #expect(size(.shortEdge, edge: 1000) == CGSize(width: 1500, height: 1000))
        #expect(size(.fit) == CGSize(width: 1000, height: 667))
        #expect(size(.fit, box: (3000, 1000)) == CGSize(width: 1500, height: 1000))
        #expect(size(.percent) == CGSize(width: 1500, height: 1000))
    }

    @Test func exportsAreNeverUpscaled() {
        #expect(size(.longEdge, edge: 8000) == CGSize(width: 6000, height: 4000))
        #expect(size(.fit, box: (9000, 9000)) == CGSize(width: 6000, height: 4000))
        #expect(size(.percent, percent: 300) == CGSize(width: 6000, height: 4000))
    }

    @Test func watermarksSitAtTheirAnchor() {
        let image = CGSize(width: 1000, height: 500)
        let mark = CGSize(width: 200, height: 100)
        func rect(_ anchor: Watermark.Anchor, size: Double = 20, flipped: Bool = false) -> CGRect {
            let rect = WatermarkLayout.rect(imageSize: image, watermarkSize: mark,
                                            watermark: Watermark(identifier: "", name: "", anchor: anchor, margin: 3,
                                                                 size: size),
                                            flipped: flipped)
            // Whole pixels, so floating-point error does not count.
            return CGRect(x: rect.minX.rounded(), y: rect.minY.rounded(), width: rect.width.rounded(),
                          height: rect.height.rounded())
        }
        #expect(rect(.bottomRight) == CGRect(x: 770, y: 30, width: 200, height: 100))
        #expect(rect(.bottomRight, flipped: true) == CGRect(x: 770, y: 370, width: 200, height: 100))
        #expect(rect(.topLeft) == CGRect(x: 30, y: 370, width: 200, height: 100))
        #expect(rect(.center) == CGRect(x: 400, y: 200, width: 200, height: 100))
        #expect(rect(.top, flipped: true) == CGRect(x: 400, y: 30, width: 200, height: 100))
        // Too large for the image: shrunk to fit inside the margins.
        #expect(rect(.left, size: 100) == CGRect(x: 30, y: 30, width: 880, height: 440))
    }

    @Test func resizingKeepsTheEdgesIntact() throws {
        let engine = RenderEngine()
        let gray = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5))
            .cropped(to: CGRect(x: 10, y: 20, width: 600, height: 400))
        let small = gray.resized(to: CGSize(width: 151, height: 100))
        #expect(small.extent == CGRect(x: 0, y: 0, width: 151, height: 100))
        let cgImage = try #require(engine.makeCGImage(small, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                                                      bitsPerComponent: 8))
        let pixels = RGBA(cgImage)
        #expect(abs(Int(pixels[0, 0].r) - Int(pixels[75, 50].r)) <= 2)
        #expect(abs(Int(pixels[150, 99].g) - Int(pixels[75, 50].g)) <= 2)
    }
}

@Suite("Export metadata")
struct ExportMetadataTests {
    let source: [CFString: Any] = [
        kCGImagePropertyExifDictionary: [kCGImagePropertyExifFNumber: 2.8, kCGImagePropertyExifPixelXDimension: 6000],
        kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "Maker", kCGImagePropertyTIFFOrientation: 6,
                                         kCGImagePropertyTIFFCopyright: "Old notice"],
        kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 45.5, kCGImagePropertyGPSLatitudeRef: "N"],
        kCGImagePropertyIPTCDictionary: [kCGImagePropertyIPTCCity: "Town", kCGImagePropertyIPTCKeywords: ["old"],
                                         kCGImagePropertyIPTCHeadline: "Headline"],
    ]
    let values = SidecarValues(rating: Rating(clamping: 5), colorLabel: .red, keywords: ["dog", "beach"],
                               creator: "Pat Doe", rights: "© Pat Doe", caption: "On the beach",
                               usageTerms: "Ask first", contact: CreatorContact(email: "pat@example.com"),
                               title: "Dog Day", altText: "A dog running on sand",
                               extendedDescription: "A brown dog runs left to right along a beach at low tide.",
                               jobTitle: "Photographer")

    func make(_ mode: ExportSettings.Metadata) -> ExportMetadata {
        var settings = ExportSettings()
        settings.metadata = mode
        settings.ppi = 240
        return ExportMetadata.make(source: source, values: values, settings: settings)
    }

    func dictionary(_ metadata: ExportMetadata, _ key: CFString) -> [CFString: Any]? {
        metadata.properties[key] as? [CFString: Any]
    }

    func xmp(_ metadata: ExportMetadata, _ path: String) -> String? {
        metadata.xmp.flatMap { CGImageMetadataCopyStringValueWithPath($0, nil, path as CFString) as String? }
    }

    func xmpArray(_ metadata: ExportMetadata, _ path: String) -> [String] {
        guard let xmp = metadata.xmp, let tag = CGImageMetadataCopyTagWithPath(xmp, nil, path as CFString),
              let items = CGImageMetadataTagCopyValue(tag) as? [CGImageMetadataTag] else { return [] }
        return items.compactMap { CGImageMetadataTagCopyValue($0) as? String }
    }

    @Test func allKeepsCameraDataAndTakesTheLibrarysFields() {
        let metadata = make(.all)
        #expect(dictionary(metadata, kCGImagePropertyExifDictionary)?[kCGImagePropertyExifFNumber] as? Double == 2.8)
        #expect(dictionary(metadata, kCGImagePropertyExifDictionary)?[kCGImagePropertyExifPixelXDimension] == nil)
        #expect(dictionary(metadata, kCGImagePropertyGPSDictionary) != nil)
        let tiff = dictionary(metadata, kCGImagePropertyTIFFDictionary)
        #expect(tiff?[kCGImagePropertyTIFFMake] as? String == "Maker")
        #expect(tiff?[kCGImagePropertyTIFFOrientation] == nil)
        #expect(tiff?[kCGImagePropertyTIFFCopyright] as? String == "© Pat Doe")
        let iptc = dictionary(metadata, kCGImagePropertyIPTCDictionary)
        #expect(iptc?[kCGImagePropertyIPTCKeywords] as? [String] == ["dog", "beach"])
        #expect(iptc?[kCGImagePropertyIPTCCity] as? String == "Town")
        #expect(iptc?[kCGImagePropertyIPTCHeadline] as? String == "Headline")
        #expect(iptc?[kCGImagePropertyIPTCObjectName] as? String == "Dog Day")
        #expect(iptc?[kCGImagePropertyIPTCBylineTitle] as? [String] == ["Photographer"])
        #expect(metadata.properties[kCGImagePropertyOrientation] as? Int == 1)
        #expect(metadata.properties[kCGImagePropertyDPIWidth] as? Int == 240)

        #expect(Set(xmpArray(metadata, "dc:subject")) == ["dog", "beach"])
        #expect(xmp(metadata, "dc:description") == "On the beach")
        #expect(xmp(metadata, "dc:rights") == "© Pat Doe")
        #expect(xmp(metadata, "xmpRights:UsageTerms") == "Ask first")
        #expect(xmp(metadata, "Iptc4xmpCore:CreatorContactInfo.Iptc4xmpCore:CiEmailWork") == "pat@example.com")
        #expect(xmp(metadata, "dc:title") == "Dog Day")
        #expect(xmp(metadata, "Iptc4xmpCore:AltTextAccessibility") == "A dog running on sand")
        #expect(xmp(metadata, "Iptc4xmpCore:ExtDescrAccessibility")?.hasPrefix("A brown dog") == true)
        #expect(xmp(metadata, "photoshop:AuthorsPosition") == "Photographer")
        // Culling stays in the app.
        #expect(xmp(metadata, "xmp:Rating") == nil && xmp(metadata, "xmp:Label") == nil)
    }

    @Test func noLocationDropsCoordinatesAndPlaceNames() {
        let metadata = make(.noLocation)
        #expect(dictionary(metadata, kCGImagePropertyGPSDictionary) == nil)
        #expect(dictionary(metadata, kCGImagePropertyIPTCDictionary)?[kCGImagePropertyIPTCCity] == nil)
        #expect(dictionary(metadata, kCGImagePropertyExifDictionary) != nil)
        #expect(Set(xmpArray(metadata, "dc:subject")) == ["dog", "beach"])
    }

    @Test func copyrightKeepsOnlyRightsAndContact() {
        let metadata = make(.copyright)
        #expect(dictionary(metadata, kCGImagePropertyExifDictionary) == nil)
        #expect(dictionary(metadata, kCGImagePropertyGPSDictionary) == nil)
        let tiff = dictionary(metadata, kCGImagePropertyTIFFDictionary)
        #expect(tiff?[kCGImagePropertyTIFFMake] == nil)
        #expect(tiff?[kCGImagePropertyTIFFArtist] as? String == "Pat Doe")
        let iptc = dictionary(metadata, kCGImagePropertyIPTCDictionary)
        #expect(iptc?[kCGImagePropertyIPTCKeywords] == nil && iptc?[kCGImagePropertyIPTCHeadline] == nil)
        #expect(iptc?[kCGImagePropertyIPTCCopyrightNotice] as? String == "© Pat Doe")
        #expect(xmp(metadata, "dc:rights") == "© Pat Doe")
        #expect(xmp(metadata, "Iptc4xmpCore:CreatorContactInfo.Iptc4xmpCore:CiEmailWork") == "pat@example.com")
        #expect(xmpArray(metadata, "dc:subject").isEmpty && xmp(metadata, "dc:description") == nil)
        // The job title goes with the creator; the descriptive texts stay out.
        #expect(xmp(metadata, "photoshop:AuthorsPosition") == "Photographer")
        #expect(iptc?[kCGImagePropertyIPTCBylineTitle] as? [String] == ["Photographer"])
        #expect(xmp(metadata, "dc:title") == nil && xmp(metadata, "Iptc4xmpCore:AltTextAccessibility") == nil)
        #expect(iptc?[kCGImagePropertyIPTCObjectName] == nil)
    }

    /// ImageIO on macOS 15 parses no XMP that starts with the `<?xpacket?>`
    /// wrapper, so export hands it the root element alone. Newer macOS
    /// accepts both, so this checks the bytes rather than the parse.
    @Test func xmpReachesImageIOWithoutThePacketWrapper() throws {
        let document = XMPDocument.empty()
        document.setArray(XMPDocument.Namespace.dc, "subject", .bag, ["dog"])
        let text = String(decoding: document.rootElementData(), as: UTF8.self)
        #expect(text.hasPrefix("<x:xmpmeta") && !text.contains("xpacket"))
        let metadata = try #require(CGImageMetadataCreateFromXMPData(document.rootElementData() as CFData))
        #expect(CGImageMetadataCopyTagWithPath(metadata, nil, "dc:subject" as CFString) != nil)
    }

    @Test func noneWritesOnlyOrientationAndResolution() {
        let metadata = make(.none)
        #expect(Set(metadata.properties.keys) == [kCGImagePropertyOrientation, kCGImagePropertyDPIWidth,
                                                  kCGImagePropertyDPIHeight])
        #expect(metadata.xmp == nil)
    }
}

@Suite("Export settings and presets")
struct ExportPresetTests {
    @Test func settingsDecodeWithDefaultsForMissingOrUnknownValues() throws {
        let settings = try ExportSettings.decode(from: #"{"format":"tiff","sizing":"somethingNew","ppi":240}"#)
        #expect(settings.format == .tiff && settings.ppi == 240)
        #expect(settings.sizing == ExportSettings().sizing)
        #expect(try ExportSettings.decode(from: "{}") == ExportSettings())
        var custom = ExportSettings()
        custom.watermarkEnabled = true
        custom.watermark = Watermark(identifier: String(repeating: "a", count: 64), name: "logo.png", anchor: .top)
        #expect(try ExportSettings.decode(from: custom.jsonString()) == custom)
    }

    @Test func presetsAreSavedUpdatedAndDeleted() async throws {
        let catalog = try Catalog.makeInMemory()
        var settings = ExportSettings()
        settings.format = .tiff
        var saved = try await catalog.saveExportPreset(ExportPreset(name: "Print", settings: settings))
        _ = try await catalog.saveExportPreset(ExportPreset(name: "a web", settings: ExportSettings()))
        #expect(try await catalog.exportPresets().map(\.name) == ["a web", "Print"])
        saved.settings.ppi = 360
        _ = try await catalog.saveExportPreset(saved)
        let presets = try await catalog.exportPresets()
        #expect(presets.count == 2 && presets.last?.settings.ppi == 360 && presets.last?.settings.format == .tiff)
        try await catalog.deleteExportPreset(id: try #require(saved.id))
        #expect(try await catalog.exportPresets().map(\.name) == ["a web"])
    }
}

@Suite("Export job")
struct ExportJobTests {
    struct Library {
        let folder: URL
        let output: URL
        let catalog: Catalog
        let job: ExportJob
        let watermarks: WatermarkStore

        func items(grouped: Bool = true) async throws -> [CatalogItem] {
            try await catalog.libraryItems(matching: LibraryFilter(groupsPairs: grouped))
        }

        func run(_ settings: ExportSettings, policy: ExportConflictPolicy = .keepBoth) async throws -> ExportSummary {
            let ids = ExportTargets.resolve(try await items()).versionIDs
            return await job.run(ExportRequest(versionIDs: ids, settings: settings, destination: output, policy: policy))
        }
    }

    /// a.DNG + a.jpg (a pair) and b.jpg with GPS, keywords and a copyright.
    func makeLibrary(_ root: URL) async throws -> Library {
        let folder = root.appending(path: "Shoot")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try SyntheticDNG.write(to: folder.appending(path: "a.DNG"), options: .init(width: 600, height: 400, seed: 1))
        try SyntheticImages.writeJPEG(to: folder.appending(path: "a.jpg"), width: 600, height: 400, seed: 1)
        var exif = SyntheticImages.Exif(dateTimeOriginal: "2024:05:01 10:00:00")
        exif.latitude = 45.5
        exif.longitude = -122.6
        try SyntheticImages.writeJPEG(to: folder.appending(path: "b.jpg"), width: 480, height: 640, seed: 2, exif: exif)
        let catalog = try Catalog.makeInMemory()
        _ = try await Importer(catalog: catalog, metadataReader: ImageIOMetadataReader()).importFolder(folder)
        let b = try #require(try await catalog.allImages().first { $0.fileName == "b.jpg" })
        try await catalog.applySidecarValues(SidecarValues(rating: Rating(clamping: 4), keywords: ["dog"],
                                                           creator: "Pat Doe", rights: "© Pat Doe"),
                                             toImage: try #require(b.id))
        let watermarks = WatermarkStore(directory: root.appending(path: "Watermarks"))
        let renderer = ExportRenderer(generator: PreviewGenerator(), watermarks: watermarks)
        return Library(folder: folder, output: root.appending(path: "Out"), catalog: catalog,
                       job: ExportJob(catalog: catalog, renderer: renderer), watermarks: watermarks)
    }

    func properties(_ url: URL) throws -> [CFString: Any] {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    }

    @Test func pairsExportOnceFromTheirRAWAndVideosAreLeftOut() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let library = try await makeLibrary(root)
            let grouped = try await library.items()
            let ungrouped = try await library.items(grouped: false)
            let raw = try #require(ungrouped.first { $0.fileName == "a.DNG" })
            #expect(ExportTargets.resolve(grouped).versionIDs.contains(raw.versionID))
            #expect(ExportTargets.resolve(ungrouped).versionIDs.count == 2)
            var video = try #require(ungrouped.first { $0.fileName == "b.jpg" })
            video = CatalogItem(versionID: 99, imageID: 99, volumeID: video.volumeID, rating: .unrated, flag: .none,
                                colorLabel: .none, contentHash: "", editStackHash: "", relativePath: "Shoot/clip.mov",
                                pixelWidth: 1920, pixelHeight: 1080, orientation: 1)
            #expect(ExportTargets.resolve(ungrouped + [video]).videos == 1)
        }
    }

    @Test func jpegsAreResizedTaggedAndStrippedOfLocation() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let library = try await makeLibrary(root)
            var settings = ExportSettings()
            settings.sizing = .longEdge
            settings.edgeLength = 300
            settings.sharpening = .standard
            settings.metadata = .noLocation
            settings.ppi = 240
            let reported = Mutex<[Int]>([])
            let summary = await library.job.run(
                ExportRequest(versionIDs: ExportTargets.resolve(try await library.items()).versionIDs,
                              settings: settings, destination: library.output)) { done, _ in
                    reported.withLock { $0.append(done) }
                }
            #expect(summary.failures.isEmpty && summary.written.count == 2)
            #expect(Set(summary.written.map(\.lastPathComponent)) == ["a.jpg", "b.jpg"])
            #expect(reported.withLock { $0.last } == 2)

            let a = try properties(library.output.appending(path: "a.jpg"))
            #expect(a[kCGImagePropertyPixelWidth] as? Int == 300 && a[kCGImagePropertyPixelHeight] as? Int == 200)
            #expect((a[kCGImagePropertyProfileName] as? String)?.contains("sRGB") == true)
            let b = try properties(library.output.appending(path: "b.jpg"))
            #expect(b[kCGImagePropertyPixelWidth] as? Int == 225 && b[kCGImagePropertyPixelHeight] as? Int == 300)
            #expect(b[kCGImagePropertyGPSDictionary] == nil)
            #expect(b[kCGImagePropertyDPIWidth] as? Int == 240)
            let iptc = b[kCGImagePropertyIPTCDictionary] as? [CFString: Any]
            #expect(iptc?[kCGImagePropertyIPTCKeywords] as? [String] == ["dog"])
            #expect((b[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFCopyright] as? String
                == "© Pat Doe")
            let source = try #require(CGImageSourceCreateWithURL(library.output.appending(path: "b.jpg") as CFURL, nil))
            let xmp = try #require(CGImageSourceCopyMetadataAtIndex(source, 0, nil))
            #expect(CGImageMetadataCopyStringValueWithPath(xmp, nil, "xmp:Rating" as CFString) == nil)
        }
    }

    @Test func tiffsKeepSixteenBitsTheirCompressionAndProfile() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let library = try await makeLibrary(root)
            var settings = ExportSettings()
            settings.format = .tiff
            settings.tiffBitDepth = 16
            settings.tiffCompression = .zip
            settings.colorSpace = .proPhoto
            settings.metadata = .all
            let summary = try await library.run(settings)
            #expect(summary.failures.isEmpty && summary.written.count == 2)
            let a = try properties(library.output.appending(path: "a.tif"))
            #expect(a[kCGImagePropertyDepth] as? Int == 16)
            #expect(a[kCGImagePropertyHasAlpha] as? Bool != true)
            #expect((a[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFCompression] as? Int == 8)
            #expect(a[kCGImagePropertyPixelWidth] as? Int == 600)
            let profile = (a[kCGImagePropertyProfileName] as? String) ?? ""
            #expect(profile.contains("ROMM") || profile.contains("ProPhoto"))
            let b = try properties(library.output.appending(path: "b.tif"))
            #expect(b[kCGImagePropertyGPSDictionary] != nil)
        }
    }

    @Test func existingFilesAreSkippedOverwrittenOrKept() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let library = try await makeLibrary(root)
            var settings = ExportSettings()
            settings.sizing = .longEdge
            settings.edgeLength = 100
            _ = try await library.run(settings)

            let skipped = try await library.run(settings, policy: .skip)
            #expect(skipped.skippedExisting == 2 && skipped.written.isEmpty)

            let target = library.output.appending(path: "b.jpg")
            let before = try FileManager.default.attributesOfItem(atPath: target.path)[.modificationDate] as? Date
            try await Task.sleep(for: .milliseconds(20))
            let overwritten = try await library.run(settings, policy: .overwrite)
            #expect(overwritten.written.count == 2)
            let after = try FileManager.default.attributesOfItem(atPath: target.path)[.modificationDate] as? Date
            #expect(after != before)

            let kept = try await library.run(settings, policy: .keepBoth)
            #expect(Set(kept.written.map(\.lastPathComponent)) == ["a-2.jpg", "b-2.jpg"])
            let files = try FileManager.default.contentsOfDirectory(atPath: library.output.path)
            #expect(files.sorted() == ["a-2.jpg", "a.jpg", "b-2.jpg", "b.jpg"])
        }
    }

    @Test func videosOfflineMastersAndCancellationAreReported() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let library = try await makeLibrary(root)
            var items = try await library.job.items(for: ExportTargets.resolve(try await library.items()).versionIDs)
            var video = items[0]
            video.details.image.fileName = "clip.mov"
            var offline = items[1]
            offline.isOnline = false
            items = [video, offline]
            var settings = ExportSettings()
            settings.sizing = .longEdge
            settings.edgeLength = 100
            let request = ExportRequest(versionIDs: [], settings: settings, destination: library.output)
            let summary = await library.job.run(request, items: items)
            #expect(summary.skippedVideos == 1 && summary.written.isEmpty)
            #expect(summary.failures.map(\.reason) == [.offline(volumeName: offline.details.volume.name)])

            let job = library.job
            let all = try await job.items(for: ExportTargets.resolve(try await library.items()).versionIDs)
            let cancelled = await Task {
                withUnsafeCurrentTask { $0?.cancel() }
                return await job.run(request, items: all)
            }.value
            #expect(cancelled.cancelled && cancelled.written.isEmpty)
        }
    }

    @Test func watermarksAreDrawnWhereTheLayoutSays() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let library = try await makeLibrary(root)
            let png = root.appending(path: "logo.png")
            let green = CIImage(color: CIColor(red: 0, green: 1, blue: 0)).cropped(to: CGRect(x: 0, y: 0, width: 40, height: 20))
            let context = CIContext()
            try context.writePNGRepresentation(of: green, to: png, format: .RGBA8,
                                               colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
            var settings = ExportSettings()
            settings.sizing = .longEdge
            settings.edgeLength = 300
            settings.jpegQuality = 1
            settings.watermarkEnabled = true
            settings.watermark = try library.watermarks.importFile(at: png)
            settings.watermark?.margin = 0
            settings.watermark?.size = 20
            settings.watermark?.opacity = 1
            let summary = try await library.run(settings)
            #expect(summary.failures.isEmpty)

            // b.jpg is 225 × 300: the watermark is 60 × 30 in the bottom right corner.
            let source = try #require(CGImageSourceCreateWithURL(library.output.appending(path: "b.jpg") as CFURL, nil))
            let pixels = RGBA(try #require(CGImageSourceCreateImageAtIndex(source, 0, nil)))
            let inside = pixels[200, 285]
            #expect(inside.g > 200 && inside.r < 60 && inside.b < 60)
            let outside = pixels[100, 150]
            #expect(!(outside.g > 200 && outside.r < 60 && outside.b < 60))

            try FileManager.default.removeItem(at: library.watermarks.fileURL(for: try #require(settings.watermark).identifier))
            let missing = try await library.run(settings)
            #expect(missing.failures.count == 2 && missing.failures.allSatisfy { $0.reason == .missingWatermark })
        }
    }
}

/// 8-bit sRGB pixels of an image, top row first.
struct RGBA {
    let width: Int
    let bytes: [UInt8]

    init(_ image: CGImage) {
        width = image.width
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                                    bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        self.bytes = bytes
    }

    subscript(x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
        let offset = (y * width + x) * 4
        return (bytes[offset], bytes[offset + 1], bytes[offset + 2])
    }
}
