import Foundation
@testable import PhotoCore

/// A catalog with one volume and one project, plus helpers to add masters.
struct CatalogFixture {
    let catalog: Catalog
    let volume: VolumeRecord
    let project: ProjectRecord

    static func make(projectName: String = "Fixture") async throws -> CatalogFixture {
        let catalog = try Catalog.makeInMemory()
        let volume = try await catalog.registerVolume(
            VolumeDescriptor(identity: "TEST-VOLUME", name: "Test", mountPath: "/Volumes/Test"))
        let project = try await catalog.createProject(name: projectName)
        return CatalogFixture(catalog: catalog, volume: volume, project: project)
    }

    static func master(_ index: Int, hash: String? = nil, captureDate: Date? = nil,
                       path: String? = nil) -> NewMaster {
        NewMaster(relativePath: path ?? "shoot/IMG_\(String(format: "%04d", index)).CR3",
                  fileSize: Int64(1000 + index),
                  modifiedAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(index)),
                  contentHash: hash ?? String(repeating: String(format: "%02x", index % 256), count: 32),
                  metadata: ImageMetadata(captureDate: captureDate ?? Date(timeIntervalSince1970: 1_600_000_000 + Double(index)),
                                          pixelWidth: 6000, pixelHeight: 4000))
    }

    /// Inserts masters into the fixture project and returns their default version ids.
    @discardableResult
    func addMasters(_ masters: [NewMaster], project: ProjectRecord? = nil) async throws -> [Int64] {
        try await catalog.insertMasters(masters, volumeID: volume.id!, projectID: (project ?? self.project).id!)
            .insertedVersionIDs
    }
}
