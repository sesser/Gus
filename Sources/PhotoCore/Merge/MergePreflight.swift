import Foundation

/// What a merge asks the file system before it starts (design §6.2): that
/// every master can be read and that the reference's folder can be written
/// to. Asked off the main actor (a network volume can be slow), when the
/// sheet opens and again when Merge is pressed. Nothing is created to find
/// out: a refused merge leaves nothing behind (R14).
public struct MergePreflight: Sendable {
    public var isReadable: @Sendable (URL) -> Bool
    public var isWritableFolder: @Sendable (URL) -> Bool

    public init(isReadable: @escaping @Sendable (URL) -> Bool, isWritableFolder: @escaping @Sendable (URL) -> Bool) {
        self.isReadable = isReadable
        self.isWritableFolder = isWritableFolder
    }

    /// The real file system.
    public static let disk = MergePreflight(
        isReadable: { url in FileManager.default.isReadableFile(atPath: url.path) },
        isWritableFolder: { folder in
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue,
                  FileManager.default.isWritableFile(atPath: folder.path) else { return false }
            let readOnly = (try? folder.resourceValues(forKeys: [.volumeIsReadOnlyKey]))?.volumeIsReadOnly ?? false
            return !readOnly
        })

    /// The first refusal from the disk (case 8, then case 9) and the frame it
    /// flags, or nil when the merge may go ahead.
    public func check(_ selection: MergeSelection) -> (refusal: MergeRefusal, flagged: Int64)? {
        for frame in selection.frames where !isReadable(frame.url) {
            return (.unreadable(name: frame.displayName), frame.versionID)
        }
        let reference = selection.referenceFrame
        if !isWritableFolder(reference.folder) {
            return (.unwritableFolder(reference: reference.displayName, folder: reference.folder.lastPathComponent),
                    reference.versionID)
        }
        return nil
    }
}
