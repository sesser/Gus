import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

extension CommandRegistry {
    /// Every command, in the order `help` lists them.
    public static let standard = CommandRegistry(commands: [
        RenderCommands.render, RenderCommands.adjustments,
        LibraryCommands.projects, LibraryCommands.images,
        LibraryCommands.develop, LibraryCommands.rate, LibraryCommands.flag, LibraryCommands.label,
        LibraryCommands.export, MergeCommands.merge,
        MaskCommands.list, MaskCommands.add, MaskCommands.set, MaskCommands.remove,
    ])
}

enum RenderCommands {
    static let render = CommandSpec(
        id: "render",
        summary: """
            Renders a master file, or a version from the library, through the preview pipeline to a PNG (16 bits), \
            JPEG or TIFF (16 bits), chosen by the output's extension.
            """,
        access: .read,
        parameters: [
            CommandParameter("input", .path, "A master file to render (or --version).", positional: true),
            CommandParameter("version", .integer, "A version id from the library (or a file)."),
            CommandParameter("libraryRoot", .path, """
                The library folder. With --version, the app's standard library when left out; a file is rendered \
                without reading any library unless this names one.
                """),
            CommandParameter("out", .path, """
                Where to write the image. Never an original: the file being rendered is refused, and so is a master \
                of the library the command reads (--version or --library-root), by place or by content \
                (outputIsMaster). A file rendered without --library-root is checked against itself only.
                """, required: true),
            CommandParameter("longEdge", .integer, "Largest side in pixels; full resolution when left out."),
            CommandParameter("stack", .path, "An edit stack (JSON) used instead of the version's own."),
            CommandParameter("set", .string, "kind.parameter=value, applied over the stack (see adjustments).",
                             repeatable: true),
            CommandParameter("original", .flag, "Render without any edits."),
            CommandParameter("colorSpace", .string, "sRGB (default), displayP3, adobeRGB or proPhoto."),
            CommandParameter("software", .flag, "Core Image's software renderer, where there is one."),
            CommandParameter("demosaic", .string, """
                For a raw LibRaw decodes: automatic (the default: the GPU demosaic where the pattern allows) or \
                libraw (LibRaw's own demosaic, for comparing).
                """),
        ],
        run: runRender)

    static let adjustments = CommandSpec(
        id: "adjustments",
        summary: """
            Lists every adjustment module with its parameters (names, types, ranges and defaults), and under local \
            the masks' controls, shapes, operations and limits.
            """,
        access: .read,
        parameters: [],
        run: { _ in ["modules": .array(Adjustments.moduleDescriptions.map(describe)), "local": MaskCommands.description] })

    static func describe(_ module: AdjustmentModuleDescription) -> JSONValue {
        let section = module.group.flatMap { group in Adjustments.Section.allCases.first { $0.groups.contains(group) } }
        return [
            "kind": .string(module.kind.rawValue),
            "group": JSONValue(module.group?.rawValue),
            "section": JSONValue(section?.rawValue),
            "parameters": .array(module.parameters.map { parameter in
                var object: [String: JSONValue] = [
                    "name": .string(parameter.name),
                    "default": parameter.defaultValue.map(JSONValue.init) ?? .null,
                ]
                switch parameter.type {
                case .number(let range):
                    object["type"] = "number"
                    object["minimum"] = .number(range.lowerBound)
                    object["maximum"] = .number(range.upperBound)
                case .integer(let range):
                    object["type"] = "integer"
                    object["minimum"] = JSONValue(range.lowerBound)
                    object["maximum"] = JSONValue(range.upperBound)
                case .choice(let values):
                    object["type"] = "choice"
                    object["values"] = .array(values.map(JSONValue.string))
                case .text:
                    object["type"] = "text"
                case .points:
                    object["type"] = "points"
                case .boolean:
                    object["type"] = "boolean"
                case .okLabColor:
                    object["type"] = "color"
                    object["names"] = .array(CommonFringeColor.allCases.map { .string($0.rawValue) })
                }
                return .object(object)
            }),
        ]
    }

    /// The output format, from the file extension.
    enum OutputFormat: String {
        case png, jpeg, tiff

        init?(url: URL) {
            switch url.pathExtension.lowercased() {
            case "png": self = .png
            case "jpg", "jpeg": self = .jpeg
            case "tif", "tiff": self = .tiff
            default: return nil
            }
        }

        var type: UTType {
            switch self {
            case .png: .png
            case .jpeg: .jpeg
            case .tiff: .tiff
            }
        }

        var bitsPerComponent: Int { self == .jpeg ? 8 : 16 }
    }

    static func runRender(_ invocation: CommandInvocation) async throws -> JSONValue {
        let arguments = invocation.arguments
        let environment = invocation.environment
        let out = environment.url(arguments.string("out") ?? "")
        guard let format = OutputFormat(url: out) else {
            throw CommandError(.invalidValue, "--out must end in .png, .jpg or .tif")
        }
        let colorSpaceName = arguments.string("colorSpace") ?? ExportSettings.ColorSpace.sRGB.rawValue
        guard let colorSpace = ExportSettings.ColorSpace(rawValue: colorSpaceName) else {
            throw CommandError(.invalidValue, "--color-space is one of "
                               + ExportSettings.ColorSpace.allCases.map(\.rawValue).joined(separator: ", "))
        }
        let software = arguments.flag("software")
        var demosaic: LibRawDecoder.DemosaicChoice?
        if let name = arguments.string("demosaic") {
            guard let choice = LibRawDecoder.DemosaicChoice(rawValue: name.lowercased()) else {
                throw CommandError(.invalidValue, "--demosaic is automatic or libraw")
            }
            demosaic = choice
        }
        if software, !RenderEngine.softwareRendererIsAvailable {
            throw CommandError(.softwareRendererUnavailable, """
                Core Image has no software renderer on this Mac (it needs OpenCL, which Apple silicon does not have); \
                leave out --software to render on the GPU.
                """)
        }
        let edits: [AdjustmentEdit]
        do throws(AdjustmentEdit.Failure) {
            edits = try arguments.strings("set").map(AdjustmentEdit.parseSet)
        } catch {
            throw LibraryCommands.commandError(error)
        }
        if arguments.flag("original"), !edits.isEmpty || arguments.string("stack") != nil {
            throw CommandError(.conflictingOptions, "--original renders without edits: leave out --set and --stack")
        }

        // The source and its stored stack.
        let source: URL
        var stack = EditStack.identity
        var library: OpenLibrary?
        var versionID: Int64?
        switch (arguments.string("input"), arguments.integer("version")) {
        case (let input?, nil):
            source = environment.url(input)
            if arguments.string("libraryRoot") != nil {
                library = try environment.openLibrary(arguments)
            }
        case (nil, let id?):
            let opened = try environment.openLibrary(arguments)
            guard let details = try await opened.catalog.details(forVersion: Int64(id)) else {
                throw CommandError(.versionNotFound, "No version \(id)")
            }
            source = details.volume.url(forRelativePath: details.image.relativePath)
            stack = try details.version.readableEditStack()
            library = opened
            versionID = Int64(id)
        default:
            throw CommandError(.missingArgument, "render needs a file or --version, not both")
        }
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw CommandError(.fileNotFound, "No file at \(source.path)")
        }
        // Before rendering, which can take seconds: an output that is refused is refused at once.
        try await refuseOriginal(out, source: source, library: library)
        if let stackPath = arguments.string("stack") {
            do {
                stack = try EditStack.decode(from: Data(contentsOf: environment.url(stackPath)))
            } catch {
                throw CommandError(.invalidValue, "--stack is not an edit stack: \(error)")
            }
        }
        do throws(AdjustmentEdit.Failure) {
            stack = try stack.applying(edits)
        } catch {
            throw LibraryCommands.commandError(error)
        }
        if arguments.flag("original") {
            stack = .identity
        }

        // The preview generator's path, as export uses it.
        let engine = RenderEngine(contextCount: 1, name: "command-line", softwareRenderer: software)
        let generator = PreviewGenerator(engine: engine, renderer: AdjustmentRenderer(lookTables: library?.lookTables,
                                                                                     maskRasters: library?.maskRasters))
        let clock = ContinuousClock()
        let started = clock.now
        let rendering = try LibRawDecoder.$demosaicOverride.withValue(demosaic) {
            try generator.rendering(source: source, stack: stack, longEdge: arguments.integer("longEdge"))
        }
        let image = rendering.image
        guard let cgImage = engine.makeCGImage(image, colorSpace: colorSpace.cgColorSpace,
                                               bitsPerComponent: format.bitsPerComponent)
        else { throw CommandError(.renderFailed, "Rendering \(source.path) failed") }
        let renderTime = clock.now - started
        try write(cgImage, format: format, to: out)

        var result: [String: JSONValue] = [
            "output": .string(out.path),
            "source": .string(source.path),
            "format": .string(format.rawValue),
            "width": JSONValue(cgImage.width),
            "height": JSONValue(cgImage.height),
            "bitsPerComponent": JSONValue(format.bitsPerComponent),
            "colorSpace": .string(colorSpace.rawValue),
            "renderer": .string(software ? "software" : (engine.isMetalBacked ? "metal" : "default")),
            "renderSeconds": .number(Double(renderTime.components.attoseconds) / 1e18
                                     + Double(renderTime.components.seconds)),
            "renderHash": .string(stack.renderHash),
            "editStack": try JSONValue(encoding: stack),
        ]
        if let versionID { result["versionID"] = JSONValue(versionID) }
        result["machineLearning"] = machineLearningJSON(rendering.machineLearning)
        result["decoder"] = .string(decoderName(rendering.decoder))
        if let demosaic = rendering.demosaic { result["demosaic"] = demosaicJSON(demosaic) }
        result["lensCorrections"] = lensCorrectionsJSON(Adjustments(stack: stack), lens: rendering.lens)
        return .object(result)
    }

    /// Per lens correction group (issue #87, design §16): the source status
    /// the Adjust tab shows by name (`LensCorrectionStatus.Caption`) and
    /// whether the render applied the group.
    static func lensCorrectionsJSON(_ values: Adjustments, lens: CameraLensState?) -> JSONValue {
        let plan = LensCorrectionPlan(values.effective, lens: lens)
        var object: [String: JSONValue] = [:]
        for group in LensCorrectionStatus.Group.allCases {
            let status = LensCorrectionStatus(group, values: values, lens: lens,
                                              kernelsAvailable: AdjustmentRenderer.lensCorrectionKernelsAvailable)
            let applied = group == .distortion ? plan.warp != nil : plan.gain != nil
            object[group.rawValue] = ["status": .string(status.caption.rawValue),
                                      "applied": .bool(applied && AdjustmentRenderer.lensCorrectionKernelsAvailable)]
        }
        return .object(object)
    }

    static func decoderName(_ decoder: PreviewGenerator.Decoder) -> String {
        switch decoder {
        case .systemRAW: "systemRAW"
        case .libRaw: "libRaw"
        case .imageIO: "imageIO"
        }
    }

    /// Which demosaic made a LibRaw decode (R20): `method` gpu or libraw,
    /// with the pattern (`bayer`, `xTrans`) or the reason LibRaw's was used.
    static func demosaicJSON(_ demosaic: LibRawDecoder.Demosaic) -> JSONValue {
        switch demosaic {
        case .gpu(let kind): ["method": "gpu", "pattern": .string(kind.rawValue)]
        case .libRaw(let reason): ["method": "libraw", "reason": .string(reason)]
        }
    }

    /// Whether a stack's machine learning noise reduction was asked for and
    /// applied, and why not (PRD R13): `requested`, `applied`, and with a
    /// reason, `reason` (`MachineLearningNoiseReduction.Reason`) and `message`.
    static func machineLearningJSON(_ outcome: MachineLearningNoiseReduction.Outcome) -> JSONValue {
        var object: [String: JSONValue] = [
            "requested": .bool(outcome != .notRequested),
            "applied": .bool(outcome.isApplied),
        ]
        if let reason = outcome.reason {
            object["reason"] = .string(reason.rawValue)
            object["message"] = .string(reason.message)
        }
        return .object(object)
    }

    /// Originals are never written (#166). `--out` names one exact file, so
    /// one that is an original is an error, never a numbered name as export
    /// gives.
    ///
    /// The file being rendered is refused always: by place (the same folder
    /// and a name the file system takes for the same, `MasterFiles`) or by
    /// identity (a hard link, or a link to it).
    ///
    /// When the command opened a library (`--version`, or `--library-root`),
    /// every master in its catalog is refused too, by place (at its recorded
    /// mount and where its volume is mounted now) or by content
    /// (`holdsContent(ofFileAt:)`), as export asks.
    ///
    /// A file rendered without `--library-root` reads no library at all
    /// (owner's ruling on #222, 2026-11-19, narrowing the #166 ruling): even a
    /// read-only open of the standard catalog writes its `-shm` file. So only
    /// the input is refused there.
    static func refuseOriginal(_ out: URL, source: URL, library: OpenLibrary?) async throws(CommandError) {
        if MasterFiles([source]).contains(out) || isSameFile(out, source) {
            throw CommandError(.outputIsMaster, """
                --out is the file being rendered, \(source.path); originals are never written. Choose another file.
                """)
        }
        guard let library else { return }
        let masters: MasterFiles
        do {
            masters = try await library.catalog.masterFiles(mounted: VolumeAvailability.mountedVolumes())
        } catch {
            throw CommandError(.failed, "Could not read the library's masters, so nothing was written: \(error)")
        }
        if masters.contains(out) || masters.holdsContent(ofFileAt: out) {
            throw CommandError(.outputIsMaster, """
                --out is \(out.path), an original in the library (or a copy of one); originals are never written. \
                Choose another file.
                """)
        }
    }

    /// Whether two paths reach the same file (links followed, hard links
    /// included). False when either is missing.
    static func isSameFile(_ first: URL, _ second: URL) -> Bool {
        let key: Set<URLResourceKey> = [.fileResourceIdentifierKey]
        guard let one = try? first.resolvingSymlinksInPath().resourceValues(forKeys: key).fileResourceIdentifier,
              let other = try? second.resolvingSymlinksInPath().resourceValues(forKeys: key).fileResourceIdentifier
        else { return false }
        return one.isEqual(other)
    }

    /// Writes next to the target, then moves into place: the file appears complete or not at all.
    static func write(_ image: CGImage, format: OutputFormat, to url: URL) throws(CommandError) {
        let temporary = url.deletingLastPathComponent()
            .appending(path: ".\(url.lastPathComponent).\(UUID().uuidString).partial", directoryHint: .notDirectory)
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard let destination = CGImageDestinationCreateWithURL(temporary as CFURL, format.type.identifier as CFString,
                                                                1, nil)
        else { throw CommandError(.writeFailed, "Cannot write \(url.path)") }
        let properties: [CFString: Any] = format == .jpeg ? [kCGImageDestinationLossyCompressionQuality: 0.92] : [:]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CommandError(.writeFailed, "Cannot write \(url.path)") }
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
            } else {
                try FileManager.default.moveItem(at: temporary, to: url)
            }
        } catch {
            throw CommandError(.writeFailed, "Cannot write \(url.path): \(error.localizedDescription)")
        }
    }
}
