import Foundation
import GRDB
import Testing
@testable import PhotoCore

/// Issue #88, R5: stored detection results in the catalog (AC4's storage, AC5).
@Suite("Detection masks: catalog")
struct MaskRasterCatalogTests {
    static func raster(_ seed: UInt8, request: MaskRaster.Request = .foreground) throws -> MaskRaster {
        try MaskRaster(levels: (0..<64).map { UInt8(truncatingIfNeeded: Int($0) * 3 + Int(seed)) }, width: 8, height: 8,
                       instances: 1, request: request)
    }

    /// A stack with one mask of one detection of `kind` naming `digest`.
    static func stack(_ digest: String?, kind: MaskDetectionKind = .subject, exposure: Double = 0.3) -> EditStack {
        DetectionMaskModelTests.masks([MaskComponent(.detection(MaskDetection(kind: kind, raster: digest)))],
                                      exposure: exposure).editStack
    }

    static func one() async throws -> (CatalogFixture, Int64) {
        let fixture = try await CatalogFixture.make()
        let id = try #require(try await fixture.addMasters([CatalogFixture.master(1)]).first)
        return (fixture, id)
    }

    @Test("v15 adds the table and the history column and leaves existing data as it was (AC5)")
    func migration() async throws {
        let old = try DatabaseQueue()
        try CatalogSchema.migrator.migrate(old, upTo: "v14")
        try await old.write { db in
            try db.execute(sql: "INSERT INTO volume (id, identity, name, mountPath) VALUES (1, 'V', 'V', '/Volumes/V')")
            try db.execute(sql: "INSERT INTO project (id, uuid, name, createdAt) VALUES (1, 'p', 'P', '2024-01-01 00:00:00.000')")
            try db.execute(sql: """
                INSERT INTO image (id, volumeId, projectId, relativePath, fileName, fileSize, modifiedAt, contentHash,
                                   format, sortDate, importedAt)
                VALUES (1, 1, 1, 'a/1.jpg', '1.jpg', 1, '2024-01-01 00:00:00.000', 'h1', 'jpg',
                        '2024-01-01 00:00:00.000', '2024-01-01 00:00:00.000')
                """)
            try db.execute(sql: """
                INSERT INTO version (id, uuid, imageId, versionNumber, isDefault, editStack, editStackHash, createdAt, modifiedAt)
                VALUES (1, 'v', 1, 1, 1, '{"operations":[],"schemaVersion":1}', 'abc', '2024-01-01 00:00:00.000',
                        '2024-01-01 00:00:00.000')
                """)
            try db.execute(sql: """
                INSERT INTO editHistory (id, versionId, label, createdAt, stack) VALUES (7, 1, 'Exposure', '2024-01-02 00:00:00.000', x'00')
                """)
        }
        let snapshot = { (db: Database) in
            try Row.fetchAll(db, sql: "SELECT id, versionId, label, createdAt, stack FROM editHistory")
                + Row.fetchAll(db, sql: "SELECT id, editStack, editStackHash FROM version")
        }
        let rowsBefore = try old.read(snapshot)
        let catalog = try Catalog(database: old)
        let rowsAfter = try catalog.database.read(snapshot)
        #expect(rowsAfter == rowsBefore)
        #expect(try await catalog.maskRasterDigests().isEmpty)
        let column = try await catalog.database.read { db in
            try DatabaseValue.fetchOne(db, sql: "SELECT maskRasters FROM editHistory WHERE id = 7")
        }
        #expect(column?.isNull == true)
    }

    @Test("A row is stored once per bytes, never updated, and read back")
    func storeAndRead() async throws {
        let (fixture, _) = try await Self.one()
        let raster = try Self.raster(1)
        try await fixture.catalog.storeMaskRaster(raster, at: Date(timeIntervalSince1970: 1))
        try await fixture.catalog.storeMaskRaster(raster, at: Date(timeIntervalSince1970: 2))
        #expect(try await fixture.catalog.maskRasterDigests() == [raster.digest])
        let read = try #require(try await fixture.catalog.maskRaster(digest: raster.digest))
        #expect(read == raster)
        #expect(try await fixture.catalog.maskRaster(digest: try Self.raster(2).digest) == nil)
        #expect(try await fixture.catalog.maskRaster(digest: "not a digest") == nil)
    }

    @Test("Two components naming the same bytes share one row; Duplicate adds none (AC4)")
    func sharingAndDuplicate() async throws {
        let (fixture, id) = try await Self.one()
        let raster = try Self.raster(3)
        try await fixture.catalog.storeMaskRaster(raster)
        try await fixture.catalog.storeMaskRaster(raster)
        var adjustments = DetectionMaskModelTests.masks([
            MaskComponent(.detection(MaskDetection(kind: .subject, raster: raster.digest))),
            MaskComponent(.detection(MaskDetection(kind: .background, raster: raster.digest))),
        ])
        adjustments.exposure.ev = 0.1
        try await fixture.catalog.setEditStack(adjustments.editStack, forVersion: id, historyLabel: "Add Subject Mask")
        let copy = try await fixture.catalog.duplicateVersion(id: id)
        #expect(try await fixture.catalog.maskRasterDigests() == [raster.digest])
        let copied = try #require(try await fixture.catalog.version(id: copy.id!)?.decodedEditStack())
        #expect(Adjustments(stack: copied).local.maskRasterDigests == [raster.digest])
        #expect(try await fixture.catalog.removeUnreferencedMaskRasters() == 0)
    }

    @Test("History entries name the rows their snapshots refer to; a revert gives the earlier digest back (AC4)")
    func historyNamesItsRasters() async throws {
        let (fixture, id) = try await Self.one()
        let first = try Self.raster(4), second = try Self.raster(5)
        for raster in [first, second] { try await fixture.catalog.storeMaskRaster(raster) }
        try await fixture.catalog.setEditStack(Self.stack(first.digest), forVersion: id, historyLabel: "Add Subject Mask")
        try await fixture.catalog.setEditStack(Self.stack(second.digest), forVersion: id, historyLabel: "Update Detection")
        let lists = try await fixture.catalog.database.read { db in
            try String?.fetchAll(db, sql: "SELECT maskRasters FROM editHistory WHERE versionId = ? ORDER BY id", arguments: [id])
        }
        #expect(lists == ["[\"\(first.digest)\"]", "[\"\(second.digest)\"]"])
        let entries = try await fixture.catalog.editHistory(forVersion: id)
        let earlier = try #require(entries.last)
        let snapshot = try #require(try await fixture.catalog.editHistoryStack(entryID: earlier.id, forVersion: id))
        #expect(Adjustments(stack: snapshot).local.maskRasterDigests == [first.digest])
        #expect(try await fixture.catalog.maskRaster(digest: first.digest) == first)
    }

    @Test("Cleanup keeps rows any stack or history entry names, and deletes the rest (AC5)")
    func cleanup() async throws {
        let (fixture, id) = try await Self.one()
        let catalog = fixture.catalog
        let other = try #require(try await fixture.addMasters([CatalogFixture.master(2)]).first)
        let named = try Self.raster(10), inHistory = try Self.raster(11), unnamed = try Self.raster(12)
        let ofRemoved = try Self.raster(13)
        for raster in [named, inHistory, unnamed, ofRemoved] { try await catalog.storeMaskRaster(raster) }

        // Update: the stack names `named`, its history still names `inHistory`.
        try await catalog.setEditStacks([id: Self.stack(inHistory.digest)], historyLabel: "Add Subject Mask",
                                        at: Date(), byteBudget: EditHistory.maxBytes)
        try await catalog.setEditStacks([id: Self.stack(named.digest)], historyLabel: "Update Detection",
                                        at: Date(), byteBudget: EditHistory.maxBytes)
        try await catalog.setEditStack(Self.stack(ofRemoved.digest), forVersion: other, historyLabel: "Add People Mask")

        #expect(try await catalog.removeUnreferencedMaskRasters() == 1)
        #expect(try await catalog.maskRasterDigests() == [named.digest, inHistory.digest, ofRemoved.digest])

        // The history trimmed past the entry that named `inHistory` (a budget of one entry).
        try await catalog.setEditStacks([id: Self.stack(named.digest, exposure: 0.5)], historyLabel: "Exposure",
                                        at: Date(), byteBudget: 1)
        #expect(try await catalog.editHistory(forVersion: id).count == 1)
        // The version removed from the library, with its history.
        _ = try await catalog.removePhotos(versionIDs: [other])

        #expect(try await catalog.removeUnreferencedMaskRasters() == 2)
        #expect(try await catalog.maskRasterDigests() == [named.digest])
        // Nothing left to do.
        #expect(try await catalog.removeUnreferencedMaskRasters() == 0)
    }

    @Test("A stack this build can't read still keeps the rows its text names")
    func unreadableStacksStillName() async throws {
        let (fixture, id) = try await Self.one()
        let raster = try Self.raster(20)
        try await fixture.catalog.storeMaskRaster(raster)
        let json = MaskModelTests.stack(masks: #"[{"id":"00000000-0000-4000-8000-000000000001","components":[{"shape":"subject","raster":"\#(raster.digest)","refine":3}]}]"#)
        try await UnreadableStackTests.store(json, forVersion: id, in: fixture.catalog)
        #expect(try await fixture.catalog.removeUnreferencedMaskRasters() == 0)
    }

    @Test("Undo Duplicate takes a copy's history out and puts it back with the rows it names")
    func undoDuplicateKeepsReferences() async throws {
        let (fixture, id) = try await Self.one()
        let catalog = fixture.catalog
        let raster = try Self.raster(30)
        try await catalog.storeMaskRaster(raster)
        let copy = try await catalog.duplicateVersion(id: id)
        let copyID = try #require(copy.id)
        try await catalog.setEditStack(Self.stack(raster.digest), forVersion: copyID, historyLabel: "Add Subject Mask")
        try await catalog.setEditStack(Self.stack(nil), forVersion: copyID, historyLabel: "Update Detection")
        let removed = try await catalog.removeCopies(versionIDs: [copyID])
        try await catalog.restoreCopies(removed)
        // Only the restored history names it now.
        #expect(try await catalog.removeUnreferencedMaskRasters() == 0)
        #expect(try await catalog.maskRasterDigests() == [raster.digest])
    }

    @Test("Digests are found in a stack's text exactly where a component names one")
    func referencesInText() {
        let a = DetectionMaskModelTests.digestA, b = DetectionMaskModelTests.digestB
        let json = #"{"raster":"\#(a)","shape":"subject"},{"raster":"\#(b)","shape":"people"},{"raster":"\#(a)"}"#
        #expect(MaskRasterReferences.digests(inStackJSON: json) == [a, b])
        #expect(MaskRasterReferences.digests(inStackJSON: #"{"raster":"abc"}"#).isEmpty)
        #expect(MaskRasterReferences.decode(MaskRasterReferences.encode([a, b])!) == [a, b])
        #expect(MaskRasterReferences.decode("[\"\(a)\"") == nil, "cut short")
        #expect(MaskRasterReferences.decode("[\"abc\"]") == nil, "not a digest")
        #expect(MaskRasterReferences.encode([]) == nil)
    }

    // MARK: Security review

    /// Writes a row as a damaged or crafted catalog could hold it.
    static func insertRow(_ catalog: Catalog, digest: String, width: Int, height: Int, data: Data) async throws {
        try await catalog.database.write { db in
            try db.execute(sql: """
                INSERT INTO maskRaster (digest, encoding, width, height, instances, data, request, revision,
                                        systemVersion, createdAt)
                VALUES (?, ?, ?, ?, 1, ?, 'foreground', 1, 'test', ?)
                """, arguments: [digest, MaskRaster.encoding, width, height, data, Date()])
        }
    }

    @Test("Rows over the size limits, or whose bytes don't hash to their key, are not read (L1, L2)")
    func craftedRows() async throws {
        let (fixture, _) = try await Self.one()
        let catalog = fixture.catalog
        let good = try Self.raster(40)
        // Too wide by its row, though its bytes are a small, valid PNG.
        let wideKey = String(repeating: "c3", count: 32)
        try await Self.insertRow(catalog, digest: wideKey, width: 4096, height: 1, data: good.png)
        #expect(try await catalog.maskRaster(digest: wideKey) == nil)
        // More bytes than any row this build writes: not loaded.
        let bigKey = String(repeating: "d4", count: 32)
        try await Self.insertRow(catalog, digest: bigKey, width: 8, height: 8,
                                 data: Data(count: MaskRaster.maximumStoredBytes + 1))
        #expect(try await catalog.maskRaster(digest: bigKey) == nil)
        // A good PNG under another result's key.
        let wrongKey = String(repeating: "e5", count: 32)
        try await Self.insertRow(catalog, digest: wrongKey, width: 8, height: 8, data: good.png)
        #expect(try await catalog.maskRaster(digest: wrongKey) == nil)
        #expect(MaskRasterStore(catalog: catalog).lookup(wrongKey) == .missing)
        // The real one reads.
        try await catalog.storeMaskRaster(good)
        #expect(try await catalog.maskRaster(digest: good.digest) == good)
    }

    @Test("A damaged history list is read from its snapshot; if that fails too, nothing is deleted (L3)")
    func damagedHistoryList() async throws {
        let (fixture, id) = try await Self.one()
        let catalog = fixture.catalog
        let named = try Self.raster(50), unnamed = try Self.raster(51)
        for raster in [named, unnamed] { try await catalog.storeMaskRaster(raster) }
        try await catalog.setEditStack(Self.stack(named.digest), forVersion: id, historyLabel: "Add Subject Mask")
        try await catalog.setEditStack(Self.stack(nil), forVersion: id, historyLabel: "Update Detection")
        // Only the first entry names `named`; damage its list.
        try await catalog.database.write { db in
            try db.execute(sql: """
                UPDATE editHistory SET maskRasters = '["cut' WHERE id = (SELECT MIN(id) FROM editHistory WHERE versionId = ?)
                """, arguments: [id])
        }
        #expect(try await catalog.removeUnreferencedMaskRasters() == 1)
        #expect(try await catalog.maskRasterDigests() == [named.digest], "kept through the snapshot")

        // The snapshot damaged as well: this launch deletes nothing.
        try await catalog.storeMaskRaster(unnamed)
        try await catalog.database.write { db in
            try db.execute(sql: """
                UPDATE editHistory SET stack = x'00' WHERE id = (SELECT MIN(id) FROM editHistory WHERE versionId = ?)
                """, arguments: [id])
        }
        #expect(try await catalog.removeUnreferencedMaskRasters() == 0)
        #expect(try await catalog.maskRasterDigests() == [named.digest, unnamed.digest])
    }
}
