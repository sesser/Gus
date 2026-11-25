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
        #expect(Self.badge(choice: false, shown: .sdr) == .sdr)
        // RI-3: offline with the choice off, SDR only when the file is known to have a gain map.
        #expect(Self.badge(hasGainMap: false, choice: false, offline: true) == .none)
        #expect(Self.badge(choice: false, offline: true) == .sdr)
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
