import AppKit
import PhotoCore

/// The debug script's Spots commands (docs/features/healing/design.md §16):
///
///     spots on|off              Edit Spots (H)
///     spots overlay on|off      the spot overlay (V)
///     spots print               the spots, the selection, the tool, the caption
///     spot add <x> <y>          a click on the photo at unit coordinates of the photo as shown
///                               (waits for its automatic source; refused at the limit or with no source)
///     spot select <n>|none      by placement order, from 1
///     spot next|previous        Select Next / Previous Spot
///     spot delete               the selected spot     spot clear    Delete All Spots
///     spot mode heal|clone      the selected spot, and the next one
///     spot set size|feather|opacity <value>   (size in percent of the long edge)
///     spot drag spot|source|size <x> <y>      a drag of the selected spot, its source or its
///                               ring's handle to unit coordinates of the photo as shown, one undo step
///     spot source auto          Choose Source Automatically (waits)
///     spot nudge left|right|up|down [source] [large] [hold]   the option-arrow keys (saves at once;
///                               with hold, waits unsaved as a menu-chosen nudge does, until the next change)
///     spot enable on|off        the Spots heading's check box
///     spot fill <n>             adds n small spots on a grid with set sources, as one step (for the limit)
@MainActor
enum DebugSpotCommands {
    static func run(_ words: [String], model: LibraryModel) async {
        let editor = model.editor
        guard let verb = words.first else { return }
        let arguments = Array(words.dropFirst())
        func number(_ index: Int) -> Double? { arguments.count > index ? Double(arguments[index]) : nil }
        switch verb {
        case "add":
            guard let x = number(0), let y = number(1) else { return print("spot add <x> <y>") }
            editor.addSpot(atOutput: CGPoint(x: x, y: y))
            await editor.spotPlacementTask?.value
        case "select":
            if arguments.first == "none" {
                editor.selectedSpotID = nil
            } else if let n = number(0).map(Int.init), editor.adjustments.spots.spots.indices.contains(n - 1) {
                editor.selectedSpotID = editor.adjustments.spots.spots[n - 1].id
            }
        case "next", "previous":
            editor.selectSpot(next: verb == "next")
        case "delete":
            editor.deleteSelectedSpot()
        case "clear":
            editor.deleteAllSpots()
        case "mode":
            if let mode = arguments.first.flatMap(SpotMode.init(rawValue:)) { editor.setSpotMode(mode) }
        case "set":
            guard let control = arguments.first, let value = number(1) else { return print("spot set <control> <value>") }
            switch control {
            case "size": editor.setSpotSize(percent: value, phase: .committed)
            case "feather": editor.setSpotFeather(value, phase: .committed)
            case "opacity": editor.setSpotOpacity(value, phase: .committed)
            default: print("spot set size|feather|opacity <value>")
            }
        case "drag":
            await drag(arguments, editor: editor)
        case "source":
            editor.chooseSpotSourceAutomatically()
            await editor.spotSourceTask?.value
        case "nudge":
            guard let direction = arguments.first.flatMap(nudge) else { return print("spot nudge left|right|up|down") }
            model.nudgeSpot(direction, source: arguments.contains("source"), large: arguments.contains("large"))
            if !arguments.contains("hold") { editor.commitSpotNudge() }
        case "fill":
            guard let count = number(0).map(Int.init), count > 0 else { return print("spot fill <n>") }
            let side = Int(Double(count).squareRoot().rounded(.up))
            let spots = (0..<count).map { index in
                let x = 0.05 + 0.9 * (Double(index % side) + 0.5) / Double(side)
                let y = 0.05 + 0.9 * (Double(index / side) + 0.5) / Double(side)
                return Spot(center: MaskPoint(x: x, y: y), size: 0.002, source: MaskPoint(x: x + 0.01, y: y))
            }
            editor.changeSpots(String(localized: "Add Spot", comment: "Undo action name and History label"), phase: .committed) {
                $0.spots += spots
            }
        case "enable":
            editor.setEnabled(Adjustments.Group.spots, arguments.first == "on")
        default:
            print("unknown spot command: \(words.joined(separator: " "))")
        }
    }

    static func runTool(_ words: [String], model: LibraryModel) {
        switch (words.first, words.dropFirst().first) {
        case ("on", _): if !model.editor.isEditingSpots { model.toggleEditingSpots() }
        case ("off", _): model.editor.setEditingSpots(false)
        case ("overlay", "on"): if !model.editor.showsSpotOverlay { model.toggleSpotOverlay() }
        case ("overlay", "off"): if model.editor.showsSpotOverlay { model.toggleSpotOverlay() }
        case ("print", _): printState(model)
        default: print("spots on|off|overlay on|off|print")
        }
    }

    private static func nudge(_ name: String) -> LibraryModel.SpotNudge? {
        switch name {
        case "left": .left
        case "right": .right
        case "up": .up
        case "down": .down
        default: nil
        }
    }

    /// Five changing steps from the part's place to the point, then the release.
    private static func drag(_ arguments: [String], editor: AdjustmentEditor) async {
        guard arguments.count >= 3, let x = Double(arguments[1]), let y = Double(arguments[2]),
              let spot = editor.selectedSpot, let target = editor.maskPoint(fromOutput: CGPoint(x: x, y: y)),
              let geometry = editor.spotGeometry else { return print("spot drag spot|source|size <x> <y> (a spot selected)") }
        let start: MaskPoint = arguments[0] == "source" ? spot.source : spot.center
        for step in 1...5 {
            let t = Double(step) / 5
            let point = MaskPoint(x: start.x + (target.x - start.x) * t, y: start.y + (target.y - start.y) * t)
            let phase: EditPhase = step == 5 ? .committed : .changing
            switch arguments[0] {
            case "spot": editor.moveSpot(spot.id, to: point, phase: phase)
            case "source": editor.moveSpotSource(spot.id, to: point, phase: phase)
            case "size":
                let center = geometry.pixels(spot.center), pointer = geometry.pixels(point)
                editor.resizeSpot(spot.id, to: Double(hypot(pointer.x - center.x, pointer.y - center.y)) / geometry.longEdge,
                                  actionName: String(localized: "Resize Spot", comment: "Undo action name and History label"),
                                  phase: phase)
            default: return print("spot drag spot|source|size <x> <y>")
            }
            try? await Task.sleep(for: .milliseconds(40))
        }
    }

    static func printState(_ model: LibraryModel) {
        let editor = model.editor
        let values = editor.adjustments
        let template = editor.spotTemplate
        print("spots: editing \(editor.isEditingSpots), overlay \(editor.showsSpotOverlay), can edit \(model.canEditSpots), "
            + "on \(values.isEnabled(Adjustments.Group.spots)), count \(values.spots.spots.count), "
            + "visible \(editor.visibleSpots.count), at limit \(editor.spotsAtLimit), notice \(editor.spotNotice.map { "\($0)" } ?? "none")")
        print("spots next: \(template.mode.rawValue) size \(format(template.size * 100))% feather \(format(template.feather)) "
            + "opacity \(format(template.opacity))")
        let frame = editor.spotGeometry
        for (index, spot) in values.spots.spots.enumerated() {
            let selected = spot.id == editor.selectedSpotID ? " selected" : ""
            let shown = editor.outputPoint(fromMask: spot.center).map { "shown \(format($0.x)),\(format($0.y))" } ?? ""
            let pixels = frame.map { geometry in
                let c = geometry.pixels(spot.center), s = geometry.pixels(spot.source)
                return "px \(format(c.x)),\(format(c.y)) r \(format(geometry.radius(spot.size))) source px \(format(s.x)),\(format(s.y))"
            } ?? ""
            print("spot \(index + 1)\(selected): \(spot.mode.rawValue) at \(format(spot.center.x)),\(format(spot.center.y)) "
                + "size \(format(spot.size * 100))% source \(format(spot.source.x)),\(format(spot.source.y)) "
                + "feather \(format(spot.feather)) opacity \(format(spot.opacity)) \(shown) \(pixels) "
                + "label \"\(SpotText.elementLabel(spot, editor: editor))\"")
        }
        print("spots caption: \(SpotCaption(editor).text)")
    }

    private static func format(_ value: Double) -> String { String(format: "%.4f", value) }
    private static func format(_ value: CGFloat) -> String { String(format: "%.4f", Double(value)) }
}
