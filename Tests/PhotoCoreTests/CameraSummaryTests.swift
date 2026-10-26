import Foundation
import Testing
@testable import PhotoCore

@Suite("Camera summary")
struct CameraSummaryTests {
    private func file(_ name: String, _ kind: FileKind, at time: String, make: String? = "SONY",
                      model: String? = "ILCE-7M3", count: Int? = nil) -> SourceFile {
        var metadata = ImageMetadata(captureDate: ExifDate.parse("2026:10:24 " + time)?.date, cameraMake: make,
                                     cameraModel: model)
        metadata.shutterCount = count
        return SourceFile(url: URL(fileURLWithPath: "/card/DCIM/100MSDCF/" + name), size: 1, modifiedAt: .distantPast,
                          kind: kind, metadata: metadata)
    }

    @Test func namesReadTheWayPeopleWriteThem() {
        let cases: [(String?, String?, String?)] = [
            ("SONY", "ILCE-7M3", "Sony ILCE-7M3"),
            ("NIKON CORPORATION", "NIKON Z 6_2", "Nikon Z 6_2"),
            ("Canon", "Canon EOS R5", "Canon EOS R5"),
            ("FUJIFILM", "X-T4", "Fujifilm X-T4"),
            ("OLYMPUS IMAGING CORP.", "E-M5", "Olympus E-M5"),
            ("LEICA CAMERA AG", "LEICA Q2", "Leica Q2"),
            ("samsung", "Galaxy S24 Ultra", "Samsung Galaxy S24 Ultra"),
            ("DJI", "FC3582", "DJI FC3582"),
            ("OM Digital Solutions", "OM-1", "OM Digital Solutions OM-1"),
            (nil, "X100V", "X100V"),
            ("Apple", nil, "Apple"),
            ("  ", " ", nil),
            (nil, nil, nil),
        ]
        for (make, model, expected) in cases {
            #expect(CameraSummary.displayName(make: make, model: model) == expected, "\(make ?? "nil") + \(model ?? "nil")")
        }
    }

    @Test func readsTheNewestPhotoAndTheRAWOfAPair() throws {
        let shots = [
            SourceShot(files: [file("DSC00001.ARW", .raw, at: "10:00:00", count: 4022),
                               file("DSC00001.JPG", .jpeg, at: "10:00:00")]),
            SourceShot(files: [file("DSC00002.ARW", .raw, at: "10:00:05", count: 4023),
                               file("DSC00002.JPG", .jpeg, at: "10:00:05")]),
            // Newer, but videos come after photos.
            SourceShot(files: [file("C0001.MP4", .video, at: "10:05:00")]),
            // Newer still, but names no camera (a screenshot copied onto the card).
            SourceShot(files: [file("Screenshot.PNG", .png, at: "11:00:00", make: nil, model: nil)]),
        ]
        let camera = try #require(CameraSummary(newestOf: shots.reversed()))
        #expect(camera == CameraSummary(name: "Sony ILCE-7M3", shutterCount: 4023, fileName: "DSC00002.ARW"))
    }

    @Test func fallsBackToVideosAndToNothing() {
        let video = SourceShot(files: [file("C0001.MP4", .video, at: "10:05:00")])
        #expect(CameraSummary(newestOf: [video])?.name == "Sony ILCE-7M3")
        #expect(CameraSummary(newestOf: [video])?.shutterCount == nil)
        let unnamed = SourceShot(files: [file("a.JPG", .jpeg, at: "10:00:00", make: nil, model: nil)])
        #expect(CameraSummary(newestOf: [unnamed]) == nil)
        #expect(CameraSummary(newestOf: []) == nil)
    }

    @Test func exifToolCountComesFromTheFirstNonZeroTag() {
        #expect(ExifToolMetadataReader.metadata(from: ["ShutterCount": 4023, "ShutterCount2": 4023]).shutterCount == 4023)
        #expect(ExifToolMetadataReader.metadata(from: ["ShutterCount": 0, "ShutterCount3": 12_345]).shutterCount == 12_345)
        #expect(ExifToolMetadataReader.metadata(from: ["Make": "Canon"]).shutterCount == nil)
    }
}
