import Foundation

/// Describes volumes and splits file paths into volume + relative path.
public enum VolumeResolver {
    static let keys: Set<URLResourceKey> = [
        .volumeUUIDStringKey, .volumeNameKey, .volumeIsLocalKey, .volumeIsRemovableKey,
        .volumeIsEjectableKey, .volumeIsInternalKey, .volumeURLForRemountingKey,
    ]

    /// Describes the volume mounted at `volumeURL`.
    ///
    /// Identity is the volume UUID when there is one. Network shares often have no
    /// UUID, so their remount URL (e.g. `smb://server/share`) is used instead, and as
    /// a last resort the name plus mount point.
    public static func descriptor(forVolumeAt volumeURL: URL) throws -> VolumeDescriptor {
        let values = try volumeURL.resourceValues(forKeys: keys)
        let mountPath = volumeURL.standardizedFileURL.path
        let name = values.volumeName ?? (mountPath as NSString).lastPathComponent
        let identity: String
        if let uuid = values.volumeUUIDString {
            identity = "uuid:\(uuid)"
        } else if let remote = values.volumeURLForRemounting {
            identity = "remote:\(remote.absoluteString)"
        } else {
            identity = "mount:\(name)@\(mountPath)"
        }
        let isNetwork = values.volumeIsLocal == false
        let isRemovable = values.volumeIsRemovable == true || values.volumeIsEjectable == true
            || values.volumeIsInternal == false
        return VolumeDescriptor(identity: identity, name: name, mountPath: mountPath,
                                isRemovable: isRemovable, isNetwork: isNetwork)
    }

    /// `fileURL`'s path relative to `mountPath`, without a leading slash, or nil if
    /// the file is not under it.
    public static func relativePath(of fileURL: URL, inVolumeAt mountPath: String) -> String? {
        let path = fileURL.standardizedFileURL.path
        let prefix = mountPath.hasSuffix("/") ? mountPath : mountPath + "/"
        guard path.hasPrefix(prefix) else { return nil }
        let relative = String(path.dropFirst(prefix.count))
        return relative.isEmpty ? nil : relative
    }
}

/// Matches catalog volumes against what is mounted right now.
public enum VolumeAvailability {
    public struct Reconciliation: Equatable, Sendable {
        /// Catalog volumes that are mounted.
        public var online: Set<Int64>
        /// Catalog volumes mounted at a different path than recorded, with the new path.
        public var moved: [Int64: String]
    }

    /// Descriptors for every mounted volume, including hidden system volumes.
    public static func mountedVolumes() -> [VolumeDescriptor] {
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: Array(VolumeResolver.keys),
                                                         options: []) ?? []
        return urls.compactMap { try? VolumeResolver.descriptor(forVolumeAt: $0) }
    }

    public static func reconcile(_ volumes: [VolumeRecord], mounted: [VolumeDescriptor]) -> Reconciliation {
        let byIdentity = Dictionary(mounted.map { ($0.identity, $0) }, uniquingKeysWith: { first, _ in first })
        var result = Reconciliation(online: [], moved: [:])
        for volume in volumes {
            guard let id = volume.id, let match = byIdentity[volume.identity] else { continue }
            result.online.insert(id)
            if match.mountPath != volume.mountPath {
                result.moved[id] = match.mountPath
            }
        }
        return result
    }
}

extension Catalog {
    /// Updates mount paths of volumes that were remounted elsewhere and returns the
    /// ids of volumes that are online. Offline volumes keep all their rows.
    public func refreshVolumeAvailability(mounted: [VolumeDescriptor] = VolumeAvailability.mountedVolumes()) async throws -> Set<Int64> {
        let reconciliation = VolumeAvailability.reconcile(try await volumes(), mounted: mounted)
        for (id, path) in reconciliation.moved {
            try await updateVolume(id: id, mountPath: path)
        }
        return reconciliation.online
    }
}
