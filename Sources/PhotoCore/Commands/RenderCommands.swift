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
        LibraryCommands.export,
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
            CommandParameter("libraryRoot", .path, "The library folder; the app's standard library when left out."),
            CommandParameter("out", .path, "Where to write the image.", required: true),
            CommandParameter("longEdge", .integer, "Largest side in pixels; full resolution when left out."),
            CommandParameter("stack", .path, "An edit stack (JSON) used instead of the version's own."),
            CommandParameter("set", .string, "kind.parameter=value, applied over the stack (see adjustments).",
                             repeatable: true),
            CommandParameter("original", .flag, "Render without any edits."),
            CommandParameter("colorSpace", .string, "sRGB (default), displayP3, adobeRGB or proPhoto."),
            CommandParameter("software", .flag, "Core Image's software renderer, where there is one."),
        ],
        run: runRender)

    static let adjustments = CommandSpec(
        id: "adjustments",
        summary: "Lists every adjustment module with its parameters: names, types, ranges and defaults.",
        access: .read,
        parameters: [],
        run: { _ in ["modules": .array(Adjustments.moduleDescriptions.map(describe))] })

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
        let generator = PreviewGenerator(engine: engine, renderer: AdjustmentRenderer(lookTables: library?.lookTables))
        let clock = ContinuousClock()
        let started = clock.now
        let image = try generator.image(source: source, stack: stack, longEdge: arguments.integer("longEdge"))
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
        return .object(result)
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
