import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import PhotoCore

/// Issue #88: detection components in the stack (R2, R3, R5, R8, R12) and the
/// stored raster's encoding (R5).
@Suite("Detection masks: model")
struct DetectionMaskModelTests {
    static let digestA = String(repeating: "a1", count: 32)
    static let digestB = String(repeating: "b2", count: 32)

    static func masks(_ components: [MaskComponent], exposure: Double = 0.3) -> Adjustments {
        var values = LocalValues()
        values.exposure = exposure
        var adjustments = Adjustments()
        adjustments.local.masks = [Mask(id: MaskModelTests.ids[0], name: "Subject", components: components,
                                        adjustments: values)]
        return adjustments
    }

    @Test("Each kind round-trips through the stack with its digest and no pixels; a failed one has no digest")
    func roundTrip() throws {
        let adjustments = Self.masks([
            MaskComponent(.detection(MaskDetection(kind: .subject, raster: Self.digestA))),
            MaskComponent(.detection(MaskDetection(kind: .people, raster: Self.digestB)), operation: .subtract),
            MaskComponent(.detection(MaskDetection(kind: .background, raster: Self.digestA)), operation: .intersect,
                          invert: true),
            MaskComponent(.detection(MaskDetection(kind: .people)), operation: .add),
        ])
        let json = try MaskModelTests.fixed(adjustments.editStack).jsonString()
        #expect(json.contains(#"{"raster":"\#(Self.digestA)","shape":"subject"}"#))
        #expect(json.contains(#"{"operation":"subtract","raster":"\#(Self.digestB)","shape":"people"}"#))
        #expect(json.contains(#"{"invert":true,"operation":"intersect","raster":"\#(Self.digestA)","shape":"background"}"#))
        #expect(json.contains(#"{"shape":"people"}"#), "a failed detection holds its kind and no digest")
        let decoded = try EditStack.decode(from: json)
        #expect(Adjustments(stack: decoded) == adjustments)
        #expect(adjustments.local.maskRasterDigests == [Self.digestA, Self.digestB])
        // Kind and digest only: about 150 bytes a component (status.md §5).
        #expect(json.utf8.count < 1_000)
    }

    @Test("A digest that is not one, or an unknown key, makes the stack unreadable (R12)",
          arguments: [
            #"[{"id":"00000000-0000-4000-8000-000000000001","components":[{"shape":"subject","raster":"abc"}]}]"#,
            #"[{"id":"00000000-0000-4000-8000-000000000001","components":[{"shape":"people","raster":"\#(String(repeating: "A1", count: 32))"}]}]"#,
            #"[{"id":"00000000-0000-4000-8000-000000000001","components":[{"shape":"people","raster":12}]}]"#,
            #"[{"id":"00000000-0000-4000-8000-000000000001","components":[{"shape":"subject","confidence":0.9}]}]"#,
            #"[{"id":"00000000-0000-4000-8000-000000000001","components":[{"shape":"background","feather":10}]}]"#,
          ])
    func strictReading(masks: String) {
        do {
            _ = try EditStack.decode(from: MaskModelTests.stack(masks: masks))
            Issue.record("read a stack it should refuse")
        } catch {
            #expect(EditStack.ReadFailure(error) == .damaged)
        }
    }

    @Test("A stack with a detection this build can't read is never written over (AC12)")
    func unreadableIsNotOverwritten() async throws {
        let json = MaskModelTests.stack(masks: #"[{"id":"00000000-0000-4000-8000-000000000001","components":[{"shape":"subject","raster":"zz"}]}]"#)
        let fixture = try await CatalogFixture.make()
        let id = try #require(try await fixture.addMasters([CatalogFixture.master(1)]).first)
        try await UnreadableStackTests.store(json, forVersion: id, in: fixture.catalog)
        await #expect(throws: UnreadableEditStacks.self) {
            try await fixture.catalog.setEditStack(Self.masks([]).editStack, forVersion: id, historyLabel: "Test")
        }
        #expect(try await UnreadableStackTests.stored(id, in: fixture.catalog).json == json)
    }

    @Test("A changed digest changes the render hash; the same digest keeps it (AC4)")
    func renderHashFollowsTheDigest() {
        let a = Self.masks([MaskComponent(.detection(MaskDetection(kind: .subject, raster: Self.digestA)))])
        let b = Self.masks([MaskComponent(.detection(MaskDetection(kind: .subject, raster: Self.digestB)))])
        let again = Self.masks([MaskComponent(.detection(MaskDetection(kind: .subject, raster: Self.digestA)))])
        #expect(a.editStack.renderHash != b.editStack.renderHash)
        #expect(a.editStack.renderHash == again.editStack.renderHash)
    }

    @Test("Paste and presets omit detection components (AC8)")
    func pasteAndPresetsOmitDetections() {
        var source = Self.masks([MaskComponent(.detection(MaskDetection(kind: .people, raster: Self.digestA)))])
        source.exposure.ev = 0.4
        var target = Adjustments()
        target.local.masks = [Mask(id: MaskModelTests.ids[5], name: "Mine")]
        #expect(source.pasted(onto: target).local == target.local)
        #expect(source.pasted(onto: target).exposure.ev == 0.4)
        let preset = AdjustmentPreset(name: "all", adjustments: source)
        #expect(preset.adjustments.local.isIdentity)
        #expect(preset.applied(onto: target).local == target.local)
    }

    @Test("Detection kinds use the request of their result; Background turns Subject's around")
    func kinds() {
        #expect(MaskDetectionKind.subject.request == .foreground)
        #expect(MaskDetectionKind.background.request == .foreground)
        #expect(MaskDetectionKind.people.request == .person)
        #expect(MaskDetectionKind.allCases.filter(\.isInverted) == [.background])
        #expect(MaskShape.names.suffix(3) == ["subject", "people", "background"])
    }

    // MARK: The stored raster

    @Test("A raster is an 8-bit gray PNG named by the SHA-256 of its bytes, read back exactly")
    func rasterRoundTrip() throws {
        let levels = (0..<(7 * 5)).map { UInt8(($0 * 37) % 256) }
        let raster = try MaskRaster(levels: levels, width: 7, height: 5, instances: 2, request: .person)
        #expect(raster.digest == Digest.sha256Hex(raster.png))
        #expect(MaskRaster.isDigest(raster.digest))
        let pixels = try MaskRaster.pixels(fromPNG: raster.png)
        #expect(pixels == MaskRaster.Pixels(width: 7, height: 5, levels: levels))
        // The same pixels give the same bytes in one build, so the same row.
        #expect(try MaskRaster(levels: levels, width: 7, height: 5, instances: 2, request: .person).digest == raster.digest)
    }

    @Test("An empty result is one black pixel with no instances, shared by every empty result")
    func emptyRaster() throws {
        let empty = MaskRaster.empty(.foreground)
        #expect(empty.instances == 0 && empty.width == 1 && empty.height == 1)
        #expect(try MaskRaster.pixels(fromPNG: empty.png).levels == [0])
        #expect(MaskRaster.empty(.person).digest == empty.digest)
    }

    @Test("Sizes outside the limits are refused")
    func rasterSizes() {
        #expect(throws: MaskRaster.Failure.invalidSize) {
            try MaskRaster(levels: [], width: 0, height: 0, instances: 0, request: .foreground)
        }
        #expect(throws: MaskRaster.Failure.invalidSize) {
            try MaskRaster(levels: [0, 0], width: 3, height: 1, instances: 0, request: .foreground)
        }
        #expect(throws: MaskRaster.Failure.invalidSize) {
            try MaskRaster(levels: [UInt8](repeating: 0, count: 4097), width: 4097, height: 1, instances: 0,
                           request: .foreground)
        }
    }

    @Test("Bytes that are not an 8-bit gray PNG are damaged")
    func damagedRaster() throws {
        #expect(throws: MaskRaster.Failure.unreadable) { try MaskRaster.pixels(fromPNG: Data("not a png".utf8)) }
        let raster = try MaskRaster(levels: [10, 20, 30, 40], width: 2, height: 2, instances: 1, request: .foreground)
        #expect(throws: MaskRaster.Failure.unreadable) { try MaskRaster.pixels(fromPNG: raster.png.prefix(20)) }
        // An RGB PNG of the same size is not what the build writes.
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = try #require(CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8,
                                             space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        #expect(throws: MaskRaster.Failure.unreadable) { try MaskRaster.pixels(fromPNG: data as Data) }
    }
}
