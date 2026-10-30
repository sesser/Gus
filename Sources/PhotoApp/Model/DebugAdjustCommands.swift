import AppKit
import PhotoCore

/// The debug script's commands for the Adjust tab:
///
///     adjust <name> <value>     (exposure, contrast, highlights, shadows, whites, blacks,
///                               clarity, dehaze, vibrance, saturation, temperature, tint,
///                               warmth, shift, amount, radius, detail, masking,
///                               luminance-nr, color-nr, balance, blending, intensity,
///                               vignette, vignette-size, roundness, grain, grain-shadows,
///                               grain-midtones, grain-highlights, roughness, grain-color, grain-size)
///     adjust lutspace srgb|displayP3|adobeRGB|proPhoto
///     adjust off|on <group>     (profile, whiteBalance, light, presence, toneCurve, sharpening,
///                               noiseReduction, colorMixer, colorGrade, lookTable, vignette, grain)
///     adjust look standard|neutral|flat       adjust wb <preset>
///     adjust curve rgb|red|green|blue <x,y> <x,y> …
///     adjust grade shadows|midtones|highlights <hue> <amount> [<luminance>]
///     adjust mix red|orange|yellow|green|aqua|blue|purple|magenta <hue> <saturation> <luminance>
///     adjust auto exposure|wb   (waits for the measurement)
///     adjust reset all|develop|tone|details|colorMixer|colorGrading|effects
///     adjust crop begin|done|cancel|reset|show   (begin waits for the crop frame)
///     adjust crop rect <x> <y> <width> <height>  (unit coordinates of the turned frame)
///     adjust crop angle <degrees> | turn left|right | aspect free|square|threeTwo|fourThree|sixteenNine
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
        "vignette": \.vignette.amount, "vignette-size": \.vignette.size, "roundness": \.vignette.roundness,
        "grain": \.grain.strength, "grain-shadows": \.grain.shadows, "grain-midtones": \.grain.midtones,
        "grain-highlights": \.grain.highlights, "roughness": \.grain.roughness, "grain-color": \.grain.color,
        "grain-size": \.grain.size,
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
        case "off", "on":
            guard let group = Adjustments.Group(rawValue: arguments.first ?? "") else { break }
            editor.setEnabled(group, name == "on")
        case "lutspace":
            let space = LookTable.ColorSpace(rawValue: arguments.first ?? "") ?? .sRGB
            editor.change(actionName, phase: .committed) { $0.lookTable.colorSpace = space }
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
        case "mix":
            guard let band = ColorMixer.Band(rawValue: arguments.first ?? "") else { break }
            let values = arguments.dropFirst().compactMap(Double.init)
            guard values.count == 3 else { break }
            editor.change(actionName, phase: .committed) {
                $0.colorMixer[band] = .init(hue: values[0], saturation: values[1], luminance: values[2])
            }
        case "curve":
            guard let channel = ToneCurve.Channel(rawValue: arguments.first ?? "") else { break }
            let points = arguments.dropFirst().compactMap { pair -> CurvePoint? in
                let parts = pair.split(separator: ",").compactMap { Double($0) }
                return parts.count == 2 ? CurvePoint(x: parts[0], y: parts[1]) : nil
            }
            editor.change(actionName, phase: .committed) { $0.toneCurve[channel] = points }
        case "crop":
            await runCrop(arguments, editor: editor)
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

    private static func runCrop(_ arguments: [String], editor: AdjustmentEditor) async {
        let numbers = arguments.dropFirst().compactMap(Double.init)
        switch arguments.first {
        case "begin":
            editor.beginCrop()
            for _ in 0..<200 where editor.cropSession == nil {
                try? await Task.sleep(for: .milliseconds(50))
            }
        case "done": editor.endCrop(save: true)
        case "cancel": editor.endCrop(save: false)
        case "reset": editor.resetCrop()
        case "rect" where numbers.count == 4:
            editor.setCropRect(CropRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3]))
        case "angle" where numbers.count == 1:
            editor.straighten(numbers[0], phase: .changing)
        case "turn":
            editor.rotate(clockwise: arguments.dropFirst().first != "left")
        case "aspect":
            editor.setCropAspect(CropAspect(rawValue: arguments.dropFirst().first ?? "") ?? .free)
        case "show":
            if let session = editor.cropSession {
                print("debug-script: crop session \(session.crop) aspect \(session.aspect)"
                      + " camera \(session.cameraRect) source \(session.sourceSize)")
            } else {
                print("debug-script: crop none, saved \(editor.adjustments.crop)")
            }
        default:
            print("debug-script: unknown crop command \(arguments.joined(separator: " "))")
        }
    }

    static func printState(_ editor: AdjustmentEditor) {
        let json = (try? editor.adjustments.editStack.jsonString()) ?? "?"
        print("debug-script: adjust state \(editor.state) live \(editor.showsLive) original \(editor.showsOriginal)"
              + " hash \(editor.item?.editStackHash.prefix(12) ?? "-") stack \(json)")
    }
}
