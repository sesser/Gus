import CoreGraphics
import Foundation
import Testing
@testable import PhotoCore

/// The merge sheet's frames, reference and refusals (issue #150; design §5, §6).
@Suite("HDR merge selection")
struct MergeSelectionTests {
    static func frame(_ id: Int64, _ name: String, kind: FileKind = .raw, image: Int64? = nil, copy: Bool = false,
                      online: Bool = true, size: CGSize? = CGSize(width: 600, height: 400), second: Double,
                      compensation: Double? = nil, time: Double? = 1.0 / 60, folder: String = "/shoot") -> MergeFrame {
        let ext = kind == .raw ? "dng" : kind == .video ? "mov" : "jpg"
        return MergeFrame(versionID: id, imageID: image ?? id, volumeID: 1, projectID: 1,
                          displayName: copy ? name + " copy" : name, fileName: name + "." + ext,
                          relativePath: "shoot/\(name).\(ext)", kind: kind, isCopy: copy, isOnline: online,
                          url: URL(fileURLWithPath: folder).appending(path: name + "." + ext), pixelSize: size,
                          date: Date(timeIntervalSinceReferenceDate: second), exposureTime: time,
                          exposureCompensation: compensation, fNumber: 8, iso: 200)
    }

    @Test("Frames are in capture order and the 0 EV frame is the reference, wherever it is in time")
    func orderAndReference() {
        let selection = MergeSelection(frames: [
            Self.frame(1, "B", second: 2, compensation: 0), Self.frame(2, "A", second: 1, compensation: -2),
            Self.frame(3, "C", second: 3, compensation: 2),
        ])
        #expect(selection.frames.map(\.displayName) == ["A", "B", "C"])
        #expect(selection.referenceFrame.displayName == "B")
        #expect(selection.refusal == nil)
        #expect(!selection.sameExposure)
    }

    @Test("With no compensation, or the same on every frame, the earliest frame is the reference")
    func earliestWithoutCompensation() {
        let none = MergeSelection(frames: [Self.frame(1, "B", second: 2), Self.frame(2, "A", second: 1)])
        #expect(none.referenceFrame.displayName == "A")
        let allZero = MergeSelection(frames: [Self.frame(1, "B", second: 2, compensation: 0),
                                              Self.frame(2, "A", second: 1, compensation: 0)])
        #expect(allZero.referenceFrame.displayName == "A")
    }

    @Test("The same exposure on every frame is a note, not a refusal")
    func sameExposureNote() {
        let selection = MergeSelection(frames: [Self.frame(1, "A", second: 1, compensation: 0),
                                                Self.frame(2, "B", second: 2, compensation: 0)])
        #expect(selection.sameExposure)
        #expect(selection.refusal == nil)
        let unknown = MergeSelection(frames: [Self.frame(1, "A", second: 1, time: nil), Self.frame(2, "B", second: 2, time: nil)])
        #expect(!unknown.sameExposure)
    }

    @Test("Refusal 1: the two files of one pair are one frame")
    func tooFew() {
        let selection = MergeSelection(frames: [Self.frame(1, "A", second: 1)])
        #expect(selection.refusal == .tooFew)
        #expect(selection.flagged == [1])
    }

    @Test("Refusal 2: more than nine frames flags the tenth onward")
    func tooMany() {
        let frames = (1...11).map { Self.frame(Int64($0), "F\($0)", second: Double($0)) }
        let selection = MergeSelection(frames: frames)
        #expect(selection.refusal == .tooMany(limit: 9))
        #expect(selection.flagged == [10, 11])
    }

    @Test("Refusal 3: a video among the photos, named")
    func video() {
        let selection = MergeSelection(frames: [Self.frame(1, "A", second: 1), Self.frame(2, "Clip", kind: .video, second: 2),
                                                Self.frame(3, "C", second: 3)])
        #expect(selection.refusal == .video(name: "Clip"))
        #expect(selection.flagged == [2])
    }

    @Test("Refusal 4: a copy beside its own original, named with it")
    func copyOfOriginal() {
        let selection = MergeSelection(frames: [Self.frame(1, "A", second: 1), Self.frame(2, "A", image: 1, copy: true, second: 1),
                                                Self.frame(3, "C", second: 3)])
        #expect(selection.refusal == .sameFile(copy: "A copy", original: "A"))
        #expect(selection.flagged == [2])
    }

    @Test("A copy selected without its original is a frame like any other")
    func copyAlone() {
        let selection = MergeSelection(frames: [Self.frame(2, "A", image: 1, copy: true, second: 1),
                                                Self.frame(3, "C", second: 3)])
        #expect(selection.refusal == nil)
    }

    @Test("Refusal 5: raws and non-raws, flagging the minority")
    func mixed() {
        let selection = MergeSelection(frames: [Self.frame(1, "A", second: 1), Self.frame(2, "B", kind: .jpeg, second: 2),
                                                Self.frame(3, "C", second: 3)])
        #expect(selection.refusal == .mixedKinds)
        #expect(selection.flagged == [2])
        let mostlyJPEG = MergeSelection(frames: [Self.frame(1, "A", second: 1), Self.frame(2, "B", kind: .jpeg, second: 2),
                                                 Self.frame(3, "C", kind: .jpeg, second: 3)])
        #expect(mostlyJPEG.flagged == [1])
    }

    @Test("Refusal 6: a frame of another size than the reference, named with it")
    func differentSize() {
        let selection = MergeSelection(frames: [Self.frame(1, "A", second: 1, compensation: 0),
                                                Self.frame(2, "B", size: CGSize(width: 400, height: 600), second: 2,
                                                           compensation: 1)])
        #expect(selection.refusal == .differentSize(name: "B", reference: "A"))
        #expect(selection.flagged == [2])
    }

    @Test("Refusal 7: offline frames, the first named and all counted")
    func offline() {
        let selection = MergeSelection(frames: [Self.frame(1, "A", online: false, second: 1), Self.frame(2, "B", second: 2),
                                                Self.frame(3, "C", online: false, second: 3)])
        #expect(selection.refusal == .offline(name: "A", count: 2))
        #expect(selection.flagged == [1, 3])
    }

    @Test("Refusals come in order: count and kind before content and availability")
    func order() {
        let selection = MergeSelection(frames: [Self.frame(1, "A", online: false, second: 1),
                                                Self.frame(2, "Clip", kind: .video, second: 2),
                                                Self.frame(3, "C", kind: .jpeg, second: 3)])
        #expect(selection.refusal == .video(name: "Clip"))
    }

    @Test("Refusals from the disk: an unreadable master, then an unwritable folder")
    func preflight() {
        let selection = MergeSelection(frames: [Self.frame(1, "A", second: 1, compensation: 0),
                                                Self.frame(2, "B", second: 2, compensation: 1)])
        let unreadable = MergePreflight(isReadable: { !$0.lastPathComponent.hasPrefix("B") }, isWritableFolder: { _ in false })
        #expect(unreadable.check(selection)?.refusal == .unreadable(name: "B"))
        #expect(unreadable.check(selection)?.flagged == 2)
        let readOnly = MergePreflight(isReadable: { _ in true }, isWritableFolder: { _ in false })
        #expect(readOnly.check(selection)?.refusal == .unwritableFolder(reference: "A", folder: "shoot"))
        #expect(readOnly.check(selection)?.flagged == 1)
        let fine = MergePreflight(isReadable: { _ in true }, isWritableFolder: { _ in true })
        #expect(fine.check(selection) == nil)
    }

    @Test("The result's name: the reference's stem, _HDR, numbered past files and masters")
    func naming() {
        let selection = MergeSelection(frames: [Self.frame(1, "IMG_1233", second: 1, compensation: -2),
                                                Self.frame(2, "IMG_1234", second: 2, compensation: 0)])
        let none = MasterFiles.none.names(in: URL(fileURLWithPath: "/shoot"))
        #expect(selection.resultName(format: .tiff, masters: none, files: []) == "IMG_1234_HDR.tif")
        #expect(selection.resultName(format: .dng, masters: none, files: []) == "IMG_1234_HDR.dng")
        #expect(selection.resultName(format: .tiff, masters: none, files: ["IMG_1234_HDR.tif"]) == "IMG_1234_HDR-2.tif")
        // A master whose file is gone still owns its name.
        let masters = MasterFiles([URL(fileURLWithPath: "/shoot/IMG_1234_HDR.tif"),
                                   URL(fileURLWithPath: "/shoot/IMG_1234_HDR-2.tif")])
        #expect(selection.resultName(format: .tiff, masters: masters.names(in: URL(fileURLWithPath: "/shoot")),
                                     files: []) == "IMG_1234_HDR-3.tif")
    }

    @Test("C3: a file of the same stem in any format, or its sidecar, numbers the result")
    func numbersPastTheStem() {
        let selection = MergeSelection(frames: [Self.frame(1, "IMG_1233", second: 1, compensation: -2),
                                                Self.frame(2, "IMG_1234", second: 2, compensation: 0)])
        let none = MasterFiles.none.names(in: URL(fileURLWithPath: "/shoot"))
        // A DNG after a TIFF merge, compared as the file system compares names.
        #expect(selection.resultName(format: .dng, masters: none, files: ["img_1234_hdr.TIF"]) == "IMG_1234_HDR-2.dng")
        #expect(selection.resultName(format: .tiff, masters: none, files: ["IMG_1234_HDR.xmp"]) == "IMG_1234_HDR-2.tif")
        #expect(selection.resultName(format: .dng, masters: none,
                                     files: ["IMG_1234_HDR.tif", "IMG_1234_HDR-2.dng", "IMG_1234_HDR-2.xmp"])
                == "IMG_1234_HDR-3.dng")
        // A master of that stem whose file is gone.
        let masters = MasterFiles([URL(fileURLWithPath: "/shoot/IMG_1234_HDR.tif")])
        #expect(selection.resultName(format: .dng, masters: masters.names(in: URL(fileURLWithPath: "/shoot")),
                                     files: []) == "IMG_1234_HDR-2.dng")
        // Other stems don't count.
        #expect(selection.resultName(format: .dng, masters: none, files: ["IMG_1234.dng", "IMG_1234_HDRX.tif"])
                == "IMG_1234_HDR.dng")
    }
}

/// The header's thumbnail follows the reference (design §5.1, §5.8; review F8).
@Suite("HDR merge header thumbnail")
struct MergePreviewItemTests {
    private func item(_ id: Int64, _ path: String, partner: Int64? = nil, partnerKind: FileKind? = nil) -> CatalogItem {
        var item = CatalogItem(versionID: id, imageID: id, volumeID: 1, rating: .unrated, flag: .none, colorLabel: .none,
                               contentHash: "", editStackHash: "", relativePath: path, pixelWidth: 10, pixelHeight: 10,
                               orientation: 1)
        item.partnerVersionID = partner
        item.partnerKind = partnerKind
        item.representsPair = partner != nil
        return item
    }

    @Test("Pairs shown as their JPEG: the reference's pair item, not the first")
    func pairsShownAsJPEG() {
        // RAWs 1, 2, 3 are the frames; the grid shows JPEGs 11, 12, 13.
        let items = [item(11, "a/IMG_1.jpg", partner: 1, partnerKind: .raw),
                     item(12, "a/IMG_2.jpg", partner: 2, partnerKind: .raw),
                     item(13, "a/IMG_3.jpg", partner: 3, partnerKind: .raw)]
        #expect(MergeSelection.versionIDs(for: items) == [1, 2, 3])
        #expect(MergeSelection.item(showing: 2, in: items)?.versionID == 12)
        #expect(MergeSelection.item(showing: 3, in: items)?.versionID == 13)
    }

    @Test("Pairs shown as their RAW and single files: the frame's own item")
    func ownItem() {
        let items = [item(1, "a/IMG_1.dng", partner: 11, partnerKind: .jpeg), item(2, "a/IMG_2.dng"),
                     item(3, "a/IMG_3.jpg")]
        #expect(MergeSelection.item(showing: 1, in: items)?.versionID == 1)
        #expect(MergeSelection.item(showing: 3, in: items)?.versionID == 3)
        // An unknown reference: the first item, as before.
        #expect(MergeSelection.item(showing: 99, in: items)?.versionID == 1)
        #expect(MergeSelection.item(showing: 1, in: []) == nil)
    }
}
