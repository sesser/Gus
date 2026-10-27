import AppKit
import PhotoCore
import SwiftUI
import UniformTypeIdentifiers

/// Folders dragged in from Finder: each is imported in place as its own
/// project, as Import Folder… does (see `DroppedFolders` and
/// `LibraryModel.importFolders`). Photos dragged out of the grid carry their
/// own type, so these drop targets do not react to them.
@MainActor
enum FolderDrop {
    static let types: [UTType] = [.fileURL]

    /// The drop action for `onDrop(of: FolderDrop.types, …)`.
    static func accept(_ providers: [NSItemProvider], model: LibraryModel) -> Bool {
        let providers = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !providers.isEmpty else { return false }
        Task { model.importFolders(await urls(from: providers)) }
        return true
    }

    /// The dropped file URLs, in drop order.
    static func urls(from providers: [NSItemProvider]) async -> [URL] {
        var urls: [URL] = []
        for provider in providers {
            let url: URL? = await withCheckedContinuation { continuation in
                _ = provider.loadObject(ofClass: URL.self) { url, _ in continuation.resume(returning: url) }
            }
            if let url { urls.append(url) }
        }
        return urls
    }
}

/// Laid over the browser while folders are dragged over it.
struct FolderDropHighlight: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.accentColor.opacity(0.12))
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.accentColor, lineWidth: 3)
            Label("Drop folders to import each one as a project", systemImage: "folder.badge.plus")
                .font(.title3)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
        }
        .padding(6)
        .allowsHitTesting(false)
    }
}
