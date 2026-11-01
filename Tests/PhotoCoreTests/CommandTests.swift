import Foundation
import PhotoFixtures
import Testing
@testable import PhotoCore

/// The command line, run in process through `CommandLineInterface` against a
/// temporary library.
@Suite("Commands")
struct CommandTests {
    /// A library with three JPEGs imported in place.
    struct TemporaryLibrary {
        var root: URL
        var photos: URL
        var locations: LibraryLocations
        var versionIDs: [Int64]
        var cli: CommandLineInterface

        /// Runs a command line with this library's root added; the result is
        /// stdout's object, or stderr's on failure.
        func run(_ arguments: String...) async -> (output: CommandLineInterface.Output, json: JSONValue) {
            let output = await cli.run(arguments + ["--library-root", root.path])
            let text = output.exitCode == 0 ? output.standardOutput : output.standardError
            return (output, (try? JSONValue.parse(text)) ?? .null)
        }
    }

    static func withLibrary(_ body: (TemporaryLibrary) async throws -> Void) async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let photos = root.appending(path: "Photos", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: photos, withIntermediateDirectories: true)
            for index in 1...3 {
                try SyntheticImages.writeJPEG(to: photos.appending(path: "IMG_000\(index).jpg"), width: 320, height: 240,
                                              seed: UInt64(index),
                                              exif: .init(dateTimeOriginal: "2026:10:0\(index) 10:00:00"))
            }
            let locations = LibraryLocations.rooted(at: root.appending(path: "Library", directoryHint: .isDirectory))
            try locations.createDirectories()
            let catalog = try Catalog.open(at: locations.catalogFileURL)
            _ = try await Importer(catalog: catalog, metadataReader: ImageIOMetadataReader()).importFolder(photos)
            let ids = try await catalog.libraryItems(matching: LibraryFilter(groupsPairs: false)).map(\.versionID)
            let cli = CommandLineInterface(environment: CommandEnvironment(currentDirectory: root))
            try await body(TemporaryLibrary(root: root.appending(path: "Library"), photos: photos, locations: locations,
                                            versionIDs: ids, cli: cli))
        }
    }

    // MARK: Output contract

    @Test("Success prints one object on stdout; failure one object with error and code on stderr")
    func outputContract() async throws {
        try await Self.withLibrary { library in
            let success = await library.run("query", "projects")
            #expect(success.output.exitCode == 0 && success.output.standardError.isEmpty)
            #expect(success.json["projects"]?.arrayValue?.count == 1)

            let usage = await library.run("rate", "--version", "1", "--stars", "3")
            #expect(usage.output.exitCode == 2 && usage.output.standardOutput.isEmpty)
            #expect(usage.json["code"] == "unknownOption" && usage.json["error"]?.stringValue != nil)

            let failure = await library.run("rate", "--version", "999", "--rating", "3")
            #expect(failure.output.exitCode == 1 && failure.output.standardOutput.isEmpty)
            #expect(failure.json["code"] == "versionNotFound")

            let missing = await library.cli.run(["query", "projects", "--library-root", library.root.path + "-nope"])
            #expect(missing.exitCode == 1 && missing.standardError.contains("libraryNotFound"))
        }
    }

    @Test("Help names the product from the branding and lists every command")
    func helpListsCommands() async throws {
        let cli = CommandLineInterface(environment: CommandEnvironment(currentDirectory: URL(fileURLWithPath: "/")))
        let output = await cli.run(["help"])
        let json = try JSONValue.parse(output.standardOutput)
        #expect(json["product"] == .string(AppBranding.displayName))
        #expect(json["commands"]?.arrayValue?.compactMap { $0["id"]?.stringValue }
                == CommandRegistry.standard.commands.map(\.id))
        let topic = try JSONValue.parse(await cli.run(["help", "query", "images"]).standardOutput)
        #expect(topic["command"]?["id"] == "query.images")
    }

    // MARK: Render

    @Test("Rendering the same file with the same edits gives the same bytes")
    func renderIsDeterministic() async throws {
        try await Self.withLibrary { library in
            let input = library.photos.appending(path: "IMG_0001.jpg").path
            var outputs: [Data] = []
            for name in ["a.png", "b.png"] {
                let out = library.root.deletingLastPathComponent().appending(path: name).path
                let result = await library.run("render", input, "--out", out, "--long-edge", "200",
                                               "--set", "exposure.ev=0.5", "--set", "presence.clarity=40")
                #expect(result.output.exitCode == 0, "\(result.output.standardError)")
                #expect(result.json["width"] == 200 && result.json["height"] == 150)
                #expect(result.json["bitsPerComponent"] == 16 && result.json["colorSpace"] == "sRGB")
                outputs.append(try Data(contentsOf: URL(fileURLWithPath: out)))
            }
            #expect(outputs[0] == outputs[1])
            let expected = try EditStack.identity.applying([.set(kind: "exposure", parameter: "ev", value: "0.5"),
                                                            .set(kind: "presence", parameter: "clarity", value: "40")])
            let result = await library.run("render", input, "--out",
                                           library.root.deletingLastPathComponent().appending(path: "c.jpg").path,
                                           "--set", "exposure.ev=0.5", "--set", "presence.clarity=40")
            #expect(result.json["renderHash"] == .string(expected.renderHash))
            #expect(result.json["format"] == "jpeg" && result.json["width"] == 320)
        }
    }

    @Test("Rendering a version uses its stored edits")
    func renderVersion() async throws {
        try await Self.withLibrary { library in
            let id = String(library.versionIDs[0])
            _ = await library.run("develop", "--version", id, "--set", "tone.contrast=30")
            let out = library.root.deletingLastPathComponent().appending(path: "v.tif").path
            let result = await library.run("render", "--version", id, "--out", out)
            #expect(result.output.exitCode == 0, "\(result.output.standardError)")
            #expect(result.json["editStack"]?["operations"]?.arrayValue?.first?["kind"] == "tone")
            let original = await library.run("render", "--version", id, "--out", out, "--original")
            #expect(original.json["renderHash"] == .string(EditStack.identity.renderHash))
        }
    }

    @Test("--software is refused where Core Image has no software renderer")
    func softwareRendererIsReported() async throws {
        try await Self.withLibrary { library in
            let result = await library.run("render", library.photos.appending(path: "IMG_0001.jpg").path, "--out",
                                           library.root.deletingLastPathComponent().appending(path: "s.png").path,
                                           "--software")
            if RenderEngine.softwareRendererIsAvailable {
                #expect(result.json["renderer"] == "software")
            } else {
                #expect(result.json["code"] == "softwareRendererUnavailable")
            }
        }
    }

    // MARK: --set

    @Test("--set values are checked against the module descriptions",
          arguments: [
              ("exposure.ev=1", nil), ("toneCurve.rgb=0,0,0.5,0.6,1,1", nil), ("rawDecode.look=flat", nil),
              ("whiteBalance.temperature=5000", nil),
              ("exposure.ev=9", "exposure.ev: 9.0 is outside -5.0 … 5.0"),
              ("exposure.ev=bright", "exposure.ev: not a number: bright"),
              ("exposure=1", "exposure=1 is not kind.parameter=value (or kind.parameter, kind, all to reset)"),
              ("nope.ev=1", "No adjustment module nope; see the adjustments command"),
              ("exposure.stops=1", "exposure has no parameter stops"),
              ("rawDecode.look=fancy", "rawDecode.look: one of standard, neutral, flat"),
              ("toneCurve.rgb=0,0,1", "toneCurve.rgb: a list x0,y0,x1,y1,… of at least two points, each 0 … 1"),
              ("crop.x=0.1", "crop.x has no effect alone (a crop needs x, y, width and height)"),
          ] as [(String, String?)])
    func setParsing(text: String, error: String?) async throws {
        try await Self.withLibrary { library in
            let result = await library.run("develop", "--version", String(library.versionIDs[0]), "--set", text,
                                           "--dry-run")
            if let error {
                #expect(result.output.exitCode == 1)
                #expect(result.json["code"] == "invalidEdit")
                #expect(result.json["error"] == .string(error))
            } else {
                #expect(result.output.exitCode == 0, "\(result.output.standardError)")
                #expect(result.json["written"] == false && result.json["changed"] == true)
            }
        }
    }

    @Test("Setting a default leaves the parameter out; resets come before sets")
    func editsNormalize() throws {
        let stack = try EditStack.identity.applying([.set(kind: "exposure", parameter: "ev", value: "1")])
        #expect(try stack.applying([.set(kind: "exposure", parameter: "ev", value: "0")]) == .identity)
        #expect(try stack.applying([.reset(kind: "exposure", parameter: nil)]) == .identity)
        #expect(try stack.applying([.resetAll]) == .identity)
        let crop = try EditStack.identity.applying(["x=0.1", "y=0.1", "width=0.5", "height=0.5"].map {
            .set(kind: "crop", parameter: String($0.split(separator: "=")[0]), value: String($0.split(separator: "=")[1]))
        })
        #expect(Adjustments(stack: crop).crop.rect == CropRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5))
    }

    @Test("Changing a module that is turned off turns it back on")
    func editsEnableModules() throws {
        var adjustments = Adjustments()
        adjustments.exposure.ev = 1
        adjustments.setEnabled(.light, false)
        let changed = try adjustments.editStack.applying([.set(kind: "exposure", parameter: "ev", value: "2")])
        #expect(Adjustments(stack: changed).isEnabled(.light))
    }

    // MARK: Library

    @Test("develop then query: the stored stack and its hash come back")
    func developThenQuery() async throws {
        try await Self.withLibrary { library in
            let id = library.versionIDs[1]
            let developed = await library.run("develop", "--version", String(id), "--set", "exposure.ev=1",
                                              "--set", "vignette.amount=-40")
            #expect(developed.json["written"] == true)
            let hash = try #require(developed.json["renderHash"])

            let rules = #"{"rules": [{"field": "fileName", "comparison": "contains", "value": {"text": "IMG_0002"}}]}"#
            let query = await library.run("query", "images", rules)
            #expect(query.output.exitCode == 0, "\(query.output.standardError)")
            let images = try #require(query.json["images"]?.arrayValue)
            #expect(images.count == 1)
            #expect(images.first?["versionID"] == JSONValue(id))
            #expect(images.first?["renderHash"] == hash)
            let kinds = images.first?["editStack"]?["operations"]?.arrayValue?.compactMap { $0["kind"]?.stringValue }
            #expect(kinds == ["exposure", "vignette"])

            let reset = await library.run("develop", "--version", String(id), "--reset", "all", "--set", "exposure.ev=2")
            #expect(reset.json["editStack"]?["operations"]?.arrayValue?.count == 1)
        }
    }

    @Test("rate, flag and label write; query reads them back")
    func cullingRoundTrip() async throws {
        try await Self.withLibrary { library in
            let ids = library.versionIDs.prefix(2).map(String.init)
            #expect(await library.run("rate", "--version", ids[0], "--version", ids[1], "4").output.exitCode == 0)
            #expect(await library.run("flag", "--version", ids[0], "--flag", "picked").output.exitCode == 0)
            #expect(await library.run("label", "--version", ids[1], "--label", "blue").output.exitCode == 0)
            #expect(await library.run("rate", "--version", ids[0], "--rating", "6").json["code"] == "invalidValue")

            let rules = #"[{"field": "rating", "comparison": "atLeast", "value": {"number": 4}}]"#
            let images = try #require(await library.run("query", "images", "--rules", rules).json["images"]?.arrayValue)
            #expect(images.count == 2)
            let first = images.first { $0["versionID"]?.numberValue == Double(ids[0]) }
            #expect(first?["flag"] == "picked" && first?["rating"] == 4)
            #expect(images.first { $0["versionID"]?.numberValue == Double(ids[1]) }?["colorLabel"] == "blue")
        }
    }

    @Test("Write commands refuse while the app holds the library lock; reads go on")
    func writesRefuseWhileLocked() async throws {
        try await Self.withLibrary { library in
            let id = String(library.versionIDs[0])
            let lock = try LibraryLock.acquire(library.locations)

            let refused = await library.run("rate", "--version", id, "--rating", "2")
            #expect(refused.output.exitCode == 1 && refused.json["code"] == "libraryLocked")
            #expect(refused.json["error"]?.stringValue?.contains("process \(getpid())") == true)
            let develop = await library.run("develop", "--version", id, "--set", "exposure.ev=1")
            #expect(develop.json["code"] == "libraryLocked")
            #expect(await library.run("develop", "--version", id, "--set", "exposure.ev=1", "--dry-run")
                        .output.exitCode == 0)
            #expect(await library.run("query", "projects").output.exitCode == 0)
            #expect(await library.run("query", "images").json["images"]?.arrayValue?.first?["rating"] == 0)

            lock.release()
            #expect(await library.run("rate", "--version", id, "--rating", "2").output.exitCode == 0)
            // The command gave the lock back when it was done.
            #expect(throws: Never.self) { try LibraryLock.acquire(library.locations).release() }
        }
    }

    @Test("export writes the versions with inline settings")
    func exportWritesFiles() async throws {
        try await Self.withLibrary { library in
            let destination = library.root.deletingLastPathComponent().appending(path: "Out").path
            let result = await library.run("export", "--version", String(library.versionIDs[0]), "--to", destination,
                                           "--settings", #"{"format": "tiff", "sizing": "longEdge", "edgeLength": 100}"#)
            #expect(result.output.exitCode == 0, "\(result.output.standardError)")
            let written = try #require(result.json["written"]?.arrayValue?.first?.stringValue)
            #expect(written.hasSuffix(".tif"))
            let size = try #require(PreviewGenerator.nativeSize(URL(fileURLWithPath: written)))
            #expect(max(size.width, size.height) == 100)
            #expect(await library.run("export", "--version", String(library.versionIDs[0]), "--to", destination,
                                      "--preset", "Nope").json["code"] == "presetNotFound")
        }
    }

    // MARK: adjustments

    @Test("adjustments lists every module and every parameter")
    func adjustmentsListsEveryModule() async throws {
        let cli = CommandLineInterface(environment: CommandEnvironment(currentDirectory: URL(fileURLWithPath: "/")))
        let json = try JSONValue.parse(await cli.run(["adjustments"]).standardOutput)
        let modules = try #require(json["modules"]?.arrayValue)
        let kinds = Set(modules.compactMap { $0["kind"]?.stringValue })
        let expected = Set(Adjustments.Group.allCases.flatMap(\.kinds).map(\.rawValue) + [Crop.kind.rawValue])
        #expect(kinds == expected)
        let exposure = modules.first { $0["kind"] == "exposure" }
        #expect(exposure?["group"] == "light" && exposure?["section"] == "develop")
        #expect(exposure?["parameters"]?.arrayValue?.first?["minimum"] == -5)
    }
}

/// The parameter descriptions against what each module reads and writes.
@Suite("Adjustment parameters")
struct AdjustmentParameterTests {
    /// A value other than the default.
    static func otherValue(_ parameter: AdjustmentParameter) -> EditParameter {
        switch parameter.type {
        case .number(let range):
            let value = range.lowerBound + (range.upperBound - range.lowerBound) * 0.375
            return .number(parameter.defaultValue == .number(value) ? range.upperBound : value)
        case .integer(let range):
            return .number(Double(parameter.defaultValue == .number(Double(range.upperBound)) ? range.lowerBound
                                  : range.upperBound))
        case .choice(let values):
            return .string(values.last { .string($0) != parameter.defaultValue } ?? values[0])
        case .text:
            return .string("test")
        case .points:
            return .list([0, 0.1, 1, 0.9].map(EditParameter.number))
        }
    }

    @Test("Every parameter a module writes is described, and every description is read",
          arguments: Adjustments.moduleDescriptions.map(\.kind.rawValue))
    func descriptionsMatchModules(kind: String) throws {
        let module = try #require(Adjustments.moduleDescription(EditOperationKind(rawValue: kind)))
        var parameters: [String: EditParameter] = [:]
        for parameter in module.parameters {
            parameters[parameter.name] = Self.otherValue(parameter)
        }
        let stack = EditStack(operations: [EditOperation(kind: module.kind, parameters: parameters)])
        let written = Adjustments(stack: stack).parameters(of: module.kind)
        #expect(Set(written.keys) == Set(module.parameters.map(\.name)))
        #expect(written == parameters)
    }

    @Test("A parameter at its described default is left out",
          arguments: Adjustments.moduleDescriptions.map(\.kind.rawValue))
    func defaultsAreLeftOut(kind: String) throws {
        let module = try #require(Adjustments.moduleDescription(EditOperationKind(rawValue: kind)))
        for parameter in module.parameters {
            guard let value = parameter.defaultValue else { continue }
            let stack = EditStack(operations: [EditOperation(kind: module.kind, parameters: [parameter.name: value])])
            #expect(Adjustments(stack: stack).parameters(of: module.kind)[parameter.name] == nil, "\(parameter.name)")
        }
    }
}
