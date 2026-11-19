import Foundation
import GRDB
import Testing
@testable import PhotoCore

/// The Profile group is gone (issue #219): a Look an older build stored is
/// kept, written back unchanged and never rendered; Reset All removes it;
/// presets, paste and Lightroom import carry none. AC2 (the render) is
/// `RAWDecodeTests.storedLookRendersAsDefault` and
/// `LibRawDecoderTests`; AC8 is in `CommandTests`; AC9's corpus entries are
/// in `EditStackCorpusTests`.
@Suite("Stored Look (issue #219)")
struct StoredLookTests {
    /// A stack as a build with the Profile group saved it.
    static func stored(look: String = "flat", decoderVersion: String? = nil, exposure: Double? = 0.5) -> EditStack {
        var decode: [String: EditParameter] = ["look": .string(look)]
        if let decoderVersion { decode["decoderVersion"] = .string(decoderVersion) }
        var operations = [EditOperation(kind: "rawDecode", parameters: decode)]
        if let exposure { operations.append(EditOperation(kind: "exposure", parameters: ["ev": .number(exposure)])) }
        return EditStack(operations: operations)
    }

    static func storedLook(_ stack: EditStack?) -> EditParameter? {
        stack?.operations.first { $0.kind == RawDecode.kind }?.parameters["look"]
    }

    static func oneVersion() async throws -> (CatalogFixture, Int64) {
        let fixture = try await CatalogFixture.make()
        let id = try #require(try await fixture.addMasters([CatalogFixture.master(1)]).first)
        return (fixture, id)
    }

    // MARK: R1, R6: no Profile group

    @Test("No group, heading or preset group is Profile; Light is White Balance, Tone and Presence (R1, R6)")
    func noProfileGroup() {
        #expect(Adjustments.Group(rawValue: "profile") == nil)
        #expect(!Adjustments.Group.presetGroups.flatMap(\.kinds).contains(RawDecode.kind))
        #expect(Adjustments.Section.develop.groups == [.whiteBalance, .light, .presence])
        #expect(!Adjustments.Section.allCases.flatMap(\.groups).flatMap(\.kinds).contains(RawDecode.kind))
        // A photo whose only edit is a stored Look has nothing to reset under Light.
        let values = Adjustments(stack: Self.stored(exposure: nil))
        #expect(!values.isModified(.develop) && values.modifiedGroups.isEmpty)
    }

    // MARK: AC3: kept by every write but Reset All

    @Test("AC3: an edit, a heading's reset and on/off, paste and a preset keep a stored Look")
    func valueWritesKeepIt() {
        var values = Adjustments(stack: Self.stored(look: "flat", decoderVersion: "7.dng"))
        #expect(values.decode == RawDecode(storedLook: "flat", decoderVersion: "7.dng"))
        values.tone.contrast = 20
        values = values.resetting(.develop)
        values.presence.vibrance = 10
        values.setEnabled(.presence, false)
        values.setEnabled(.presence, true)
        #expect(Self.storedLook(values.editStack) == .string("flat"))

        var source = Adjustments()
        source.exposure.ev = 1
        source.decode = RawDecode(storedLook: "neutral")
        #expect(source.pasted(onto: values).decode == values.decode)
        let preset = AdjustmentPreset(name: "Bright", adjustments: source)
        #expect(preset.applied(onto: values).decode == values.decode)
        #expect(preset.applied(onto: values).exposure.ev == 1)
    }

    @Test("AC3: a stored Look written back by Adjustments is byte for byte the stack that was read",
          arguments: ["flat", "neutral", "standard"])
    func roundTripsUnchanged(look: String) throws {
        let stack = Self.stored(look: look, decoderVersion: "8")
        let written = Adjustments(stack: stack).editStack
        #expect(written.hasSameContent(as: stack))
        #expect(written.renderHash == stack.renderHash)
    }

    @Test("AC3: a batch action other than Reset All keeps it")
    func batchKeepsIt() async throws {
        let (fixture, id) = try await Self.oneVersion()
        let catalog = fixture.catalog
        try await catalog.setEditStack(Self.stored(), forVersion: id, historyLabel: "Old")
        _ = try await catalog.changeEditStacks(ofVersions: [id], historyLabel: "Auto Exposure") { values in
            var changed = values
            changed.exposure.ev = 1.25
            return changed
        }
        let saved = try #require(try await catalog.version(id: id)?.decodedEditStack())
        #expect(Self.storedLook(saved) == .string("flat"))
        #expect(Adjustments(stack: saved).exposure.ev == 1.25)
    }

    @Test("AC3: photocli develop keeps it, as do undo and redo writes")
    func developAndUndoKeepIt() async throws {
        try await CommandTests.withLibrary { library in
            let id = library.versionIDs[0]
            let catalog = try Catalog.open(at: library.locations.catalogFileURL)
            let original = Self.stored()
            try await catalog.setEditStack(original, forVersion: id, historyLabel: "Old")
            let developed = await library.run("develop", "--version", String(id), "--set", "exposure.ev=1")
            #expect(developed.output.exitCode == 0)
            let after = try #require(try await catalog.version(id: id)?.decodedEditStack())
            #expect(Self.storedLook(after) == .string("flat"))
            #expect(Adjustments(stack: after).exposure.ev == 1)
            // Undo writes the stack before the edit back; redo the one after.
            try await catalog.setEditStack(original, forVersion: id, historyLabel: "Undo Develop")
            #expect(try await catalog.version(id: id)?.decodedEditStack().hasSameContent(as: original) == true)
            try await catalog.setEditStack(after, forVersion: id, historyLabel: "Redo Develop")
            #expect(Self.storedLook(try await catalog.version(id: id)?.decodedEditStack()) == .string("flat"))
            // photocli's own Reset All clears it too.
            let reset = await library.run("develop", "--version", String(id), "--reset", "all")
            #expect(reset.output.exitCode == 0)
            #expect(try await catalog.version(id: id)?.decodedEditStack() == .identity)
        }
    }

    // MARK: AC11: history

    @Test("AC11: reverting to an entry holding look = neutral writes it back, and undoing that restores the stack")
    func historyRevertAndUndo() async throws {
        let (fixture, id) = try await Self.oneVersion()
        let catalog = fixture.catalog
        let old = Self.stored(look: "neutral")
        try await catalog.setEditStack(old, forVersion: id, historyLabel: "Profile")
        var later = Adjustments(stack: old)
        later.decode = RawDecode()
        later.exposure.ev = 2
        try await catalog.setEditStack(later.editStack, forVersion: id, historyLabel: "Reset Adjustments")
        let entry = try #require(try await catalog.editHistory(forVersion: id).last)
        #expect(entry.label == "Profile")
        let snapshot = try #require(try await catalog.editHistoryStack(entryID: entry.id, forVersion: id))
        #expect(snapshot.hasSameContent(as: old))
        // The revert, through the editor's values as the app writes it.
        try await catalog.setEditStack(Adjustments(stack: snapshot).editStack, forVersion: id, historyLabel: "Revert")
        let reverted = try #require(try await catalog.version(id: id)?.decodedEditStack())
        #expect(reverted.hasSameContent(as: old))
        // Nothing of it reaches the decoder (R2).
        #expect(Adjustments(stack: reverted).decodeSettings == .none)
        // Undo of the revert.
        try await catalog.setEditStack(later.editStack, forVersion: id, historyLabel: "Undo Revert")
        #expect(try await catalog.version(id: id)?.decodedEditStack().hasSameContent(as: later.editStack) == true)
    }

    // MARK: AC12: Reset All

    @Test("AC12: Reset All removes the stored decode, a Look and a decoder version alike, and leaves nothing to reset",
          arguments: [Self.stored(look: "flat"), Self.stored(look: "neutral", decoderVersion: "7.dng"),
                      EditStack(operations: [EditOperation(kind: "rawDecode", parameters: ["decoderVersion": .string("7")])])])
    func resetAllRemovesIt(stack: EditStack) {
        let reset = Adjustments(stack: stack).resettingAll()
        #expect(!reset.editStack.operations.contains { $0.kind == RawDecode.kind })
        #expect(reset == Adjustments(stack: .identity) && reset.isDefault)
        #expect(reset.editStack == .identity)
    }

    @Test("AC12: Reset All keeps operations this build does not understand")
    func resetAllKeepsUnknown() {
        let future = EditOperation(kind: "futureModule", kindVersion: 2, parameters: ["x": .number(1)])
        var stack = Self.stored()
        stack.operations.append(future)
        let reset = Adjustments(stack: stack).resettingAll()
        #expect(reset.editStack.operations.map(\.kind) == ["futureModule"])
    }

    @Test("AC12: the grid's Reset All, a batch write, removes it")
    func batchResetAllRemovesIt() async throws {
        let (fixture, id) = try await Self.oneVersion()
        let catalog = fixture.catalog
        try await catalog.setEditStack(Self.stored(look: "flat", decoderVersion: "7.dng"), forVersion: id,
                                       historyLabel: "Old")
        _ = try await catalog.changeEditStacks(ofVersions: [id], historyLabel: "Reset Adjustments") { $0.resettingAll() }
        let saved = try #require(try await catalog.version(id: id)?.decodedEditStack())
        #expect(saved == .identity && Adjustments(stack: saved).isDefault)
    }

    // MARK: AC4: a stored decoder version still renders

    @Test("AC4: a stored non-machine-learning decoder version still reaches the decoder; a stored Look does not")
    func storedDecoderVersionRenders() {
        let values = Adjustments(stack: Self.stored(look: "flat", decoderVersion: "7.dng", exposure: nil))
        #expect(values.decodeSettings == RAWDecodeSettings(decoderVersion: "7.dng"))
        #expect(!values.asksForMachineLearning)
        // Turned off (an earlier build's unchecked Profile), it does not apply, as before.
        var stack = Self.stored(look: "flat", decoderVersion: "7.dng", exposure: nil)
        stack.operations[0].isEnabled = false
        let off = Adjustments(stack: stack)
        #expect(off.decodeSettings == .none)
        #expect(off.editStack.operations.first?.isEnabled == false)
    }

    // MARK: AC6: old presets

    @Test("AC6: a preset saved with Profile reads, keeps its stored decode, and applies nothing from it")
    func oldPresetsInTheCatalog() async throws {
        let (fixture, id) = try await Self.oneVersion()
        let catalog = fixture.catalog
        let preset = AdjustmentPreset(name: "Old Flat", groups: [.light],
                                      adjustments: Adjustments(presetStack: Self.stored(look: "flat", exposure: 0.7)),
                                      keepingStoredDecode: true)
        let saved = try await catalog.saveAdjustmentPreset(preset)
        // As an older build stored it: the group list names Profile.
        try await catalog.database.write { db in
            try db.execute(sql: "UPDATE adjustmentPreset SET groups = 'light,profile' WHERE id = ?", arguments: [saved.id])
        }
        let loaded = try #require(try await catalog.adjustmentPresets().first { $0.id == saved.id })
        #expect(loaded.groups == [.light])
        #expect(loaded.adjustments.decode.storedLook == "flat")
        // Renamed and saved again, its stored data still holds the Look.
        var renamed = loaded
        renamed.name = "Renamed"
        _ = try await catalog.saveAdjustmentPreset(renamed)
        let settings = try await catalog.database.read { db in
            try String.fetchOne(db, sql: "SELECT settings FROM adjustmentPreset WHERE id = ?", arguments: [saved.id])
        }
        #expect(Self.storedLook(try EditStack.decode(from: try #require(settings))) == .string("flat"))

        // Applied to a photo with its own stored Look: only Tone changes.
        try await catalog.setEditStack(Self.stored(look: "neutral", exposure: nil), forVersion: id, historyLabel: "Old")
        _ = try await catalog.changeEditStacks(ofVersions: [id], historyLabel: "Apply Preset") { loaded.applied(onto: $0) }
        let after = try #require(try await catalog.version(id: id)?.decodedEditStack())
        #expect(Self.storedLook(after) == .string("neutral"))
        #expect(Adjustments(stack: after).exposure.ev == 0.7)

        // A preset that had only Profile: no settings, and applying it changes nothing.
        let profileOnly = AdjustmentPreset(name: "Only Profile", groups: AdjustmentPreset.decodeGroups("profile"),
                                           adjustments: Adjustments(presetStack: Self.stored(exposure: nil)),
                                           keepingStoredDecode: true)
        #expect(profileOnly.groups.isEmpty)
        let target = Adjustments(stack: after)
        #expect(profileOnly.applied(onto: target) == target)
    }

    @Test("AC6: a preset file with a stored Look imports without error and applies nothing from it")
    func oldPresetFiles() throws {
        let preset = AdjustmentPreset(name: "Old Neutral",
                                      adjustments: Adjustments(presetStack: Self.stored(look: "neutral", exposure: 0.4)),
                                      keepingStoredDecode: true)
        let store = LookTableStore(directory: FileManager.default.temporaryDirectory
            .appending(path: "stored-look-luts-\(UUID().uuidString)"))
        let file = try PresetFile(data: PresetFile(presets: [preset], store: store).data())
        let imported = try #require(file.adjustmentPresets().first)
        #expect(imported.adjustments.decode.storedLook == "neutral")
        #expect(imported.includesEveryGroup)
        let target = Adjustments(stack: Self.stored(look: "flat", exposure: nil))
        let applied = imported.applied(onto: target)
        #expect(applied.decode == target.decode)
        #expect(applied.exposure.ev == 0.4)
    }

    // MARK: AC7: Lightroom profiles

    static func convert(profile: String, asLook: Bool) -> CameraRawConversion {
        var values: [String: CameraRawValue] = ["Exposure2012": .number(0.3)]
        if asLook {
            values["Look"] = .record(["Name": .string(profile)])
        } else {
            values["CameraProfile"] = .string(profile)
        }
        return CameraRawMapping.convert(CameraRawSettings(name: "P", values: values))
    }

    @Test("AC7: a Flat, Neutral or other named profile is reported and sets nothing",
          arguments: ["Flat", "Neutral", "Camera Neutral", "Camera Standard", "Adobe Landscape", "Adobe Vivid",
                      "Vintage 05"])
    func otherProfilesAreReported(name: String) {
        for asLook in [false, true] {
            let conversion = Self.convert(profile: name, asLook: asLook)
            #expect(conversion.unsupported == [.profile], "\(name)")
            #expect(conversion.adjustments.decode == RawDecode())
            #expect(conversion.groups == [.light])
        }
    }

    @Test("AC7: a Standard-family profile is not reported and sets nothing",
          arguments: ["Standard", "Adobe Color", "Adobe Standard", "default", "Embedded", "ADOBE STANDARD", " Adobe Color "])
    func standardProfilesAreNotReported(name: String) {
        for asLook in [false, true] {
            let conversion = Self.convert(profile: name, asLook: asLook)
            #expect(conversion.unsupported.isEmpty, "\(name)")
            #expect(conversion.adjustments.decode == RawDecode())
            #expect(conversion.groups == [.light])
        }
    }

    @Test("AC7: a monochrome profile is reported once, as black and white")
    func monochromeIsBlackAndWhite() {
        let conversion = Self.convert(profile: "Adobe Monochrome", asLook: true)
        #expect(conversion.unsupported.contains(.blackAndWhite) && !conversion.unsupported.contains(.profile))
    }
}
