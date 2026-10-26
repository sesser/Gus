import AppKit
import PhotoCore

/// The debug script's commands for the Adjust tab:
///
///     adjust <name> <value>     (exposure, contrast, highlights, shadows, whites, blacks,
///                               clarity, dehaze, vibrance, saturation, temperature, tint,
///                               warmth, shift, amount, radius, detail, masking,
///                               luminance-nr, color-nr, balance, blending, intensity)
///     adjust look standard|neutral|flat       adjust wb <preset>
///     adjust curve rgb|red|green|blue <x,y> <x,y> …
///     adjust grade shadows|midtones|highlights <hue> <amount> [<luminance>]
///     adjust auto exposure|wb   (waits for the measurement)
///     adjust reset all|develop|tone|details|colorGrading
///     original on|off           tab info|adjust          print adjustments
@MainActor
enum DebugAdjustCommands {
    static let numbers: [String: WritableKeyPath<Adjustments, Double>] = [
        "exposure": \.exposure.ev,
        "contrast": \.tone.contrast, "highlights": \.tone.highlights, "shadows": \.tone.shadows,
        "whites": \.tone.whites, "blacks": \.tone.blacks,
        "clarity": \.presence.clarity, "dehaze": \.presence.dehaze,
        "vibrance": \.presence.vibrance, "saturation": \.presence.saturation,
        "warmth": \.whiteBalance.relativeTemperature, "shift": \.whiteBalance.relativeTint,
        "amount": \.sharpen.amount, "radius": \.sharpen.radius, "detail": \.sharpen.detail, "masking": \.sharpen.masking,
        "balance": \.colorGrade.balance, "blending": \.colorGrade.blending, "intensity": \.lookTable.intensity,
    ]

    static func run(_ words: [String], editor: AdjustmentEditor) async {
        guard let name = words.first else { return }
        let arguments = Array(words.dropFirst())
        let value = Double(arguments.first ?? "")
        let actionName = "Debug \(name)"
        switch name {
        case "auto":
            if arguments.first == "wb" { editor.autoWhiteBalance() } else { editor.autoExposure() }
            try? await Task.sleep(for: .milliseconds(50))
            while editor.isMeasuring { try? await Task.sleep(for: .milliseconds(50)) }
        case "reset":
            if let section = Adjustments.Section(rawValue: arguments.first ?? "") {
                editor.reset(section)
            } else {
                editor.resetAll()
            }
        case "look":
            editor.change(actionName, phase: .committed) {
                $0.decode.look = RawDecode.Look(rawValue: arguments.first ?? "") ?? .standard
            }
        case "wb":
            let preset = WhiteBalance.Preset(rawValue: arguments.first ?? "") ?? .asShot
            editor.change(actionName, phase: .committed) { $0.whiteBalance = .raw(preset) }
        case "temperature", "tint":
            guard let value else { break }
            let defaults = editor.rawDefaults
            editor.change(actionName, phase: .committed) {
                $0.whiteBalance.preset = .custom
                $0.whiteBalance.temperature = name == "temperature" ? value : $0.whiteBalance.temperature ?? defaults?.temperature
                $0.whiteBalance.tint = name == "tint" ? value : $0.whiteBalance.tint ?? defaults?.tint
            }
        case "luminance-nr":
            editor.change(actionName, phase: .committed) { $0.noiseReduction.luminance = value }
        case "color-nr":
            editor.change(actionName, phase: .committed) { $0.noiseReduction.color = value }
        case "curve":
            guard let channel = ToneCurve.Channel(rawValue: arguments.first ?? "") else { break }
            let points = arguments.dropFirst().compactMap { pair -> CurvePoint? in
                let parts = pair.split(separator: ",").compactMap { Double($0) }
                return parts.count == 2 ? CurvePoint(x: parts[0], y: parts[1]) : nil
            }
            editor.change(actionName, phase: .committed) { $0.toneCurve[channel] = points }
        case "grade":
            guard let range = ColorGrade.Range(rawValue: arguments.first ?? "") else { break }
            let numbers = arguments.dropFirst().compactMap(Double.init)
            guard numbers.count >= 2 else { break }
            editor.change(actionName, phase: .committed) {
                $0.colorGrade[range] = GradeWheel(hue: numbers[0], amount: numbers[1],
                                                  luminance: numbers.count > 2 ? numbers[2] : 0)
            }
        default:
            guard let keyPath = numbers[name], let value else {
                print("debug-script: unknown adjustment \(name)")
                return
            }
            editor.change(actionName, phase: .committed) { $0[keyPath: keyPath] = value }
        }
    }

    static func printState(_ editor: AdjustmentEditor) {
        let json = (try? editor.adjustments.editStack.jsonString()) ?? "?"
        print("debug-script: adjust state \(editor.state) live \(editor.showsLive) original \(editor.showsOriginal)"
              + " hash \(editor.item?.editStackHash.prefix(12) ?? "-") stack \(json)")
    }
}
