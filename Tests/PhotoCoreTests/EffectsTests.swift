import CoreImage
import Foundation
import Testing
@testable import PhotoCore

@Suite("Adjustment groups")
struct AdjustmentGroupTests {
    private func edited() -> Adjustments {
        var adjustments = Adjustments()
        adjustments.exposure.ev = 0.5
        adjustments.presence.vibrance = 20
        adjustments.vignette = Vignette(amount: -40, size: 60, roundness: 20)
        adjustments.grain = Grain(strength: 80, shadows: 10, roughness: 70, color: 25, size: 1.5)
        return adjustments
    }

    @Test func effectsRoundTripAndLeaveOutDefaults() throws {
        let adjustments = edited()
        let stack = adjustments.editStack
        #expect(stack.operations.map(\.kind.rawValue) == ["exposure", "presence", "vignette", "grain"])
        #expect(stack.operations[2].parameters == ["amount": .number(-40), "size": .number(60), "roundness": .number(20)])
        #expect(stack.operations[3].parameters["midtones"] == nil)
        #expect(Adjustments(stack: try EditStack.decode(from: try stack.jsonData())) == adjustments)

        var table = Adjustments()
        table.lookTable = LookTable(identifier: String(repeating: "cd", count: 32), name: "X", colorSpace: .proPhoto)
        #expect(table.editStack.operations[0].parameters["colorSpace"] == .string("proPhoto"))
        #expect(Adjustments(stack: table.editStack).lookTable.colorSpace == .proPhoto)
        table.lookTable.colorSpace = .sRGB
        #expect(table.editStack.operations[0].parameters["colorSpace"] == nil)
    }

    @Test func turningAGroupOffKeepsItsValuesButNotItsPixels() throws {
        var adjustments = edited()
        adjustments.setEnabled(.light, false)
        #expect(!adjustments.isEnabled(.light))
        #expect(adjustments.isEnabled(.presence))
        #expect(adjustments.exposure.ev == 0.5)
        let stack = adjustments.editStack
        #expect(stack.operations.first { $0.kind == Exposure.kind }?.isEnabled == false)
        // The tone module is at its defaults, so nothing records it as off.
        #expect(adjustments.disabled == [Exposure.kind])

        let decoded = Adjustments(stack: try EditStack.decode(from: try stack.jsonData()))
        #expect(decoded == adjustments)
        #expect(decoded.preserved.isEmpty)
        #expect(decoded.effective.exposure.ev == 0)
        #expect(decoded.effective.presence.vibrance == 20)

        // Renders (and caches) the same as without the module.
        var without = edited()
        without.exposure = Exposure()
        #expect(stack.renderHash == without.editStack.renderHash)

        adjustments.setEnabled(.light, true)
        #expect(adjustments == edited())
    }

    @Test func editingAGroupThatIsOffTurnsItOn() {
        var adjustments = edited()
        adjustments.setEnabled(.grain, false)
        adjustments.setEnabled(.vignette, false)
        var next = adjustments
        next.grain.strength = 90
        next.enableModules(changedFrom: adjustments)
        #expect(next.isEnabled(.grain))
        #expect(!next.isEnabled(.vignette))
        // A group with nothing to turn off stays on.
        var empty = Adjustments()
        empty.setEnabled(.toneCurve, false)
        #expect(empty.isEnabled(.toneCurve))
        #expect(empty == .none)
    }

    @Test func resettingAHeadingClearsItsGroups() {
        var adjustments = edited()
        adjustments.lookTable = LookTable(identifier: String(repeating: "ab", count: 32), name: "Film")
        adjustments.colorGrade.midtones = GradeWheel(hue: 30, amount: 20)
        adjustments.setEnabled(.vignette, false)
        let reset = adjustments.resetting(.effects)
        #expect(reset.vignette == Vignette() && reset.grain == Grain() && reset.lookTable == LookTable())
        #expect(reset.disabled.isEmpty)
        #expect(reset.colorGrade == adjustments.colorGrade)
        #expect(adjustments.resetting(.colorGrading).lookTable == adjustments.lookTable)
        #expect(Adjustments.Section.allCases.flatMap(\.groups).count == Adjustments.Group.allCases.count)
    }

    @Test func grainAndLookTablesKeepRenditionsSDR() {
        var adjustments = Adjustments()
        adjustments.vignette.amount = -30
        #expect(adjustments.preservesExtendedRange)
        adjustments.grain.strength = 50
        #expect(!adjustments.preservesExtendedRange)
        adjustments.setEnabled(.grain, false)
        #expect(adjustments.preservesExtendedRange)
    }
}

@Suite("Effects rendering")
struct EffectsRenderingTests {
    let engine = RenderEngine()

    private func solid(_ value: Double, width: Int = 300, height: Int = 200) -> CIImage {
        CIImage(color: CIColor(red: value, green: value, blue: value, colorSpace: RenderEngine.workingColorSpace)!)
            .cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
    }

    /// Linear values of every pixel, row by row from the bottom.
    private func pixels(_ image: CIImage) -> [Float] {
        let extent = image.extent.integral
        var buffer = [Float](repeating: 0, count: Int(extent.width * extent.height) * 4)
        buffer.withUnsafeMutableBytes { bytes in
            engine.context.render(image, toBitmap: bytes.baseAddress!, rowBytes: Int(extent.width) * 16,
                                  bounds: extent, format: .RGBAf, colorSpace: RenderEngine.workingColorSpace)
        }
        return buffer
    }

    private func render(_ adjustments: Adjustments, _ image: CIImage) -> CIImage {
        AdjustmentRenderer().render(adjustments, to: image, context: RenderContext())
    }

    @Test func vignetteDarkensTheCornersNotTheCenter() {
        var adjustments = Adjustments()
        adjustments.vignette.amount = -100
        let image = solid(0.3)
        let out = pixels(render(adjustments, image))
        let width = 300
        let center = out[(100 * width + 150) * 4]
        let corner = out[(2 * width + 2) * 4]
        #expect(abs(center - 0.3) < 0.01)
        #expect(corner < 0.12)
        #expect(render(adjustments, image).extent == image.extent)

        adjustments.vignette.amount = 60
        #expect(pixels(render(adjustments, image))[(2 * width + 2) * 4] > 0.45)

        // A rectangular vignette darkens the middle of the edges more than an ellipse.
        adjustments.vignette = Vignette(amount: -100, size: 50, roundness: 0)
        let ellipse = pixels(render(adjustments, image))[(100 * width + 2) * 4]
        adjustments.vignette.roundness = -100
        let rectangle = pixels(render(adjustments, image))[(100 * width + 2) * 4]
        #expect(rectangle < ellipse)
    }

    @Test func grainAddsTextureAroundTheSameLevel() {
        var adjustments = Adjustments()
        adjustments.grain = Grain(strength: 100, shadows: 50, midtones: 50, highlights: 50)
        let image = solid(0.18, width: 2400, height: 1600)
        let out = pixels(render(adjustments, image))
        let reds = stride(from: 0, to: out.count, by: 4).map { Double(out[$0]) }
        let mean = reds.reduce(0, +) / Double(reds.count)
        let deviation = (reds.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(reds.count)).squareRoot()
        #expect(abs(mean - 0.18) < 0.01)
        #expect(deviation > 0.005, "\(deviation)")
        // Monochrome by default.
        #expect(abs(out[4000] - out[4001]) < 1e-4)
        // The same every time, so renders are reproducible.
        #expect(pixels(render(adjustments, image)) == out)

        adjustments.grain.color = 100
        let colored = pixels(render(adjustments, image))
        #expect(stride(from: 0, to: 4000, by: 4).contains { abs(colored[$0] - colored[$0 + 2]) > 1e-3 })

        // No highlight amount: white areas get no grain.
        adjustments.grain = Grain(strength: 100, shadows: 50, midtones: 50, highlights: 0)
        let white = pixels(render(adjustments, solid(1, width: 2400, height: 1600)))
        #expect(stride(from: 0, to: white.count, by: 4).allSatisfy { abs(white[$0] - 1) < 0.002 })
    }

    @Test func lookTablesFollowTheirColorSpace() throws {
        let lut = try CubeLUT(parsing: CubeLUTTests.swapCube(size: 17)).colorCube()
        let image = solid(0.2)
        let tinted = CIImage(color: CIColor(red: 0.6, green: 0.2, blue: 0.05, colorSpace: RenderEngine.workingColorSpace)!)
            .cropped(to: CGRect(x: 0, y: 0, width: 8, height: 8))
        let srgb = pixels(AdjustmentRenderer.lookTable(tinted, lut, intensity: 1, colorSpace: .sRGB))
        let proPhoto = pixels(AdjustmentRenderer.lookTable(tinted, lut, intensity: 1, colorSpace: .proPhoto))
        #expect(abs(srgb[0] - proPhoto[0]) > 0.01)
        // Grey stays grey in any space.
        let grey = pixels(AdjustmentRenderer.lookTable(image, lut, intensity: 1, colorSpace: .adobeRGB))
        #expect(abs(grey[0] - 0.2) < 0.01)
    }
}

@Suite("Look-up table library")
struct LookTableLibraryTests {
    @Test func namesComeFromHeadersThenFileNames() {
        #expect(LookTableNaming.descriptiveName(in: "TITLE \"Portra Soft\"\nLUT_3D_SIZE 2\n") == "Portra Soft")
        #expect(LookTableNaming.descriptiveName(in: "# Created with Some Tool v2\n# Title: Gold 200\nLUT_3D_SIZE 2\n")
            == "Gold 200")
        #expect(LookTableNaming.descriptiveName(in: "# Velvia Punch\nLUT_3D_SIZE 2\n0 0 0\n") == "Velvia Punch")
        #expect(LookTableNaming.descriptiveName(in: "# Generated by a converter\nLUT_3D_SIZE 2\n") == nil)
        #expect(LookTableNaming.descriptiveName(in: "LUT_3D_SIZE 2\n0 0 0\n# Name: too late\n") == nil)

        #expect(LookTableNaming.cleanedFileName("kodak_portra-160.cube") == "Kodak Portra 160")
        #expect(LookTableNaming.cleanedFileName("Matte_02_Warm.CUBE") == "Matte 02 Warm")
        #expect(LookTableNaming.removingCommonPrefix(["Film Pack 01 KP160", "Film Pack 01 FJ400", "Film Pack 01 TX"])
            == ["KP160", "FJ400", "TX"])
        #expect(LookTableNaming.removingCommonPrefix(["Warm", "Warm Strong"]) == ["Warm", "Warm Strong"])
        #expect(LookTableNaming.removingCommonPrefix(["Pack One blue hour", "Pack One Gold"]) == ["Blue Hour", "Gold"])
        #expect(LookTableNaming.removingCommonPrefix(["Only One"]) == ["Only One"])
    }

    @Test func builtInTablesAreReadableAndInstallOnDemand() async throws {
        #expect(BuiltInLookTables.all.count >= 6)
        #expect(Set(BuiltInLookTables.all.map(\.identifier)).count == BuiltInLookTables.all.count)
        for table in BuiltInLookTables.all {
            let lut = try CubeLUT(parsing: String(decoding: table.data, as: UTF8.self))
            #expect(lut.size == BuiltInLookTables.dimension)
        }
        #expect(BuiltInLookTables.fixed(0.5) == "0.500000")
        #expect(BuiltInLookTables.fixed(1.2) == "1.000000")
        try await RepositoryFiles.withTemporaryDirectory { root in
            let store = LookTableStore(directory: root.appending(path: "LUTs"))
            let mono = try #require(BuiltInLookTables.all.first { $0.key == "mono" })
            #expect(!store.contains(mono.identifier))
            #expect(store.cube(for: mono.identifier)?.dimension == BuiltInLookTables.dimension)
            #expect(store.contains(mono.identifier))
        }
    }

    @Test func importsAFolderIntoCollections() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let folder = root.appending(path: "Pack")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try CubeLUTTests.swapCube().write(to: folder.appending(path: "Pack_One_Swap.cube"), atomically: true,
                                              encoding: .utf8)
            try CubeLUTTests.identityCube(size: 2, title: "Clean").write(
                to: folder.appending(path: "Pack_One_Identity.cube"), atomically: true, encoding: .utf8)
            try "nonsense".write(to: folder.appending(path: "Pack_One_Broken.cube"), atomically: true, encoding: .utf8)

            let candidates = LookTableImport.candidates(in: folder)
            #expect(candidates.map(\.name) == ["Broken", "Clean", "Swap"])
            #expect(candidates[0].failure != nil)

            let catalog = try Catalog.makeInMemory()
            let store = LookTableStore(directory: root.appending(path: "Library/LUTs"))
            let result = try await LookTableImport.run(candidates, into: .new("Pack One"), colorSpace: .adobeRGB,
                                                       store: store, catalog: catalog)
            #expect(result.added == 2)
            var collections = try await catalog.lookTableCollections()
            #expect(collections.map(\.name) == ["Pack One"])
            #expect(collections[0].entries.map(\.name) == ["Clean", "Swap"])
            #expect(collections[0].entries.allSatisfy { $0.colorSpace == .adobeRGB && store.contains($0.identifier) })

            // Again into the same collection: nothing new.
            let again = try await LookTableImport.run(candidates, into: .existing(result.collectionID),
                                                      colorSpace: .sRGB, store: store, catalog: catalog)
            #expect(again.added == 0)
            await #expect(throws: LookTableImport.Failure.nothingToImport) {
                try await LookTableImport.run([candidates[0]], into: .new("Empty"), colorSpace: .sRGB,
                                              store: store, catalog: catalog)
            }
            #expect(try await catalog.lookTableCollections().count == 1)

            let entryID = try #require(collections[0].entries[1].rowID)
            try await catalog.renameLookTableEntry(id: entryID, to: "Red Blue")
            try await catalog.setLookTableColorSpace(.sRGB, forEntry: entryID)
            try await catalog.renameLookTableCollection(id: result.collectionID, to: "Renamed")
            collections = try await catalog.lookTableCollections()
            #expect(collections[0].name == "Renamed")
            #expect(collections[0].entries[1].name == "Red Blue" && collections[0].entries[1].colorSpace == .sRGB)

            let firstID = try #require(collections[0].entries[0].rowID)
            try await catalog.deleteLookTableEntry(id: firstID)
            #expect(try await catalog.lookTableCollections()[0].entries.count == 1)
            try await catalog.deleteLookTableCollection(id: result.collectionID)
            #expect(try await catalog.lookTableCollections().isEmpty)
            let leftovers = try await catalog.database.read { db in
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM lookTableEntry")
            }
            #expect(leftovers == 0)
            // The files stay for edits that use them.
            #expect(store.contains(collections[0].entries[1].identifier))
        }
    }
}
