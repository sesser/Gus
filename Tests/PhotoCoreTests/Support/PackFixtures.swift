import Compression
import Foundation
@testable import PhotoCore

/// Writes zip archives in memory, stored or deflated, for the reader's tests.
enum ZipWriter {
    struct Member {
        var path: String
        var data: Data
        var deflated = true
    }

    static func archive(_ members: [Member]) -> Data {
        var out = Data()
        var directory = Data()
        for member in members {
            let stored = member.deflated ? deflate(member.data) : member.data
            let method: UInt16 = member.deflated ? 8 : 0
            let crc = CRC32.checksum(member.data)
            let name = Data(member.path.utf8)
            let offset = out.count
            append32(&out, 0x0403_4B50)
            append16(&out, 20); append16(&out, 0); append16(&out, method); append16(&out, 0); append16(&out, 0)
            append32(&out, crc); append32(&out, UInt32(stored.count)); append32(&out, UInt32(member.data.count))
            append16(&out, UInt16(name.count)); append16(&out, 0)
            out += name
            out += stored
            append32(&directory, 0x0201_4B50)
            append16(&directory, 20); append16(&directory, 20); append16(&directory, 0); append16(&directory, method)
            append16(&directory, 0); append16(&directory, 0)
            append32(&directory, crc); append32(&directory, UInt32(stored.count)); append32(&directory, UInt32(member.data.count))
            append16(&directory, UInt16(name.count)); append16(&directory, 0); append16(&directory, 0)
            append16(&directory, 0); append16(&directory, 0); append32(&directory, 0); append32(&directory, UInt32(offset))
            directory += name
        }
        let directoryOffset = out.count
        out += directory
        append32(&out, 0x0605_4B50)
        append16(&out, 0); append16(&out, 0)
        append16(&out, UInt16(members.count)); append16(&out, UInt16(members.count))
        append32(&out, UInt32(directory.count)); append32(&out, UInt32(directoryOffset))
        append16(&out, 0)
        return out
    }

    static func archive(_ files: [String: Data], deflated: Bool = true) -> Data {
        archive(files.keys.sorted().map { Member(path: $0, data: files[$0]!, deflated: deflated) })
    }

    /// Raw deflate (the Compression framework's ZLIB).
    static func deflate(_ data: Data) -> Data {
        guard !data.isEmpty else { return Data([0x03, 0x00]) }
        let capacity = data.count + 1024
        var out = Data(count: capacity)
        let written = out.withUnsafeMutableBytes { (destination: UnsafeMutableRawBufferPointer) -> Int in
            data.withUnsafeBytes { (source: UnsafeRawBufferPointer) -> Int in
                compression_encode_buffer(destination.bindMemory(to: UInt8.self).baseAddress!, capacity,
                                          source.bindMemory(to: UInt8.self).baseAddress!, data.count, nil, COMPRESSION_ZLIB)
            }
        }
        return out.prefix(written)
    }

    private static func append16(_ data: inout Data, _ value: UInt16) {
        data.append(UInt8(value & 0xFF)); data.append(UInt8(value >> 8))
    }

    private static func append32(_ data: inout Data, _ value: UInt32) {
        for shift in stride(from: 0, to: 32, by: 8) { data.append(UInt8((value >> UInt32(shift)) & 0xFF)) }
    }
}

/// Made-up preset packs laid out as the format has them. The values are our
/// own; only the structure and the tool identifiers follow the format.
enum PackFixture {
    /// A valid 2×2×2 identity cube.
    static let identityCube = Data(("# test\nLUT_3D_SIZE 2\nDOMAIN_MIN 0.0 0.0 0.0\nDOMAIN_MAX 1.0 1.0 1.0\n"
        + "0 0 0\n1 0 0\n0 1 0\n1 1 0\n0 0 1\n1 0 1\n0 1 1\n1 1 1\n").utf8)
    /// Another valid cube, with different content.
    static let swapCube = Data(("LUT_3D_SIZE 2\n"
        + "0 0 0\n0 0 1\n0 1 0\n0 1 1\n1 0 0\n1 0 1\n1 1 0\n1 1 1\n").utf8)

    static func param(_ name: String, _ value: Double, _ defaultValue: Double = 0, optionType: String = "0",
                      option: Any = "0", pretty: String? = nil) -> [String: Any] {
        var raw: [String: Any] = ["name": name, "value": text(value), "default": text(defaultValue),
                                  "min": "-100", "max": "100", "opt_data_type": optionType, "opt_data_value": option]
        if let pretty { raw["pretty_name"] = pretty }
        return raw
    }

    static func text(_ value: Double) -> String {
        value == value.rounded() && abs(value) < 1e15 ? String(Int(value)) : String(value)
    }

    static func curve(_ name: String, _ values: [String]) -> [String: Any] {
        param(name, 50, 50, option: values)
    }

    static func effect(_ id: String, _ params: [String: Any]...) -> [String: Any] {
        ["id": id, "params_array": params]
    }

    static func tool(_ name: String, _ effects: [String: Any]..., enabled: Bool = true, mask: String = "",
                     blendMode: String = "0") -> [String: Any] {
        ["permanent": "true", "locked": "false", "enabled": enabled ? "true" : "false", "tool_name": name,
         "mask": mask, "source_image": "", "blend_mode": blendMode, "effects_array": effects]
    }

    static func tool(_ name: LuminarTool, _ effects: [String: Any]..., enabled: Bool = true, mask: String = "",
                     blendMode: String = "0") -> [String: Any] {
        ["permanent": "true", "locked": "false", "enabled": enabled ? "true" : "false", "tool_name": name.rawValue,
         "mask": mask, "source_image": "", "blend_mode": blendMode, "effects_array": effects]
    }

    static func layer(_ tools: [[String: Any]], opacity: String = "1", blendMode: String = "0") -> [String: Any] {
        ["enabled": "true", "alive": "true", "source_image": "", "mask": "", "blend_mode": blendMode,
         "opacity": opacity, "edits_array": tools]
    }

    static func template(_ name: String, uuid: String = "00000000-0000-0000-0000-000000000001",
                         _ tools: [[String: Any]], layers: [[String: Any]]? = nil) -> [String: Any] {
        ["name": name, "uuid": uuid, "layers_array": layers ?? [layer(tools)], "canvas_size": ["1", "1"]]
    }

    static func json(_ object: Any) -> Data {
        try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    static func parsed(_ tools: [[String: Any]], layers: [[String: Any]]? = nil) -> LuminarTemplate {
        LuminarTemplate(template("Test", tools, layers: layers))
    }

    static func convert(_ tools: [[String: Any]], resources: [String: Data] = [:],
                        layers: [[String: Any]]? = nil) -> LuminarConversion {
        LuminarMapping.convert(parsed(tools, layers: layers), resources: resources)
    }

    static func lutTool(_ fileName: String = "TABLE.CUBE", amount: Double = 80, pretty: String? = "Look",
                        contrast: Double = 0, saturation: Double = 0) -> [String: Any] {
        tool(.lookUpTable, effect("MIPLLUTMappingEffect",
                                  param("Texture", 0, 50, optionType: "2", option: fileName, pretty: pretty),
                                  param("Amount", amount, 30), param("Contrast", contrast), param("Saturation", saturation)))
    }

    static func strings(_ pairs: [String: String]) -> Data {
        Data(pairs.keys.sorted().map { "\"\($0)\" = \"\(pairs[$0]!)\";\n" }.joined().utf8)
    }

    static let packID = "aaaaaaaa-0000-0000-0000-000000000000"

    struct Preset {
        var uuid: String
        var name: String
        var german: String?
        var tools: [[String: Any]]
        var resources: [String: Data] = [:]
    }

    /// A pack's files: `Config/config.json`, its config listing the presets in this order, and their folders.
    static func files(name: String? = "Test Pack", germanName: String? = "Testpaket", presets: [Preset],
                      extraListed: [String] = []) -> [String: Data] {
        var files: [String: Data] = [
            "Config/config.json": json(["name": "Category", "identifier": "c", "version": 1.1]),
            "\(packID)/config.json": json(["name": "Pack Name", "identifier": packID,
                                           "templates": presets.map { "\($0.uuid).lnp" } + extraListed,
                                           "description": "Short Description"]),
        ]
        if let name { files["\(packID)/localizations/en.strings"] = strings(["Pack Name": name]) }
        if let germanName { files["\(packID)/localizations/de.strings"] = strings(["Pack Name": germanName]) }
        for preset in presets {
            let folder = "\(packID)/\(preset.uuid).lnp"
            files["\(folder)/template.lmps"] = json(template(preset.name, uuid: preset.uuid, preset.tools))
            files["\(folder)/localizations/en.strings"] = strings([preset.name: preset.name])
            if let german = preset.german { files["\(folder)/localizations/de.strings"] = strings([preset.name: german]) }
            files["\(folder)/icon.jpg"] = Data([0xFF, 0xD8, 0xFF])
            for (fileName, data) in preset.resources { files["\(folder)/resources/\(fileName)"] = data }
        }
        return files
    }

    /// Two presets: Beta (vibrance) listed first, then Alpha (a table and Develop).
    static func twoPresets() -> [Preset] {
        [
            Preset(uuid: "22222222-0000-0000-0000-000000000000", name: "Beta", german: nil,
                   tools: [tool(.color, effect("MIPLVibranceEffect", param("Vibrance", 20)))]),
            Preset(uuid: "11111111-0000-0000-0000-000000000000", name: "Alpha", german: "Alfa",
                   tools: [lutTool("TABLE.CUBE"),
                           tool(.develop, effect("MIPLDevelopCommonEffectID", param("Exposure", -50), param("Contrast", 10)))],
                   resources: ["TABLE.CUBE": identityCube]),
        ]
    }

    static func packData(_ presets: [Preset] = twoPresets(), name: String? = "Test Pack") -> Data {
        ZipWriter.archive(files(name: name, presets: presets))
    }
}
