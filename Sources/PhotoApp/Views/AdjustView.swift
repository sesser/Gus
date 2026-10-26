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
        if model.mode != .loupe {
            message(String(localized: "Open a photo in the loupe to adjust it."))
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
                        AdjustToolbar(editor: editor)
                        AdjustSection(.develop, editor: editor) {
                            DevelopControls(editor: editor)
                        }
                        Divider()
                        AdjustSection(.tone, editor: editor) {
                            ToneCurveControls(editor: editor)
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

/// Original toggle and reset for everything.
private struct AdjustToolbar: View {
    let editor: AdjustmentEditor

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
                profile
            }
            whiteBalance
            HStack(alignment: .center) {
                ControlGroupLabel(text: String(localized: "Light"))
                Spacer()
                AppKitButton(title: String(localized: "Auto"), style: .push,
                             help: String(localized: "Set the exposure from the photo's brightness"),
                             isEnabled: !editor.isMeasuring) {
                    editor.autoExposure()
                }
            }
            adjustSlider(editor, String(localized: "Exposure"), \.exposure.ev, range: Exposure.range, format: .stops)
            adjustSlider(editor, String(localized: "Contrast"), \.tone.contrast)
            adjustSlider(editor, String(localized: "Highlights"), \.tone.highlights)
            adjustSlider(editor, String(localized: "Shadows"), \.tone.shadows)
            adjustSlider(editor, String(localized: "Whites"), \.tone.whites)
            adjustSlider(editor, String(localized: "Blacks"), \.tone.blacks)
            ControlGroupLabel(text: String(localized: "Presence"))
            adjustSlider(editor, String(localized: "Clarity"), \.presence.clarity)
            adjustSlider(editor, String(localized: "Dehaze"), \.presence.dehaze)
            adjustSlider(editor, String(localized: "Vibrance"), \.presence.vibrance)
            adjustSlider(editor, String(localized: "Saturation"), \.presence.saturation)
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
        ControlGroupLabel(text: String(localized: "White Balance"))
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
