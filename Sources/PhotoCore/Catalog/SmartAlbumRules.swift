import Foundation
import GRDB

/// The query behind a smart album: "match all" or "match any" of a flat list of
/// rules. Stored as JSON in `smartAlbum.rules`; the field, comparison and value
/// keys are generic identifiers that stay the same across renames and releases.
public struct SmartAlbumRules: Codable, Hashable, Sendable {
    public enum Match: String, Codable, Sendable, CaseIterable {
        case all
        case any
    }

    public var match: Match
    public var rules: [SmartRule]

    public init(match: Match = .all, rules: [SmartRule] = []) {
        self.match = match
        self.rules = rules
    }

    public func jsonString() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(self), as: UTF8.self)
    }

    public static func decode(from json: String) throws -> SmartAlbumRules {
        try JSONDecoder().decode(SmartAlbumRules.self, from: Data(json.utf8))
    }
}

/// One condition, such as "rating is at least 3" or "lens contains 35mm".
public struct SmartRule: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var field: Field
    public var comparison: Comparison
    public var value: RuleValue

    public init(id: UUID = UUID(), field: Field, comparison: Comparison? = nil, value: RuleValue = RuleValue()) {
        self.id = id
        self.field = field
        self.comparison = comparison ?? field.kind.comparisons[0]
        self.value = value
    }

    public enum Field: String, Codable, Sendable, CaseIterable {
        case rating, flag, colorLabel
        case keyword, hasKeywords
        case fileType, fileName
        case captureDate, importDate
        case project
        case camera, lens, cameraSerial
        case iso, aperture, shutterSpeed, focalLength, exposureCompensation
        case flash, whiteBalance, hasLocation
        case artist, copyright, caption

        public var kind: Kind {
            switch self {
            case .rating, .iso, .aperture, .shutterSpeed, .focalLength, .exposureCompensation: .number
            case .flag, .colorLabel, .fileType, .whiteBalance, .project: .choice
            case .keyword: .keyword
            case .hasKeywords, .flash, .hasLocation: .flag
            case .fileName, .camera, .lens, .cameraSerial, .artist, .copyright, .caption: .text
            case .captureDate, .importDate: .date
            }
        }
    }

    public enum Kind: Sendable {
        case number, text, date, choice, keyword, flag

        public var comparisons: [Comparison] {
            switch self {
            case .number: [.atLeast, .atMost, .equals, .notEquals, .between]
            case .text: [.contains, .doesNotContain, .equals, .notEquals, .beginsWith, .endsWith, .isEmpty, .isNotEmpty]
            case .date: [.inLastDays, .notInLastDays, .on, .before, .after, .between]
            case .choice: [.equals, .notEquals]
            case .keyword: [.has, .doesNotHave]
            case .flag: [.isTrue, .isFalse]
            }
        }
    }

    public enum Comparison: String, Codable, Sendable, CaseIterable {
        case equals, notEquals
        case atLeast, atMost, between
        case contains, doesNotContain, beginsWith, endsWith, isEmpty, isNotEmpty
        case on, before, after, inLastDays, notInLastDays
        case has, doesNotHave
        case isTrue, isFalse
    }
}

/// A rule's operand. Which members matter depends on the field and comparison:
/// numbers (`number`, `upperNumber` for between, `number` days for "in the last"),
/// text, days as `YYYY-MM-DD` in `text` / `upperText`, choices as identifiers in
/// `text` (see `SmartRule.choices(for:)`), keyword and project ids in `id`.
public struct RuleValue: Codable, Hashable, Sendable {
    public var number: Double?
    public var upperNumber: Double?
    public var text: String?
    public var upperText: String?
    public var id: Int64?

    public init(number: Double? = nil, upperNumber: Double? = nil, text: String? = nil, upperText: String? = nil,
                id: Int64? = nil) {
        self.number = number
        self.upperNumber = upperNumber
        self.text = text
        self.upperText = upperText
        self.id = id
    }
}

extension SmartRule {
    /// Identifiers for choice fields (other than projects), in display order.
    public static func choices(for field: Field) -> [String] {
        switch field {
        case .flag: ["picked", "rejected", "unflagged"]
        case .colorLabel: ColorLabel.allCases.map { String($0.rawValue) }
        case .fileType: FileKind.allCases.map(\.rawValue)
        case .whiteBalance: ["auto", "manual"]
        default: []
        }
    }
}

// MARK: - SQL

extension SmartAlbumRules {
    /// A condition over `version` and `image`, or nil when there are no usable
    /// rules (the album then shows everything in its scope). Incomplete rules
    /// (no value yet, while the editor is open) are skipped.
    func sqlCondition(now: Date, timeZone: TimeZone = .current) -> (sql: String, arguments: StatementArguments)? {
        let parts = rules.compactMap { $0.sqlCondition(now: now, timeZone: timeZone) }
        guard !parts.isEmpty else { return nil }
        var arguments = StatementArguments()
        for part in parts { arguments += part.arguments }
        let joiner = match == .all ? " AND " : " OR "
        return ("(" + parts.map(\.sql).joined(separator: joiner) + ")", arguments)
    }
}

extension SmartRule {
    func sqlCondition(now: Date, timeZone: TimeZone) -> (sql: String, arguments: StatementArguments)? {
        switch field.kind {
        case .number: numberCondition()
        case .text: textCondition()
        case .date: dateCondition(now: now, timeZone: timeZone)
        case .choice: choiceCondition()
        case .keyword: keywordCondition()
        case .flag: flagCondition()
        }
    }

    private var column: String {
        switch field {
        case .rating: "version.rating"
        case .iso: "image.iso"
        case .aperture: "image.fNumber"
        case .shutterSpeed: "image.exposureTime"
        case .focalLength: "image.focalLength"
        case .exposureCompensation: "image.exposureCompensation"
        case .fileName: "image.fileName"
        case .camera: "trim(ifnull(image.cameraMake, '') || ' ' || ifnull(image.cameraModel, ''))"
        case .lens: "image.lensModel"
        case .cameraSerial: "image.cameraSerial"
        case .artist: "image.artist"
        case .copyright: "image.copyright"
        case .caption: "image.caption"
        case .captureDate: "image.localDate"
        case .importDate: "image.importedAt"
        case .flag: "version.flag"
        case .colorLabel: "version.colorLabel"
        case .whiteBalance: "image.whiteBalance"
        case .project: "image.projectId"
        case .fileType: "image.format"
        case .keyword, .hasKeywords, .flash, .hasLocation: ""
        }
    }

    private func numberCondition() -> (String, StatementArguments)? {
        guard let value = value.number else { return nil }
        // Apertures and shutter speeds come from rationals; "is ƒ/2.8" should
        // not depend on the last decimal.
        let tolerance = max(abs(value) * 0.005, 1e-9)
        switch comparison {
        case .atLeast: return ("\(column) >= ?", [value - tolerance])
        case .atMost: return ("\(column) <= ?", [value + tolerance])
        case .equals: return ("\(column) BETWEEN ? AND ?", [value - tolerance, value + tolerance])
        case .notEquals: return ("(\(column) IS NULL OR \(column) NOT BETWEEN ? AND ?)", [value - tolerance, value + tolerance])
        case .between:
            guard let upper = self.value.upperNumber else { return nil }
            return ("\(column) BETWEEN ? AND ?", [min(value, upper) - tolerance, max(value, upper) + tolerance])
        default: return nil
        }
    }

    private func textCondition() -> (String, StatementArguments)? {
        let text = (value.text ?? "").trimmingCharacters(in: .whitespaces)
        let escaped = text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_")
        switch comparison {
        case .isEmpty: return ("(\(column) IS NULL OR \(column) = '')", [])
        case .isNotEmpty: return ("(\(column) IS NOT NULL AND \(column) <> '')", [])
        default: break
        }
        guard !text.isEmpty else { return nil }
        switch comparison {
        case .contains: return ("\(column) LIKE ? ESCAPE '\\'", ["%\(escaped)%"])
        case .doesNotContain: return ("(\(column) IS NULL OR \(column) NOT LIKE ? ESCAPE '\\')", ["%\(escaped)%"])
        case .beginsWith: return ("\(column) LIKE ? ESCAPE '\\'", ["\(escaped)%"])
        case .endsWith: return ("\(column) LIKE ? ESCAPE '\\'", ["%\(escaped)"])
        case .equals: return ("\(column) = ? COLLATE NOCASE", [text])
        case .notEquals: return ("(\(column) IS NULL OR \(column) <> ? COLLATE NOCASE)", [text])
        default: return nil
        }
    }

    private func dateCondition(now: Date, timeZone: TimeZone) -> (String, StatementArguments)? {
        // Capture dates compare as local days (`image.localDate`); import dates
        // are instants, compared against the start of local days.
        let isCapture = field == .captureDate
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        func dayStart(_ day: String) -> Date? {
            let parts = day.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 3 else { return nil }
            return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
        }
        func bound(_ day: String) -> (any DatabaseValueConvertible)? {
            isCapture ? day : dayStart(day)
        }
        func nextDay(_ day: String) -> (any DatabaseValueConvertible)? {
            guard let start = dayStart(day), let next = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
            return isCapture ? LocalDate.format(next, in: timeZone) : next
        }
        switch comparison {
        case .inLastDays, .notInLastDays:
            guard let days = value.number, days >= 0 else { return nil }
            let today = calendar.startOfDay(for: now)
            guard let first = calendar.date(byAdding: .day, value: -Int(days) + 1, to: today) else { return nil }
            let start: any DatabaseValueConvertible = isCapture ? LocalDate.format(first, in: timeZone) : first
            return comparison == .inLastDays
                ? ("\(column) >= ?", [start])
                : ("(\(column) IS NULL OR \(column) < ?)", [start])
        default:
            break
        }
        guard let day = value.text, let start = bound(day), let end = nextDay(day) else { return nil }
        switch comparison {
        case .on: return ("(\(column) >= ? AND \(column) < ?)", [start, end])
        case .before: return ("\(column) < ?", [start])
        case .after: return ("\(column) >= ?", [end])
        case .between:
            guard let upper = value.upperText, let upperEnd = nextDay(upper) else { return nil }
            return ("(\(column) >= ? AND \(column) < ?)", [start, upperEnd])
        default: return nil
        }
    }

    private func choiceCondition() -> (String, StatementArguments)? {
        let negate = comparison == .notEquals
        func compare(_ values: [any DatabaseValueConvertible]) -> (String, StatementArguments) {
            let list = databaseQuestionMarks(count: values.count)
            return negate
                ? ("(\(column) IS NULL OR \(column) NOT IN (\(list)))", StatementArguments(values))
                : ("\(column) IN (\(list))", StatementArguments(values))
        }
        switch field {
        case .project:
            guard let id = value.id else { return nil }
            return compare([id])
        case .flag:
            let flags: [String: Flag] = ["picked": .picked, "rejected": .rejected, "unflagged": .none]
            guard let flag = value.text.flatMap({ flags[$0] }) else { return nil }
            return compare([flag.rawValue])
        case .colorLabel:
            guard let label = value.text.flatMap(Int.init).flatMap(ColorLabel.init(rawValue:)) else { return nil }
            return compare([label.rawValue])
        case .whiteBalance:
            guard let mode = value.text, let raw = ["auto": 0, "manual": 1][mode] else { return nil }
            return compare([raw])
        case .fileType:
            guard let kind = value.text.flatMap(FileKind.init(rawValue:)) else { return nil }
            let extensions = SupportedFormats.allExtensions.filter { FileKind(pathExtension: $0) == kind }.sorted()
            return compare(extensions)
        default:
            return nil
        }
    }

    private func keywordCondition() -> (String, StatementArguments)? {
        guard let id = value.id else { return nil }
        let subquery = "SELECT versionId FROM versionKeyword WHERE keywordId = ?"
        return comparison == .doesNotHave
            ? ("version.id NOT IN (\(subquery))", [id])
            : ("version.id IN (\(subquery))", [id])
    }

    private func flagCondition() -> (String, StatementArguments)? {
        let yes = comparison == .isTrue
        switch field {
        case .hasKeywords:
            let exists = "EXISTS (SELECT 1 FROM versionKeyword WHERE versionKeyword.versionId = version.id)"
            return (yes ? exists : "NOT \(exists)", [])
        case .flash:
            return (yes ? "image.flashFired = 1" : "ifnull(image.flashFired, 0) = 0", [])
        case .hasLocation:
            return (yes ? "image.latitude IS NOT NULL" : "image.latitude IS NULL", [])
        default:
            return nil
        }
    }
}
