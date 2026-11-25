import PhotoCore
import Testing

/// The single loupe caption's crowding order (issue #282, design §20.1, QA
/// Q6): thirteen levels, the never-dropped parts at every one, and each level
/// changing only what the design's table says.
@Suite("Loupe caption levels")
struct LoupeCaptionLevelsTests {
    typealias Part = LoupeCaptionPart

    @Test func thirteenLevelsNumberedInOrder() {
        #expect(LoupeCaptionLevel.all.map(\.number) == Array(1...13))
    }

    @Test func levelOneShowsEverythingWholeAndCentered() throws {
        let first = try #require(LoupeCaptionLevel.all.first)
        #expect(first.centersMarks)
        #expect(first.markSpacing == 10)
        for part in Part.allCases {
            #expect(first.form(of: part) == .whole, "\(part)")
        }
    }

    @Test func theNeverDroppedPartsAreShownAtEveryLevel() {
        #expect(LoupeCaptionLevel.neverDropped == [.versionBadge, .hdrBadge, .offline, .mapBadge, .flag, .rating, .colorDot])
        for level in LoupeCaptionLevel.all {
            for part in LoupeCaptionLevel.neverDropped {
                #expect(level.shows(part), "level \(level.number) drops \(part)")
            }
            // The badge that says which version is on screen, the HDR badge of an HLG, PQ or DNG
            // photo, Offline, the flag and the dot are whole, or (the version badge) short: never cut.
            for part in LoupeCaptionLevel.alwaysWhole {
                let form = level.form(of: part)
                #expect(form == .whole || (part == .versionBadge && form == .short), "level \(level.number) \(part) \(String(describing: form))")
            }
            // The rating is stars or a star and a digit; a map's badge is never cut below 80 pt.
            #expect(level.form(of: .rating) == .whole || level.form(of: .rating) == .compact)
            if case .truncating(let minimum) = level.form(of: .mapBadge) { #expect(minimum == 80) }
        }
    }

    @Test func centeredLevelsKeepThePosition() {
        // `CenteredCaptionRow` lays out position, marks, badges: a centered level needs all three.
        for level in LoupeCaptionLevel.all where level.centersMarks {
            #expect(level.shows(.position))
        }
    }

    /// Each level against the one above it: exactly the design's row, nothing else.
    @Test func eachLevelChangesOnlyWhatTheTableSays() {
        struct Difference: Equatable {
            var dropped: Set<Part> = []
            var reformed: [Part: LoupeCaptionForm] = [:]
            var uncenters = false
            var spacing: Double?
        }
        let expected: [Int: Difference] = [
            2: Difference(reformed: [.versionBadge: .short]),
            3: Difference(uncenters: true),
            4: Difference(dropped: [.position]),
            5: Difference(dropped: [.filmStripToggle]),
            6: Difference(dropped: [.spinner], reformed: [.rating: .compact], spacing: 6),
            7: Difference(dropped: [.copy]),
            8: Difference(dropped: [.filtered]),
            9: Difference(dropped: [.machineLearning]),
            10: Difference(dropped: [.spotLimit]),
            11: Difference(reformed: [.colorName: .truncating(minimumWidth: 24), .mapBadge: .truncating(minimumWidth: 80)]),
            12: Difference(dropped: [.original]),
            13: Difference(reformed: [.colorName: .truncating(minimumWidth: 0)]),
        ]
        let levels = LoupeCaptionLevel.all
        for (above, level) in zip(levels, levels.dropFirst()) {
            var difference = Difference()
            for part in Part.allCases {
                switch (above.form(of: part), level.form(of: part)) {
                case (.some, nil): difference.dropped.insert(part)
                case (nil, .some): Issue.record("level \(level.number) brings back \(part)")
                case (.some(let old), .some(let new)) where old != new: difference.reformed[part] = new
                default: break
                }
            }
            if above.centersMarks != level.centersMarks {
                #expect(!level.centersMarks, "level \(level.number) centers the marks again")
                difference.uncenters = true
            }
            if above.markSpacing != level.markSpacing { difference.spacing = level.markSpacing }
            #expect(difference == expected[level.number], "level \(level.number)")
        }
    }

    @Test func theLastLevelShowsOnlyTheNeverDroppedPartsAndTheLabelName() throws {
        let last = try #require(LoupeCaptionLevel.all.last)
        #expect(Set(last.forms.keys) == LoupeCaptionLevel.neverDropped.union([.colorName]))
        #expect(last.form(of: .colorName) == .truncating(minimumWidth: 0))
        #expect(last.form(of: .rating) == .compact)
        #expect(last.form(of: .versionBadge) == .short)
        #expect(!last.centersMarks)
    }
}
