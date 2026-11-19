import PhotoCore

/// The debug script's Black & White commands (bw-module design §16), under
/// `adjust` so each runs in its own undo group:
///
///     adjust bw print                       (the state, as the heading and the menu show it)
///     adjust bw toggle                      (the heading's check box)
///     adjust bw on|off                      (Turn On / Turn Off from the heading's context menu)
///     adjust bw filter yellow|orange|red|green|blue   (a quick-set: the segment or the menu item)
///     adjust bw nofilter                    (Adjust ▸ Black & White ▸ No Filter)
///     adjust bw set <filter> <value>        (a slider's value, committed)
///     adjust bw reset                       (the heading's reset)
///
/// Every command prints the state after it.
@MainActor
enum DebugBlackAndWhiteCommands {
    static func run(_ arguments: [String], editor: AdjustmentEditor) {
        let filter = arguments.dropFirst().first.flatMap(BlackAndWhite.Filter.init(rawValue:))
        switch arguments.first {
        case "print", nil:
            break
        case "toggle":
            editor.toggleBlackAndWhite()
        case "on", "off":
            editor.setEnabled(Adjustments.Group.blackAndWhite, arguments.first == "on")
        case "filter":
            guard let filter else { return unknown(arguments) }
            editor.chooseBlackAndWhite(filter)
        case "nofilter":
            editor.clearBlackAndWhiteFilters()
        case "set":
            guard let filter, let value = arguments.dropFirst(2).first.flatMap(Double.init) else { return unknown(arguments) }
            editor.setBlackAndWhite(filter, value, phase: .committed)
        case "reset":
            editor.reset(.blackAndWhite)
        default:
            return unknown(arguments)
        }
        printState(editor)
    }

    /// One line: whether it is on and applies, the five values, the quick-set
    /// the segmented control and menu show (its index, -1 for none), the check
    /// box, and the caption shown.
    static func printState(_ editor: AdjustmentEditor) {
        let values = editor.adjustments
        let module = values.blackAndWhite
        let filters = BlackAndWhite.Filter.allCases
        let amounts = filters.map { "\($0.rawValue) \(SliderFormat.plain.text(module[$0]))" }.joined(separator: ", ")
        let quickSet = editor.blackAndWhiteQuickSet
        let segment = quickSet.flatMap { filters.firstIndex(of: $0) } ?? -1
        print("debug-script: blackAndWhite on \(module.isOn) applies \(values.blackAndWhiteApplies)"
              + " turnedOff \(!values.isEnabled(Adjustments.Group.blackAndWhite)) [\(amounts)]"
              + " quickSet \(quickSet?.rawValue ?? "none") segment \(segment)"
              + " checkbox \(values.blackAndWhiteApplies ? "on" : "off") noFilter \(editor.blackAndWhiteHasNoFilter)"
              + " modified \(values.isModified(Adjustments.Section.blackAndWhite))"
              + " caption \(editor.sourceIsMonochrome ? "monochrome" : "static")")
    }

    private static func unknown(_ arguments: [String]) {
        print("debug-script: unknown black and white command \(arguments.joined(separator: " "))")
    }
}
