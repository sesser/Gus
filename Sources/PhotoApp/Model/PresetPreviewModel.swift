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
    /// Previews by `previewID(_:)`, of the photo being shown. Those not in
    /// `rendered` still show an earlier edit until their new render replaces
    /// them, so the pictures never blank out and change size.
    private(set) var previews: [String: DecodedImage] = [:]
    @ObservationIgnored private var key: String?
    /// Previews rendered for `key`.
    @ObservationIgnored private var rendered: Set<String> = []
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

    /// Identifies the photo and the saved adjustments the previews start from.
    /// Values being dragged do not count: the previews follow once the change
    /// is saved.
    func key(for item: CatalogItem) -> String {
        "\(item.versionID)-\(item.editStackHash)"
    }

    /// Renders the previews of `presets` on `item`, unless they were rendered
    /// for its current adjustments already.
    func render(_ presets: [AdjustmentPreset], on item: CatalogItem) async {
        guard let library, !item.isVideo, let url = library.sourceURL(for: item) else { return }
        let key = key(for: item)
        if key != self.key {
            self.key = key
            rendered = []
        }
        if sessionVersionID != item.versionID {
            sessionVersionID = item.versionID
            previews = [:]
            session = LiveRenderSession(source: url, generator: library.previews.interactiveGenerator,
                                        longEdge: Self.longEdge, colorSpace: library.previews.displayColorSpace)
        }
        guard let session, let base = await baseAdjustments(of: item), self.key == key else { return }
        for preset in presets where !rendered.contains(Self.previewID(preset)) {
            guard !Task.isCancelled, self.key == key else { return }
            guard let frame = try? await session.render(preset.applied(onto: base)) else { continue }
            guard !Task.isCancelled, self.key == key else { return }
            let id = Self.previewID(preset)
            previews[id] = frame.image
            rendered.insert(id)
        }
    }

    private func baseAdjustments(of item: CatalogItem) async -> Adjustments? {
        guard let library else { return nil }
        let editor = library.editor
        if editor.state == .ready, editor.item?.versionID == item.versionID { return editor.savedAdjustments }
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
