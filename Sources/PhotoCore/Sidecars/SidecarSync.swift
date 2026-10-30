import Foundation
import os

/// Keeps XMP sidecars in step with the catalog, which is the source of truth.
///
/// For each master the catalog remembers what its sidecar looked like when the
/// app last read or wrote it, and the values at that moment (the baseline).
/// Comparing the baseline, the library and the file tells what happened:
///
/// - file unchanged, library changed: the library's values are written;
/// - file changed (by another app): the photo is flagged for review and its
///   sidecar is left alone until someone chooses what to keep;
/// - file and library agree: only the baseline is updated.
///
/// Originals are never written. A master whose own bytes changed (another app
/// embedded metadata in a JPEG) is re-hashed, and its embedded values go
/// through the same comparison.
public actor SidecarSync {
    public let catalog: Catalog
    public let metadataReader: any MetadataReader
    public let hasher: any ContentHasher
    private static let log = Logger(subsystem: AppBranding.bundleIdentifier, category: "sidecars")

    public init(catalog: Catalog, metadataReader: any MetadataReader, hasher: any ContentHasher = SHA256ContentHasher()) {
        self.catalog = catalog
        self.metadataReader = metadataReader
        self.hasher = hasher
    }

    public struct Report: Sendable, Equatable {
        public var written = 0
        public var changedOnDisk = 0
        public var failed = 0
        public var checked = 0

        public init() {}

        mutating func add(_ other: Report) {
            written += other.written
            changedOnDisk += other.changedOnDisk
            failed += other.failed
            checked += other.checked
        }
    }

    // MARK: Queue

    /// Handles queued changes on mounted volumes, writing sidecars when the
    /// files allow it. Masters on other volumes stay queued.
    public func processQueue(mountedVolumes: Set<Int64>) async throws -> Report {
        var report = Report()
        var skipped: Set<Int64> = []
        while true {
            try Task.checkCancellation()
            let owners = try await catalog.queuedSidecarOwners(limit: 256 + skipped.count).filter { !skipped.contains($0) }
            guard !owners.isEmpty else { break }
            let targets = try await catalog.sidecarTargets(owners: owners)
            var done: [Int64] = []
            for target in targets {
                guard mountedVolumes.contains(target.volumeID) else {
                    skipped.insert(target.imageID)
                    continue
                }
                report.add(try await sync(target, writing: true))
                done.append(target.imageID)
            }
            // Owners whose master is gone from the catalog.
            done += owners.filter { owner in !targets.contains { $0.imageID == owner } }
            try await catalog.dequeueSidecarWork(done)
        }
        return report
    }

    // MARK: Checking

    /// Looks for sidecars and masters changed outside the app among the given
    /// masters (by default every master on the mounted volumes).
    public func checkForChanges(mountedVolumes: Set<Int64>, owners: [Int64]? = nil) async throws -> Report {
        var report = Report()
        let all: [Int64]
        if let owners {
            all = owners
        } else {
            all = try await catalog.sidecarOwners(onVolumes: mountedVolumes)
        }
        for chunk in all.chunked(into: 256) {
            try Task.checkCancellation()
            for target in try await catalog.sidecarTargets(owners: Array(chunk)) where mountedVolumes.contains(target.volumeID) {
                report.add(try await checkMaster(target))
                report.add(try await sync(target, writing: false))
                report.checked += 1
            }
        }
        return report
    }

    /// Notices a master whose bytes changed: its catalog hash, size and date are
    /// updated, and values embedded by another app are compared with the
    /// library's when the master has no sidecar.
    private func checkMaster(_ target: SidecarTarget) async throws -> Report {
        var report = Report()
        guard let attributes = try? target.masterURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
              let size = attributes.fileSize, let modified = attributes.contentModificationDate
        else { return report }
        guard Int64(size) != target.masterSize || abs(modified.timeIntervalSince(target.masterModifiedAt)) >= 0.001 else {
            return report
        }
        let hash = try await hasher.contentHash(of: target.masterURL)
        do {
            try await catalog.updateMasterFile(imageID: target.imageID, size: Int64(size), modifiedAt: modified, contentHash: hash)
        } catch {
            Self.log.error("Could not record the new content of \(target.masterURL.path, privacy: .public): \(String(describing: error), privacy: .public)")
            return report
        }
        guard hash != target.contentHash, findSidecar(target) == nil,
              let embedded = try await metadataReader.metadata(for: [target.masterURL])[target.masterURL]
        else { return report }
        let disk = Self.values(from: embedded)
        let baseline = target.baseline ?? target.values
        if !disk.sameAs(baseline), !disk.sameAs(target.values) {
            try await flag(target, disk: disk, source: .embedded, baseline: baseline)
            report.changedOnDisk += 1
        }
        return report
    }

    static func values(from metadata: ImageMetadata) -> SidecarValues {
        let culling = metadata.embeddedCulling
        return SidecarValues(rating: culling.rating, flag: culling.flag, colorLabel: culling.label, keywords: metadata.keywords,
                             creator: metadata.artist, rights: metadata.copyright, caption: metadata.caption,
                             usageTerms: metadata.usageTerms, contact: metadata.creatorContact, title: metadata.title,
                             altText: metadata.altText, extendedDescription: metadata.extendedDescription,
                             jobTitle: metadata.jobTitle)
    }

    // MARK: One master

    private func findSidecar(_ target: SidecarTarget) -> (url: URL, size: Int64, modifiedAt: Date)? {
        var names = SidecarFiles.candidateNames(forMaster: target.masterURL.lastPathComponent, preferred: target.sidecarName)
        if let known = target.sync?.sidecarName { names.insert(known, at: 0) }
        return SidecarFiles.locate(in: target.folder, names: names)
    }

    func syncWriting(_ target: SidecarTarget) async throws -> Report {
        try await sync(target, writing: true)
    }

    /// Compares baseline, library and file for one master; writes when
    /// `writing` and the file has not changed since the baseline.
    private func sync(_ target: SidecarTarget, writing: Bool) async throws -> Report {
        var report = Report()
        // Already waiting for review: leave it until someone decides.
        if target.sync?.status == .changedOnDisk { return report }
        let baseline = target.baseline
        let library = target.values

        guard let found = findSidecar(target) else {
            // No sidecar. Write one when the library says something the file
            // (as last seen) does not.
            let reference = baseline ?? SidecarValues()
            if writing, !library.sameAs(reference) || (target.sync?.sidecarName != nil && !library.isEmpty) {
                report.add(try await write(target, url: target.folder.appending(path: target.sidecarName),
                                           previous: baseline))
            }
            return report
        }

        let known = target.sync
        let unchangedOnDisk = known?.sidecarName == found.url.lastPathComponent && known?.sidecarSize == found.size
            && known.flatMap { $0.sidecarModifiedAt }.map { abs($0.timeIntervalSince(found.modifiedAt)) < 0.001 } == true
        var disk: SidecarRead?
        if !unchangedOnDisk {
            do {
                disk = try SidecarFiles.read(found.url)
            } catch {
                report.failed += 1
                try await markFailed(target, error: "unreadable sidecar: \(error)")
                return report
            }
        }
        if let read = disk, read.file.digest == known?.sidecarDigest {
            // Touched but not changed: remember the new date.
            try await record(target, file: read.file, baseline: baseline ?? read.values)
            disk = nil
        }

        if let disk {
            // Changed since the app last saw it (or never seen).
            if disk.values.sameAs(library) {
                try await record(target, file: disk.file, baseline: library)
            } else if let baseline, disk.values.sameAs(baseline) {
                // Rewritten with the same values (another app re-saved it): not an
                // outside change. The library's newer values go out when writing.
                if writing {
                    report.add(try await write(target, url: found.url, previous: baseline))
                } else {
                    try await record(target, file: disk.file, baseline: baseline)
                }
            } else {
                try await flag(target, disk: disk.values, source: .sidecar, baseline: baseline ?? library, file: disk.file)
                report.changedOnDisk += 1
            }
        } else if writing, let baseline, !library.sameAs(baseline) {
            report.add(try await write(target, url: found.url, previous: baseline))
        } else if baseline == nil, writing, !library.isEmpty {
            report.add(try await write(target, url: found.url, previous: nil))
        }
        return report
    }

    private func write(_ target: SidecarTarget, url: URL, previous: SidecarValues?) async throws -> Report {
        var report = Report()
        do {
            let file = try SidecarFiles.write(target.values, previous: previous, to: url)
            try await record(target, file: file, baseline: target.values)
            report.written += 1
        } catch {
            Self.log.error("Could not write \(url.path, privacy: .public): \(String(describing: error), privacy: .public)")
            try await markFailed(target, error: String(describing: error))
            report.failed += 1
        }
        return report
    }

    private func record(_ target: SidecarTarget, file: SidecarFileState?, baseline: SidecarValues) async throws {
        try await catalog.saveSync(MetadataSyncRecord(
            imageId: target.imageID, sidecarName: file?.name, sidecarSize: file?.size, sidecarModifiedAt: file?.modifiedAt,
            sidecarDigest: file?.digest, baseline: try baseline.jsonString(), status: .inStep, diskValues: nil,
            diskSource: file == nil ? .embedded : .sidecar, checkedAt: Date(), error: nil))
    }

    private func flag(_ target: SidecarTarget, disk: SidecarValues, source: MetadataSyncRecord.Source,
                      baseline: SidecarValues, file: SidecarFileState? = nil) async throws {
        let baselineJSON = try baseline.jsonString()
        var record = target.sync ?? MetadataSyncRecord(
            imageId: target.imageID, sidecarName: nil, sidecarSize: nil, sidecarModifiedAt: nil, sidecarDigest: nil,
            baseline: baselineJSON, status: .inStep, diskValues: nil, diskSource: source, checkedAt: nil, error: nil)
        record.status = .changedOnDisk
        record.diskValues = try disk.jsonString()
        record.diskSource = source
        record.checkedAt = Date()
        if let file {
            record.sidecarName = file.name
            record.sidecarSize = file.size
            record.sidecarModifiedAt = file.modifiedAt
            record.sidecarDigest = file.digest
        }
        try await catalog.saveSync(record)
    }

    private func markFailed(_ target: SidecarTarget, error: String) async throws {
        let baselineJSON = try (target.baseline ?? SidecarValues()).jsonString()
        var record = target.sync ?? MetadataSyncRecord(
            imageId: target.imageID, sidecarName: nil, sidecarSize: nil, sidecarModifiedAt: nil, sidecarDigest: nil,
            baseline: baselineJSON, status: .inStep, diskValues: nil, diskSource: .sidecar, checkedAt: nil, error: nil)
        record.status = .writeFailed
        record.error = error
        record.checkedAt = Date()
        try await catalog.saveSync(record)
    }

    // MARK: Review

    public enum Resolution: Sendable, Equatable {
        /// Keep the library's values; the sidecar is rewritten with them.
        case keepLibrary
        /// Take the file's values into the library.
        case useFile
        /// Take these fields from the file and keep the rest; with
        /// `mergeKeywords`, keywords from both sides are kept.
        case fields(Set<SidecarValues.Field>, mergeKeywords: Bool)
    }

    /// Settles outside changes for the masters of `changes`. Masters on volumes
    /// that are not mounted keep their library values and get their sidecar
    /// written when the volume returns.
    public func resolve(_ changes: [DiskChange], with resolution: Resolution, mountedVolumes: Set<Int64>) async throws {
        let targets = Dictionary(uniqueKeysWithValues: try await catalog.sidecarTargets(owners: changes.map(\.imageID))
            .map { ($0.imageID, $0) })
        for change in changes {
            guard var target = targets[change.imageID] else { continue }
            var values = change.library
            switch resolution {
            case .keepLibrary:
                break
            case .useFile:
                values = change.disk
            case .fields(let fields, let merge):
                values = values.taking(fields, from: change.disk)
                if merge {
                    values.keywords = ImageMetadata.uniqueKeywords(change.library.keywords + change.disk.keywords)
                }
            }
            if !values.sameAs(change.library) {
                try await catalog.applySidecarValues(values, toImage: change.imageID)
            }
            target.values = values
            // The file is accepted as seen; what is written next starts from it.
            var record = target.sync
            record?.status = .inStep
            record?.diskValues = nil
            if let record { try await catalog.saveSync(record) }
            target.sync = record
            if change.source == .sidecar, mountedVolumes.contains(target.volumeID), let found = findSidecar(target),
               !values.sameAs(change.disk) {
                _ = try await write(target, url: found.url, previous: change.disk)
            } else {
                try await self.record(target, file: target.sync.flatMap { sync in
                    sync.sidecarName.map { SidecarFileState(name: $0, size: sync.sidecarSize ?? 0,
                                                            modifiedAt: sync.sidecarModifiedAt ?? Date(),
                                                            digest: sync.sidecarDigest ?? "") }
                }, baseline: values)
            }
        }
        // The library changes above queued these masters; they are settled now.
        try await catalog.dequeueSidecarWork(changes.map(\.imageID))
    }
}

extension SidecarSync {
    /// Writes sidecars for these masters now, whatever the queue holds (used
    /// for metadata applied at import, which always goes into sidecars).
    public func writeSidecars(forImages imageIDs: [Int64], mountedVolumes: Set<Int64>) async throws -> Report {
        let owners = Array(Set(try await catalog.database.read { db in
            try Catalog.sidecarOwners(db, images: imageIDs).values
        })).sorted()
        var report = Report()
        for chunk in owners.chunked(into: 256) {
            for target in try await catalog.sidecarTargets(owners: Array(chunk)) where mountedVolumes.contains(target.volumeID) {
                report.add(try await syncForced(target))
            }
        }
        try await catalog.dequeueSidecarWork(owners)
        return report
    }

    /// The new master has values its (absent) sidecar lacks: write it.
    private func syncForced(_ target: SidecarTarget) async throws -> Report {
        var forced = target
        // A fresh baseline of "nothing" makes the library's values differ.
        forced.sync = nil
        return try await syncWriting(forced)
    }
}
