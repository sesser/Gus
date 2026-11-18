import Foundation

/// A preset of a pack converted to adjustments.
public struct LuminarConversion: Sendable {
    public var adjustments: Adjustments
    /// The groups the preset sets, which applying it replaces.
    public var groups: Set<Adjustments.Group>
    /// Each tool that changed anything, in tool order: mapped, approximated or left out.
    public var tools: [LuminarToolReport]
    /// The look-up table the preset applies, to install with it.
    public var lookTable: PresetFile.Table?
}

/// Maps the tools of a pack's preset onto adjustment modules (PRD #203 R4).
///
/// The pack applies a stack of tools in order; here each kind of control is
/// one module, rendered in a fixed order. Tools that set the same control add
/// up (two Develop instances, Develop and Color saturation, Structure and
/// Details clarity); curve-like tools (Develop's curves, Supercontrast, Matte)
/// compose in tool order. Tools with no control here are approximated with the
/// closest ones, or left out and reported, never imitated. A converted preset
/// replaces only the groups it sets.
///
/// The format's scales are not documented; every scale that was assumed
/// rather than known is a named constant below (R10).
public enum LuminarMapping {
    // MARK: Assumed scales (R10)

    /// Stops at Exposure ±100.
    public static let exposureRangeEV = 2.0
    /// Channel offset (0 … 1, perceptual) at Color Balance ±100.
    public static let colorBalanceFullScale = 0.2
    /// Red up and blue down (0 … 1, perceptual) at Warmth ±100.
    public static let warmthFullScale = 0.1
    /// How much of Warmth each tonal range gets.
    public static let warmthRangeWeights: [ColorGrade.Range: Double] = [.shadows: 0.5, .midtones: 1, .highlights: 1]
    /// Clarity per point of Structure.
    public static let structureToClarity = 0.75
    /// Clarity per point of the Details Enhancer's mean small, medium and large detail.
    public static let detailsToClarity = 1.0
    /// Color Mixer saturation per point of warm or cool color saturation.
    public static let splitWarmthToSaturation = 1.0
    /// Slope added at a Supercontrast region's pivot at amount 100.
    public static let supercontrastGain = 0.5
    /// How far (in half-widths of its region) Supercontrast balance ±100 moves a region's pivot.
    public static let supercontrastPivotTravel = 0.8

    /// Decimal places kept; values that round to their default are left out.
    static let precision = 4.0

    public static func convert(_ template: LuminarTemplate, resources: [String: Data]) -> LuminarConversion {
        var converter = Converter(template: template, resources: resources)
        converter.run()
        return converter.finish()
    }
}

extension LuminarMapping {
    /// The pack's band suffixes of the HSL channels, by band.
    static let bandSuffixes: [(String, ColorMixer.Band)] = [
        ("Red", .red), ("Orange", .orange), ("Yellow", .yellow), ("Green", .green),
        ("Aqua", .aqua), ("Blue", .blue), ("Purple", .purple), ("Magenta", .magenta),
    ]

    private struct CurveStep {
        var index: Int
        var curve: LuminarCurves.Curve
        /// The points of a plain point curve, kept exactly when it is the only step.
        var points: [CurvePoint]?
    }

    private struct ReportKey: Hashable {
        var tool: LuminarToolReference
        var status: LuminarToolReport.Status
    }

    private struct Converter {
        let template: LuminarTemplate
        /// Resources by lowercased file name.
        let resources: [String: (name: String, data: Data)]

        var whiteBalance = WhiteBalance()
        var exposure = 0.0
        var tone = Tone()
        var presence = Presence()
        var mixer: [ColorMixer.Band: ColorMixer.Shift] = [:]
        var curveSteps: [ToneCurve.Channel: [CurveStep]] = [:]
        var gradeOffsets: [ColorGrade.Range: SIMD3<Double>] = [:]
        var gradeBalance: Double?
        var isBlackAndWhite = false
        var sharpenSources: [(amount: Double, radius: Double, masking: Double)] = []
        var lookTable: LookTable?
        var table: PresetFile.Table?
        var vignette: Vignette?
        var grain: Grain?

        var reports: [ReportKey] = []
        var controls: [ReportKey: [PresetControl]] = [:]

        init(template: LuminarTemplate, resources: [String: Data]) {
            self.template = template
            var byName: [String: (name: String, data: Data)] = [:]
            for (name, data) in resources { byName[name.lowercased()] = (name, data) }
            self.resources = byName
        }

        // MARK: Report

        mutating func report(_ tool: LuminarToolReference, _ status: LuminarToolReport.Status,
                             _ controls: [PresetControl] = []) {
            let key = ReportKey(tool: tool, status: status)
            if !reports.contains(key) { reports.append(key) }
            for control in controls where !(self.controls[key] ?? []).contains(control) {
                self.controls[key, default: []].append(control)
            }
        }

        mutating func report(_ tool: LuminarTool, _ status: LuminarToolReport.Status, _ controls: [PresetControl] = []) {
            report(.known(tool), status, controls)
        }

        mutating func unreport(_ tool: LuminarTool) {
            reports.removeAll { $0.tool == .known(tool) && $0.status != .leftOut }
        }

        // MARK: Driver

        mutating func run() {
            if template.hasLayerSettings { report(.layers, .approximated) }
            let tools = template.tools.filter(\.isEnabled)
            // A preset holds a Develop for files that are not raw and one for raws; here there is one
            // set of values. The first's relative values suit any file, so the raw one is used only alone.
            let usesRawDevelop = !tools.contains { $0.name == LuminarTool.develop.rawValue && Self.changes($0) }
            for tool in tools where Self.changes(tool) {
                if tool.isMasked {
                    report(.masks, .leftOut)
                    continue
                }
                if tool.blendMode != "0" { report(.layers, .approximated) }
                if tool.name == LuminarTool.rawDevelop.rawValue, !usesRawDevelop {
                    report(.rawDevelop, .leftOut)
                    continue
                }
                guard let handled = handle(tool) else {
                    report(LuminarToolReference(identifier: tool.name), .leftOut)
                    continue
                }
                for effect in tool.effects where !handled.contains(effect.id) && Self.changes(effect) {
                    report(LuminarToolReference(identifier: effect.id), .leftOut)
                }
            }
        }

        /// The ids of the effects the tool's handler read, or nil for a tool with no handler.
        mutating func handle(_ tool: LuminarTemplate.Tool) -> Set<String>? {
            switch LuminarTool(rawValue: tool.name) {
            case .develop, .rawDevelop: develop(tool)
            case .aiNoiseReduction: leftOut(tool, as: .aiNoiseReduction)
            case .lookUpTable: lookUpTable(tool)
            case .color: color(tool)
            case .none where tool.name == "ColorEnhancerAdjustmentLayer": colorEnhancer(tool)
            case .colorToning: splitToning(tool)
            case .supercontrast: supercontrast(tool)
            case .matte: matte(tool)
            case .grain: grain(tool)
            case .vignette: vignette(tool)
            case .none where tool.name == "DetailsEnhancerAdjustmentLayer": details(tool)
            case .structure: structure(tool)
            case .none where tool.name == "LandscapeEnhancerAdjustmentLayer": landscape(tool)
            case .dramatic: dramatic(tool)
            case .blackAndWhite: blackAndWhite(tool)
            case .none where tool.name == "AIEnhanceAdjustmentLayer": aiEnhance(tool)
            case .atmosphere: leftOut(tool, as: .atmosphere)
            case .glow: leftOut(tool, as: .glow)
            case .highKey: leftOut(tool, as: .highKey)
            default: nil
            }
        }

        mutating func leftOut(_ tool: LuminarTemplate.Tool, as name: LuminarTool) -> Set<String> {
            report(name, .leftOut)
            return Set(tool.effects.map(\.id))
        }

        // MARK: Develop

        mutating func develop(_ tool: LuminarTemplate.Tool) -> Set<String> {
            let name: LuminarTool = tool.name == LuminarTool.rawDevelop.rawValue ? .rawDevelop : .develop
            var handled = Set<String>()
            var mapped = false
            for effect in tool.effects {
                handled.insert(effect.id)
                switch effect.id {
                case "MIPLDevelopCommonEffectID", "MIPLRawDevelopEffect":
                    exposure += effect.value("Exposure") / 100 * LuminarMapping.exposureRangeEV
                    tone.contrast += effect.value("Contrast")
                    tone.highlights += effect.value("Highlights")
                    tone.shadows += effect.value("Shadows")
                    if ["Exposure", "Contrast", "Highlights", "Shadows", "Temperature", "Tint"].contains(where: effect.isChanged) {
                        mapped = true
                    }
                    developWhiteBalance(effect)
                    if effect.isChanged(LuminarTool.smartTone.rawValue) { report(.smartTone, .leftOut) }
                    if effect.isChanged(LuminarTool.texture.rawValue) { report(.texture, .leftOut) }
                    if effect.parameters.contains(where: { $0.name.hasPrefix("Denoise_") && $0.isChanged }) {
                        report(.noiseReduction, .leftOut)
                    }
                    if effect.isChanged("Brightness") { report(.unknown("Brightness"), .leftOut) }
                case "MIPLBlackWhiteEffect":
                    tone.whites += effect.value("Whites")
                    tone.blacks += effect.value("Blacks")
                    if effect.isChanged("Whites") || effect.isChanged("Blacks") { mapped = true }
                case "MIPLSaturationEffect":
                    presence.saturation += effect.value("Saturation")
                    if effect.isChanged("Saturation") { mapped = true }
                case "MIPLVibranceEffect":
                    presence.vibrance += effect.value("Vibrance")
                    if effect.isChanged("Vibrance") { mapped = true }
                case "MIPLCurveEffect":
                    let channels: [(String, ToneCurve.Channel)] = [("RGB", .rgb), ("R", .red), ("G", .green), ("B", .blue)]
                    for (parameter, channel) in channels {
                        guard let option = effect.parameter(parameter)?.optionValue,
                              let points = LuminarCurves.points(option), !LuminarCurves.isIdentity(points) else { continue }
                        curveSteps[channel, default: []].append(
                            CurveStep(index: tool.index, curve: LuminarCurves.spline(points), points: points))
                        mapped = true
                    }
                case LuminarTool.sharpening.rawValue:
                    addSharpening(effect)
                case LuminarTool.noiseReduction.rawValue:
                    if Self.changes(effect) { report(.noiseReduction, .leftOut) }
                case LuminarTool.lensCorrection.rawValue:
                    if Self.changes(effect) { report(.lensCorrection, .leftOut) }
                default:
                    handled.remove(effect.id)
                }
            }
            if mapped { report(name, .mapped) }
            return handled
        }

        mutating func developWhiteBalance(_ effect: LuminarTemplate.Effect) {
            if effect.id == "MIPLRawDevelopEffect" {
                // Kelvin and tint: the default is the photo's as-shot value, so only a change counts.
                if effect.isChanged("Temperature") || effect.isChanged("Tint") {
                    whiteBalance.preset = .custom
                    whiteBalance.temperature = Self.clamp(effect.value("Temperature"), WhiteBalance.temperatureRange)
                    whiteBalance.tint = Self.clamp(effect.value("Tint"), WhiteBalance.tintRange)
                }
            } else {
                // −100 … +100, relative: the relative white balance of files that are not raw.
                whiteBalance.relativeTemperature += effect.value("Temperature")
                whiteBalance.relativeTint += effect.value("Tint")
            }
        }

        mutating func addSharpening(_ effect: LuminarTemplate.Effect) {
            let amount = effect.value("Amount")
            guard amount > 0 else { return }
            let radius = effect.value("Radius", 50)
            // 0 … 100 (50 by default) to 0.5 … 3 px (1 by default).
            let pixels = radius <= 50 ? 0.5 + radius / 100 : 1 + (radius - 50) / 25
            sharpenSources.append((amount, pixels, effect.value("Masking", 35)))
            report(.sharpening, .mapped)
        }

        // MARK: Look-up table

        mutating func lookUpTable(_ tool: LuminarTemplate.Tool) -> Set<String> {
            guard let effect = tool.effect("MIPLLUTMappingEffect") else { return [] }
            guard let file = effect.parameters.first(where: { $0.fileName != nil }), let fileName = file.fileName else {
                return [effect.id]
            }
            if lookTable != nil {
                report(.lookUpTable, .leftOut)
                return [effect.id]
            }
            guard let found = resources[fileName.lowercased()] else {
                report(.lookUpTable, .leftOut)
                return [effect.id]
            }
            let stem = (found.name as NSString).deletingPathExtension
            let name = [file.prettyName ?? "", template.name, stem].first { !$0.isEmpty } ?? stem
            let identifier = Digest.sha256Hex(found.data)
            table = PresetFile.Table(identifier: identifier, name: name, fileName: "\(name).cube",
                                     colorSpace: LookTable.ColorSpace.sRGB.rawValue, data: found.data)
            lookTable = LookTable(identifier: identifier, name: name,
                                  intensity: Self.clamp(effect.value("Amount", 100), 0...100))
            report(.lookUpTable, .mapped)
            if effect.isChanged("Contrast") || effect.isChanged("Saturation") {
                tone.contrast += effect.value("Contrast")
                presence.saturation += effect.value("Saturation")
                report(.lookUpTable, .approximated, [.contrast, .saturation])
            }
            return [effect.id]
        }

        // MARK: Color

        mutating func color(_ tool: LuminarTemplate.Tool) -> Set<String> {
            var handled = Set<String>()
            for effect in tool.effects {
                handled.insert(effect.id)
                switch effect.id {
                case "MIPLSaturationEffect":
                    presence.saturation += effect.value("Saturation")
                    if effect.isChanged("Saturation") { report(.color, .mapped) }
                case "MIPLVibranceEffect":
                    presence.vibrance += effect.value("Vibrance")
                    if effect.isChanged("Vibrance") { report(.color, .mapped) }
                case "MIPLChannelsEffect":
                    for (suffix, band) in LuminarMapping.bandSuffixes {
                        var shift = mixer[band] ?? ColorMixer.Shift()
                        shift.hue += effect.value("h\(suffix)")
                        shift.saturation += effect.value("s\(suffix)")
                        shift.luminance += effect.value("l\(suffix)")
                        mixer[band] = shift
                    }
                    if effect.parameters.contains(where: \.isChanged) { report(.color, .mapped) }
                case LuminarTool.hueShift.rawValue:
                    if Self.changes(effect) { report(.hueShift, .leftOut) }
                case LuminarTool.removeColorCast.rawValue:
                    if effect.isChanged("Amount"), effect.value("Amount") > 0 { report(.removeColorCast, .leftOut) }
                default:
                    handled.remove(effect.id)
                }
            }
            return handled
        }

        mutating func colorEnhancer(_ tool: LuminarTemplate.Tool) -> Set<String> {
            var handled = Set<String>()
            for effect in tool.effects {
                handled.insert(effect.id)
                switch effect.id {
                case "MIPLBrillianceWarmthEffect":
                    if effect.isChanged(LuminarTool.vividness.rawValue) {
                        presence.vibrance += effect.value(LuminarTool.vividness.rawValue)
                        report(.vividness, .approximated, [.vibrance])
                    }
                    if effect.isChanged(LuminarTool.warmth.rawValue) {
                        let warmth = effect.value(LuminarTool.warmth.rawValue) / 100 * LuminarMapping.warmthFullScale
                        for range in ColorGrade.Range.allCases {
                            addGrade(range, SIMD3(warmth, 0, -warmth), weight: LuminarMapping.warmthRangeWeights[range] ?? 1)
                        }
                        report(.warmth, .approximated, [.colorGrading])
                    }
                case LuminarTool.colorBalance.rawValue:
                    if Self.changes(effect) {
                        let prefixes: [(String, ColorGrade.Range)] = [("S", .shadows), ("M", .midtones), ("H", .highlights)]
                        for (prefix, range) in prefixes {
                            let scale = LuminarMapping.colorBalanceFullScale / 100
                            addGrade(range, SIMD3(effect.value("\(prefix)Red") * scale, effect.value("\(prefix)Green") * scale,
                                                  effect.value("\(prefix)Blue") * scale))
                        }
                        report(.colorBalance, .approximated, [.colorGrading])
                    }
                case LuminarTool.warmAndCoolColors.rawValue:
                    let groups: [(String, [ColorMixer.Band])] = [("Warm Colors", [.red, .orange, .yellow]),
                                                                ("Cool Colors", [.aqua, .blue, .purple])]
                    for (parameter, bands) in groups where effect.isChanged(parameter) {
                        for band in bands {
                            var shift = mixer[band] ?? ColorMixer.Shift()
                            shift.saturation += effect.value(parameter) * LuminarMapping.splitWarmthToSaturation
                            mixer[band] = shift
                        }
                        report(.warmAndCoolColors, .approximated, [.colorMixer])
                    }
                case LuminarTool.colorContrast.rawValue:
                    if Self.changes(effect) { report(.colorContrast, .leftOut) }
                default:
                    handled.remove(effect.id)
                }
            }
            return handled
        }

        mutating func addGrade(_ range: ColorGrade.Range, _ offset: SIMD3<Double>, weight: Double = 1) {
            gradeOffsets[range, default: .zero] += offset * weight
        }

        mutating func splitToning(_ tool: LuminarTemplate.Tool) -> Set<String> {
            guard let effect = tool.effect("MIPLSplitToningEffect") else { return [] }
            let scale = effect.value("Amount", 50) / 50
            let ranges: [(ColorGrade.Range, String)] = [(.shadows, "Shadows"), (.highlights, "Highlights")]
            for (range, prefix) in ranges {
                let amount = effect.value("\(prefix)Saturation") * scale
                if amount > 0 {
                    addGrade(range, ColorGradeCube.offset(for: GradeWheel(hue: effect.value("\(prefix)Hue"), amount: amount)))
                    report(.colorToning, .mapped)
                }
            }
            if effect.isChanged("Balance") { gradeBalance = Self.clamp(effect.value("Balance")) }
            return [effect.id]
        }

        // MARK: Tone

        mutating func supercontrast(_ tool: LuminarTemplate.Tool) -> Set<String> {
            guard let effect = tool.effect("MIPLSmartContrastEffect") else { return [] }
            let amounts = ["Shadows", "Midtones", "Highlights"].map { effect.value($0) }
            let balances = ["MiddleS", "MiddleM", "MiddleH"].map { effect.value($0) }
            if amounts.contains(where: { $0 != 0 }) {
                curveSteps[.rgb, default: []].append(
                    CurveStep(index: tool.index, curve: LuminarCurves.supercontrast(amounts: amounts, balances: balances)))
                report(.supercontrast, .approximated, [.toneCurve])
            }
            return [effect.id]
        }

        mutating func matte(_ tool: LuminarTemplate.Tool) -> Set<String> {
            guard let effect = tool.effect("MIPLFadeEffect") else { return [] }
            let amount = effect.value("Amount")
            guard amount > 0 else { return [effect.id] }
            curveSteps[.rgb, default: []].append(CurveStep(
                index: tool.index,
                curve: LuminarCurves.matte(amount: amount, fade: effect.value("Fade"), contrast: effect.value("Contrast", 20))))
            presence.saturation += amount / 100 * effect.value("Saturation", -20)
            // Its toning has no equivalent: part of what makes the look approximate.
            report(.matte, .approximated, [.toneCurve, .saturation])
            return [effect.id]
        }

        // MARK: Detail

        mutating func details(_ tool: LuminarTemplate.Tool) -> Set<String> {
            var handled = Set<String>()
            for effect in tool.effects {
                handled.insert(effect.id)
                switch effect.id {
                case LuminarTool.sharpening.rawValue:
                    addSharpening(effect)
                case LuminarTool.detailsEnhancer.rawValue:
                    let sizes = ["Small", "Medium", "Large"].map { effect.value("Overall_\($0)_Detail") }
                    if sizes.contains(where: { $0 != 0 }) {
                        presence.clarity += (sizes[0] + sizes[1] + sizes[2]) / 3 * LuminarMapping.detailsToClarity
                        report(.detailsEnhancer, .approximated, [.clarity])
                    }
                default:
                    handled.remove(effect.id)
                }
            }
            return handled
        }

        mutating func structure(_ tool: LuminarTemplate.Tool) -> Set<String> {
            guard let effect = tool.effect("MIPLAIStructureEffect") else { return [] }
            if effect.value("Amount") != 0 {
                presence.clarity += effect.value("Amount") * LuminarMapping.structureToClarity
                report(.structure, .approximated, [.clarity])
            }
            return [effect.id]
        }

        mutating func dramatic(_ tool: LuminarTemplate.Tool) -> Set<String> {
            guard let effect = tool.effect("MIPLComplexBleachEffect") else { return [] }
            let strength = effect.value("Amount") / 100
            if strength > 0 {
                tone.contrast += strength * effect.value("Contrast")
                presence.clarity += strength * effect.value("Local Contrast")
                presence.saturation += strength * effect.value("Saturation")
                report(.dramatic, .approximated, [.contrast, .clarity, .saturation])
            }
            return [effect.id]
        }

        // MARK: Landscape, AI

        mutating func landscape(_ tool: LuminarTemplate.Tool) -> Set<String> {
            var handled = Set<String>()
            for effect in tool.effects {
                handled.insert(effect.id)
                switch effect.id {
                case LuminarTool.dehaze.rawValue:
                    presence.dehaze += effect.value("Amount")
                    if effect.value("Amount") != 0 { report(.dehaze, .mapped) }
                case LuminarTool.goldenHour.rawValue:
                    if effect.value("Amount") != 0 { report(.goldenHour, .leftOut) }
                case LuminarTool.foliage.rawValue:
                    if Self.changes(effect) { report(.foliage, .leftOut) }
                default:
                    handled.remove(effect.id)
                }
            }
            return handled
        }

        mutating func aiEnhance(_ tool: LuminarTemplate.Tool) -> Set<String> {
            var handled = Set<String>()
            for effect in tool.effects {
                if effect.id == LuminarTool.accentAI.rawValue {
                    handled.insert(effect.id)
                    if Self.changes(effect) { report(.accentAI, .leftOut) }
                } else if effect.id == LuminarTool.skyEnhancer.rawValue {
                    handled.insert(effect.id)
                    if Self.changes(effect) { report(.skyEnhancer, .leftOut) }
                }
            }
            return handled
        }

        // MARK: Black and white

        mutating func blackAndWhite(_ tool: LuminarTemplate.Tool) -> Set<String> {
            guard let effect = tool.effect("MIPLBWChannels_v1_Effect") else { return [] }
            // Choices are multiples of 10: Apply 10 is on.
            guard effect.value("Apply") > 0 else { return [effect.id] }
            isBlackAndWhite = true
            // Grading here comes after desaturation; there, tinting done before the conversion turns
            // gray with the rest of the image. Drop it; toning from later tools still applies.
            gradeOffsets = [:]
            gradeBalance = nil
            for tinting in [LuminarTool.warmth, .colorBalance, .colorToning] { unreport(tinting) }
            let names = ["Red", "Yellow", "Green", "Cyan", "Blue", "Violet"]
            var luminance: [String: Double] = [:]
            for name in names { luminance[name] = effect.value("l\(name)") }
            let byBand: [(ColorMixer.Band, Double)] = [
                (.red, luminance["Red"]!), (.orange, (luminance["Red"]! + luminance["Yellow"]!) / 2),
                (.yellow, luminance["Yellow"]!), (.green, luminance["Green"]!), (.aqua, luminance["Cyan"]!),
                (.blue, luminance["Blue"]!), (.purple, luminance["Violet"]!),
                (.magenta, (luminance["Violet"]! + luminance["Red"]!) / 2),
            ]
            for (band, value) in byBand {
                var shift = mixer[band] ?? ColorMixer.Shift()
                shift.luminance += value
                mixer[band] = shift
            }
            // Color the conversion keeps in some hues has no equivalent: part of the approximation.
            report(.blackAndWhite, .approximated, [.colorMixer, .saturation])
            return [effect.id]
        }

        // MARK: Effects

        mutating func grain(_ tool: LuminarTemplate.Tool) -> Set<String> {
            guard let effect = tool.effect("MIPLGrainNewEffect") else { return [] }
            let amount = effect.value("Amount")
            if amount > 0 {
                let size = effect.value("Size", 20)
                // 0 … 100 (20 by default) to 0.5 … 3 (1 by default).
                let mapped = size <= 20 ? 0.5 + size / 40 : 1 + (size - 20) / 40
                var grain = Grain()
                grain.strength = Self.clamp(amount, Grain.strengthRange)
                grain.size = Self.clamp(mapped, Grain.sizeRange)
                grain.roughness = Self.clamp(effect.value("Roughness", 30), 0...100)
                self.grain = grain
                report(.grain, .mapped)
            }
            return [effect.id]
        }

        mutating func vignette(_ tool: LuminarTemplate.Tool) -> Set<String> {
            guard let effect = tool.effect("MIPLVignetteEffect") else { return [] }
            if effect.value("Amount") != 0 {
                vignette = Vignette(amount: Self.clamp(effect.value("Amount")),
                                    size: Self.clamp(effect.value("Vignette Size", 50), 0...100),
                                    roundness: Self.clamp(effect.value("Roundness")))
                if ["Feather", "Inner Light", "Offset X", "Offset Y"].contains(where: effect.isChanged) {
                    // Its feather, inner light and offset stay at this app's: approximated in its own control.
                    report(.vignette, .approximated)
                } else {
                    report(.vignette, .mapped)
                }
            }
            return [effect.id]
        }

        // MARK: Final values

        func finish() -> LuminarConversion {
            var values = Adjustments()
            values.exposure.ev = Self.rounded(Self.clamp(exposure, Exposure.range))
            values.tone = Tone(contrast: Self.rounded(Self.clamp(tone.contrast)),
                               highlights: Self.rounded(Self.clamp(tone.highlights)),
                               shadows: Self.rounded(Self.clamp(tone.shadows)),
                               whites: Self.rounded(Self.clamp(tone.whites)),
                               blacks: Self.rounded(Self.clamp(tone.blacks)))
            values.presence = Presence(clarity: Self.rounded(Self.clamp(presence.clarity)),
                                       dehaze: Self.rounded(Self.clamp(presence.dehaze)),
                                       vibrance: Self.rounded(Self.clamp(presence.vibrance)),
                                       saturation: Self.rounded(Self.clamp(presence.saturation)))
            if isBlackAndWhite {
                values.presence.vibrance = 0
                values.presence.saturation = -100
            }
            var balance = whiteBalance
            balance.temperature = balance.temperature.map(Self.rounded)
            balance.tint = balance.tint.map(Self.rounded)
            balance.relativeTemperature = Self.rounded(Self.clamp(balance.relativeTemperature))
            balance.relativeTint = Self.rounded(Self.clamp(balance.relativeTint))
            values.whiteBalance = balance
            for (band, shift) in mixer {
                values.colorMixer[band] = ColorMixer.Shift(hue: Self.rounded(Self.clamp(shift.hue)),
                                                           saturation: Self.rounded(Self.clamp(shift.saturation)),
                                                           luminance: Self.rounded(Self.clamp(shift.luminance)))
            }
            for channel in ToneCurve.Channel.allCases {
                if let points = Self.curvePoints(curveSteps[channel] ?? []) { values.toneCurve[channel] = points }
            }
            values.colorGrade = grade()
            if let lookTable {
                values.lookTable = lookTable
                values.lookTable.intensity = Self.rounded(lookTable.intensity)
            }
            if let vignette {
                values.vignette = Vignette(amount: Self.rounded(vignette.amount), size: Self.rounded(vignette.size),
                                           roundness: Self.rounded(vignette.roundness))
            }
            if let strongest = sharpenSources.max(by: Self.isWeaker) {
                let amount = sharpenSources.reduce(0) { $0 + $1.amount }
                values.sharpen.amount = Self.rounded(Self.clamp(amount, Sharpen.amountRange))
                values.sharpen.radius = Self.rounded(Self.clamp(strongest.radius, Sharpen.radiusRange))
                values.sharpen.masking = Self.rounded(Self.clamp(strongest.masking, 0...100))
            }
            if let grain {
                values.grain = Grain(strength: Self.rounded(grain.strength), roughness: Self.rounded(grain.roughness),
                                     size: Self.rounded(grain.size))
            }
            return LuminarConversion(adjustments: values, groups: values.modifiedGroups, tools: toolReports(),
                                     lookTable: table)
        }

        /// The sharpening source whose radius and masking win: the largest amount, then radius, then masking.
        static func isWeaker(_ a: (amount: Double, radius: Double, masking: Double),
                             _ b: (amount: Double, radius: Double, masking: Double)) -> Bool {
            if a.amount != b.amount { return a.amount < b.amount }
            if a.radius != b.radius { return a.radius < b.radius }
            return a.masking < b.masking
        }

        func grade() -> ColorGrade {
            var grade = ColorGrade()
            for range in ColorGrade.Range.allCases {
                let wheel = Self.wheel(fromOffset: gradeOffsets[range] ?? .zero)
                if Self.rounded(wheel.amount) > 0 {
                    grade[range] = GradeWheel(hue: Self.rounded(wheel.hue), amount: Self.rounded(Self.clamp(wheel.amount, 0...100)))
                }
            }
            if let gradeBalance, ColorGrade.Range.allCases.contains(where: { grade[$0].amount > 0 }) {
                grade.balance = Self.rounded(gradeBalance)
            }
            return grade
        }

        /// Reports in tool order; a tool approximated anywhere is not also listed as mapped.
        func toolReports() -> [LuminarToolReport] {
            let approximated = Set(reports.filter { $0.status == .approximated }.map(\.tool))
            return reports.compactMap { key in
                if key.status == .mapped, approximated.contains(key.tool) { return nil }
                return LuminarToolReport(tool: key.tool, status: key.status, controls: controls[key] ?? [])
            }
        }

        // MARK: Helpers

        static func curvePoints(_ steps: [CurveStep]) -> [CurvePoint]? {
            guard !steps.isEmpty else { return nil }
            if steps.count == 1, let points = steps[0].points {
                return points.map { CurvePoint(x: rounded($0.x), y: rounded($0.y)) }
            }
            let ordered = steps.enumerated().sorted { a, b in
                a.element.index == b.element.index ? a.offset < b.offset : a.element.index < b.element.index
            }.map(\.element.curve)
            return LuminarCurves.sampled(ordered).map { CurvePoint(x: rounded($0.x), y: rounded($0.y)) }
        }

        /// The hue and amount of the grading wheel closest to adding `offset`. Only its zero-sum (color)
        /// part counts; its mean would be a brightness change. The amount may exceed 100.
        static func wheel(fromOffset offset: SIMD3<Double>) -> (hue: Double, amount: Double) {
            let mean = (offset.x + offset.y + offset.z) / 3
            let color = offset - SIMD3(repeating: mean)
            guard let hue = hue(of: color) else { return (0, 0) }
            let unit = ColorGradeCube.offset(for: GradeWheel(hue: hue, amount: 100))
            let unitLength = (unit * unit).sum().squareRoot()
            return (hue, 100 * (color * color).sum().squareRoot() / unitLength)
        }

        /// HSV hue in degrees (0 ..< 360), or nil for gray.
        static func hue(of value: SIMD3<Double>) -> Double? {
            let high = max(value.x, value.y, value.z), low = min(value.x, value.y, value.z)
            let chroma = high - low
            guard chroma >= 1e-12 else { return nil }
            var sector: Double
            if high == value.x {
                sector = ((value.y - value.z) / chroma).truncatingRemainder(dividingBy: 6)
                if sector < 0 { sector += 6 }
            } else if high == value.y {
                sector = (value.z - value.x) / chroma + 2
            } else {
                sector = (value.x - value.y) / chroma + 4
            }
            let degrees = (sector * 60).truncatingRemainder(dividingBy: 360)
            return degrees < 0 ? degrees + 360 : degrees
        }

        static func clamp(_ value: Double, _ range: ClosedRange<Double> = -100...100) -> Double {
            min(max(value, range.lowerBound), range.upperBound)
        }

        /// Rounded to `precision` decimals, with no negative zero.
        static func rounded(_ value: Double) -> Double {
            let scale = pow(10, LuminarMapping.precision)
            let result = (value * scale).rounded() / scale
            return result == 0 ? 0 : result
        }

        /// True when an effect changes anything: a curve that is not the identity, a changed value, a file.
        static func changes(_ effect: LuminarTemplate.Effect) -> Bool {
            if effect.id == "MIPLCurveEffect" {
                return effect.parameters.contains { parameter in
                    LuminarCurves.points(parameter.optionValue).map { !LuminarCurves.isIdentity($0) } ?? false
                }
            }
            return effect.parameters.contains { $0.isChanged || $0.fileName != nil }
        }

        static func changes(_ tool: LuminarTemplate.Tool) -> Bool {
            tool.effects.contains(where: changes)
        }
    }
}
