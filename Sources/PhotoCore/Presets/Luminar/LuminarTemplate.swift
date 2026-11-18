import Foundation

/// The edit recipe of one preset of a pack (`template.lmps`, JSON): layers,
/// each an ordered list of tools (`edits_array`), each tool one or more
/// effects, each effect named parameters. Every value is text; numbers come
/// with their default. A parameter whose `opt_data_type` is 2 names a file of
/// the preset's `resources/` folder (a look-up table).
public struct LuminarTemplate: Sendable, Hashable {
    public struct Parameter: Sendable, Hashable {
        public var name: String
        var rawValue: String
        var rawDefault: String
        var optionType: String
        /// `opt_data_value`: a list or a text (a file name, or a curve written as a list).
        var optionValue: OptionValue
        var prettyName: String?

        public var value: Double { LuminarTemplate.number(rawValue) }
        public var defaultValue: Double { LuminarTemplate.number(rawDefault) }

        /// Away from its default, with float noise ignored; text compared as text.
        public var isChanged: Bool {
            let value = value, defaultValue = defaultValue
            if value.isNaN || defaultValue.isNaN { return rawValue != rawDefault }
            return abs(value - defaultValue) > 1e-6
        }

        /// The resource file this parameter names, if any.
        var fileName: String? {
            guard optionType == "2", case .text(let text) = optionValue, !text.isEmpty, text != "0" else { return nil }
            return text
        }
    }

    enum OptionValue: Sendable, Hashable {
        case text(String)
        case list([String])
    }

    public struct Effect: Sendable, Hashable {
        public var id: String
        public var parameters: [Parameter]

        func parameter(_ name: String) -> Parameter? { parameters.first { $0.name == name } }

        /// The parameter's number, or `fallback` when it is missing or not a number.
        func value(_ name: String, _ fallback: Double = 0) -> Double {
            guard let value = parameter(name)?.value, !value.isNaN else { return fallback }
            return value
        }

        func isChanged(_ name: String) -> Bool { parameter(name)?.isChanged ?? false }
    }

    public struct Tool: Sendable, Hashable {
        public var name: String
        public var isEnabled: Bool
        public var isMasked: Bool
        var blendMode: String
        public var effects: [Effect]
        /// Position in the preset's tool order, across layers.
        var index: Int

        func effect(_ id: String) -> Effect? { effects.first { $0.id == id } }
    }

    public var name: String
    public var uuid: String
    public var tools: [Tool]
    /// Layers after the first, opacity below 1, blend modes, layer masks or image layers.
    var hasLayerSettings: Bool

    /// Reads a template; throws when the data is not a JSON object.
    public init(data: Data) throws {
        var text = data
        if text.starts(with: [0xEF, 0xBB, 0xBF]) { text = text.dropFirst(3) }
        guard let object = try JSONSerialization.jsonObject(with: Data(text)) as? [String: Any] else {
            throw LuminarPack.Failure.unreadableSettings
        }
        self.init(object)
    }

    init(_ object: [String: Any]) {
        name = Self.text(object["name"])
        uuid = Self.text(object["uuid"])
        var tools: [Tool] = []
        var layerSettings = false
        let layers = (object["layers_array"] as? [Any] ?? []).compactMap { $0 as? [String: Any] }
        let enabledLayers = layers.filter { Self.flag($0["enabled"], default: true) }
        if enabledLayers.count > 1 { layerSettings = true }
        for layer in enabledLayers {
            let opacity = Self.number(Self.text(layer["opacity"], default: "1"))
            if opacity != 1 || Self.text(layer["blend_mode"], default: "0") != "0"
                || Self.isPresent(layer["mask"]) || Self.isPresent(layer["source_image"]) {
                layerSettings = true
            }
            for case let edit as [String: Any] in layer["edits_array"] as? [Any] ?? [] {
                var effects: [Effect] = []
                for case let effect as [String: Any] in edit["effects_array"] as? [Any] ?? [] {
                    var parameters: [Parameter] = []
                    for case let raw as [String: Any] in effect["params_array"] as? [Any] ?? [] {
                        parameters.append(Parameter(
                            name: Self.text(raw["name"]), rawValue: Self.text(raw["value"]),
                            rawDefault: Self.text(raw["default"]), optionType: Self.text(raw["opt_data_type"], default: "0"),
                            optionValue: Self.option(raw["opt_data_value"]), prettyName: raw["pretty_name"] as? String))
                    }
                    effects.append(Effect(id: Self.text(effect["id"]), parameters: parameters))
                }
                tools.append(Tool(name: Self.text(edit["tool_name"]), isEnabled: Self.flag(edit["enabled"], default: true),
                                  isMasked: Self.isPresent(edit["mask"]), blendMode: Self.text(edit["blend_mode"], default: "0"),
                                  effects: effects, index: tools.count))
            }
        }
        self.tools = tools
        hasLayerSettings = layerSettings
    }

    // MARK: Values

    /// A finite number from text (surrounding spaces allowed), or NaN.
    static func number(_ text: String) -> Double {
        guard let value = Double(text.trimmingCharacters(in: .whitespaces)), value.isFinite else { return .nan }
        return value
    }

    static func text(_ value: Any?, default fallback: String = "") -> String {
        switch value {
        case let text as String: text
        // JSONSerialization gives NSNumbers, and 0 and 1 also cast to Bool: only a real boolean reads as one.
        case let number as NSNumber where CFGetTypeID(number) == CFBooleanGetTypeID(): number.boolValue ? "true" : "false"
        case let number as NSNumber: number.stringValue
        default: fallback
        }
    }

    static func flag(_ value: Any?, default fallback: Bool) -> Bool {
        guard value != nil else { return fallback }
        return text(value).lowercased() == "true"
    }

    /// True for a non-empty text, list or object (a mask, an image layer's source).
    static func isPresent(_ value: Any?) -> Bool {
        switch value {
        case let text as String: !text.isEmpty
        case let list as [Any]: !list.isEmpty
        case let object as [String: Any]: !object.isEmpty
        case let number as NSNumber: number.doubleValue != 0
        default: false
        }
    }

    static func option(_ value: Any?) -> OptionValue {
        if let list = value as? [Any] { return .list(list.map { text($0) }) }
        return .text(text(value, default: "0"))
    }
}
