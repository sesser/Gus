import CoreImage
import Darwin
import Foundation
import Testing

/// What a RAW golden was decoded by: the macOS build and the RAW decoder
/// version. Core Image's RAW decoder is Apple's code and changes with macOS
/// releases (the synthetic DNG decodes differently on macOS 15 and 26 than on
/// 27: mean OkLab ΔE about 0.0002, largest about 0.02, outside the goldens'
/// tolerance), so a RAW golden is compared only where its fingerprint matches.
/// Stored beside each RAW golden as `<name>.fingerprint.json`.
struct DecoderFingerprint: Codable, Equatable, Sendable, CustomStringConvertible {
    /// "27.2", for people reading the file; the build identifies the release.
    var macOSVersion: String
    /// The build (`kern.osversion`), for example "26B123".
    var macOSBuild: String
    /// The decoder version that decoded the golden: the case's own, or the
    /// decoder's default for the file.
    var decoderVersion: String

    var description: String { "macOS \(macOSVersion) (\(macOSBuild)), RAW decoder \(decoderVersion)" }

    /// This Mac, decoding `url` with `decoderVersion` (nil: the decoder's default).
    static func current(decoding url: URL, decoderVersion: String? = nil) -> DecoderFingerprint {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let decoder = decoderVersion ?? CIRAWFilter(imageURL: url)?.decoderVersion.rawValue ?? "none"
        return DecoderFingerprint(macOSVersion: "\(version.majorVersion).\(version.minorVersion)"
                                      + (version.patchVersion > 0 ? ".\(version.patchVersion)" : ""),
                                  macOSBuild: build, decoderVersion: decoder)
    }

    static let build: String = {
        var size = 0
        guard sysctlbyname("kern.osversion", nil, &size, nil, 0) == 0, size > 0 else { return "unknown" }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname("kern.osversion", &bytes, &size, nil, 0) == 0 else { return "unknown" }
        return String(decoding: bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }()

    /// The same build and decoder version.
    func matches(_ other: DecoderFingerprint) -> Bool {
        macOSBuild == other.macOSBuild && decoderVersion == other.decoderVersion
    }

    static func url(forGolden name: String) -> URL {
        Goldens.directory.appending(path: "\(name).fingerprint.json", directoryHint: .notDirectory)
    }

    static func stored(forGolden name: String) -> DecoderFingerprint? {
        guard let data = try? Data(contentsOf: url(forGolden: name)) else { return nil }
        return try? JSONDecoder().decode(DecoderFingerprint.self, from: data)
    }

    func write(forGolden name: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try (encoder.encode(self) + Data("\n".utf8)).write(to: Self.url(forGolden: name))
    }
}

/// Whether the RAW goldens can be compared on this Mac, decided once.
struct RAWGoldenComparison: Sendable {
    /// Every RAW golden has a fingerprint matching this Mac.
    var isComparable: Bool
    /// Why the comparison is skipped, naming both fingerprints.
    var skipReason: String

    init(names: [String], current: DecoderFingerprint) {
        let stored = names.map { DecoderFingerprint.stored(forGolden: $0) }
        if let missing = zip(names, stored).first(where: { $0.1 == nil })?.0 {
            isComparable = false
            skipReason = "RAW golden \(missing) has no fingerprint (run UPDATE_GOLDENS=1)"
        } else if let other = stored.compactMap({ $0 }).first(where: { !$0.matches(current) }) {
            isComparable = false
            skipReason = "RAW goldens were decoded on \(other); this Mac is \(current). "
                + "Compared only on the same build and decoder; the relative RAW decode checks still run."
        } else {
            isComparable = true
            skipReason = ""
        }
    }
}
