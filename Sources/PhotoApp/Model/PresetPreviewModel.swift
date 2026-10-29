import Observation
import PhotoCore
import PhotoUI

/// Small renders of the focused photo with each preset, for the Adjust tab's
/// Presets heading. A render session of its own decodes the master at this
/// size, so the loupe's frames never wait for them.
@MainActor
@Observable
final class PresetPreviewModel {
    @ObservationIgnored weak var library: LibraryModel?
    /// Previews by `previewID(_:)`, for `key`.
    private(set) var previews: [String: DecodedImage] = [:]
    @ObservationIgnored private var key: String?
    @ObservationIgnored private var session: LiveRenderSession?
    @ObservationIgnored private var sessionVersionID: Int64?
    /// Counts pictures the pointer entered, so leaving one ends the preview
    /// only when it did not move straight to another.
    @ObservationIgnored private var hoverCount = 0

    static let longEdge = 320

    static func previewID(_ preset: AdjustmentPreset) -> String {
        let groups = preset.groups.map(\.rawValue).sorted().joined(separator: ",")
        return "\(preset.uuid)-\(groups)-\(preset.adjustments.editStack.renderHash)"
    }

    /// Identifies the photo and the adjustments the previews start from: the
    /// editor's while the loupe edits the photo, otherwise the saved ones.
    func key(for item: CatalogItem) -> String {
        guard let library else { return "" }
        let editor = library.editor
        if editor.state == .ready, editor.item?.versionID == item.versionID {
            return "\(item.versionID)-\(editor.adjustments.editStack.renderHash)"
        }
        return "\(item.versionID)-\(item.editStackHash)"
    }

    /// Renders the previews of `presets` on `item`, unless they were rendered
    /// for its current adjustments already.
    func render(_ presets: [AdjustmentPreset], on item: CatalogItem) async {
        guard let library, !item.isVideo, let url = library.sourceURL(for: item) else { return }
        let key = key(for: item)
        if key != self.key {
            self.key = key
            previews = [:]
        }
        if sessionVersionID != item.versionID {
            sessionVersionID = item.versionID
            session = LiveRenderSession(source: url, generator: library.previews.interactiveGenerator,
                                        longEdge: Self.longEdge, colorSpace: library.previews.displayColorSpace)
        }
        guard let session, let base = await baseAdjustments(of: item), self.key == key else { return }
        for preset in presets where previews[Self.previewID(preset)] == nil {
            guard !Task.isCancelled, self.key == key else { return }
            guard let frame = try? await session.render(preset.applied(onto: base)) else { continue }
            guard !Task.isCancelled, self.key == key else { return }
            previews[Self.previewID(preset)] = frame.image
        }
    }

    private func baseAdjustments(of item: CatalogItem) async -> Adjustments? {
        guard let library else { return nil }
        let editor = library.editor
        if editor.state == .ready, editor.item?.versionID == item.versionID { return editor.adjustments }
        let stack = (try? await library.catalog.version(id: item.versionID)?.decodedEditStack()) ?? .identity
        return Adjustments(stack: stack)
    }

    /// Shows the preset in the loupe while the pointer is on its picture.
    func hover(_ preset: AdjustmentPreset, isInside: Bool) {
        guard let library, library.mode == .loupe else { return }
        let editor = library.editor
        hoverCount += 1
        if isInside {
            library.previewAdjustmentPreset(preset)
        } else {
            let count = hoverCount
            Task {
                try? await Task.sleep(for: .milliseconds(120))
                if hoverCount == count { editor.endPreview() }
            }
        }
    }
}
