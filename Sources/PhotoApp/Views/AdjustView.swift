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
        content
    }

    @ViewBuilder
    private var content: some View {
        if model.mode != .loupe {
            // Sliders stay in the loupe; presets apply to the selection.
            AppKitScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ContentUnavailableView {
                        Label("Open a Photo to Adjust It", systemImage: "slider.horizontal.3")
                    } actions: {
                        AppKitButton(title: String(localized: "Open in Loupe"), style: .push,
                                     help: String(localized: "Show the focused photo in the loupe"),
                                     isEnabled: model.focusedItem != nil) {
                            model.openLoupe()
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    InspectorSeparator()
                    PresetsSection(model: model)
                }
                .padding(InspectorMetrics.padding)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else if model.isComparing {
            // Nothing is edited while comparing (side-by-side-comparison
            // design §11); the tab stays selectable.
            ContentUnavailableView {
                Label("Not Available While Comparing", systemImage: ComparisonRules.toolbarSymbolName)
            } description: {
                Text("Stop comparing to adjust the active photo.", comment: "Adjust tab while two photos are compared")
            } actions: {
                AppKitButton(title: ComparisonText.stop, style: .push) {
                    model.stopComparing()
                }
            }
        } else {
            switch model.loupeAdjustState {
            case .idle:
                // Only while the loupe opens, before the spinner: an empty pane
                // (design.md N1, D-Q3).
                Color.clear
            case .loading:
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            // design.md N1; the symbols are the ones the grid, the film strip
            // and the app's other "Can't …" states use.
            case .video:
                ContentUnavailableView("No Adjustments for Videos", systemImage: "video")
            case .offline:
                ContentUnavailableView("Original Offline", systemImage: "externaldrive.badge.xmark",
                                       description: Text("Connect its volume to adjust this photo.",
                                                         comment: "Adjust tab: the photo's original is offline"))
            case .unreadable(let failure):
                ContentUnavailableView("Can't Edit This Photo", systemImage: "exclamationmark.triangle",
                                       description: Text(AdjustText.unreadableMessage(failure)))
            case .ready:
                // The workflow's order (render order is unchanged).
                AppKitScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        PresetsSection(model: model)
                        InspectorSeparator()
                        CropSection(editor: editor)
                        InspectorSeparator()
                        AdjustSection(.develop, editor: editor) {
                            DevelopControls(editor: editor)
                        }
                        InspectorSeparator()
                        AdjustSection(.tone, editor: editor) {
                            ToneCurveControls(editor: editor)
                                .showsTurnedOff(.toneCurve, editor: editor)
                        }
                        InspectorSeparator()
                        AdjustSection(.colorMixer, editor: editor) {
                            ColorMixerControls(editor: editor)
                                .showsTurnedOff(.colorMixer, editor: editor)
                        }
                        InspectorSeparator()
                        AdjustSection(.colorGrading, editor: editor) {
                            ColorGradeControls(editor: editor)
                                .showsTurnedOff(.colorGrade, editor: editor)
                        }
                        InspectorSeparator()
                        AdjustSection(.details, editor: editor) {
                            DetailControls(model: model)
                        }
                        InspectorSeparator()
                        AdjustSection(.lens, editor: editor) {
                            LensControls(model: model)
                        }
                        InspectorSeparator()
                        MasksSection(editor: editor)
                        InspectorSeparator()
                        AdjustSection(.effects, editor: editor) {
                            EffectsControls(model: model)
                        }
                    }
                    .padding(InspectorMetrics.padding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

/// The original toggle and reset for everything.
/// The pinned row of the loupe's Adjust tab: Original (`\\`) on the left,
/// the ⋯ menu on the right.
struct AdjustHeader: View {
    let model: LibraryModel

    private var editor: AdjustmentEditor { model.editor }

    var body: some View {
        HStack(spacing: 8) {
            // A toggle: its bezel shows when the original is on screen.
            AppKitButton(title: String(localized: "Original"), symbol: "square.split.2x1",
                         style: .toggle(isOn: editor.showsOriginal),
                         help: String(localized: "Compare with the original (\\)"),
                         isEnabled: editor.cropSession == nil) {
                editor.toggleOriginal()
            }
            Spacer()
            AppKitMenuButton(title: "", symbol: "ellipsis.circle", entries: [
                .item(String(localized: "Copy Adjustments"), isEnabled: model.focusedItem != nil) { model.copyAdjustments() },
                .item(String(localized: "Paste Adjustments"), isEnabled: model.copiedAdjustments != nil) {
                    model.pasteAdjustments()
                },
                .separator,
                .item(String(localized: "Save Adjustments as Preset…"), isEnabled: model.canSaveAdjustmentPreset) {
                    model.promptForAdjustmentPreset()
                },
                .separator,
                .item(String(localized: "Reset All Adjustments"), isEnabled: !editor.adjustments.isDefault) {
                    model.resetAllAdjustments()
                },
            ], help: String(localized: "More adjustment commands"))
        }
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
        VStack(alignment: .leading, spacing: 2) {
            if editor.isRaw {
                GroupLabel(.profile, editor: editor)
                profile
                    .showsTurnedOff(.profile, editor: editor)
            } else if editor.usesFallbackDecoder {
                fallbackDecoderNote
            }
            GroupLabel(.whiteBalance, editor: editor)
            VStack(alignment: .leading, spacing: 2) {
                whiteBalance
            }
            .showsTurnedOff(.whiteBalance, editor: editor)
            GroupLabel(.light, editor: editor) {
                AppKitButton(title: String(localized: "Auto"), style: .push,
                             help: String(localized: "Set the exposure from the photo's brightness"),
                             isEnabled: !editor.isMeasuring) {
                    editor.autoExposure()
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                adjustSlider(editor, String(localized: "Exposure"), \.exposure.ev, range: Exposure.range, format: .stops)
                adjustSlider(editor, String(localized: "Contrast"), \.tone.contrast)
                adjustSlider(editor, String(localized: "Highlights"), \.tone.highlights)
                adjustSlider(editor, String(localized: "Shadows"), \.tone.shadows)
                adjustSlider(editor, String(localized: "Whites"), \.tone.whites)
                adjustSlider(editor, String(localized: "Blacks"), \.tone.blacks)
            }
            .showsTurnedOff(.light, editor: editor)
            GroupLabel(.presence, editor: editor)
            VStack(alignment: .leading, spacing: 2) {
                adjustSlider(editor, String(localized: "Clarity"), \.presence.clarity)
                adjustSlider(editor, String(localized: "Dehaze"), \.presence.dehaze)
                adjustSlider(editor, String(localized: "Vibrance"), \.presence.vibrance)
                adjustSlider(editor, String(localized: "Saturation"), \.presence.saturation)
            }
            .showsTurnedOff(.presence, editor: editor)
        }
    }

    /// In the Profile group's place for a raw the system's RAW decoder gives no
    /// image for: nothing there could apply to LibRaw's decode, and the note
    /// says so instead of the group going missing (issue #161).
    private var fallbackDecoderNote: some View {
        VStack(alignment: .leading, spacing: 2) {
            ControlGroupLabel(text: AdjustText.title(.profile))
                .frame(height: InspectorMetrics.groupLabelHeight)
                .padding(.top, InspectorMetrics.groupLabelTop)
            Text(FallbackDecoderText.note)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 2)
        }
        .accessibilityElement(children: .combine)
    }

    private var profile: some View {
        VStack(alignment: .leading, spacing: 2) {
            LabeledPopUp(title: String(localized: "Profile")) {
                AppKitPopUp(items: RawDecode.Look.allCases.map { .init(title: Self.lookTitle($0), tag: $0.rawValue) },
                            selection: editor.adjustments.decode.look.rawValue) { tag in
                    editor.change(String(localized: "Profile"), phase: .committed) {
                        $0.decode.look = RawDecode.Look(rawValue: tag) ?? .standard
                    }
                }
            }
            if let defaults = editor.rawDefaults, defaults.offeredDecoderVersions.count > 1 {
                LabeledPopUp(title: String(localized: "Decoder")) {
                    decoderPopUp(defaults)
                }
            }
        }
    }

    /// A second view of machine learning noise reduction's one state (ml-denoise
    /// design §4): the machine learning version is selected while it applies,
    /// otherwise the decoder that renders. It is listed only where it is available.
    private func decoderPopUp(_ defaults: RawDefaults) -> some View {
        let status = editor.machineLearning
        let versions = defaults.offeredDecoderVersions
        let learned = MachineLearningNoiseReduction.machineLearningVersion(in: versions)
        let selection = status?.isApplied == true ? learned : nil
        let isEnabled = status?.decoderChoiceIsEnabled ?? true
        return AppKitPopUp(items: versions.reversed().map { version in
            .init(title: version == defaults.defaultDecoderVersion
                      ? String(localized: "\(version) (default)", comment: "RAW decoder version")
                      : version == learned ? MachineLearningText.decoderItem(version) : version,
                  tag: version)
        }, selection: selection ?? editor.adjustments.decode.decoderVersion ?? defaults.defaultDecoderVersion,
           isEnabled: isEnabled, help: isEnabled ? nil : MachineLearningText.decoderDimmedHelp) { tag in
            editor.chooseDecoder(tag)
        }
        // SwiftUI sets a hosted control's enabled state from its environment too.
        .disabled(!isEnabled)
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
        LabeledPopUp(title: String(localized: "Mode", comment: "White balance: As Shot, Auto, Daylight…")) {
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
    let model: LibraryModel

    private var editor: AdjustmentEditor { model.editor }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            GroupLabel(.sharpening, editor: editor)
            VStack(alignment: .leading, spacing: 2) {
                adjustSlider(editor, String(localized: "Amount"), \.sharpen.amount, range: Sharpen.amountRange,
                             format: .plain)
                adjustSlider(editor, String(localized: "Radius"), \.sharpen.radius, range: Sharpen.radiusRange,
                             defaultValue: 1, format: .decimal)
                adjustSlider(editor, String(localized: "Detail"), \.sharpen.detail, range: 0...100, defaultValue: 25,
                             format: .plain)
            }
            .showsTurnedOff(.sharpening, editor: editor)
            // Masking and the map that shows it (sharpen-mask-preview design §4): the
            // toggle is never dimmed by the group being off (R10).
            VStack(alignment: .leading, spacing: 0) {
                adjustSlider(editor, String(localized: "Masking"), \.sharpen.masking, range: 0...100, format: .plain)
                    .showsTurnedOff(.sharpening, editor: editor)
                AppKitButton(title: SharpeningMapText.name, style: .toggle(isOn: editor.showsSharpeningMap),
                             help: mapHelp, isEnabled: model.canShowSharpeningMap) {
                    model.toggleSharpeningMap(from: .button)
                }
                .disabled(!model.canShowSharpeningMap)
                .padding(.top, 6)
                // The legend while the map is on screen, the hint otherwise.
                Text(editor.shownSharpeningMap.map(SharpeningMapText.legend) ?? SharpeningMapText.hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
            .background(InspectorRevealAnchor(isRequested: model.revealsMaskingRow) {
                model.revealsMaskingRow = false
            })
            GroupLabel(.noiseReduction, editor: editor)
            let defaults = editor.rawDefaults
            if let status = editor.machineLearning, status.state != .notOffered {
                machineLearningRow(status)
            }
            VStack(alignment: .leading, spacing: 2) {
                noiseSlider(String(localized: "Luminance"), \.noiseReduction.luminance,
                            defaultValue: editor.luminanceNoiseReductionDefault)
                if editor.isRaw, let color = defaults?.colorNoiseReduction {
                    let colorIsAvailable = editor.machineLearning?.colorIsAvailable ?? true
                    noiseSlider(String(localized: "Color"), \.noiseReduction.color, defaultValue: color,
                                isEnabled: colorIsAvailable, help: colorIsAvailable ? nil : MachineLearningText.colorHelp)
                }
            }
            .showsTurnedOff(.noiseReduction, editor: editor)
        }
    }

    /// Use machine learning and its caption (ml-denoise design §3): dimmed
    /// only where it cannot be turned on; the caption says why, or what it does.
    private func machineLearningRow(_ status: MachineLearningNoiseReduction.Status) -> some View {
        let caption = MachineLearningText.caption(status.state)
        return VStack(alignment: .leading, spacing: 2) {
            AppKitCheckbox(state: status.asks ? .on : .off, label: MachineLearningText.checkBoxTitle,
                           help: MachineLearningText.checkBoxHelp(status.state), title: MachineLearningText.checkBoxTitle,
                           isEnabled: status.checkBoxIsEnabled) {
                editor.setMachineLearning(!status.asks)
            }
            .disabled(!status.checkBoxIsEnabled)
            .frame(minHeight: SliderRow.height)
            if let caption {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    if MachineLearningText.showsTriangle(status.state) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .accessibilityHidden(true)
                    }
                    Text(caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, InspectorMetrics.checkBoxTitleInset)
                .padding(.bottom, 2)
            }
        }
    }

    /// The toggle's tooltip, saying why it is dimmed when it is.
    private var mapHelp: String {
        if model.isReviewing {
            String(localized: "Exit Review (F) to show the sharpening map.",
                   comment: "Tooltip of the dimmed Sharpening Map toggle in review mode")
        } else if editor.cropSession != nil {
            String(localized: "Finish cropping to show the sharpening map.",
                   comment: "Tooltip of the dimmed Sharpening Map toggle during a crop session")
        } else {
            String(localized: "Show where Masking lets sharpening through, in place of the photo",
                   comment: "Tooltip and VoiceOver help of the Sharpening Map toggle")
        }
    }

    /// Noise reduction left at nil follows the decoder's default for the camera.
    private func noiseSlider(_ title: String, _ keyPath: WritableKeyPath<Adjustments, Double?>,
                             defaultValue: Double, isEnabled: Bool = true, help: String? = nil) -> AdjustSlider {
        AdjustSlider(title: title, value: editor.adjustments[keyPath: keyPath] ?? defaultValue, range: 0...100,
                     defaultValue: defaultValue, format: .plain, isEnabled: isEnabled, help: help) { value, phase in
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
