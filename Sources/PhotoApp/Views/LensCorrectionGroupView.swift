import PhotoCore
import SwiftUI

/// The Distortion or Lens Vignetting group at the top of the Lens heading
/// (docs/features/lens-corrections/design.md §3): its label with a check box
/// that is always shown, the Source control (Auto | Manual), one caption, the
/// Amount in Manual, and Constrain to image under Distortion.
struct LensCorrectionGroupView: View {
    let editor: AdjustmentEditor
    let group: LensCorrectionStatus.Group

    var body: some View {
        let status = editor.lensStatus(group)
        let title = LensCorrectionText.title(group)
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 0) {
                ControlGroupLabel(text: title)
                Spacer(minLength: 4)
                // Always shown: "on with Auto" is itself an edit (design §3.1).
                AppKitCheckbox(state: status.isChecked ? .on : .off, label: title,
                               help: status.isChecked ? String(localized: "Turn off \(title) to compare")
                                                      : String(localized: "Turn on \(title)")) {
                    editor.toggleLensGroup(group)
                }
                .frame(width: InspectorMetrics.checkSlot)
                Color.clear
                    .frame(width: InspectorMetrics.resetSlot, height: 1)
            }
            .frame(height: InspectorMetrics.groupLabelHeight)
            .padding(.top, InspectorMetrics.groupLabelTop)
            sourceRow(status)
            caption(status)
            if status.showsAmount {
                AdjustSlider(title: LensCorrectionText.amountTitle, value: amount, range: -100...100, defaultValue: 0,
                             format: .signed, help: LensCorrectionText.amountHelp(group),
                             accessibilityLabel: LensCorrectionText.amountLabel(group),
                             fieldAccessibilityLabel: LensCorrectionText.amountValueLabel(group)) { value, phase in
                    editor.setLensAmount(group, value, phase: phase)
                }
            }
            if group == .distortion {
                let constrain = editor.adjustments.distortion.constrain
                AppKitCheckbox(state: constrain ? .on : .off, label: LensCorrectionText.constrainTitle,
                               help: LensCorrectionText.constrainHelp, title: LensCorrectionText.constrainTitle) {
                    editor.setConstrainToImage(!constrain)
                }
                .frame(minHeight: SliderRow.height)
            }
        }
        // Unchecked: the rows read as off and stay usable (design §3.3).
        .environment(\.adjustGroupIsOn, status.isChecked)
    }

    private var amount: Double {
        group == .distortion ? editor.adjustments.distortion.amount : editor.adjustments.lensVignetting.amount
    }

    private func sourceRow(_ status: LensCorrectionStatus) -> some View {
        let autoHelp = status.autoUnavailable.map(LensCorrectionText.autoUnavailableHelp) ?? LensCorrectionText.autoHelp
        return HStack(spacing: InspectorMetrics.gap) {
            Text(LensCorrectionText.sourceTitle)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: InspectorMetrics.labelWidth, alignment: .leading)
            AppKitSegmented(labels: [LensCorrectionText.auto, LensCorrectionText.manual],
                            selection: status.selectedSegment ?? -1,
                            toolTips: [autoHelp, LensCorrectionText.manualHelp],
                            accessibilityLabel: LensCorrectionText.sourceLabel(group), fillsWidth: true,
                            enabledSegments: [status.autoUnavailable == nil, true]) { index in
                guard index >= 0 else { return }
                editor.setLensSource(group, index == 0 ? .auto : .manual)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(minHeight: SliderRow.height)
    }

    /// One caption, one role at a time (design §4); rows 3 and 5 carry a warning symbol.
    private func caption(_ status: LensCorrectionStatus) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            if status.caption.isWarning {
                Image(systemName: "exclamationmark.triangle")
                    .accessibilityHidden(true)
            }
            Text(LensCorrectionText.caption(status.caption, group: group))
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.top, 4)
        .padding(.bottom, 2)
    }
}
