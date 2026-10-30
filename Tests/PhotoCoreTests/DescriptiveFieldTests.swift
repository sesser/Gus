import Foundation
import GRDB
import Testing
@testable import PhotoCore

@Suite("Descriptive fields")
struct DescriptiveFieldTests {
    private func master(_ path: String, _ index: Int) -> NewMaster {
        CatalogFixture.master(index, hash: String(format: "%064x", index), path: path)
    }

    private func image(_ catalog: Catalog, _ versionID: Int64) async throws -> ImageRecord {
        try #require(try await catalog.details(forVersion: versionID)).image
    }

    private func clearQueue(_ catalog: Catalog) async throws {
        try await catalog.database.write { db in try db.execute(sql: "DELETE FROM sidecarQueue") }
    }

    private func queued(_ catalog: Catalog) async throws -> Set<Int64> {
        try await catalog.database.read { db in Set(try Int64.fetchAll(db, sql: "SELECT imageId FROM sidecarQueue")) }
    }

    @Test func settingAFieldReachesEveryPhotoAndUndoPutsBackEachValue() async throws {
        let fixture = try await CatalogFixture.make()
        let catalog = fixture.catalog
        let ids = try await fixture.addMasters([master("a/IMG_1.CR3", 1), master("a/IMG_2.CR3", 2)])
        try await catalog.setDescriptiveField(.title, to: "First", forVersions: [ids[0]])
        try await clearQueue(catalog)

        var summary = try await catalog.descriptiveSummary(forVersions: ids)
        #expect(summary.imageCount == 2)
        #expect(summary.mixed == [.title])
        #expect(summary.values[.title] == nil)

        let change = try await catalog.setDescriptiveField(.title, to: "  Both \n", forVersions: ids)
        #expect(try await image(catalog, ids[0]).title == "Both")
        #expect(try await image(catalog, ids[1]).title == "Both")
        summary = try await catalog.descriptiveSummary(forVersions: ids)
        #expect(summary.mixed.isEmpty && summary.values[.title] == "Both")
        // Changes reach the sidecars.
        #expect(try await queued(catalog).count == 2)

        let redo = try await catalog.restoreDescriptiveField(change)
        #expect(try await image(catalog, ids[0]).title == "First")
        #expect(try await image(catalog, ids[1]).title == nil)

        try await catalog.restoreDescriptiveField(redo)
        #expect(try await image(catalog, ids[0]).title == "Both")
        #expect(try await image(catalog, ids[1]).title == "Both")
    }

    @Test func emptyTextClearsAField() async throws {
        let fixture = try await CatalogFixture.make()
        let ids = try await fixture.addMasters([master("a/IMG_1.CR3", 1)])
        try await fixture.catalog.setDescriptiveField(.altText, to: "A dog", forVersions: ids)
        try await fixture.catalog.setDescriptiveField(.altText, to: "   ", forVersions: ids)
        #expect(try await image(fixture.catalog, ids[0]).altText == nil)
    }

    @Test func contactFieldsShareTheContactAndClearingTheLastRemovesIt() async throws {
        let fixture = try await CatalogFixture.make()
        let catalog = fixture.catalog
        let ids = try await fixture.addMasters([master("a/IMG_1.CR3", 1)])
        try await catalog.setDescriptiveField(.city, to: "Moab", forVersions: ids)
        try await catalog.setDescriptiveField(.email, to: "pat@example.com", forVersions: ids)
        try await catalog.setDescriptiveField(.jobTitle, to: "Photographer", forVersions: ids)
        var record = try await image(catalog, ids[0])
        #expect(record.metadata.creatorContact == CreatorContact(email: "pat@example.com", city: "Moab"))
        #expect(record.jobTitle == "Photographer")

        try await catalog.setDescriptiveField(.city, to: nil, forVersions: ids)
        try await catalog.setDescriptiveField(.email, to: nil, forVersions: ids)
        record = try await image(catalog, ids[0])
        #expect(record.creatorContact == nil)
        #expect(record.jobTitle == "Photographer")
    }

    @Test func pairPartnersShareTheFields() async throws {
        let fixture = try await CatalogFixture.make()
        let catalog = fixture.catalog
        let ids = try await fixture.addMasters([master("a/IMG_1.CR3", 1), master("a/IMG_1.JPG", 2)])
        try await catalog.setDescriptiveField(.caption, to: "Pair", forVersions: [ids[1]])
        #expect(try await image(catalog, ids[0]).caption == "Pair")
        #expect(try await image(catalog, ids[1]).caption == "Pair")
        #expect(try await catalog.descriptiveSummary(forVersions: [ids[0]]).imageCount == 2)
    }

    @Test func sidecarValuesCarryTheNewFields() async throws {
        let fixture = try await CatalogFixture.make()
        let catalog = fixture.catalog
        let ids = try await fixture.addMasters([master("a/IMG_1.CR3", 1)])
        try await catalog.setDescriptiveField(.title, to: "T", forVersions: ids)
        try await catalog.setDescriptiveField(.extendedDescription, to: "Long", forVersions: ids)
        let imageID = try await image(catalog, ids[0]).id!
        let target = try #require(try await catalog.sidecarTargets(owners: [imageID]).first)
        #expect(target.values.title == "T" && target.values.extendedDescription == "Long")

        var disk = target.values
        disk.title = "From another app"
        disk.jobTitle = "Editor"
        try await catalog.applySidecarValues(disk, toImage: imageID)
        let record = try await image(catalog, ids[0])
        #expect(record.title == "From another app" && record.jobTitle == "Editor")
    }

    @Test func readingTheFileAgainKeepsTheLibrarysValues() async throws {
        let fixture = try await CatalogFixture.make()
        let catalog = fixture.catalog
        let ids = try await fixture.addMasters([master("a/IMG_1.CR3", 1)])
        try await catalog.setDescriptiveField(.rights, to: "© Library", forVersions: ids)
        let imageID = try await image(catalog, ids[0]).id!
        var fromFile = ImageMetadata()
        fromFile.copyright = "© File"
        fromFile.title = "File title"
        try await catalog.refreshMetadata([imageID: fromFile], checked: [imageID])
        let record = try await image(catalog, ids[0])
        #expect(record.copyright == "© Library")
        #expect(record.title == "File title")
    }

    @Test func oldBaselinesDecodeWithoutTheNewFields() throws {
        let old = #"{"caption":"c","colorLabel":0,"flag":0,"keywords":[],"rating":0}"#
        let values = try SidecarValues.decode(from: old)
        #expect(values.caption == "c" && values.title == nil && values.jobTitle == nil)
    }

    @Test func exifToolReadsTheNewTagsWithIIMFallbacks() {
        let xmp = ExifToolMetadataReader.metadata(from: [
            "Title": "T", "AltTextAccessibility": "Alt", "ExtDescrAccessibility": "Ext", "AuthorsPosition": "Job",
        ])
        #expect(xmp.title == "T" && xmp.altText == "Alt" && xmp.extendedDescription == "Ext" && xmp.jobTitle == "Job")
        let iim = ExifToolMetadataReader.metadata(from: ["ObjectName": "Name", "By-lineTitle": "Position"])
        #expect(iim.title == "Name" && iim.jobTitle == "Position")
    }
}
