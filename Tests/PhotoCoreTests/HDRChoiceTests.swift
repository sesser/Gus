import Foundation
import PhotoFixtures
import Testing
@testable import PhotoCore

/// Issue #282: the per-photo HDR choice, stored in the edit stack (R1 to R3,
/// R12, R17). The loupe's use of it is checked by the debug script.
@Suite("HDR choice (issue #282)")
struct HDRChoiceTests {
    private static func on(_ values: Adjustments = Adjustments()) -> Adjustments {
        var values = values
        values.hdr.isOn = true
        return values
    }

    private static func exposure(_ ev: Double) -> Adjustments {
        var values = Adjustments()
        values.exposure.ev = ev
        return values
    }

    // MARK: The stack

    @Test("Off is the default and leaves no operation; on is one `hdr` operation, read back")
    func storedAsOneOperation() throws {
        #expect(Adjustments().editStack == .identity)
        let stack = Self.on().editStack
        #expect(stack.operations.count == 1)
        let operation = try #require(stack.operations.first)
        #expect(operation.kind.rawValue == "hdr" && operation.kindVersion == 1 && operation.isEnabled)
        #expect(operation.parameters == ["on": .bool(true)])
        #expect(stack.schemaVersion == 1)
        let read = try EditStack.decode(from: stack.jsonData())
        #expect(Adjustments(stack: read).hdr.isOn && read.hdrChoice)
        #expect(!EditStack.identity.hdrChoice)
    }

    @Test("Code review C4: a turned-off `hdr` operation reads as off in the editor's values and the catalog's copy alike")
    func turnedOffOperationIsOff() throws {
        let written = EditStack(operations: [EditOperation(kind: HDRChoice.kind, isEnabled: false,
                                                           parameters: ["on": .bool(true)])])
        let stack = try EditStack.decode(from: written.jsonData())
        var values = Adjustments(stack: stack)
        #expect(!stack.hdrChoice)
        #expect(!values.hdrIsOn)
        // Kept as it was until the choice is set: written back unchanged.
        #expect(values.editStack.hasSameContent(as: stack))
        // Turning it on turns the operation on; both readings agree again.
        values.hdrIsOn = true
        #expect(values.hdrIsOn && values.editStack.hdrChoice)
        #expect(values.editStack.hasSameContent(as: Self.on().editStack))
        values.hdrIsOn = false
        #expect(values.editStack == .identity)
        // Show Original keeps the choice as it applies (`AdjustmentEditor.originalValues`).
        var original = Adjustments.none
        original.hdrIsOn = Adjustments(stack: stack).hdrIsOn
        #expect(!original.hdrIsOn)
    }

    @Test("R12: the choice is not in the render hash, so SDR previews are the same with it on or off")
    func notInRenderHash() {
        #expect(Self.on().editStack.renderHash == EditStack.identity.renderHash)
        #expect(Self.on().editStack.isIdentity)
        let edited = Self.exposure(1)
        #expect(Self.on(edited).editStack.renderHash == edited.editStack.renderHash)
        // The stacks still differ: history and undo see the change.
        #expect(!Self.on(edited).editStack.hasSameContent(as: edited.editStack))
    }

    @Test("R2: Reset All turns it off; resetting a heading leaves it; it counts as an edit")
    func resetAll() {
        let values = Self.on(Self.exposure(1))
        #expect(!values.resettingAll().hdr.isOn)
        #expect(values.resettingAll().isDefault)
        for section in Adjustments.Section.allCases {
            #expect(values.resetting(section).hdr.isOn)
        }
        #expect(!Self.on().isDefault)
        // It enables nothing that counts groups (Save as Preset, Copy Adjustments' defaults).
        #expect(Self.on().modifiedGroups.isEmpty)
    }

    @Test("AC3: presets and Paste Adjustments neither carry nor change the choice")
    func presetsAndPasteKeepTheTargets() {
        let hdrSource = Self.on(Self.exposure(1))
        let sdrSource = Self.exposure(-1)
        let sdrTarget = Adjustments()
        let hdrTarget = Self.on()
        let groups = Set(Adjustments.Group.presetGroups)
        #expect(!sdrTarget.replacing(groups, from: hdrSource).hdr.isOn)
        #expect(hdrTarget.replacing(groups, from: sdrSource).hdr.isOn)
        for items in [Set(CopyItem.all), Set([CopyItem.group(.light)])] {
            #expect(!CopiedAdjustments(hdrSource, items: items).pasted(onto: sdrTarget).hdr.isOn)
            #expect(CopiedAdjustments(sdrSource, items: items).pasted(onto: hdrTarget).hdr.isOn)
        }
        #expect(sdrTarget.replacing(groups, from: hdrSource).exposure.ev == 1)
    }

    @Test("R17: scripts see the module and its one parameter; set and reset work as for other edits")
    func scriptable() throws {
        let module = try #require(Adjustments.moduleDescription(HDRChoice.kind))
        #expect(module.group == nil && module.parameters.map(\.name) == ["on"])
        let on = try EditStack.identity.applying([.set(kind: HDRChoice.kind, parameter: "on", value: "true")])
        #expect(on.hdrChoice)
        let reset = try on.applying([.reset(kind: HDRChoice.kind, parameter: nil)])
        #expect(!reset.hdrChoice)
        let off = try on.applying([.set(kind: HDRChoice.kind, parameter: "on", value: "false")])
        #expect(!off.hdrChoice)
    }

    // MARK: The catalog

    @Test("R2: the catalog keeps the choice with the stack; items carry it; History snapshots restore it")
    func catalogColumnAndHistory() async throws {
        let fixture = try await CatalogFixture.make()
        let ids = try await fixture.addMasters([CatalogFixture.master(1), CatalogFixture.master(2)])
        let catalog = fixture.catalog
        try await catalog.setEditStack(Self.exposure(1).editStack, forVersion: ids[0], historyLabel: "Exposure")
        try await catalog.setEditStack(Self.on(Self.exposure(1)).editStack, forVersion: ids[0],
                                       historyLabel: "Turn On HDR")
        var items = try await catalog.libraryItems(versionIDs: ids)
        #expect(items.first { $0.versionID == ids[0] }?.hdr == true)
        #expect(items.first { $0.versionID == ids[1] }?.hdr == false)
        // The render hash is the one without the choice.
        #expect(items.first { $0.versionID == ids[0] }?.editStackHash == Self.exposure(1).editStack.renderHash)

        // History: the entry before Turn On HDR has the choice off (Q3).
        let entries = try await catalog.editHistory(forVersion: ids[0])
        #expect(entries.map(\.label) == ["Turn On HDR", "Exposure"])
        let older = try #require(try await catalog.editHistoryStack(entryID: entries[1].id, forVersion: ids[0]))
        #expect(!older.hdrChoice)
        try await catalog.setEditStack(older, forVersion: ids[0], historyLabel: "Revert")
        items = try await catalog.libraryItems(versionIDs: [ids[0]])
        #expect(items.first?.hdr == false)
    }

    @Test("R2: a virtual copy starts with the original's choice and is independent")
    func virtualCopy() async throws {
        let fixture = try await CatalogFixture.make()
        let id = try #require(try await fixture.addMasters([CatalogFixture.master(1)]).first)
        let catalog = fixture.catalog
        try await catalog.setEditStack(Self.on().editStack, forVersion: id, historyLabel: "Turn On HDR")
        let copy = try await catalog.duplicateVersion(id: id)
        let copyID = try #require(copy.id)
        #expect(try copy.decodedEditStack().hdrChoice)
        #expect(try await catalog.libraryItems(versionIDs: [copyID]).first?.hdr == true)
        // Undo and redo of Duplicate take the copy out and put it back with its choice.
        let removed = try await catalog.removeCopies(versionIDs: [copyID])
        try await catalog.restoreCopies(removed)
        #expect(try await catalog.libraryItems(versionIDs: [copyID]).first?.hdr == true)
        try await catalog.setEditStack(.identity, forVersion: copyID, historyLabel: "Turn Off HDR")
        let items = try await catalog.libraryItems(versionIDs: [id, copyID])
        #expect(items.first { $0.versionID == id }?.hdr == true)
        #expect(items.first { $0.versionID == copyID }?.hdr == false)
    }

    @Test("A batch change (paste, a preset, Reset All from the grid) keeps the column in step with each stack")
    func batchKeepsTheColumn() async throws {
        let fixture = try await CatalogFixture.make()
        let ids = try await fixture.addMasters([CatalogFixture.master(1), CatalogFixture.master(2)])
        let catalog = fixture.catalog
        try await catalog.setEditStacks([ids[0]: Self.on().editStack, ids[1]: Self.on().editStack],
                                        historyLabel: "Turn On HDR")
        _ = try await catalog.changeEditStacks(ofVersions: ids, historyLabel: "Apply Preset") {
            $0.replacing(Set(Adjustments.Group.presetGroups), from: Self.exposure(2))
        }
        #expect(try await catalog.libraryItems(versionIDs: ids).allSatisfy(\.hdr))
        _ = try await catalog.changeEditStacks(ofVersions: ids, historyLabel: "Reset Adjustments") { $0.resettingAll() }
        #expect(try await catalog.libraryItems(versionIDs: ids).allSatisfy { !$0.hdr })
    }

    // MARK: The version badge (R4, R5, design §4, §5)

    private static func badge(hasGainMap: Bool = true, choice: Bool = true, offline: Bool = false,
                              viewSetting: Bool = true, extendedRange: Bool = true, failed: Bool = false,
                              shown: ShownVersion? = .hdr, isMap: Bool = false,
                              file: Float? = 3.7, allowed: Float? = nil) -> HDRVersionBadge {
        HDRVersionBadge(hasGainMap: hasGainMap, choice: choice, offline: offline, viewSetting: viewSetting,
                        extendedRange: extendedRange, failed: failed, shown: shown, isMap: isMap,
                        fileHeadroom: file, allowedNow: allowed)
    }

    @Test("AC4: the badge says the version and the first reason HDR isn't shown, in the design's order")
    func badgeReasons() {
        #expect(Self.badge() == .hdr(fileHeadroom: 3.7, allowedNow: nil))
        #expect(Self.badge(shown: .sdr) == .loading)
        #expect(Self.badge(shown: nil) == .loading)
        #expect(Self.badge(choice: false, shown: .sdr) == .sdr(offline: false))
        // RI-3: offline with the choice off, SDR only when the file is known to have a gain map.
        #expect(Self.badge(hasGainMap: false, choice: false, offline: true) == .none)
        // Design §19.1: its help tag can't name Turn On HDR, dimmed while offline.
        #expect(Self.badge(choice: false, offline: true) == .sdr(offline: true))
        #expect(Self.badge(choice: false, offline: true).name == "sdr cached")
        // A file without a gain map has no badge; a map shows none (RI-4).
        #expect(Self.badge(hasGainMap: false, choice: false) == .none)
        #expect(Self.badge(isMap: true) == .none)
        // First match wins.
        #expect(Self.badge(offline: true, viewSetting: false, extendedRange: false, failed: true) == .blocked(.offline))
        #expect(Self.badge(viewSetting: false, extendedRange: false, failed: true) == .blocked(.hidden))
        #expect(Self.badge(extendedRange: false, failed: true) == .blocked(.noHDRDisplay))
        #expect(Self.badge(failed: true) == .blocked(.failed))
    }

    @Test("RI-7, design §18.2: a low allowance is HDR, fitted, never a reason; fitted compares at one decimal")
    func badgeFitted() {
        #expect(Self.badge(allowed: 1.29).isFitted)
        #expect(Self.badge(allowed: 1.0) == .hdr(fileHeadroom: 3.7, allowedNow: 1.0))
        #expect(Self.badge(allowed: 1.0).isFitted)
        #expect(!Self.badge(allowed: 3.74).isFitted)
        #expect(!Self.badge(file: 2.62, allowed: 2.6).isFitted)
        #expect(!Self.badge(allowed: nil).isFitted)
        #expect(Self.badge(allowed: 1.29).name == "hdr fitted")
        #expect(Self.badge(failed: true).name == "sdr failed")
    }

    @Test("AC12: the export notice counts exported photos with HDR on, once each; a pair exporting its raw doesn't count")
    func exportCount() {
        func item(_ id: Int64, _ path: String, hdr: Bool, partner: Int64? = nil, partnerKind: FileKind? = nil) -> CatalogItem {
            var item = CatalogItem(versionID: id, imageID: id, volumeID: 1, rating: .unrated, flag: .none, colorLabel: .none,
                                   contentHash: String(repeating: "a", count: 64), editStackHash: EditStack.identity.renderHash,
                                   relativePath: path, pixelWidth: 10, pixelHeight: 10, orientation: 1)
            item.hdr = hdr
            item.partnerVersionID = partner
            item.partnerKind = partnerKind
            return item
        }
        let on = item(1, "a/IMG_1.HEIC", hdr: true)
        let off = item(2, "a/IMG_2.HEIC", hdr: false)
        let pairJPEG = item(3, "a/IMG_3.JPG", hdr: true, partner: 4, partnerKind: .raw)
        let video = item(5, "a/IMG_5.MOV", hdr: true)
        #expect(ExportTargets.hdrCount([on, off, on, pairJPEG, video]) == 1)
        #expect(ExportTargets.hdrCount([off]) == 0)
    }

    // MARK: photocli (AC15)

    @Test("AC15: develop sets and resets the choice on a gain-map photo, query reads it, other files are refused")
    func commandLine() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let photos = root.appending(path: "Photos", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: photos, withIntermediateDirectories: true)
            let gainMap = photos.appending(path: "IMG_0001.jpg")
            try HDRTestImages.writeGainMap(to: gainMap, width: 96, height: 64, seed: 1, gain: 2, container: .jpeg)
            try SyntheticImages.writeJPEG(to: photos.appending(path: "IMG_0002.jpg"), width: 96, height: 64, seed: 2)
            let locations = LibraryLocations.rooted(at: root.appending(path: "Library", directoryHint: .isDirectory))
            try locations.createDirectories()
            let catalog = try Catalog.open(at: locations.catalogFileURL)
            _ = try await Importer(catalog: catalog, metadataReader: ImageIOMetadataReader()).importFolder(photos)
            let items = try await catalog.libraryItems(matching: LibraryFilter(groupsPairs: false))
            let hdrID = try #require(items.first { $0.fileName == "IMG_0001.jpg" }?.versionID)
            let plainID = try #require(items.first { $0.fileName == "IMG_0002.jpg" }?.versionID)
            let cli = CommandLineInterface(environment: .hermetic(currentDirectory: root))
            func run(_ arguments: String...) async -> JSONValue {
                let output = await cli.run(arguments + ["--library-root", root.appending(path: "Library").path])
                let text = output.exitCode == 0 ? output.standardOutput : output.standardError
                return (try? JSONValue.parse(text)) ?? .null
            }

            let listed = try JSONValue.parse(await cli.run(["adjustments"]).standardOutput)
            #expect(listed["modules"]?.arrayValue?.contains { $0["kind"] == "hdr" } == true)

            let set = await run("develop", "--version", String(hdrID), "--set", "hdr.on=true")
            #expect(set["written"] == true)
            #expect(try await catalog.libraryItems(versionIDs: [hdrID]).first?.hdr == true)
            #expect(set["renderHash"]?.stringValue == EditStack.identity.renderHash)
            let rules = #"{"rules": [{"field": "fileName", "comparison": "contains", "value": {"text": "IMG_0001"}}]}"#
            let images = await run("query", "images", rules)["images"]?.arrayValue
            let kinds = images?.first?["editStack"]?["operations"]?.arrayValue?.compactMap { $0["kind"]?.stringValue }
            #expect(kinds == ["hdr"])

            let reset = await run("develop", "--version", String(hdrID), "--set", "hdr.on=false")
            #expect(reset["written"] == true)
            #expect(try await catalog.libraryItems(versionIDs: [hdrID]).first?.hdr == false)

            let refused = await run("develop", "--version", String(plainID), "--set", "hdr.on=true")
            #expect(refused["code"] == "invalidEdit")
            #expect(try await catalog.libraryItems(versionIDs: [plainID]).first?.hdr == false)

            // An original that can't be read: never turned on (it can't be told to have a gain map).
            try FileManager.default.removeItem(at: gainMap)
            let offline = await run("develop", "--version", String(hdrID), "--set", "hdr.on=true")
            #expect(offline["code"] == "fileNotFound")
            #expect(try await catalog.libraryItems(versionIDs: [hdrID]).first?.hdr == false)
        }
    }
}

/// Issue #282: what the choice must not change (R12, R14, R15), and the HDR
/// histogram (R10). Synthetic gain-map files.
@Suite("HDR choice: SDR output, measurements and the histogram (issue #282)")
struct HDRChoiceOutputTests {
    private static func values(hdr: Bool) -> Adjustments {
        var values = Adjustments()
        values.exposure.ev = 0.4
        values.tone.contrast = 25
        values.hdr.isOn = hdr
        return values
    }

    @Test("AC11: previews and photocli render are the same bytes with the choice on and off")
    func sdrOutputUnchanged() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let url = root.appending(path: "same.heic")
            try HDRTestImages.writePatternedGainMap(to: url, width: 640, height: 480, seed: 2850)
            let generator = PreviewGenerator()
            let off = try generator.jpegData(source: url, stack: Self.values(hdr: false).editStack,
                                             tiers: Set(PreviewTier.allCases))
            let on = try generator.jpegData(source: url, stack: Self.values(hdr: true).editStack,
                                            tiers: Set(PreviewTier.allCases))
            #expect(!off.isEmpty && off == on)

            let cli = CommandLineInterface(environment: .hermetic(currentDirectory: root))
            var outputs: [Data] = []
            for hdr in [false, true] {
                let stack = root.appending(path: "stack-\(hdr).json")
                try Self.values(hdr: hdr).editStack.jsonData().write(to: stack)
                let out = root.appending(path: "out-\(hdr).tiff")
                let result = await cli.run(["render", url.path, "--stack", stack.path, "--out", out.path, "--long-edge", "320"])
                #expect(result.exitCode == 0, "\(result.standardError)")
                outputs.append(try Data(contentsOf: out))
            }
            #expect(outputs[0] == outputs[1])
        }
    }

    @Test("AC13: Auto Exposure, Auto White Balance and Color Alignment measure the same with the choice on and off")
    func measurementsUnchanged() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let url = root.appending(path: "measure.heic")
            try HDRTestImages.writePatternedGainMap(to: url, width: 640, height: 480, seed: 2851)
            let generator = PreviewGenerator()
            let adjuster = AutoAdjuster(generator: generator)
            let off = Self.values(hdr: false), on = Self.values(hdr: true)
            #expect(try adjuster.exposure(source: url, adjustments: off) == adjuster.exposure(source: url, adjustments: on))
            #expect(try adjuster.whiteBalance(source: url, adjustments: off)
                    == adjuster.whiteBalance(source: url, adjustments: on))
            #expect(try ColorAlignmentMeasurement.measure(source: url, adjustments: off, generator: generator)
                    == ColorAlignmentMeasurement.measure(source: url, adjustments: on, generator: generator))
        }
    }

    @Test("AC9: the HDR histogram counts values above white, differs from the SDR one, and is the same at any display")
    func histogram() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let url = root.appending(path: "histogram.heic")
            try HDRTestImages.writePatternedGainMap(to: url, width: 800, height: 600, seed: 2852, bright: 4, dim: 1.5)
            let session = LiveRenderSession(source: url, generator: PreviewGenerator(), longEdge: 600, colorSpace: nil)
            var values = Adjustments()
            values.hdr.isOn = true
            let dim = try await session.render(values, hdrHeadroom: 1.3)
            let bright = try await session.render(values, hdrHeadroom: 16)
            let hdr = try #require(dim.hdrHistogram)
            // The same whatever the display allows: the whole HDR version (R10).
            #expect(bright.hdrHistogram == hdr)
            #expect(hdr.shareAboveWhite > 0.1)
            let aboveWhite = hdr.luminance[HDRHistogram.sdrBins...].reduce(0, +)
            #expect(aboveWhite > 0)
            // The SDR histogram (the Tone Curve's backdrop) stays, and has nothing above white.
            let sdr = try #require(dim.histogram)
            #expect(sdr.luminance.count == Histogram.binCount)
            // A draft while dragging means the same axis: still above white, close to the settled share.
            let draft = try await session.render(values, interactive: true, hdrHeadroom: 1.3)
            let drafted = try #require(draft.hdrHistogram)
            #expect(abs(drafted.shareAboveWhite - hdr.shareAboveWhite) < 0.05)
            // Darkened until nothing is above white: the HDR axis stays, its right part empty (R8).
            values.exposure.ev = -3
            let dark = try #require(try await session.render(values, hdrHeadroom: 4).hdrHistogram)
            #expect(dark.shareAboveWhite == 0 && dark.luminance.count == HDRHistogram.binCount)
        }
    }

    @Test("The HDR histogram's bins: 0 to white on the display scale, then 3 stops linear in stops")
    func histogramBins() {
        #expect(HDRHistogram.binCount == 255)
        #expect(HDRHistogram.bin(0) == 0)
        #expect(HDRHistogram.bin(1) == HDRHistogram.sdrBins - 1)
        #expect(HDRHistogram.bin(0.18) == Int(HDRHistogram.encoded(0.18) * 153))
        #expect(HDRHistogram.bin(1.0001) == HDRHistogram.sdrBins)
        #expect(HDRHistogram.bin(2) == HDRHistogram.sdrBins + 34)
        #expect(HDRHistogram.bin(4) == HDRHistogram.sdrBins + 68)
        #expect(HDRHistogram.bin(8) == HDRHistogram.binCount - 1)
        #expect(HDRHistogram.bin(100) == HDRHistogram.binCount - 1)
        #expect(HDRHistogram.bin(.nan) == 0)
    }
}
