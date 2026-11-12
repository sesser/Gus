import PhotoCore
import PhotoUI
import SwiftUI

/// The comparison's caption row (side-by-side-comparison design §9): the
/// loupe's one line at the bottom edge, split at the panes' seam. A caption
/// per pane, aligned to its pane, and the link toggle centered on the seam.
struct ComparisonCaption: View {
    let model: LibraryModel

    var body: some View {
        // The toggle between two captions of equal width: on the seam, and
        // never under a caption's text.
        HStack(spacing: ComparisonCaptionMetrics.spacing) {
            ComparisonPaneCaption(model: model, side: .left)
                .frame(maxWidth: .infinity)
            ComparisonLinkToggle(model: model)
                .fixedSize()
                .layoutPriority(1)
            ComparisonPaneCaption(model: model, side: .right)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, ComparisonCaptionMetrics.edgeInset)
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .frame(height: LoupeCaption.height)
    }
}

/// The caption's measurements.
enum ComparisonCaptionMetrics {
    /// The row's outer padding, as the single loupe's caption.
    static let edgeInset: CGFloat = 12
    /// Between a caption's parts, and between the captions and the link toggle.
    static let spacing: CGFloat = 8
    /// A middle-truncated name keeps about six characters round its ellipsis.
    static let minimumNameWidth: CGFloat = 56
}

/// One pane's caption: the photo's name (a copy's own, as in the window
/// title) and position, the culling marks in the middle, the badges at the
/// trailing end. Short of room, it drops the position, then middle-truncates
/// the name, then drops the HDR badge; the marks, with the label's name, and
/// the Copy and Offline badges never go (side-by-side-comparison design §9,
/// §16 D15).
private struct ComparisonPaneCaption: View {
    let model: LibraryModel
    let side: ComparisonSide

    var body: some View {
        if let item = model.comparisonItem(side), let index = model.indexOfVersion(item.versionID) {
            ViewThatFits(in: .horizontal) {
                row(item, index, showsPosition: true, truncatesName: false, showsHDR: true)
                row(item, index, showsPosition: false, truncatesName: false, showsHDR: true)
                row(item, index, showsPosition: false, truncatesName: true, showsHDR: true)
                row(item, index, showsPosition: false, truncatesName: true, showsHDR: false)
            }
        }
    }

    private var isActive: Bool { model.comparison?.active == side }

    private func row(_ item: CatalogItem, _ index: Int, showsPosition: Bool, truncatesName: Bool, showsHDR: Bool) -> some View {
        HStack(spacing: ComparisonCaptionMetrics.spacing) {
            HStack(spacing: 0) {
                name(item, truncates: truncatesName)
                if showsPosition {
                    Text(verbatim: " · " + PhotoAccessibility.position(index, of: model.items.count))
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            CullingMarks(item: item)
                .fixedSize()
            badges(item, showsHDR: showsHDR)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    /// The photo's name in full: in the single loupe it is the window
    /// title, which can't show two. The active pane's is primary and semibold, so the
    /// active side never rests on the ring's color alone.
    @ViewBuilder
    private func name(_ item: CatalogItem, truncates: Bool) -> some View {
        let text = Text(verbatim: PhotoName.inFull(item))
            .fontWeight(isActive ? .semibold : .regular)
            .foregroundStyle(isActive ? .primary : .secondary)
            .lineLimit(1)
        if truncates {
            text.truncationMode(.middle)
                .frame(minWidth: ComparisonCaptionMetrics.minimumNameWidth, idealWidth: ComparisonCaptionMetrics.minimumNameWidth,
                       maxWidth: .infinity, alignment: .leading)
        } else {
            text.fixedSize()
        }
    }

    @ViewBuilder
    private func badges(_ item: CatalogItem, showsHDR: Bool) -> some View {
        HStack(spacing: 6) {
            // About the source, so once: in the right caption only.
            if side == .right, model.isFiltered {
                CaptionBadge(title: String(localized: "Filtered"),
                             help: String(localized: "A filter hides some of this source's photos"))
            }
            if showsHDR, let headroom = model.comparisonHDRHeadroom[side] {
                CaptionBadge(title: String(localized: "HDR"),
                             help: String(localized: "Highlights up to \(headroom.formatted(.number.precision(.fractionLength(1))))× SDR white are shown with the display's extended range"))
            }
            // Identity badges nearest the toggle, as in the single loupe; a
            // copy's never goes: a truncated name loses "copy" first.
            if item.isCopy {
                CaptionBadge(title: DuplicateText.badge, help: DuplicateText.badgeHelp(item.fileName))
            }
            if model.isOffline(item) {
                CaptionBadge(title: String(localized: "Offline"),
                             help: String(localized: "The volume \(model.volumeName(for: item) ?? "") is not connected. Showing the cached preview."))
            }
            // The strip's toggle, at the right caption's trailing end; review hides both.
            if side == .right, !model.isReviewing {
                FilmStripToggle(model: model)
                    .padding(.leading, 2)
            }
        }
        .fixedSize()
    }
}

/// The link toggle on the seam (design §5, §9): bordered, so its bezel
/// shows the on state, since nothing else on screen shows the link.
struct ComparisonLinkToggle: View {
    let model: LibraryModel

    var body: some View {
        Toggle(isOn: Binding(get: { model.linksComparison }, set: { model.setComparisonLinked($0) })) {
            Label(ComparisonText.link, systemImage: ComparisonRules.linkSymbolName)
                .labelStyle(.iconOnly)
                .frame(minWidth: FilmStripMetrics.minimumHitSize, minHeight: FilmStripMetrics.minimumHitSize)
                .contentShape(Rectangle())
        }
        .toggleStyle(.button)
        .controlSize(.small)
        .help(ComparisonText.linkHelp(linked: model.linksComparison))
        .accessibilityLabel(ComparisonText.link)
    }
}
