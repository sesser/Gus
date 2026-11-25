import Foundation

/// The parts of the single loupe's caption that the crowding order acts on
/// (issue #282, design §20.1). A badge added to the caption later needs a
/// case here and its own row in `LoupeCaptionLevel.changes`.
public enum LoupeCaptionPart: String, CaseIterable, Hashable, Sendable {
    case position
    case filmStripToggle
    case spinner
    case filtered
    case copy
    case machineLearning
    case spotLimit
    case original
    /// A sharpening or fringe map's badge, in Original's place.
    case mapBadge
    /// A gain-map photo's version badge (with its warning mark).
    case versionBadge
    /// The HDR badge of an HLG, PQ or floating-point DNG photo.
    case hdrBadge
    case offline
    case rating
    case flag
    case colorDot
    case colorName
}

/// How a part is drawn at a level.
public enum LoupeCaptionForm: Equatable, Sendable {
    /// In full, at its own width.
    case whole
    /// The version badge's short form: the warning mark and SDR.
    case short
    /// The rating as one star and its digit.
    case compact
    /// Takes the room left, up to its whole width, and is cut (at the tail
    /// for the label name, in the middle for a map's badge) down to this
    /// width, never below it.
    case truncating(minimumWidth: Double)
}

/// One level of the loupe caption's crowding order (issue #282, design
/// §20.1): what is shown, and in which form, when the levels before it don't
/// fit. The caption takes the first level that fits whole; each level keeps
/// the changes of the levels above it. Dropping a part takes it off screen
/// only: nothing about the photo, the filter or the strip changes.
public struct LoupeCaptionLevel: Equatable, Identifiable, Sendable {
    /// 1 to 13, as in design §20.1's table.
    public let number: Int
    /// Levels 1 and 2: the marks in the middle of the row. From level 3 they
    /// follow the position, the badges at the trailing edge.
    public let centersMarks: Bool
    /// Between the stars, the flag and the label.
    public let markSpacing: Double
    /// Every part shown, with its form; a part not in it is dropped.
    public let forms: [LoupeCaptionPart: LoupeCaptionForm]

    public var id: Int { number }

    /// The part's form, or nil where the level drops it.
    public func form(of part: LoupeCaptionPart) -> LoupeCaptionForm? { forms[part] }

    public func shows(_ part: LoupeCaptionPart) -> Bool { forms[part] != nil }

    /// The parts no level drops (design §20.1): the version badge, the HDR
    /// badge of an HLG, PQ or DNG photo, Offline, a map's badge (which may
    /// only truncate), the flag, the rating (in one form or the other) and
    /// the color dot.
    public static let neverDropped: Set<LoupeCaptionPart> = [
        .versionBadge, .hdrBadge, .offline, .mapBadge, .flag, .rating, .colorDot,
    ]

    /// The parts that stay whole at every level.
    public static let alwaysWhole: Set<LoupeCaptionPart> = [.versionBadge, .hdrBadge, .offline, .flag, .colorDot]

    /// Between the marks and the badges, and between the position and the
    /// marks, at every level (centered or not).
    public static let gap: Double = 8
    public static let markSpacing: Double = 10
    public static let compactMarkSpacing: Double = 6
    /// Between the compact rating's star and its digit.
    public static let compactRatingSpacing: Double = 2
    public static let colorNameMinimumWidth: Double = 24
    public static let mapBadgeMinimumWidth: Double = 80

    /// One change in the order.
    public enum Change: Equatable, Sendable {
        case drop(LoupeCaptionPart)
        case form(LoupeCaptionPart, LoupeCaptionForm)
        case uncenterMarks
        case compactMarkSpacing
    }

    /// Design §20.1's table, one entry per level: what that level changes
    /// from the one above it. Level 1 changes nothing.
    public static let changes: [[Change]] = [
        // 1. Marks centered, badges in full.
        [],
        // 2. The version badge in its short form (help tag, VoiceOver).
        [.form(.versionBadge, .short)],
        // 3. Marks after the position, badges trailing.
        [.uncenterMarks],
        // 4. Position dropped (the film strip).
        [.drop(.position)],
        // 5. Film strip button dropped (View ▸ Show / Hide Film Strip).
        [.drop(.filmStripToggle)],
        // 6. Spinner dropped (the badge or control that waits); marks compact.
        [.drop(.spinner), .form(.rating, .compact), .compactMarkSpacing],
        // 7. Copy dropped (window title).
        [.drop(.copy)],
        // 8. Filtered dropped (window subtitle, filter toolbar item).
        [.drop(.filtered)],
        // 9. Machine Learning Not Applied dropped (Noise Reduction group).
        [.drop(.machineLearning)],
        // 10. Spot Limit dropped (Spots heading).
        [.drop(.spotLimit)],
        // 11. The label name truncates at the tail, a map's badge in the middle (help tags).
        [.form(.colorName, .truncating(minimumWidth: colorNameMinimumWidth)),
         .form(.mapBadge, .truncating(minimumWidth: mapBadgeMinimumWidth))],
        // 12. Original dropped (View menu, \).
        [.drop(.original)],
        // 13. Last: the label name may shrink to nothing, leaving the dot (help tag, VoiceOver).
        [.form(.colorName, .truncating(minimumWidth: 0))],
    ]

    /// The thirteen levels, in order.
    public static let all: [LoupeCaptionLevel] = {
        var forms = Dictionary(uniqueKeysWithValues: LoupeCaptionPart.allCases.map { ($0, LoupeCaptionForm.whole) })
        var centers = true
        var spacing = markSpacing
        var levels: [LoupeCaptionLevel] = []
        for (index, changes) in changes.enumerated() {
            for change in changes {
                switch change {
                case .drop(let part): forms[part] = nil
                case .form(let part, let form): forms[part] = form
                case .uncenterMarks: centers = false
                case .compactMarkSpacing: spacing = compactMarkSpacing
                }
            }
            levels.append(LoupeCaptionLevel(number: index + 1, centersMarks: centers, markSpacing: spacing, forms: forms))
        }
        return levels
    }()
}
