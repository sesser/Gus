import AppKit
import PhotoCore
import SwiftUI

/// The Adjust tab's Black & White heading (docs/features/bw-module/design.md
/// §2, §3): the standard heading, but its check box is always shown, since
/// the conversion with every filter at 0 is itself an edit (§3.1); then the
/// quick-set control, the five filter sliders and one caption. Folded by
/// default.
struct BlackAndWhiteSection: View {
    let editor: AdjustmentEditor
    @InspectorExpanded(Self.key, family: .adjust, default: false) private var isExpanded

    /// `adjust.section.blackAndWhite`, as `AdjustSection` names every heading's.
    static let key = "adjust.section.\(Adjustments.Section.blackAndWhite.rawValue)"

    var body: some View {
        let values = editor.adjustments
        let applies = values.blackAndWhiteApplies
        let isModified = values.isModified(Adjustments.Section.blackAndWhite)
        let title = BlackAndWhiteText.title
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: title, isExpanded: $isExpanded, family: .adjust,
                          // Always offered here (design §3.1).
                          turnOff: (applies ? String(localized: "Turn Off") : String(localized: "Turn On"),
                                    { editor.toggleBlackAndWhite() }),
                          reset: isModified ? { editor.reset(.blackAndWhite) } : nil) {
                AppKitCheckbox(state: applies ? .on : .off, label: title,
                               help: applies ? String(localized: "Turn off \(title) to compare")
                                             : String(localized: "Turn on \(title)")) {
                    editor.toggleBlackAndWhite()
                }
            } trailing: {
                AppKitButton(symbol: "arrow.counterclockwise", style: .borderless, tint: .secondaryLabelColor,
                             help: String(localized: "Reset \(title)"), isEnabled: isModified) {
                    editor.reset(.blackAndWhite)
                }
            }
            if isExpanded {
                BlackAndWhiteControls(editor: editor)
                    // Not applied (never on, or unchecked): the rows read as off, and stay usable (§3.3).
                    .environment(\.adjustGroupIsOn, applies)
                    .padding(.bottom, 4)
            }
        }
    }
}

private struct BlackAndWhiteControls: View {
    let editor: AdjustmentEditor

    var body: some View {
        let filters = BlackAndWhite.Filter.allCases
        let selected = editor.blackAndWhiteQuickSet.flatMap { filters.firstIndex(of: $0) } ?? -1
        VStack(alignment: .leading, spacing: 8) {
            AppKitSegmented(labels: filters.map(BlackAndWhiteText.name), selection: selected,
                            toolTips: filters.map(BlackAndWhiteText.help),
                            accessibilityLabel: BlackAndWhiteText.quickSetName) { index in
                guard filters.indices.contains(index) else { return }
                editor.chooseBlackAndWhite(filters[index])
            }
            .frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(filters, id: \.self) { filter in
                    AdjustSlider(title: BlackAndWhiteText.name(filter), value: editor.adjustments.blackAndWhite[filter],
                                 range: BlackAndWhite.amountRange, defaultValue: 0, format: .plain,
                                 help: BlackAndWhiteText.help(filter),
                                 accessibilityLabel: BlackAndWhiteText.accessibilityName(filter),
                                 fieldAccessibilityLabel: BlackAndWhiteText.fieldAccessibilityName(filter),
                                 trackTint: Self.tint(filter)) { value, phase in
                        editor.setBlackAndWhite(filter, value, phase: phase)
                    }
                }
            }
            Text(editor.sourceIsMonochrome ? BlackAndWhiteText.monochromeCaption : BlackAndWhiteText.caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
                .padding(.bottom, 2)
        }
    }

    /// The filter's system color, as the track's fill (design §5).
    static func tint(_ filter: BlackAndWhite.Filter) -> NSColor {
        switch filter {
        case .yellow: .systemYellow
        case .orange: .systemOrange
        case .red: .systemRed
        case .green: .systemGreen
        case .blue: .systemBlue
        }
    }
}
