import GRDB

/// Star rating, 0 (unrated) through 5.
public struct Rating: RawRepresentable, Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    public static let range = 0...5
    public static let unrated = Rating(clamping: 0)

    public let rawValue: Int

    public init?(rawValue: Int) {
        guard Self.range.contains(rawValue) else { return nil }
        self.rawValue = rawValue
    }

    public init(clamping value: Int) {
        rawValue = min(max(value, Self.range.lowerBound), Self.range.upperBound)
    }

    public static func < (lhs: Rating, rhs: Rating) -> Bool { lhs.rawValue < rhs.rawValue }

    public var description: String { "\(rawValue)★" }
}

/// Pick / reject flag. Stored as -1, 0, 1 so that `flag >= 0` means "not rejected".
public enum Flag: Int, Hashable, Sendable, Codable, CaseIterable {
    case rejected = -1
    case none = 0
    case picked = 1
}

/// Color label. Raw values are persisted; do not reorder.
public enum ColorLabel: Int, Hashable, Sendable, Codable, CaseIterable {
    case none = 0
    case red
    case orange
    case yellow
    case green
    case blue
    case purple
    case gray
}

extension Rating: DatabaseValueConvertible {}
extension Flag: DatabaseValueConvertible {}
extension ColorLabel: DatabaseValueConvertible {}

extension ColorLabel {
    /// The label as other apps write it to XMP (`xmp:Label`): an English color
    /// name. These are file-format values, not UI text.
    public var xmpName: String? {
        switch self {
        case .none: nil
        case .red: "Red"
        case .orange: "Orange"
        case .yellow: "Yellow"
        case .green: "Green"
        case .blue: "Blue"
        case .purple: "Purple"
        case .gray: "Gray"
        }
    }

    /// Reads an `xmp:Label` value; unknown names (custom label sets) give nil.
    public init?(xmpName: String) {
        let name = xmpName.trimmingCharacters(in: .whitespaces).lowercased()
        guard let match = ColorLabel.allCases.first(where: { $0.xmpName?.lowercased() == name })
            ?? (name == "grey" ? .gray : nil) ?? (name == "violet" ? .purple : nil)
        else { return nil }
        self = match
    }
}
