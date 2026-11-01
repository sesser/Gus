import Foundation

/// Commands over a library's catalog. Reads are always allowed; writes go
/// through the same `Catalog` calls the app makes, each as one transaction,
/// and are not undoable (undo belongs to the app's window).
enum LibraryCommands {
    static let libraryRoot = CommandParameter("libraryRoot", .path,
                                              "The library folder; the app's standard library when left out.")
    static let versions = CommandParameter("version", .integer, "A version id; repeat for several.", required: true,
                                           repeatable: true)

    // MARK: Query

    static let projects = CommandSpec(
        id: "query.projects",
        summary: "Lists the library's projects with their photo counts.",
        access: .read,
        parameters: [libraryRoot],
        run: { invocation in
            let library = try invocation.environment.openLibrary(invocation.arguments)
            let summaries = try await library.catalog.projectSummaries(groupingPairs: false)
            return ["projects": .array(summaries.map { summary in
                [
                    "id": JSONValue(summary.id),
                    "name": .string(summary.project.name),
                    "sourcePath": JSONValue(summary.project.sourcePath),
                    "createdAt": .string(ISO8601DateFormatter().string(from: summary.project.createdAt)),
                    "versionCount": JSONValue(summary.versionCount),
                ]
            })]
        })

    static let images = CommandSpec(
        id: "query.images",
        summary: """
            Lists versions matching a smart-album rule set given as JSON: {"match": "all"|"any", "rules": [{"field", \
            "comparison", "value"}]} (an array of rules alone means "all"; no rules lists everything). Each item has \
            its rating, flag, label, keywords and stored edit stack. Both files of a RAW+JPEG pair are listed.
            """,
        access: .read,
        parameters: [
            CommandParameter("rules", .json, "The rules, as JSON.", positional: true),
            CommandParameter("project", .integer, "Only this project."),
            CommandParameter("limit", .integer, "At most this many items (default 1000)."),
            libraryRoot,
        ],
        run: runImages)

    static func runImages(_ invocation: CommandInvocation) async throws -> JSONValue {
        let arguments = invocation.arguments
        let rules = try smartAlbumRules(arguments.values["rules"])
        let library = try invocation.environment.openLibrary(arguments)
        let filter = LibraryFilter(scope: .rules(rules, projectID: arguments.integer("project").map(Int64.init)),
                                   groupsPairs: false)
        let items = try await library.catalog.libraryItems(matching: filter)
        let limit = max(0, arguments.integer("limit") ?? 1000)
        var results: [JSONValue] = []
        for item in items.prefix(limit) {
            guard let details = try await library.catalog.details(forVersion: item.versionID) else { continue }
            let keywords = try await library.catalog.keywords(forVersion: item.versionID).map(\.name)
            results.append(try describe(details, keywords: keywords))
        }
        return ["count": JSONValue(items.count), "truncated": .bool(items.count > limit), "images": .array(results)]
    }

    /// Smart-album rules from scripts: ids are optional, a missing comparison
    /// takes the field's first one, a missing value is empty.
    static func smartAlbumRules(_ value: JSONValue?) throws(CommandError) -> SmartAlbumRules {
        guard let value, value != .null else { return SmartAlbumRules() }
        let object: [String: JSONValue] = value.arrayValue.map { ["rules": .array($0)] } ?? value.objectValue ?? [:]
        guard value.arrayValue != nil || value.objectValue != nil else {
            throw CommandError(.invalidValue, "--rules is an object with match and rules, or an array of rules")
        }
        let match: SmartAlbumRules.Match
        switch object["match"]?.stringValue {
        case nil: match = .all
        case let text?:
            guard let parsed = SmartAlbumRules.Match(rawValue: text) else {
                throw CommandError(.invalidValue, "match is all or any")
            }
            match = parsed
        }
        var rules: [SmartRule] = []
        for rule in object["rules"]?.arrayValue ?? [] {
            guard let name = rule["field"]?.stringValue, let field = SmartRule.Field(rawValue: name) else {
                throw CommandError(.invalidValue, "Each rule needs a field, one of "
                                   + SmartRule.Field.allCases.map(\.rawValue).joined(separator: ", "))
            }
            var comparison: SmartRule.Comparison?
            if let text = rule["comparison"]?.stringValue {
                guard let parsed = SmartRule.Comparison(rawValue: text), field.kind.comparisons.contains(parsed) else {
                    throw CommandError(.invalidValue, "\(name) compares with "
                                       + field.kind.comparisons.map(\.rawValue).joined(separator: ", "))
                }
                comparison = parsed
            }
            let value: RuleValue
            do {
                value = try (rule["value"] ?? [:]).decode(RuleValue.self)
            } catch {
                throw CommandError(.invalidValue, "The value of a \(name) rule is not valid: \(error)")
            }
            rules.append(SmartRule(field: field, comparison: comparison, value: value))
        }
        return SmartAlbumRules(match: match, rules: rules)
    }

    static func describe(_ details: VersionDetails, keywords: [String]) throws -> JSONValue {
        let version = details.version
        let image = details.image
        let url = details.volume.url(forRelativePath: image.relativePath)
        let stack = try version.decodedEditStack()
        return [
            "versionID": JSONValue(version.id ?? 0),
            "imageID": JSONValue(image.id ?? 0),
            "projectID": JSONValue(image.projectId),
            "versionNumber": JSONValue(version.versionNumber),
            "fileName": .string(image.fileName),
            "path": .string(url.path),
            "online": .bool(FileManager.default.fileExists(atPath: url.path)),
            "captureDate": image.captureDate.map { .string(ISO8601DateFormatter().string(from: $0)) } ?? .null,
            "rating": JSONValue(version.rating.rawValue),
            "flag": .string(flagName(version.flag)),
            "colorLabel": .string(labelName(version.colorLabel)),
            "keywords": .array(keywords.map(JSONValue.string)),
            "editStack": try JSONValue(encoding: stack),
            "renderHash": .string(stack.renderHash),
        ]
    }

    // MARK: Develop

    static let develop = CommandSpec(
        id: "develop",
        summary: """
            Resets, then sets, parameters of a version's edit stack: --reset kind.parameter, kind or all, then \
            --set kind.parameter=value. --dry-run prints the result without saving it. Not undoable.
            """,
        access: .writeUnlessDryRun,
        parameters: [
            CommandParameter("version", .integer, "The version id.", required: true),
            CommandParameter("set", .string, "kind.parameter=value (see adjustments).", repeatable: true),
            CommandParameter("reset", .string, "kind.parameter, kind or all.", repeatable: true),
            CommandParameter("dryRun", .flag, "Print the resulting stack and render hash; change nothing."),
            libraryRoot,
        ],
        run: runDevelop)

    static func runDevelop(_ invocation: CommandInvocation) async throws -> JSONValue {
        let arguments = invocation.arguments
        let edits: [AdjustmentEdit]
        do throws(AdjustmentEdit.Failure) {
            edits = try arguments.strings("reset").map(AdjustmentEdit.parseReset)
                + arguments.strings("set").map(AdjustmentEdit.parseSet)
        } catch {
            throw commandError(error)
        }
        let library = try invocation.environment.openLibrary(arguments)
        let id = Int64(arguments.integer("version") ?? 0)
        guard let version = try await library.catalog.version(id: id) else {
            throw CommandError(.versionNotFound, "No version \(id)")
        }
        let before = try version.decodedEditStack()
        let after: EditStack
        do throws(AdjustmentEdit.Failure) {
            after = try before.applying(edits)
        } catch {
            throw commandError(error)
        }
        let dryRun = arguments.flag("dryRun")
        let changed = after != before
        if changed, !dryRun {
            try await library.catalog.setEditStack(after, forVersion: id)
        }
        return [
            "versionID": JSONValue(id),
            "editStack": try JSONValue(encoding: after),
            "renderHash": .string(after.renderHash),
            "changed": .bool(changed),
            "written": .bool(changed && !dryRun),
            "dryRun": .bool(dryRun),
        ]
    }

    static func commandError(_ failure: AdjustmentEdit.Failure) -> CommandError {
        switch failure {
        case .malformed(let text):
            CommandError(.invalidEdit, "\(text) is not kind.parameter=value (or kind.parameter, kind, all to reset)")
        case .unknownModule(let kind):
            CommandError(.invalidEdit, "No adjustment module \(kind); see the adjustments command")
        case .unknownParameter(let kind, let parameter):
            CommandError(.invalidEdit, "\(kind) has no parameter \(parameter)")
        case .invalidValue(let kind, let parameter, let reason):
            CommandError(.invalidEdit, "\(kind).\(parameter): \(reason)")
        case .noEffect(let kind, let parameter):
            CommandError(.invalidEdit, "\(kind).\(parameter) has no effect alone (a crop needs x, y, width and height)")
        }
    }

    // MARK: Culling

    static let rate = cullingCommand(
        id: "rate", summary: "Sets the rating (0–5) of versions.", parameter: "rating", values: "0 … 5"
    ) { text, catalog, ids throws in
        guard let stars = Int(text), let rating = Rating(rawValue: stars) else { return false }
        try await catalog.setRating(rating, forVersions: ids)
        return true
    }

    static let flag = cullingCommand(
        id: "flag", summary: "Sets the flag of versions.", parameter: "flag", values: "picked, rejected or none"
    ) { text, catalog, ids throws in
        guard let flag = Flag.allCases.first(where: { flagName($0) == text }) else { return false }
        try await catalog.setFlag(flag, forVersions: ids)
        return true
    }

    static let label = cullingCommand(
        id: "label", summary: "Sets the color label of versions.", parameter: "label",
        values: ColorLabel.allCases.map(labelName).joined(separator: ", ")
    ) { text, catalog, ids throws in
        guard let label = ColorLabel.allCases.first(where: { labelName($0) == text }) else { return false }
        try await catalog.setColorLabel(label, forVersions: ids)
        return true
    }

    /// A command that sets one culling value on versions. As in the app, the
    /// value also reaches the other file of a RAW+JPEG pair.
    static func cullingCommand(
        id: String, summary: String, parameter: String, values: String,
        apply: @escaping @Sendable (String, Catalog, [Int64]) async throws -> Bool
    ) -> CommandSpec {
        CommandSpec(
            id: id,
            summary: summary + " The other file of a RAW+JPEG pair follows, as in the app. Not undoable.",
            access: .write,
            parameters: [versions, CommandParameter(parameter, .string, values, required: true, positional: true),
                         libraryRoot],
            run: { invocation in
                let arguments = invocation.arguments
                let library = try invocation.environment.openLibrary(arguments)
                let ids = arguments.integers("version")
                for versionID in ids where try await library.catalog.version(id: versionID) == nil {
                    throw CommandError(.versionNotFound, "No version \(versionID)")
                }
                let text = arguments.string(parameter) ?? ""
                guard try await apply(text, library.catalog, ids) else {
                    throw CommandError(.invalidValue, "--\(parameter) is \(values)")
                }
                return ["versionIDs": .array(ids.map(JSONValue.init)), .init(parameter): .string(text)]
            })
    }

    static func flagName(_ flag: Flag) -> String {
        switch flag {
        case .picked: "picked"
        case .rejected: "rejected"
        case .none: "none"
        }
    }

    static func labelName(_ label: ColorLabel) -> String {
        label.xmpName?.lowercased() ?? "none"
    }

    // MARK: Export

    static let export = CommandSpec(
        id: "export",
        summary: """
            Exports versions to a folder with a saved export preset (--preset, by name or id) or the default \
            settings, changed by --settings (ExportSettings as JSON, for example {"format": "tiff", \
            "sizing": "longEdge", "edgeLength": 1600}).
            """,
        access: .read,
        parameters: [
            versions,
            CommandParameter("to", .path, "The destination folder (created if needed).", required: true),
            CommandParameter("preset", .string, "A saved export preset, by name or id."),
            CommandParameter("settings", .json, "Settings over the preset's (or the defaults)."),
            CommandParameter("policy", .string, "When a file exists: keepBoth (default), overwrite or skip."),
            libraryRoot,
        ],
        run: runExport)

    static func runExport(_ invocation: CommandInvocation) async throws -> JSONValue {
        let arguments = invocation.arguments
        let library = try invocation.environment.openLibrary(arguments)
        var settings = ExportSettings()
        if let name = arguments.string("preset") {
            let presets = try await library.catalog.exportPresets()
            guard let preset = presets.first(where: { $0.name == name || $0.id.map(String.init) == name }) else {
                throw CommandError(.presetNotFound, "No export preset \(name)")
            }
            settings = preset.settings
        }
        if let overrides = arguments.values["settings"]?.objectValue {
            var merged = try JSONValue(encoding: settings).objectValue ?? [:]
            merged.merge(overrides) { $1 }
            do {
                settings = try JSONValue.object(merged).decode(ExportSettings.self)
            } catch {
                throw CommandError(.invalidValue, "--settings does not fit the export settings: \(error)")
            }
        }
        let policy: ExportConflictPolicy
        switch arguments.string("policy") ?? "keepBoth" {
        case "keepBoth": policy = .keepBoth
        case "overwrite": policy = .overwrite
        case "skip": policy = .skip
        default: throw CommandError(.invalidValue, "--policy is keepBoth, overwrite or skip")
        }
        let ids = arguments.integers("version")
        for versionID in ids where try await library.catalog.version(id: versionID) == nil {
            throw CommandError(.versionNotFound, "No version \(versionID)")
        }
        let destination = invocation.environment.url(arguments.string("to") ?? "")
        let renderer = ExportRenderer(generator: PreviewGenerator(renderer: AdjustmentRenderer(lookTables: library.lookTables)),
                                      watermarks: WatermarkStore(locations: library.locations))
        let job = ExportJob(catalog: library.catalog, renderer: renderer)
        let summary = await job.run(ExportRequest(versionIDs: ids, settings: settings, destination: destination,
                                                  policy: policy))
        return [
            "destination": .string(summary.destination.path),
            "written": .array(summary.written.map { .string($0.path) }),
            "skippedExisting": JSONValue(summary.skippedExisting),
            "skippedVideos": JSONValue(summary.skippedVideos),
            "failures": .array(summary.failures.map { failure in
                ["fileName": .string(failure.fileName), "reason": .string(String(describing: failure.reason))]
            }),
            "settings": try JSONValue(encoding: settings),
        ]
    }
}
