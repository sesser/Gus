import CoreImage
import Foundation
import ImageIO
import PhotoFixtures
import Testing
@testable import PhotoCore

/// Issue #282, first stage: a gain-map photo shown and edited in HDR, with
/// the gain map applied as the last step of the render ("gain last",
/// docs/features/gain-map-hdr/spike.md). Synthetic files only, with each
/// kind of gain map (ISO 21496-1, and Apple's alone: QA Q1, Q4) on every path
/// that makes an HDR picture; the owner's photos run in the opt-in test at
/// the end.
@Suite("Gain-map photos in HDR (issue #282)")
struct GainMapHDRTests {
    /// Linear Display P3 pixels of an image, relative to SDR white.
    struct Pixels {
        var width: Int
        var height: Int
        var luminance: [Float]
        var maximum: Float

        init(_ image: CIImage, size: CGSize? = nil) {
            var input = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
            if let size {
                input = input.transformed(by: CGAffineTransform(scaleX: size.width / image.extent.width,
                                                                y: size.height / image.extent.height))
            }
            let bounds = CGRect(origin: .zero, size: size ?? image.extent.size).integral
            width = Int(bounds.width)
            height = Int(bounds.height)
            var pixels = [Float](repeating: 0, count: width * height * 4)
            let space = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)!
            // The app's working space: a recipe built for it (Black & White's matrix, saturation)
            // renders otherwise in a default context's linear sRGB.
            CIContext(options: [.workingFormat: CIFormat.RGBAf, .workingColorSpace: RenderEngine.workingColorSpace,
                                .cacheIntermediates: false])
                .render(input, toBitmap: &pixels, rowBytes: width * 16, bounds: bounds, format: .RGBAf, colorSpace: space)
            var luminance = [Float](repeating: 0, count: width * height)
            var maximum: Float = 0
            for index in luminance.indices {
                let red = pixels[index * 4], green = pixels[index * 4 + 1], blue = pixels[index * 4 + 2]
                let weighted: Float = 0.2290 * red + 0.6917 * green
                luminance[index] = weighted + 0.0793 * blue
                maximum = max(maximum, red, green, blue)
            }
            self.luminance = luminance
            self.maximum = maximum
        }

        init(_ image: CGImage, size: CGSize? = nil) {
            self.init(CIImage(cgImage: image), size: size)
        }

        var mean: Float { luminance.reduce(0, +) / Float(luminance.count) }

        /// Mean luminance in each cell of a `columns` × `rows` grid, top row first.
        func cells(columns: Int, rows: Int) -> [Float] {
            var sums = [Float](repeating: 0, count: columns * rows)
            var counts = sums
            for y in 0..<height {
                let row = min(rows - 1, y * rows / height)
                for x in 0..<width {
                    let cell = row * columns + min(columns - 1, x * columns / width)
                    sums[cell] += luminance[y * width + x]
                    counts[cell] += 1
                }
            }
            return zip(sums, counts).map { $0 / max($1, 1) }
        }
    }

    /// RMS over pixels of how far log2(HDR / SDR) moved from the unedited
    /// pair's (the spike's ratio drift), skipping near-black pixels.
    static func drift(hdr: Pixels, sdr: Pixels, hdr0: Pixels, sdr0: Pixels) -> Double {
        var sum = 0.0, count = 0.0
        for index in hdr.luminance.indices {
            let values = [hdr.luminance[index], sdr.luminance[index], hdr0.luminance[index], sdr0.luminance[index]]
            guard values.allSatisfy({ $0 > 0.005 }) else { continue }
            let moved = log2(Double(values[0] / values[1])) - log2(Double(values[2] / values[3]))
            sum += moved * moved
            count += 1
        }
        return count > 0 ? (sum / count).squareRoot() : .nan
    }

    /// The system's own HDR decode of the file, turned as the photo is.
    static func systemHDR(_ url: URL) throws -> CIImage {
        try #require(CIImage(contentsOf: url, options: [.applyOrientationProperty: true, .expandToHDR: true]))
    }

    /// Our SDR version as it is shown: the edited render in linear Display P3, clipped to SDR white.
    static func shownSDR(_ url: URL, stack: EditStack, longEdge: Int) throws -> CIImage {
        let image = try PreviewGenerator().image(source: url, stack: stack, longEdge: longEdge)
        return GainMap.clamped(image, maximum: 1)
    }

    static func operation(_ kind: EditOperationKind, _ parameters: [String: Double]) -> EditOperation {
        EditOperation(kind: kind, parameters: parameters.mapValues { .number($0) })
    }

    static func stack(_ operations: EditOperation...) -> EditStack { EditStack(operations: operations) }

    static func cropped(_ crop: Crop) -> EditStack {
        var values = Adjustments()
        values.crop = crop
        return values.editStack
    }

    // MARK: Loading

    @Test("A gain-map HEIC or JPEG has a gain map with its file's headroom; other files have none",
          arguments: [HDRTestImages.Container.heic, .jpeg], HDRTestImages.GainMapKind.allCases)
    func loads(container: HDRTestImages.Container, kind: HDRTestImages.GainMapKind) async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let url = root.appending(path: container == .heic ? "map.heic" : "map.jpg")
            try HDRTestImages.writePatternedGainMap(to: url, width: 400, height: 300, seed: 2821, container: container,
                                                    kind: kind)
            // The fixture carries the kind it says, and only that one.
            let read = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
            #expect((CGImageSourceCopyAuxiliaryDataInfoAtIndex(read, 0, kCGImageAuxiliaryDataTypeISOGainMap) != nil) == (kind == .iso))
            if kind == .apple {
                #expect(CGImageSourceCopyAuxiliaryDataInfoAtIndex(read, 0, kCGImageAuxiliaryDataTypeHDRGainMap) != nil)
            }
            #expect(GainMap.exists(url))
            let map = try #require(GainMap.load(url))
            switch kind {
            case .iso:
                // The system's HDR decode reaches the same headroom.
                let system = Pixels(try Self.systemHDR(url))
                #expect(abs(log2(map.headroom / system.maximum)) < 0.05)
            case .apple:
                // The headroom is the maker tags' (the picture's brightest part is darker than white).
                #expect(abs(Double(map.headroom) - HDRTestImages.appleHeadroom) < 0.01)
            }
            #expect(map.headroom > 2)
            // SDR white through the gain map: the bright part's gain of 4 (its
            // SDR picture is darker than white, so the file's headroom is less).
            #expect(abs(log2(map.ceiling / 4)) < 0.05)

            // A plain JPEG, and HLG and PQ files (with or without a gain map) have none (R16).
            let plain = root.appending(path: "plain.jpg")
            try SyntheticImages.writeJPEG(to: plain, width: 400, height: 300, seed: 2822)
            #expect(!GainMap.exists(plain))
            #expect(GainMap.load(plain) == nil)
            for gainMap in [false, true] {
                let encoded = root.appending(path: "pq-\(gainMap).heic")
                try HDRTestImages.writeHDREncoded(to: encoded, width: 400, height: 300, seed: 2823, gain: 2,
                                                  transfer: .pq, gainMap: gainMap)
                #expect(!GainMap.exists(encoded))
                #expect(try PreviewGenerator().gainMapHDRImage(source: encoded, stack: .identity, longEdge: 400,
                                                               displayHeadroom: 8) == nil)
            }
            #expect(try PreviewGenerator().gainMapHDRImage(source: plain, stack: .identity, longEdge: 400,
                                                           displayHeadroom: 8) == nil)
        }
    }

    @Test("AC1: only a HEIC or JPEG, by name and content, is a gain-map photo; a gain map in another file type gives no choice")
    func onlyHEICAndJPEG() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let heic = root.appending(path: "map.heic")
            let jpeg = root.appending(path: "map.jpg")
            try HDRTestImages.writePatternedGainMap(to: heic, width: 200, height: 150, seed: 2824)
            try HDRTestImages.writePatternedGainMap(to: jpeg, width: 200, height: 150, seed: 2825, container: .jpeg)
            // HEIF and upper-case names are HEIC and JPEG files too.
            for (source, name) in [(heic, "map.HEIF"), (jpeg, "map.JPEG")] {
                let copy = root.appending(path: name)
                try FileManager.default.copyItem(at: source, to: copy)
                #expect(GainMap.exists(copy), "\(name)")
            }
            // The same bytes under a TIFF or PNG name are not (the app treats a file by its name).
            for name in ["map.tif", "map.tiff", "map.png"] {
                let copy = root.appending(path: name)
                try FileManager.default.copyItem(at: jpeg, to: copy)
                #expect(!GainMap.exists(copy), "\(name)")
                #expect(GainMap.load(copy) == nil, "\(name)")
            }
            // Another container with a gain map ImageIO reads (AVIF), named as a HEIC: not by its content.
            let avif = root.appending(path: "avif.heic")
            let read = try #require(CGImageSourceCreateWithURL(heic as CFURL, nil))
            let gainMap = try #require(CGImageSourceCopyAuxiliaryDataInfoAtIndex(read, 0, kCGImageAuxiliaryDataTypeISOGainMap))
            let picture = try #require(CGImageSourceCreateImageAtIndex(read, 0, nil))
            let destination = try #require(CGImageDestinationCreateWithURL(avif as CFURL, "public.avif" as CFString, 1, nil))
            CGImageDestinationAddImage(destination, picture, nil)
            CGImageDestinationAddAuxiliaryDataInfo(destination, kCGImageAuxiliaryDataTypeISOGainMap, gainMap)
            try #require(CGImageDestinationFinalize(destination))
            let written = try #require(CGImageSourceCreateWithURL(avif as CFURL, nil))
            #expect(CGImageSourceGetType(written) as String? == "public.avif")
            // ImageIO reads its gain map, so only the content check keeps it out.
            #expect(CGImageSourceCopyAuxiliaryDataInfoAtIndex(written, 0, kCGImageAuxiliaryDataTypeISOGainMap) != nil)
            #expect(!GainMap.exists(avif))
            #expect(GainMap.load(avif) == nil)
        }
    }

    // MARK: Orientation (R19, AC17)

    @Test("Unedited at the file's headroom, the HDR version is the system's HDR decode, in every orientation",
          arguments: [HDRTestImages.Container.heic, .jpeg], Array(Int32(1)...8))
    func matchesSystemDecode(container: HDRTestImages.Container, orientation: Int32) async throws {
        for kind in HDRTestImages.GainMapKind.allCases {
            try await matchesSystemDecode(container: container, orientation: orientation, kind: kind)
        }
    }

    func matchesSystemDecode(container: HDRTestImages.Container, orientation: Int32,
                             kind: HDRTestImages.GainMapKind) async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let url = root.appending(path: container == .heic ? "o\(orientation).heic" : "o\(orientation).jpg")
            try HDRTestImages.writePatternedGainMap(to: url, width: 800, height: 600, seed: 2824,
                                                    orientation: orientation, container: container, kind: kind)
            let made = try #require(try PreviewGenerator().gainMapHDRImage(source: url, stack: .identity, longEdge: 800,
                                                                           displayHeadroom: 100))
            let system = try Self.systemHDR(url)
            #expect(CGFloat(made.image.width) == system.extent.width && CGFloat(made.image.height) == system.extent.height)
            let ours = Pixels(made.image).cells(columns: 8, rows: 6)
            let theirs = Pixels(system).cells(columns: 8, rows: 6)
            // A gain map left unturned puts the bright part (two stops over
            // the rest) on other cells: a difference of over a stop there.
            let worst = zip(ours, theirs).map { abs(log2($0 / $1)) }.max() ?? .infinity
            #expect(worst < 0.05, "\(kind): worst cell \(worst) stops")
            #expect(made.image.contentHeadroom == made.ceiling)
        }
    }

    // MARK: Fitting to the display (R6, AC5)

    @Test("For a smaller headroom, the HDR version follows the gain map's rule and stays within it",
          arguments: HDRTestImages.GainMapKind.allCases)
    func fitsToDisplay(kind: HDRTestImages.GainMapKind) async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let url = root.appending(path: "fit.heic")
            try HDRTestImages.writePatternedGainMap(to: url, width: 800, height: 600, seed: 2825, bright: 4, dim: 1.5,
                                                    kind: kind)
            // The gain map's own rendering for a headroom: Core Image applying it to the file's
            // own picture, as loaded (orientation 1, so nothing to turn).
            let file = try #require(CIImage(contentsOf: url))
            let fileMap = try #require(CIImage(contentsOf: url, options: [.auxiliaryHDRGainMap: true]))
            let generator = PreviewGenerator()
            let full = try #require(try generator.gainMapHDRImage(source: url, stack: .identity, longEdge: 800,
                                                                  displayHeadroom: 100))
            let fileHeadroom = full.fileHeadroom
            let sdr = Pixels(try Self.shownSDR(url, stack: .identity, longEdge: 800)).cells(columns: 8, rows: 6)
            let system = Pixels(try Self.systemHDR(url)).cells(columns: 8, rows: 6)
            #expect(fileHeadroom > 2)
            for display: Float in [1.5, 2, fileHeadroom * 1.5] {
                let fitted = try #require(try generator.gainMapHDRImage(source: url, stack: .identity, longEdge: 800,
                                                                        displayHeadroom: display))
                #expect(fitted.image.contentHeadroom == GainMapHeadroom.tag(display: display, ceiling: full.ceiling))
                let pixels = Pixels(fitted.image)
                #expect(pixels.maximum <= display * 1.001)
                // ISO 21496-1: the log gain is weighted by log2(display) / log2(file headroom)
                // (base headroom 0), so each cell's brightening over SDR, in stops, is that
                // fraction of the full version's (the system's decode).
                let cells = pixels.cells(columns: 8, rows: 6)
                if kind == .iso {
                    let weight = min(1, log2(display) / log2(fileHeadroom))
                    for (index, cell) in cells.enumerated() where sdr[index] > 0.01 {
                        let expected = weight * log2(system[index] / sdr[index])
                        let got = log2(cell / sdr[index])
                        #expect(abs(got - expected) < 0.06, "cell \(index): \(got) stops, expected \(expected)")
                    }
                }
                // Either kind: what Core Image's own rule gives the file for that headroom (AC5).
                let own = Pixels(GainMap.clamped(file.applyingGainMap(fileMap, headroom: min(display, fileHeadroom)),
                                                 maximum: display)).cells(columns: 8, rows: 6)
                for (index, cell) in cells.enumerated() where own[index] > 0.01 {
                    #expect(abs(log2(cell / own[index])) < 0.05, "\(kind) at \(display), cell \(index): \(cell) against \(own[index])")
                }
            }
        }
    }

    @Test("Headroom rules: the gain map's weighting, the tag, and when to render again")
    func headroomRules() {
        #expect(GainMapHeadroom.weighting(file: 2.6, display: 16) == 2.6)
        #expect(GainMapHeadroom.weighting(file: 4.5, display: 2) == 2)
        #expect(GainMapHeadroom.weighting(file: 4.5, display: 0.8) == 1)
        #expect(GainMapHeadroom.tag(display: 16, ceiling: 2.6) == 2.6)
        #expect(GainMapHeadroom.tag(display: 2, ceiling: 2.6) == 2)
        #expect(GainMapHeadroom.tag(display: 0.9, ceiling: 2.6) == 1)
        #expect(!GainMapHeadroom.needsRender(rendered: 2, display: 2.01, ceiling: 4))
        #expect(GainMapHeadroom.needsRender(rendered: 2, display: 2.1, ceiling: 4))
        #expect(GainMapHeadroom.needsRender(rendered: 2, display: 1.9, ceiling: 4))
        #expect(!GainMapHeadroom.needsRender(rendered: 1, display: 0.8, ceiling: 4))
        // Above the photo's ceiling every display gets the same picture.
        #expect(!GainMapHeadroom.needsRender(rendered: 2.6, display: 9.8, ceiling: 2.6))
    }

    // MARK: Editing (R7, AC6)

    @Test("An edit changes the HDR version by as many stops as the SDR one, point by point",
          arguments: HDRTestImages.GainMapKind.allCases)
    func editsKeepTheBrightening(kind: HDRTestImages.GainMapKind) async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let url = root.appending(path: "edit.heic")
            try HDRTestImages.writePatternedGainMap(to: url, width: 800, height: 600, seed: 2826, kind: kind)
            let generator = PreviewGenerator()
            func pair(_ stack: EditStack) throws -> (hdr: Pixels, sdr: Pixels) {
                let hdr = try #require(try generator.gainMapHDRImage(source: url, stack: stack, longEdge: 800,
                                                                     displayHeadroom: 100))
                return (Pixels(hdr.image), Pixels(try Self.shownSDR(url, stack: stack, longEdge: 800)))
            }
            let unedited = try pair(.identity)
            let stacks: [(String, EditStack)] = [
                ("exposure +1", Self.stack(Self.operation("exposure", ["ev": 1]))),
                ("exposure -1", Self.stack(Self.operation("exposure", ["ev": -1]))),
                ("contrast +50", Self.stack(Self.operation("tone", ["contrast": 50]))),
                ("highlights -50", Self.stack(Self.operation("tone", ["highlights": -50]))),
            ]
            for (name, stack) in stacks {
                let edited = try pair(stack)
                let drift = Self.drift(hdr: edited.hdr, sdr: edited.sdr, hdr0: unedited.hdr, sdr0: unedited.sdr)
                #expect(drift < 0.05, "\(name): \(drift) stops RMS")
                // Values above SDR white stay above it after an edit that brightens.
                if name == "exposure +1" { #expect(edited.hdr.maximum > 2) }
            }
        }
    }

    // MARK: Live frames and the settled render (R9, AC8)

    @Test("A live HDR frame and the settled HDR render of the same values agree",
          arguments: HDRTestImages.GainMapKind.allCases)
    func liveMatchesSettled(kind: HDRTestImages.GainMapKind) async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let url = root.appending(path: "live.heic")
            try HDRTestImages.writePatternedGainMap(to: url, width: 1200, height: 900, seed: 2827, orientation: 6, kind: kind)
            let generator = PreviewGenerator()
            let session = LiveRenderSession(source: url, generator: generator, longEdge: 800, colorSpace: nil)
            let stacks: [(String, EditStack)] = [
                ("identity", .identity),
                ("exposure -1", Self.stack(Self.operation("exposure", ["ev": -1]))),
                ("contrast +20", Self.stack(Self.operation("tone", ["contrast": 20]))),
                ("crop, turn, straighten",
                 Self.cropped(Crop(rect: CropRect(x: 0.1, y: 0.15, width: 0.6, height: 0.5), quarterTurns: 1, angle: 3))),
            ]
            for display: Float in [2, 100] {
                for (name, stack) in stacks {
                    let frame = try await session.render(Adjustments(stack: stack), hdrHeadroom: display)
                    let settled = try #require(try generator.gainMapHDRImage(source: url, stack: stack, longEdge: 800,
                                                                             displayHeadroom: display))
                    let headroom = try #require(frame.headroom)
                    #expect(headroom == settled.image.contentHeadroom)
                    #expect(frame.image.cgImage.contentHeadroom == headroom)
                    #expect(frame.fileHeadroom == settled.fileHeadroom)
                    #expect(frame.histogram != nil)
                    let live = Pixels(frame.image.cgImage)
                    let still = Pixels(settled.image)
                    #expect(live.width == still.width && live.height == still.height)
                    let stops = abs(log2(live.mean / still.mean))
                    #expect(stops < 0.005, "\(name) at \(display): \(stops) stops")
                    if name == "identity" { #expect(live.maximum > 1.2, "an HDR frame keeps values above SDR white") }
                }
            }
            // Without a headroom, the same session's frames are SDR as before.
            let sdr = try await session.render(Adjustments())
            #expect(sdr.headroom == nil)
            #expect(sdr.image.cgImage.bitsPerComponent == 8)
        }
    }

    @Test("A map is never an HDR frame, and a file without a gain map gives SDR frames")
    func framesThatStaySDR() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let url = root.appending(path: "maps.heic")
            try HDRTestImages.writePatternedGainMap(to: url, width: 800, height: 600, seed: 2828)
            var values = Adjustments()
            values.sharpen.amount = 80
            let session = LiveRenderSession(source: url, generator: PreviewGenerator(), longEdge: 600, colorSpace: nil)
            let map = try await session.render(values, content: .sharpeningMap, hdrHeadroom: 4)
            #expect(map.headroom == nil)
            let plain = root.appending(path: "plain.jpg")
            try SyntheticImages.writeJPEG(to: plain, width: 800, height: 600, seed: 2829)
            let other = LiveRenderSession(source: plain, generator: PreviewGenerator(), longEdge: 600, colorSpace: nil)
            #expect(try await other.render(Adjustments(), hdrHeadroom: 4).headroom == nil)
        }
    }

    @Test("A region frame at 100% is the same HDR picture as the full-resolution render",
          arguments: HDRTestImages.GainMapKind.allCases)
    func regionMatchesFullResolution(kind: HDRTestImages.GainMapKind) async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let url = root.appending(path: "region.heic")
            try HDRTestImages.writePatternedGainMap(to: url, width: 1200, height: 900, seed: 2830, orientation: 3, kind: kind)
            let generator = PreviewGenerator()
            let values = Adjustments(stack: Self.stack(Self.operation("exposure", ["ev": -0.5])))
            let regions = LiveRegionRenderer(source: url, generator: generator, colorSpace: nil)
            try await regions.prepare(values)
            let unit = CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)
            let frame = try await regions.render(values, unit: unit, hdrHeadroom: 1.8)
            #expect(frame.headroom == 1.8)
            let full = try #require(try generator.gainMapHDRImage(source: url, stack: values.editStack, longEdge: nil,
                                                                  displayHeadroom: 1.8))
            // The bottom-right quarter of the full render, where orientation 3 puts the
            // stored top-left's bright part (Core Image's y axis points up).
            let whole = CIImage(cgImage: full.image)
            let quarter = whole.cropped(to: CGRect(x: whole.extent.width / 2, y: 0,
                                                   width: whole.extent.width / 2, height: whole.extent.height / 2))
            let tile = Pixels(frame.image.cgImage)
            let expected = Pixels(quarter)
            #expect(abs(log2(tile.mean / expected.mean)) < 0.005)
            // It is brightened: above the SDR tile of the same part (Apple's rule weights its gain less at 1.8,
            // so only the ISO file's bright part reaches above SDR white here).
            let sdrTile = Pixels(try await regions.render(values, unit: unit).image.cgImage)
            #expect(log2(tile.mean / sdrTile.mean) > 0.3, "\(kind): \(tile.mean) against SDR \(sdrTile.mean)")
            if kind == .iso { #expect(tile.maximum > 1.05, "the tile holds the bright part, above SDR white") }
        }
    }

    @Test("Review F1, F11: a frame is current only for what it was asked for: SDR, or HDR at the same display headroom")
    func framesAreCurrentForTheirHeadroom() async throws {
        // The rule the editor's skips use (`requestRender`): a frame of the same values and overlay
        // rendered SDR, or for another headroom, is rendered again.
        var values = Adjustments(stack: Self.stack(Self.operation("exposure", ["ev": -0.5])))
        values.hdrIsOn = true
        let current = LiveFrameRules.isCurrent(frameValues:frameOverlay:frameHeadroom:wanted:overlay:headroom:)
        #expect(current(values, nil, nil, values, nil, nil))
        #expect(current(values, nil, 2, values, nil, 2))
        #expect(!current(values, nil, nil, values, nil, 2), "View ▸ Show HDR: the SDR frame of these values")
        #expect(!current(values, nil, 2, values, nil, nil), "View ▸ Hide HDR: the HDR frame of these values")
        #expect(!current(values, nil, 3, values, nil, 2), "a brightness change or a display move")
        // Within the tolerance a reading's noise is the same headroom.
        #expect(current(values, nil, 2, values, nil, 2 * exp2(GainMapHeadroom.tolerance / 2)))
        #expect(!current(values, nil, 2, values, nil, 2 * exp2(GainMapHeadroom.tolerance * 2)))
        // Values and overlay still count.
        var other = values
        other.exposure.ev = 0
        #expect(!current(other, nil, 2, values, nil, 2))
        #expect(!current(values, UUID(), 2, values, nil, 2))

        // Both renderers record what they were asked for, also where it changes nothing (an SDR file).
        try await RepositoryFiles.withTemporaryDirectory { root in
            let url = root.appending(path: "asked.heic")
            try HDRTestImages.writePatternedGainMap(to: url, width: 600, height: 400, seed: 2836)
            let plain = root.appending(path: "plain.jpg")
            try SyntheticImages.writeJPEG(to: plain, width: 600, height: 400, seed: 2837)
            let generator = PreviewGenerator()
            let regions = LiveRegionRenderer(source: url, generator: generator, colorSpace: nil)
            try await regions.prepare(values)
            let unit = CGRect(x: 0, y: 0, width: 0.5, height: 0.5)
            let sdrTile = try await regions.render(values, unit: unit)
            let hdrTile = try await regions.render(values, unit: unit, hdrHeadroom: 1.8)
            #expect(sdrTile.requestedHeadroom == nil && hdrTile.requestedHeadroom == 1.8)
            let session = LiveRenderSession(source: url, generator: generator, longEdge: 400, colorSpace: nil)
            let sdrFrame = try await session.render(values)
            let hdrFrame = try await session.render(values, hdrHeadroom: 3)
            #expect(sdrFrame.requestedHeadroom == nil && hdrFrame.requestedHeadroom == 3)
            // The frame that makes the HDR histogram is the one rendered for a headroom.
            #expect(sdrFrame.hdrHistogram == nil && hdrFrame.hdrHistogram != nil)
            let other = LiveRenderSession(source: plain, generator: generator, longEdge: 400, colorSpace: nil)
            let plainFrame = try await other.render(Adjustments(), hdrHeadroom: 3)
            #expect(plainFrame.headroom == nil && plainFrame.requestedHeadroom == 3)
        }
    }

    @Test("Review F5: the full-resolution photo refinement (a fringe slot picked again at 100%) is HDR, as the full render",
          arguments: HDRTestImages.GainMapKind.allCases)
    func photoRefinementIsHDR(kind: HDRTestImages.GainMapKind) async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let url = root.appending(path: "refine.heic")
            try HDRTestImages.writePatternedGainMap(to: url, width: 1200, height: 900, seed: 2835, orientation: 6, kind: kind)
            let generator = PreviewGenerator()
            let values = Adjustments(stack: Self.stack(Self.operation("exposure", ["ev": -0.5])))
            let refiner = SharpeningMapRefiner(source: url, generator: generator, colorSpace: nil)
            let frame = try await refiner.render(values, longEdge: nil, content: .photo, hdrHeadroom: 1.8)
            #expect(frame.headroom == 1.8)
            #expect(frame.fileHeadroom != nil && frame.ceiling != nil)
            let full = try #require(try generator.gainMapHDRImage(source: url, stack: values.editStack, longEdge: nil,
                                                                  displayHeadroom: 1.8))
            let refined = Pixels(frame.image.cgImage)
            let expected = Pixels(full.image)
            #expect(refined.width == expected.width && refined.height == expected.height)
            #expect(abs(log2(refined.mean / expected.mean)) < 0.005)
            #expect(abs(log2(refined.maximum / expected.maximum)) < 0.01, "\(refined.maximum) against \(expected.maximum)")
            // Without a headroom, and for a map, it stays SDR as before; the HDR one is brighter.
            let sdr = try await refiner.render(values, longEdge: nil, content: .photo)
            #expect(sdr.headroom == nil)
            #expect(log2(refined.mean / Pixels(sdr.image.cgImage).mean) > 0.1)
            #expect(try await refiner.render(values, longEdge: nil, content: .fringeMap, hdrHeadroom: 1.8).headroom == nil)
        }
    }

    // MARK: The service

    @Test("The service keeps one HDR version per photo, rendered again for another display headroom",
          arguments: HDRTestImages.GainMapKind.allCases)
    func serviceCachesByHeadroom(kind: HDRTestImages.GainMapKind) async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let url = root.appending(path: "service.heic")
            try HDRTestImages.writePatternedGainMap(to: url, width: 800, height: 600, seed: 2831, kind: kind)
            let service = PreviewService(cache: PreviewDiskCache(root: root.appending(path: "cache")),
                                         editStack: { _ in .identity })
            let key = try #require(PreviewCacheKey(contentHash: String(repeating: "a", count: 64),
                                                   editStackHash: EditStack.identity.renderHash, tier: .preview))
            let request = PreviewRequest(versionID: 1, key: key, sourceURL: url)
            #expect(service.gainMapHeadroom(for: request) == nil)
            let first = try #require(try await service.gainMapHDRImage(for: request, displayHeadroom: 2))
            #expect(first.contentHeadroom == 2)
            #expect(try #require(service.gainMapHeadroom(for: request)).file > 2)
            #expect(service.memoryCachedGainMapHDRImage(for: request, displayHeadroom: 2.01) === first)
            #expect(service.memoryCachedGainMapHDRImage(for: request, displayHeadroom: 2.5) == nil)
            let second = try #require(try await service.gainMapHDRImage(for: request, displayHeadroom: 2.5))
            #expect(second.contentHeadroom == 2.5)
            #expect(service.memoryCachedGainMapHDRImage(for: request, displayHeadroom: 2) == nil)

            let plain = root.appending(path: "plain.jpg")
            try SyntheticImages.writeJPEG(to: plain, width: 400, height: 300, seed: 2832)
            let plainKey = try #require(PreviewCacheKey(contentHash: String(repeating: "b", count: 64),
                                                        editStackHash: EditStack.identity.renderHash, tier: .preview))
            #expect(try await service.gainMapHDRImage(for: PreviewRequest(versionID: 2, key: plainKey, sourceURL: plain),
                                                      displayHeadroom: 4) == nil)
        }
    }

    @Test("Code review C1, C3: only a real error is a failure; a cancelled, outdated or offline request is not")
    func outcomes() async throws {
        #expect(PreviewService.supersedes(CancellationError()))
        #expect(PreviewService.supersedes(PreviewService.Failure.staleEditStack))
        #expect(PreviewService.supersedes(PreviewService.Failure.sourceUnavailable))
        #expect(!PreviewService.supersedes(PreviewService.Failure.decodeFailed))
        #expect(!PreviewService.supersedes(PreviewGenerator.Failure.renderFailed))
        try await RepositoryFiles.withTemporaryDirectory { root in
            let url = root.appending(path: "outcome.heic")
            try HDRTestImages.writePatternedGainMap(to: url, width: 400, height: 300, seed: 2833)
            let plain = root.appending(path: "plain.jpg")
            try SyntheticImages.writeJPEG(to: plain, width: 400, height: 300, seed: 2834)
            // The service saves a different stack than the request names: a newer save.
            var values = Adjustments()
            values.exposure.ev = 1
            let edited = values.editStack
            let service = PreviewService(cache: PreviewDiskCache(root: root.appending(path: "cache")),
                                         editStack: { versionID in versionID == 4 ? edited : .identity })
            func request(_ id: Int64, _ hash: Character, _ source: URL?) throws -> PreviewRequest {
                let key = try #require(PreviewCacheKey(contentHash: String(repeating: hash, count: 64),
                                                       editStackHash: EditStack.identity.renderHash, tier: .preview))
                return PreviewRequest(versionID: id, key: key, sourceURL: source)
            }
            guard case .image = await service.gainMapHDROutcome(for: try request(1, "a", url), displayHeadroom: 2) else {
                Issue.record("A gain-map photo gives its HDR version")
                return
            }
            guard case .superseded = await service.gainMapHDROutcome(for: try request(2, "b", nil), displayHeadroom: 2) else {
                Issue.record("An offline original is not a failure")
                return
            }
            guard case .failed = await service.gainMapHDROutcome(for: try request(3, "c", plain), displayHeadroom: 2) else {
                Issue.record("A file without a gain map is a failure")
                return
            }
            guard case .superseded = await service.gainMapHDROutcome(for: try request(4, "d", url), displayHeadroom: 2) else {
                Issue.record("A request for a stack saved over since is not a failure")
                return
            }
        }
    }

    @Test("Code review C8: an original that can't be read fails without being remembered as a file with no gain map")
    func unreadableOriginalIsRetried() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let url = root.appending(path: "away.heic")
            try HDRTestImages.writePatternedGainMap(to: url, width: 400, height: 300, seed: 2838)
            let aside = root.appending(path: "aside.heic")
            let plain = root.appending(path: "plain.jpg")
            try SyntheticImages.writeJPEG(to: plain, width: 400, height: 300, seed: 2839)
            let service = PreviewService(cache: PreviewDiskCache(root: root.appending(path: "cache")),
                                         editStack: { _ in .identity })
            func request(_ id: Int64, _ hash: Character, _ source: URL) throws -> PreviewRequest {
                let key = try #require(PreviewCacheKey(contentHash: String(repeating: hash, count: 64),
                                                       editStackHash: EditStack.identity.renderHash, tier: .preview))
                return PreviewRequest(versionID: id, key: key, sourceURL: source)
            }
            // The volume went away (or a share stopped answering) after the request was made.
            try FileManager.default.moveItem(at: url, to: aside)
            #expect(throws: (any Error).self) { try GainMap.read(url) }
            guard case .failed = await service.gainMapHDROutcome(for: try request(1, "a", url), displayHeadroom: 2) else {
                Issue.record("An original that can't be read is a failure at that moment")
                return
            }
            // It came back: the same request (same photo, same edit) asks again and gets its HDR version.
            try FileManager.default.moveItem(at: aside, to: url)
            guard case .image = await service.gainMapHDROutcome(for: try request(1, "a", url), displayHeadroom: 2) else {
                Issue.record("Once readable again, the photo gives its HDR version: nothing remembered it as standard range")
                return
            }
            // A file read whole that has no gain map is still remembered, and still a failure.
            #expect(try GainMap.read(plain) == nil)
            for _ in 0..<2 {
                guard case .failed = await service.gainMapHDROutcome(for: try request(2, "b", plain), displayHeadroom: 2) else {
                    Issue.record("A file without a gain map is a failure")
                    return
                }
            }
        }
    }

    // MARK: The loupe's rules

    @Test("Once HDR is on screen in a visit, no SDR picture replaces it; maps change nothing")
    func visitHoldsHDR() {
        var visit = GainMapVisit()
        var accepted = false
        visit.begin(versionID: 7)
        // Arrival: the cached SDR preview, then HDR: one change.
        accepted = visit.accept(.sdr, wantsHDR: true)
        #expect(accepted)
        accepted = visit.accept(.hdr, wantsHDR: true, headroom: 2.5)
        #expect(accepted)
        #expect(visit.changes == 1)
        #expect(visit.renderedHeadroom == 2.5)
        // A release's cached SDR preview, an SDR full rendition: refused.
        accepted = visit.accept(.sdr, wantsHDR: true)
        #expect(!accepted)
        #expect(visit.shown == .hdr)
        // A map is neither version.
        accepted = visit.accept(.sdr, isMap: true, wantsHDR: true)
        #expect(accepted)
        #expect(visit.shown == .hdr)
        // Following the display's headroom is not a change of version.
        accepted = visit.accept(.hdr, wantsHDR: true, headroom: 2)
        #expect(accepted)
        #expect(visit.changes == 1)
        #expect(visit.renderedHeadroom == 2)
        // A visit that doesn't want HDR shows SDR.
        visit.begin(versionID: 7)
        accepted = visit.accept(.hdr, wantsHDR: false, headroom: 2)
        #expect(accepted)
        accepted = visit.accept(.sdr, wantsHDR: false)
        #expect(accepted)
        #expect(visit.changes == 1)
    }

    @Test("The display's headroom is a current reading that has settled below the layer's request")
    func displayReading() {
        var reading = DisplayHeadroomReading()
        func read(_ value: Float, at time: Double) -> Bool { reading.read(value, at: time) }
        #expect(reading.headroom(potential: 16) == 16)
        // Not asking: readings are not taken.
        #expect(!read(1.2, at: 0))
        // Asking for a photo's ceiling of 4.5 on a display that can give 3.2.
        reading.setRequest(4.5, at: 10)
        // The ramp (measured: about a second): nothing settles.
        var changed = false
        for (step, value) in [1.2, 1.3, 2.0, 2.6, 3.0, 3.2].enumerated() {
            changed = read(Float(value), at: 10 + Double(step) * 0.25) || changed
        }
        #expect(!changed)
        #expect(reading.estimate == nil)
        // Held for half a second, past the grace: what the display gives.
        #expect(!read(3.2, at: 11.5))
        #expect(read(3.2, at: 11.8))
        #expect(reading.estimate == 3.2)
        #expect(reading.headroom(potential: 16) == 3.2)
        #expect(!read(3.2, at: 12.1))
        // Brightness down: the reading rises to the request; the limit is gone.
        #expect(!read(4.5, at: 13))
        #expect(read(4.5, at: 13.6))
        #expect(reading.estimate == nil)
        #expect(reading.headroom(potential: 16) == 16)
        // Brightness up again.
        #expect(!read(2, at: 14))
        #expect(read(2, at: 14.6))
        #expect(reading.headroom(potential: 16) == 2)
        // Stopping keeps the estimate; a new request waits out the grace.
        reading.setRequest(nil, at: 15)
        #expect(!read(1.2, at: 15.5))
        #expect(reading.estimate == 2)
        reading.setRequest(2.6, at: 20)
        #expect(!read(2.6, at: 20.1))
        #expect(!read(2.6, at: 20.7))
        #expect(read(2.6, at: 21.1))
        #expect(reading.estimate == nil)
        // Never above the potential.
        #expect(reading.headroom(potential: 4) == 4)
    }

    @Test("Design §18.1: a reading at a lower request keeps the remembered limit; inactive readings are followed, not kept")
    func rememberedReading() {
        var reading = DisplayHeadroomReading()
        // Learned: the screen allows 3.2 (a photo with ceiling 4.5).
        reading.setRequest(4.5, at: 0)
        reading.read(3.2, at: 0.1)
        let learned = reading.read(3.2, at: 1.2)
        #expect(learned)
        #expect(reading.estimate == 3.2)
        // A photo with a lower ceiling (2.0): the reading settles at its request. That says nothing
        // of the limit, which stays for the next brighter photo (rule 3).
        reading.setRequest(2.0, at: 5)
        reading.read(2.0, at: 5.1)
        let confirmsLower = reading.read(2.0, at: 6.2)
        #expect(!confirmsLower)
        #expect(reading.estimate == 3.2 && reading.headroom(potential: 16) == 3.2)
        // A brighter photo again: it opens at the remembered limit.
        reading.setRequest(4.5, at: 10)
        #expect(reading.headroom(potential: 16) == 3.2)
        // Not active (rule 4): the picture follows the reading, nothing is remembered.
        reading.read(1.3, at: 10.1, remembers: false)
        let followed = reading.read(1.3, at: 11.2, remembers: false)
        #expect(followed)
        #expect(reading.headroom(potential: 16) == 1.3 && reading.estimate == 3.2)
        reading.becameActive()
        #expect(reading.headroom(potential: 16) == 3.2)
        // The screen now allows more than remembered: replaced.
        reading.read(4.5, at: 20)
        let replaced = reading.read(4.5, at: 21.2)
        #expect(replaced)
        #expect(reading.estimate == nil && reading.allowedNow == nil)
    }

    @Test("AC18: each screen's allowance is kept apart and survives the loupe stopping and starting its requests")
    func memoryPerScreen() {
        var memory = DisplayHeadroomMemory()
        // Learned on screen 1 with the app in front.
        memory[1].setRequest(4.5, at: 0)
        memory[1].read(1.29, at: 0.1)
        memory[1].read(1.29, at: 1.2)
        // The loupe goes away (the grid, a video, comparison) and the window moves to screen 2.
        memory[1].setRequest(nil, at: 2)
        #expect(memory[2].headroom(potential: 16) == 16)
        memory[2].setRequest(4.5, at: 3)
        memory[2].read(4.5, at: 3.1)
        memory[2].read(4.5, at: 4.2)
        // Back on screen 1: the next photo opens fitted to what was learned there.
        #expect(memory[1].headroom(potential: 4.18) == 1.29)
        #expect(memory[2].headroom(potential: 16) == 16)
        // Inactive readings are dropped everywhere on activation.
        memory[1].setRequest(4.5, at: 10)
        memory[1].read(1.0, at: 10.1, remembers: false)
        memory[1].read(1.0, at: 11.2, remembers: false)
        #expect(memory[1].headroom(potential: 4.18) == 1.0)
        memory.becameActive()
        #expect(memory[1].headroom(potential: 4.18) == 1.29)
    }

    // MARK: The owner's file

    /// `HEIC_GAINMAP_SAMPLE=path/to/IMG.HEIC` (never committed). Unedited at
    /// the file's headroom the HDR version matches the system's HDR decode
    /// within 0.05 stops; fitted to 1.5 it stays within 1.5; live and settled
    /// renders agree. Prints the means for status.md.
    @Test("A real gain-map HEIC in HDR", .enabled(if: ProcessInfo.processInfo.environment["HEIC_GAINMAP_SAMPLE"] != nil))
    func sample() async throws {
        let url = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["HEIC_GAINMAP_SAMPLE"]))
        let generator = PreviewGenerator()
        let made = try #require(try generator.gainMapHDRImage(source: url, stack: .identity, longEdge: 2560,
                                                              displayHeadroom: 100))
        let system = try Self.systemHDR(url)
        let size = CGSize(width: made.image.width / 4, height: made.image.height / 4)
        let ours = Pixels(made.image, size: size)
        let theirs = Pixels(system, size: size)
        let stops = log2(ours.mean / theirs.mean)
        print(String(format: "sample: file headroom %.2f, ceiling %.2f, HDR mean %.3f, system HDR mean %.3f (%+.3f stops)",
                     made.fileHeadroom, made.ceiling, ours.mean, theirs.mean, stops))
        #expect(abs(stops) < 0.05)
        let fitted = try #require(try generator.gainMapHDRImage(source: url, stack: .identity, longEdge: 2560,
                                                                displayHeadroom: 1.5))
        #expect(Pixels(fitted.image).maximum <= 1.5 * 1.001)
        let session = LiveRenderSession(source: url, generator: generator, colorSpace: nil)
        for (name, stack) in [("identity", EditStack.identity),
                              ("exposure -1", Self.stack(Self.operation("exposure", ["ev": -1]))),
                              ("contrast +20", Self.stack(Self.operation("tone", ["contrast": 20])))] {
            let frame = try await session.render(Adjustments(stack: stack), hdrHeadroom: 3)
            let settled = try #require(try generator.gainMapHDRImage(source: url, stack: stack, longEdge: 2560,
                                                                     displayHeadroom: 3))
            let live = Pixels(frame.image.cgImage, size: size).mean
            let still = Pixels(settled.image, size: size).mean
            print(String(format: "sample: %@ at 3: live %.4f settled %.4f (%+.4f stops), %.1f ms",
                         name, live, still, log2(live / still), frame.seconds * 1000))
            #expect(abs(log2(live / still)) < 0.005)
        }
    }
}
