import AppKit
import PhotoCore
import PhotoUI
import SwiftUI

/// The inspector's Adjust tab: the focused photo's adjustments under
/// collapsible headings. Editing happens in the loupe.
struct AdjustView: View {
    let model: LibraryModel

    private var editor: AdjustmentEditor { model.editor }

    var body: some View {
        VStack(spacing: 0) {
            content
            Divider()
            CopyPasteBar(model: model)
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.mode != .loupe {
            AppKitScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Open a photo in the loupe to adjust it. Paste Adjustments and presets change every selected photo.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Divider()
                    PresetsSection(model: model)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            switch editor.state {
            case .idle:
                message(String(localized: "No photo"))
            case .loading:
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .video:
                message(String(localized: "Adjustments are not available for videos."))
            case .offline:
                message(String(localized: "The original is offline. Connect its volume to adjust this photo."))
            case .ready:
                AppKitScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        AdjustToolbar(model: model)
                        PresetsSection(model: model)
                        Divider()
                        AdjustSection(.develop, editor: editor) {
                            DevelopControls(editor: editor)
                        }
                        Divider()
                        AdjustSection(.tone, editor: editor) {
                            ToneCurveControls(editor: editor)
                                .dimmedWhenOff(.toneCurve, editor: editor)
                        }
                        Divider()
                        AdjustSection(.details, editor: editor) {
                            DetailControls(editor: editor)
                        }
                        Divider()
                        AdjustSection(.colorMixer, editor: editor) {
                            ColorMixerControls(editor: editor)
                                .dimmedWhenOff(.colorMixer, editor: editor)
                        }
                        Divider()
                        AdjustSection(.colorGrading, editor: editor) {
                            ColorGradeControls(editor: editor)
                                .dimmedWhenOff(.colorGrade, editor: editor)
                        }
                        Divider()
                        AdjustSection(.effects, editor: editor) {
                            EffectsControls(model: model)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The original toggle and reset for everything.
private struct AdjustToolbar: View {
    let model: LibraryModel

    private var editor: AdjustmentEditor { model.editor }

    var body: some View {
        HStack(spacing: 8) {
            AppKitButton(title: editor.showsOriginal ? String(localized: "Show Edit") : String(localized: "Show Original"),
                         symbol: "square.split.2x1", style: .borderless,
                         help: String(localized: "Compare with the original (\\)")) {
                editor.toggleOriginal()
            }
            Spacer()
            AppKitButton(title: String(localized: "Reset All"), style: .push,
                         help: String(localized: "Remove every adjustment from this photo"),
                         isEnabled: !editor.adjustments.isDefault) {
                editor.resetAll()
            }
        }
    }
}

/// Copy and Paste Adjustments, under the Adjust tab: for the photo on screen
/// or the selection.
private struct CopyPasteBar: View {
    let model: LibraryModel

    var body: some View {
        HStack(spacing: 6) {
            AppKitButton(title: String(localized: "Copy Adjustments"), style: .push,
                         help: String(localized: "Copy this photo's adjustments"),
                         isEnabled: model.focusedItem != nil) {
                model.copyAdjustments()
            }
            AppKitButton(title: String(localized: "Paste Adjustments"), style: .push,
                         help: String(localized: "Give the copied adjustments to the photo on screen or the selection"),
                         isEnabled: model.copiedAdjustments != nil && model.focusedItem != nil) {
                model.pasteAdjustments()
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

extension View {
    /// Shows a group's controls faded while its edits are turned off. They stay
    /// usable: changing one turns the group back on.
    func dimmedWhenOff(_ group: Adjustments.Group, editor: AdjustmentEditor) -> some View {
        opacity(editor.adjustments.isEnabled(group) ? 1 : 0.45)
    }
}

/// A small caption above a group of sliders.
struct ControlGroupLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.tertiary)
            .padding(.top, 2)
    }
}

/// Binds a slider to one value of the editor's adjustments.
@MainActor
func adjustSlider(_ editor: AdjustmentEditor, _ title: String, _ keyPath: WritableKeyPath<Adjustments, Double>,
                  range: ClosedRange<Double> = -100...100, defaultValue: Double = 0,
                  format: SliderFormat = .signed) -> AdjustSlider {
    AdjustSlider(title: title, value: editor.adjustments[keyPath: keyPath], range: range, defaultValue: defaultValue,
                 format: format) { value, phase in
        editor.change(title, phase: phase) { $0[keyPath: keyPath] = value }
    }
}

private struct DevelopControls: View {
    let editor: AdjustmentEditor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if editor.isRaw {
                GroupLabel(.profile, editor: editor)
                profile
                    .dimmedWhenOff(.profile, editor: editor)
            }
            GroupLabel(.whiteBalance, editor: editor)
            VStack(alignment: .leading, spacing: 8) {
                whiteBalance
            }
            .dimmedWhenOff(.whiteBalance, editor: editor)
            GroupLabel(.light, editor: editor) {
                AppKitButton(title: String(localized: "Auto"), style: .push,
                             help: String(localized: "Set the exposure from the photo's brightness"),
                             isEnabled: !editor.isMeasuring) {
                    editor.autoExposure()
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                adjustSlider(editor, String(localized: "Exposure"), \.exposure.ev, range: Exposure.range, format: .stops)
                adjustSlider(editor, String(localized: "Contrast"), \.tone.contrast)
                adjustSlider(editor, String(localized: "Highlights"), \.tone.highlights)
                adjustSlider(editor, String(localized: "Shadows"), \.tone.shadows)
                adjustSlider(editor, String(localized: "Whites"), \.tone.whites)
                adjustSlider(editor, String(localized: "Blacks"), \.tone.blacks)
            }
            .dimmedWhenOff(.light, editor: editor)
            GroupLabel(.presence, editor: editor)
            VStack(alignment: .leading, spacing: 8) {
                adjustSlider(editor, String(localized: "Clarity"), \.presence.clarity)
                adjustSlider(editor, String(localized: "Dehaze"), \.presence.dehaze)
                adjustSlider(editor, String(localized: "Vibrance"), \.presence.vibrance)
                adjustSlider(editor, String(localized: "Saturation"), \.presence.saturation)
            }
            .dimmedWhenOff(.presence, editor: editor)
        }
    }

    private var profile: some View {
        VStack(alignment: .leading, spacing: 6) {
            LabeledPopUp(title: String(localized: "Profile")) {
                AppKitPopUp(items: RawDecode.Look.allCases.map { .init(title: Self.lookTitle($0), tag: $0.rawValue) },
                            selection: editor.adjustments.decode.look.rawValue) { tag in
                    editor.change(String(localized: "Profile"), phase: .committed) {
                        $0.decode.look = RawDecode.Look(rawValue: tag) ?? .standard
                    }
                }
            }
            if let defaults = editor.rawDefaults, defaults.decoderVersions.count > 1 {
                LabeledPopUp(title: String(localized: "Decoder")) {
                    AppKitPopUp(items: defaults.decoderVersions.reversed().map { version in
                        .init(title: version == defaults.defaultDecoderVersion
                                  ? String(localized: "\(version) (default)", comment: "RAW decoder version") : version,
                              tag: version)
                    }, selection: editor.adjustments.decode.decoderVersion ?? defaults.defaultDecoderVersion) { tag in
                        editor.change(String(localized: "Decoder"), phase: .committed) {
                            $0.decode.decoderVersion = tag == defaults.defaultDecoderVersion ? nil : tag
                        }
                    }
                }
            }
        }
    }

    static func lookTitle(_ look: RawDecode.Look) -> String {
        switch look {
        case .standard: String(localized: "Standard", comment: "RAW profile")
        case .neutral: String(localized: "Neutral", comment: "RAW profile")
        case .flat: String(localized: "Flat", comment: "RAW profile")
        }
    }

    static func presetTitle(_ preset: WhiteBalance.Preset) -> String {
        switch preset {
        case .asShot: String(localized: "As Shot", comment: "White balance preset")
        case .auto: String(localized: "Auto", comment: "White balance preset")
        case .daylight: String(localized: "Daylight", comment: "White balance preset")
        case .cloudy: String(localized: "Cloudy", comment: "White balance preset")
        case .shade: String(localized: "Shade", comment: "White balance preset")
        case .tungsten: String(localized: "Tungsten", comment: "White balance preset")
        case .fluorescent: String(localized: "Fluorescent", comment: "White balance preset")
        case .flash: String(localized: "Flash", comment: "White balance preset")
        case .custom: String(localized: "Custom", comment: "White balance preset")
        }
    }

    @ViewBuilder
    private var whiteBalance: some View {
        let balance = editor.adjustments.whiteBalance
        let presets = editor.isRaw ? WhiteBalance.Preset.allCases : WhiteBalance.Preset.relativePresets
        LabeledPopUp(title: String(localized: "Preset")) {
            AppKitPopUp(items: presets.map { .init(title: Self.presetTitle($0), tag: $0.rawValue) },
                        selection: balance.preset.rawValue, isEnabled: !editor.isMeasuring) { tag in
                pick(WhiteBalance.Preset(rawValue: tag) ?? .asShot)
            }
        }
        if editor.isRaw {
            let defaults = editor.rawDefaults
            AdjustSlider(title: String(localized: "Temperature"),
                         value: balance.temperature ?? defaults?.temperature ?? 5500,
                         range: WhiteBalance.temperatureRange, defaultValue: defaults?.temperature ?? 5500,
                         format: .kelvin, scale: .reciprocal) { value, phase in
                editor.change(String(localized: "Temperature"), phase: phase) {
                    $0.whiteBalance.temperature = value
                    $0.whiteBalance.tint = $0.whiteBalance.tint ?? defaults?.tint
                    $0.whiteBalance.preset = .custom
                }
            }
            AdjustSlider(title: String(localized: "Tint"), value: balance.tint ?? defaults?.tint ?? 0,
                         range: WhiteBalance.tintRange, defaultValue: defaults?.tint ?? 0) { value, phase in
                editor.change(String(localized: "Tint"), phase: phase) {
                    $0.whiteBalance.tint = value
                    $0.whiteBalance.temperature = $0.whiteBalance.temperature ?? defaults?.temperature
                    $0.whiteBalance.preset = .custom
                }
            }
        } else {
            AdjustSlider(title: String(localized: "Temperature"), value: balance.relativeTemperature,
                         range: -100...100, defaultValue: 0) { value, phase in
                editor.change(String(localized: "Temperature"), phase: phase) {
                    $0.whiteBalance.relativeTemperature = value
                    $0.whiteBalance.preset = .custom
                }
            }
            AdjustSlider(title: String(localized: "Tint"), value: balance.relativeTint,
                         range: -100...100, defaultValue: 0) { value, phase in
                editor.change(String(localized: "Tint"), phase: phase) {
                    $0.whiteBalance.relativeTint = value
                    $0.whiteBalance.preset = .custom
                }
            }
        }
    }

    private func pick(_ preset: WhiteBalance.Preset) {
        let name = String(localized: "White Balance")
        switch preset {
        case .auto:
            editor.autoWhiteBalance()
        case .asShot:
            editor.change(name, phase: .committed) { $0.whiteBalance = WhiteBalance() }
        case .custom:
            editor.change(name, phase: .committed) { $0.whiteBalance.preset = .custom }
        default:
            editor.change(name, phase: .committed) { $0.whiteBalance = .raw(preset) }
        }
    }
}

/// Shadows, midtones and highlights wheels, one shown at a time.
private struct ColorGradeControls: View {
    let editor: AdjustmentEditor
    @State private var range = ColorGrade.Range.midtones

    var body: some View {
        let wheel = editor.adjustments.colorGrade[range]
        let name = String(localized: "Color Grading")
        VStack(alignment: .leading, spacing: 8) {
            AppKitSegmented(labels: ColorGrade.Range.allCases.map(Self.title),
                            selection: ColorGrade.Range.allCases.firstIndex(of: range) ?? 1) { index in
                range = ColorGrade.Range.allCases[index]
            }
            ColorWheel(hue: wheel.hue, amount: wheel.amount) { hue, amount, phase in
                editor.change(name, phase: phase) {
                    $0.colorGrade[range].hue = hue
                    $0.colorGrade[range].amount = amount
                }
            }
            HStack {
                Text("Hue \(Int(wheel.hue))°  Amount \(Int(wheel.amount))")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Spacer()
            }
            AdjustSlider(title: String(localized: "Luminance"), value: wheel.luminance, range: -100...100,
                         defaultValue: 0) { value, phase in
                editor.change(name, phase: phase) { $0.colorGrade[range].luminance = value }
            }
            adjustSlider(editor, String(localized: "Balance"), \.colorGrade.balance)
            adjustSlider(editor, String(localized: "Blending"), \.colorGrade.blending, range: 0...100,
                         defaultValue: 50, format: .plain)
        }
    }

    static func title(_ range: ColorGrade.Range) -> String {
        switch range {
        case .shadows: String(localized: "Shadows")
        case .midtones: String(localized: "Midtones", comment: "Color grading range")
        case .highlights: String(localized: "Highlights")
        }
    }
}

/// One band of hues picked from a row of swatches, with its three sliders.
private struct ColorMixerControls: View {
    let editor: AdjustmentEditor
    @State private var band = ColorMixer.Band.red

    var body: some View {
        let mixer = editor.adjustments.colorMixer
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 2) {
                ForEach(ColorMixer.Band.allCases, id: \.self) { item in
                    AppKitButton(symbol: Self.symbol(item, selected: item == band, edited: !mixer[item].isZero),
                                 symbolWeight: .semibold, style: .borderless, tint: Self.swatch(item),
                                 help: Self.title(item)) {
                        band = item
                    }
                }
                Spacer()
            }
            Text(Self.title(band))
                .font(.caption)
                .foregroundStyle(.secondary)
            adjustSlider(editor, String(localized: "Hue"), \.colorMixer[band].hue)
            adjustSlider(editor, String(localized: "Saturation"), \.colorMixer[band].saturation)
            adjustSlider(editor, String(localized: "Luminance"), \.colorMixer[band].luminance)
        }
    }

    /// The picked band is a ring with a dot; bands with changes are filled.
    static func symbol(_ band: ColorMixer.Band, selected: Bool, edited: Bool) -> String {
        if selected { return "circle.inset.filled" }
        return edited ? "circle.fill" : "circle"
    }

    static func swatch(_ band: ColorMixer.Band) -> NSColor {
        NSColor(hue: band.centerHue / 360, saturation: 0.8, brightness: 0.95, alpha: 1)
    }

    static func title(_ band: ColorMixer.Band) -> String {
        switch band {
        case .red: String(localized: "Reds", comment: "Color mixer band")
        case .orange: String(localized: "Oranges", comment: "Color mixer band")
        case .yellow: String(localized: "Yellows", comment: "Color mixer band")
        case .green: String(localized: "Greens", comment: "Color mixer band")
        case .aqua: String(localized: "Aquas", comment: "Color mixer band")
        case .blue: String(localized: "Blues", comment: "Color mixer band")
        case .purple: String(localized: "Purples", comment: "Color mixer band")
        case .magenta: String(localized: "Magentas", comment: "Color mixer band")
        }
    }
}

/// Sharpening and noise reduction.
private struct DetailControls: View {
    let editor: AdjustmentEditor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GroupLabel(.sharpening, editor: editor)
            VStack(alignment: .leading, spacing: 8) {
                adjustSlider(editor, String(localized: "Amount"), \.sharpen.amount, range: Sharpen.amountRange,
                             format: .plain)
                adjustSlider(editor, String(localized: "Radius"), \.sharpen.radius, range: Sharpen.radiusRange,
                             defaultValue: 1, format: .decimal)
                adjustSlider(editor, String(localized: "Detail"), \.sharpen.detail, range: 0...100, defaultValue: 25,
                             format: .plain)
                adjustSlider(editor, String(localized: "Masking"), \.sharpen.masking, range: 0...100, format: .plain)
            }
            .dimmedWhenOff(.sharpening, editor: editor)
            Text("Sharpening is easiest to judge at 1:1 (Z), once the change is saved.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            GroupLabel(.noiseReduction, editor: editor)
            let defaults = editor.rawDefaults
            VStack(alignment: .leading, spacing: 8) {
                noiseSlider(String(localized: "Luminance"), \.noiseReduction.luminance,
                            defaultValue: editor.isRaw ? defaults?.luminanceNoiseReduction ?? 0 : 0)
                if editor.isRaw, let color = defaults?.colorNoiseReduction {
                    noiseSlider(String(localized: "Color"), \.noiseReduction.color, defaultValue: color)
                }
            }
            .dimmedWhenOff(.noiseReduction, editor: editor)
        }
    }

    /// Noise reduction left at nil follows the decoder's default for the camera.
    private func noiseSlider(_ title: String, _ keyPath: WritableKeyPath<Adjustments, Double?>,
                             defaultValue: Double) -> AdjustSlider {
        AdjustSlider(title: title, value: editor.adjustments[keyPath: keyPath] ?? defaultValue, range: 0...100,
                     defaultValue: defaultValue, format: .plain) { value, phase in
            editor.change(title, phase: phase) {
                $0[keyPath: keyPath] = abs(value - defaultValue) < 0.5 ? nil : value
            }
        }
    }
}

/// The point curve, on the composite or one channel.
private struct ToneCurveControls: View {
    let editor: AdjustmentEditor
    @State private var channel = ToneCurve.Channel.rgb

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AppKitSegmented(labels: ToneCurve.Channel.allCases.map(Self.title),
                            selection: ToneCurve.Channel.allCases.firstIndex(of: channel) ?? 0) { index in
                channel = ToneCurve.Channel.allCases[index]
            }
            CurveEditor(points: editor.adjustments.toneCurve[channel], channel: channel,
                        histogram: editor.histogram) { points, phase in
                editor.change(String(localized: "Tone Curve"), phase: phase) { $0.toneCurve[channel] = points }
            }
            HStack {
                Text("Click to add a point, drag to move it, double-click to remove it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                AppKitButton(title: String(localized: "Reset Channel"), style: .push,
                             isEnabled: editor.adjustments.toneCurve[channel] != ToneCurve.identityPoints) {
                    editor.change(String(localized: "Tone Curve"), phase: .committed) {
                        $0.toneCurve[channel] = ToneCurve.identityPoints
                    }
                }
            }
        }
    }

    static func title(_ channel: ToneCurve.Channel) -> String {
        switch channel {
        case .rgb: String(localized: "RGB", comment: "Tone curve channel")
        case .red: String(localized: "Red", comment: "Tone curve channel")
        case .green: String(localized: "Green", comment: "Tone curve channel")
        case .blue: String(localized: "Blue", comment: "Tone curve channel")
        }
    }
}

/// A caption on the left, a pop-up filling the rest.
struct LabeledPopUp<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            content
        }
    }
}
