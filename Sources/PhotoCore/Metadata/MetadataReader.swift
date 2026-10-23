import Foundation

/// Reads embedded metadata from master files.
///
/// Implementations are free to batch; files they cannot read are simply missing
/// from the result. Only cancellation is thrown.
public protocol MetadataReader: Sendable {
    func metadata(for urls: [URL]) async throws -> [URL: ImageMetadata]
}

/// Uses `primary`, then asks `fallback` for whatever `primary` could not read.
public struct FallbackMetadataReader: MetadataReader {
    public let primary: any MetadataReader
    public let fallback: any MetadataReader

    public init(primary: any MetadataReader, fallback: any MetadataReader) {
        self.primary = primary
        self.fallback = fallback
    }

    public func metadata(for urls: [URL]) async throws -> [URL: ImageMetadata] {
        var result = try await primary.metadata(for: urls)
        let missing = urls.filter { result[$0] == nil }
        if !missing.isEmpty {
            result.merge(try await fallback.metadata(for: missing)) { first, _ in first }
        }
        return result
    }
}

public enum MetadataReaders {
    /// ExifTool when it is installed (with ImageIO for anything it misses),
    /// otherwise ImageIO alone.
    public static func makeDefault() -> any MetadataReader {
        if let exiftool = ExifToolMetadataReader.locateExecutable() {
            return FallbackMetadataReader(primary: ExifToolMetadataReader(executableURL: exiftool),
                                          fallback: ImageIOMetadataReader())
        }
        return ImageIOMetadataReader()
    }
}

/// Parses EXIF-style timestamps ("2024:05:01 10:00:00", optionally with
/// sub-seconds and a "+02:00" / "Z" offset) without DateFormatter.
public enum ExifDate {
    public struct Parsed: Equatable, Sendable {
        public var date: Date
        /// Offset from UTC, or nil for a floating local time stored as UTC.
        public var offsetSeconds: Int?
    }

    public static func parse(_ text: String, subSeconds: String? = nil, offset: String? = nil) -> Parsed? {
        let bytes = Array(text.utf8)
        func number(_ start: Int, _ length: Int) -> Int? {
            guard start + length <= bytes.count else { return nil }
            var value = 0
            for byte in bytes[start..<(start + length)] {
                guard byte >= 48, byte <= 57 else { return nil }
                value = value * 10 + Int(byte - 48)
            }
            return value
        }
        guard let year = number(0, 4), let month = number(5, 2), let day = number(8, 2),
              let hour = number(11, 2), let minute = number(14, 2), let second = number(17, 2),
              (1...12).contains(month), (1...31).contains(day), hour < 24, minute < 60, second < 61,
              year > 0
        else { return nil }

        var index = 19
        var fraction = 0.0
        if index < bytes.count, bytes[index] == UInt8(ascii: ".") {
            index += 1
            var scale = 0.1
            while index < bytes.count, bytes[index] >= 48, bytes[index] <= 57 {
                fraction += Double(bytes[index] - 48) * scale
                scale /= 10
                index += 1
            }
        } else if let digits = subSeconds?.trimmingCharacters(in: .whitespaces), !digits.isEmpty,
                  digits.count <= 9, digits.allSatisfy(\.isASCII), let value = Int(digits) {
            fraction = Double(value) / pow(10, Double(digits.count))
        }

        let remainder = String(decoding: bytes[min(index, bytes.count)...], as: UTF8.self)
        let offsetSeconds = parseOffset(remainder) ?? offset.flatMap(parseOffset)

        let days = daysFromCivil(year: year, month: month, day: day)
        var seconds = Double(days * 86_400 + hour * 3_600 + minute * 60 + second) + fraction
        if let offsetSeconds { seconds -= Double(offsetSeconds) }
        return Parsed(date: Date(timeIntervalSince1970: seconds), offsetSeconds: offsetSeconds)
    }

    static func parseOffset(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed == "Z" { return 0 }
        guard let sign = trimmed.first, sign == "+" || sign == "-" else { return nil }
        let digits = trimmed.dropFirst().filter { $0 != ":" }
        guard digits.count == 4, digits.allSatisfy(\.isASCII), let value = Int(digits) else { return nil }
        let hours = value / 100
        let minutes = value % 100
        guard hours <= 14, minutes < 60 else { return nil }
        return (sign == "-" ? -1 : 1) * (hours * 3_600 + minutes * 60)
    }

    /// Days since 1970-01-01 in the proleptic Gregorian calendar (H. Hinnant).
    static func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yearOfEra = y - era * 400
        let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }
}
