import Foundation

/// A sidecar file as seen on disk.
public struct SidecarFileState: Hashable, Sendable {
    public var name: String
    public var size: Int64
    public var modifiedAt: Date
    public var digest: String
}

/// A sidecar read from disk.
public struct SidecarRead: Hashable, Sendable {
    public var values: SidecarValues
    public var file: SidecarFileState
}

/// Finds, reads and writes sidecars next to masters.
///
/// The app writes `IMG_0412.xmp` (the Adobe, Capture One and Photo Mechanic
/// convention; a RAW+JPEG pair shares it) and also reads `IMG_0412.CR3.xmp`
/// (darktable, digiKam). When two unpaired masters in a folder share a stem,
/// each gets the `name.ext.xmp` form so they do not overwrite each other.
public enum SidecarFiles {
    /// Names to look for next to a master, preferred first.
    public static func candidateNames(forMaster fileName: String, preferred: String) -> [String] {
        let stem = (fileName as NSString).deletingPathExtension
        var names = [preferred, stem + ".xmp", stem + ".XMP", fileName + ".xmp", fileName + ".XMP"]
        var seen: Set<String> = []
        names = names.filter { seen.insert($0).inserted }
        return names
    }

    /// The name the app writes: `stem.xmp`, or `name.ext.xmp` when `stemIsShared`.
    public static func preferredName(forMaster fileName: String, stemIsShared: Bool) -> String {
        stemIsShared ? fileName + ".xmp" : (fileName as NSString).deletingPathExtension + ".xmp"
    }

    /// Size and date of the first candidate that exists, without reading it.
    public static func locate(in folder: URL, names: [String]) -> (url: URL, size: Int64, modifiedAt: Date)? {
        for name in names {
            let url = folder.appending(path: name, directoryHint: .notDirectory)
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]),
                  values.isRegularFile == true
            else { continue }
            return (url, Int64(values.fileSize ?? 0), values.contentModificationDate ?? .distantPast)
        }
        return nil
    }

    public static func read(_ url: URL) throws -> SidecarRead {
        let data = try Data(contentsOf: url)
        let values = try XMPDocument(data: data).values()
        let attributes = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return SidecarRead(values: values, file: SidecarFileState(
            name: url.lastPathComponent, size: Int64(data.count),
            modifiedAt: attributes.contentModificationDate ?? Date(), digest: Digest.sha256Hex(data)))
    }

    /// Writes `values` into the sidecar at `url`, editing the existing file when
    /// there is one. The new file replaces the old one atomically.
    public static func write(_ values: SidecarValues, previous: SidecarValues?, to url: URL) throws -> SidecarFileState {
        let document: XMPDocument
        if let existing = try? Data(contentsOf: url), let parsed = try? XMPDocument(data: existing) {
            document = parsed
        } else {
            document = XMPDocument.empty()
        }
        document.apply(values, previous: previous)
        let data = document.data()
        try data.write(to: url, options: .atomic)
        let attributes = try url.resourceValues(forKeys: [.contentModificationDateKey])
        return SidecarFileState(name: url.lastPathComponent, size: Int64(data.count),
                                modifiedAt: attributes.contentModificationDate ?? Date(), digest: Digest.sha256Hex(data))
    }
}
