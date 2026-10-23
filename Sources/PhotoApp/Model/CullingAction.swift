import AppKit
import PhotoCore

/// Something the person can do to the photos they are looking at.
enum CullingAction: Equatable {
    case setRating(Rating)
    case adjustRating(Int)
    case setFlag(Flag)
    case setColorLabel(ColorLabel)

    var undoActionName: String {
        switch self {
        case .setRating, .adjustRating: String(localized: "Set Rating", comment: "Undo action name")
        case .setFlag: String(localized: "Set Flag", comment: "Undo action name")
        case .setColorLabel: String(localized: "Set Color Label", comment: "Undo action name")
        }
    }
}

/// The single place culling keys are defined. Grid and loupe both route key events
/// through here, so the bindings cannot drift apart. Bare keys are handled by
/// those views rather than as menu key equivalents, which would also fire while
/// typing in a text field or an open panel.
///
///     0–5      set rating            [ / ]    lower / raise rating
///     P        pick                  X        reject           U   clear flag
///     ⌥1–⌥7    color label           ⌥0       clear label
enum CullingKeymap {
    static func action(for event: NSEvent) -> CullingAction? {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function])
        guard let characters = event.charactersIgnoringModifiers?.lowercased(), characters.count == 1 else {
            return nil
        }
        if modifiers.isEmpty {
            switch characters {
            case "0", "1", "2", "3", "4", "5":
                return .setRating(Rating(clamping: Int(characters) ?? 0))
            case "[": return .adjustRating(-1)
            case "]": return .adjustRating(1)
            case "p": return .setFlag(.picked)
            case "x": return .setFlag(.rejected)
            case "u": return .setFlag(.none)
            default: return nil
            }
        }
        if modifiers == .option, let digit = Int(characters) ?? optionDigit(event), (0...7).contains(digit) {
            return .setColorLabel(ColorLabel(rawValue: digit) ?? .none)
        }
        return nil
    }

    /// With ⌥ held, some layouts report a symbol instead of the digit; fall back to
    /// the hardware key code of the number row.
    private static func optionDigit(_ event: NSEvent) -> Int? {
        let numberRow: [UInt16: Int] = [29: 0, 18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7]
        return numberRow[event.keyCode]
    }
}

/// Navigation keys shared by grid and loupe.
enum NavigationKey {
    case left, right, up, down, home, end, pageUp, pageDown
    case toggleLoupe
    case exitLoupe
    case toggleZoom

    static func from(_ event: NSEvent) -> NavigationKey? {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control])
        guard modifiers.isEmpty else { return nil }
        switch event.keyCode {
        case 123: return .left
        case 124: return .right
        case 125: return .down
        case 126: return .up
        case 115: return .home
        case 119: return .end
        case 116: return .pageUp
        case 121: return .pageDown
        case 36, 76, 49: return .toggleLoupe // return, enter, space
        case 53: return .exitLoupe           // escape
        default: break
        }
        if event.charactersIgnoringModifiers?.lowercased() == "z" { return .toggleZoom }
        return nil
    }
}
