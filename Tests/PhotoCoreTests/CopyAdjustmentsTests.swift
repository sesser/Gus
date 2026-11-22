import CoreGraphics
import Foundation
import PhotoFixtures
import Testing
@testable import PhotoCore

/// Copy Adjustments with a choice of what to copy (issue #243,
/// docs/features/copy-adjustments-selective): the sheet's rows, its defaults
/// and box rules, and what Paste does with a selection.
@Suite("Copy Adjustments")
struct CopyAdjustmentsTests {
    static func spot(_ index: Int, x: Double = 0.3) -> Spot {
        Spot(id: UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", index))!,
             center: MaskPoint(x: x, y: 0.4), size: 0.02, source: MaskPoint(x: 0.5, y: 0.4))
    }

    /// A photo with something in every group, a crop, masks, spots, a stored
    /// decode and an unknown operation.
    static func everything(_ seed: Double) -> Adjustments {
        var values = Adjustments()
        values.crop = Crop(rect: CropRect(x: 0.1 * seed, y: 0, width: 0.5, height: 0.5))
        values.whiteBalance.preset = .custom
        values.whiteBalance.temperature = 4000 + 100 * seed
        values.exposure.ev = 0.25 * seed
        values.tone.contrast = 10 * seed
        values.presence.clarity = 5 * seed
        values.toneCurve.rgb = [CurvePoint(x: 0, y: 0.05 * seed), CurvePoint(x: 1, y: 1)]
        values.colorMixer[.red] = ColorMixer.Shift(hue: 3 * seed)
        values.blackAndWhite.isOn = true
        values.blackAndWhite[.red] = 20 * seed
        values.colorGrade.shadows.amount = 7 * seed
        values.sharpen.amount = 30 * seed
        values.noiseReduction.luminance = 12 * seed
        values.distortion = LensDistortion(isOn: true, source: .manual, amount: 4 * seed)
        values.lensVignetting = LensVignetting(isOn: true, source: .manual, amount: 6 * seed)
        values.colorFringes.slot1 = ColorFringes.Slot(color: SIMD3(0.5, 0.2 * seed, 0.1), tolerance: 20)
        values.colorAlignment = ColorAlignment(red: 0.5 * seed, blue: -0.25 * seed)
        values.lookTable = LookTable(identifier: "table-\(Int(seed))", name: "Table", intensity: 80)
        values.vignette.amount = -15 * seed
        values.grain.strength = 9 * seed
        values.spots.spots = [spot(Int(seed)), spot(Int(seed) + 10, x: 0.7)]
        values.local.masks = [Mask(name: "Mask \(Int(seed))")]
        values.decode = RawDecode(storedLook: "flat")
        values.preserved = [EditOperation(kind: "futureThing")]
        return values
    }

    // MARK: AC2: rows

    @Test("AC2: every heading and group once, plus Crop, in the Adjust tab's visible order")
    func rowsFollowTheTab() {
        #expect(CopyRow.all == [.crop, .section(.spots), .section(.develop), .section(.tone), .section(.colorMixer),
                                .section(.blackAndWhite), .section(.colorGrading), .section(.details), .section(.lens),
                                .section(.effects)])
        let sections = CopyRow.all.compactMap { row -> Adjustments.Section? in
            if case .section(let section) = row { return section }
            return nil
        }
        #expect(sections.count == Adjustments.Section.allCases.count)
        #expect(Set(sections) == Set(Adjustments.Section.allCases))
        let items = CopyItem.all
        #expect(items.count == Adjustments.Group.allCases.count + 1)
        #expect(Set(items) == Set(Adjustments.Group.allCases.map(CopyItem.group)).union([.crop]))
        #expect(items.first == .crop)
        // Light's groups in the tab's order (White Balance, Tone, Presence); one-group headings are single rows.
        #expect(CopyRow.section(.develop).items == [.group(.whiteBalance), .group(.light), .group(.presence)])
        #expect(CopyRow.all.filter(\.isHeading) == [.section(.develop), .section(.details), .section(.lens), .section(.effects)])
        // Names for the debug script.
        for item in items { #expect(CopyItem(name: item.name) == item) }
        #expect(CopyItem(name: "masks") == nil)
    }

    @Test("AC2: a heading's box is mixed when only some of its groups are checked")
    func headingStateIsDerived() {
        var source = Adjustments()
        source.exposure.ev = 1
        var sheet = CopySheetState(source: source)
        #expect(sheet.state(of: .section(.develop)) == .mixed)
        sheet.set([.group(.whiteBalance), .group(.presence)], true)
        #expect(sheet.state(of: .section(.develop)) == .on)
        sheet.uncheckAll()
        #expect(sheet.state(of: .section(.develop)) == .off)
    }

    // MARK: AC3: defaults

    @Test("AC3: Exposure and Tone edited with a crop: Tone checked, Light mixed, the rest unchecked and marked")
    func defaultsFollowTheSource() {
        var source = Adjustments()
        source.exposure.ev = 0.7
        source.tone.contrast = 15
        source.crop = Crop(rect: CropRect(x: 0, y: 0, width: 0.8, height: 0.8))
        let sheet = CopySheetState(source: source)
        #expect(sheet.checked == [.group(.light)])
        #expect(sheet.state(of: .section(.develop)) == .mixed)
        #expect(!sheet.isChecked(.crop))
        #expect(sheet.state(of: .section(.lens)) == .off && sheet.state(of: .section(.spots)) == .off)
        // The crop is changed, so it carries no note; every other group says "No changes".
        #expect(sheet.note(for: .crop) == nil)
        #expect(sheet.note(for: .group(.light)) == nil)
        for item in CopyItem.all where item != .crop && item != .group(.light) {
            #expect(sheet.note(for: item) == .noChanges, "\(item.name)")
        }
        #expect(!sheet.sourceHasNoChanges)
    }

    @Test("R3: Crop, Spots and the Lens groups never start checked; every other changed group does")
    func uncheckedByDefault() {
        let sheet = CopySheetState(source: Self.everything(1))
        let expected = Set(CopyItem.all.filter {
            $0 != .crop && $0 != .group(.spots) && !Adjustments.Section.lens.groups.map(CopyItem.group).contains($0)
        })
        #expect(sheet.checked == expected)
        #expect(sheet.state(of: .section(.lens)) == .off)
    }

    @Test("R3: a group turned off that holds values counts as changed and says Turned off")
    func turnedOffCountsAsChanged() {
        var source = Adjustments()
        source.vignette.amount = -20
        source.setEnabled(.vignette, false)
        source.spots.spots = [Self.spot(1), Self.spot(2), Self.spot(3)]
        source.setEnabled(.spots, false)
        var sheet = CopySheetState(source: source)
        #expect(sheet.checked == [.group(.vignette)])
        #expect(sheet.note(for: .group(.vignette)) == .turnedOff)
        #expect(sheet.note(for: .group(.spots)) == .spots(count: 3, turnedOff: true))
        sheet.toggle(.group(.spots))
        #expect(sheet.note(for: .group(.spots)) == .spots(count: 3, turnedOff: true))
        // A checked group the source never changed resets on paste.
        sheet.toggle(.group(.grain))
        #expect(sheet.note(for: .group(.grain)) == .resetsOnPaste)
        sheet.toggle(.group(.grain))
        #expect(sheet.note(for: .group(.grain)) == .noChanges)
    }

    @Test("A source with no changes starts with nothing checked and says so")
    func noChangesAtAll() {
        var sheet = CopySheetState(source: Adjustments())
        #expect(sheet.checked.isEmpty && sheet.sourceHasNoChanges && !sheet.canCopy)
        sheet.checkAll()
        #expect(sheet.checked == Set(CopyItem.all) && sheet.canCopy)
        #expect(CopyItem.all.allSatisfy { sheet.note(for: $0) == .resetsOnPaste })
    }

    // MARK: Box rules (design §3.4) and AC4

    @Test("A heading's click checks all when unchecked or mixed and unchecks all when checked")
    func headingClickRule() {
        var source = Adjustments()
        source.sharpen.amount = 40
        var sheet = CopySheetState(source: source)
        #expect(sheet.state(of: .section(.details)) == .mixed)
        sheet.click(.section(.details))
        #expect(sheet.state(of: .section(.details)) == .on)
        #expect(sheet.checked.isSuperset(of: [.group(.sharpening), .group(.noiseReduction)]))
        sheet.click(.section(.details))
        #expect(sheet.state(of: .section(.details)) == .off)
        sheet.click(.section(.details))
        #expect(sheet.state(of: .section(.details)) == .on)
        // A single row flips its one item.
        sheet.click(CopyRow.crop)
        #expect(sheet.isChecked(.crop))
        sheet.click(CopyRow.crop)
        #expect(!sheet.isChecked(.crop))
    }

    @Test("AC4: with every box unchecked Copy is off")
    func nothingCheckedCannotCopy() {
        var sheet = CopySheetState(source: Self.everything(1))
        #expect(sheet.canCopy)
        sheet.uncheckAll()
        #expect(!sheet.canCopy)
        sheet.toggle(.crop)
        #expect(sheet.canCopy)
    }

    // MARK: AC5, AC6, AC10, R5: paste

    @Test("AC5: only Color Grading copied changes only the target's Color Grading (stored stacks compared)")
    func onlyColorGrading() {
        let a = Self.everything(1)
        let b = Self.everything(2)
        let copied = CopiedAdjustments(a, items: [.group(.colorGrade)])
        let result = copied.pasted(onto: b)
        #expect(result.colorGrade == a.colorGrade)
        var expected = b
        expected.colorGrade = a.colorGrade
        #expect(result.editStack.hasSameContent(as: expected.editStack))
        // Everything else, the crop, masks, spots, decode and unknown operations included, is B's.
        let others = EditStack(operations: b.editStack.operations.filter { $0.kind != ColorGrade.kind })
        #expect(EditStack(operations: result.editStack.operations.filter { $0.kind != ColorGrade.kind })
            .hasSameContent(as: others))
        #expect(result.editStack.renderHash == expected.editStack.renderHash)
    }

    @Test("AC6: a Tone Curve copied from a photo without one resets the target's")
    func copiedDefaultsReset() {
        var target = Self.everything(2)
        target.setEnabled(.toneCurve, false)
        let copied = CopiedAdjustments(Adjustments(), items: [.group(.toneCurve)])
        let result = copied.pasted(onto: target)
        #expect(result.toneCurve == ToneCurve())
        #expect(result.isEnabled(.toneCurve))
        #expect(!result.editStack.operations.contains { $0.kind == ToneCurve.kind })
        #expect(result.exposure == target.exposure)
    }

    @Test("R5: a group turned off in the source is pasted turned off, with its values")
    func onOffStatePastes() {
        var source = Adjustments()
        source.grain.strength = 30
        source.setEnabled(.grain, false)
        let result = CopiedAdjustments(source, items: [.group(.grain)]).pasted(onto: Self.everything(2))
        #expect(result.grain == source.grain && !result.isEnabled(.grain))
    }

    @Test("AC10: Crop copied gives the target the source's crop as stored; unchecked, the target's stays")
    func cropPastesAsStored() {
        var a = Adjustments()
        a.crop = Crop(rect: CropRect(x: 0.2, y: 0.1, width: 0.5, height: 0.6), quarterTurns: 1, angle: 3)
        a.exposure.ev = 1
        var b = Adjustments()
        b.crop = Crop(quarterTurns: 2)
        #expect(CopiedAdjustments(a, items: [.crop]).pasted(onto: b).crop == a.crop)
        #expect(CopiedAdjustments(a, items: [.crop]).pasted(onto: b).exposure.ev == 0)
        #expect(CopiedAdjustments(a, items: [.group(.light)]).pasted(onto: b).crop == b.crop)
        // A source without a crop, Crop copied: the target's is removed.
        #expect(CopiedAdjustments(Adjustments(), items: [.crop]).pasted(onto: b).crop.isIdentity)
    }

    @Test("R5: masks, the stored decode and unknown operations are never touched, whatever is copied")
    func neverTouched() {
        let a = Self.everything(1)
        let b = Self.everything(2)
        let result = CopiedAdjustments(a, items: Set(CopyItem.all)).pasted(onto: b)
        #expect(result.local == b.local)
        #expect(result.decode == b.decode)
        #expect(result.preserved == b.preserved)
        // Everything copied: every item is A's.
        var expected = a
        expected.local = b.local
        expected.decode = b.decode
        expected.preserved = b.preserved
        #expect(result == expected)
    }

    @Test("The clipboard holds only the copied items' values")
    func clipboardHoldsOnlyTheItems() {
        let copied = CopiedAdjustments(Self.everything(1), items: [.group(.light), .crop])
        var expected = Adjustments()
        expected.exposure = Self.everything(1).exposure
        expected.tone = Self.everything(1).tone
        expected.crop = Self.everything(1).crop
        #expect(copied.values == expected)
        // Color alignment is measured on paste only when it was copied.
        var measuring = Adjustments()
        measuring.colorAlignment = ColorAlignment(automatic: true)
        #expect(CopiedAdjustments(measuring, items: [.group(.light)]).values.needsAlignmentMeasurement == false)
        #expect(CopiedAdjustments(measuring, items: [.group(.colorAlignment)]).values.needsAlignmentMeasurement
                == measuring.needsAlignmentMeasurement)
    }

    @Test("Paste of every item but Spots is the old paste (Adjustments.pasted)")
    func everythingButSpots() {
        let a = Self.everything(1)
        let b = Self.everything(2)
        let result = a.pasted(onto: b)
        #expect(result.spots == b.spots && result.local == b.local && result.crop == a.crop)
        #expect(result.colorGrade == a.colorGrade && result.distortion == a.distortion)
    }

    // MARK: AC9, R8: spots

    @Test("AC9: Spots copied replace the target's, on/off included; kept when its frame differs")
    func spotsPasteBySize() {
        var a = Adjustments()
        a.spots.spots = [Self.spot(1), Self.spot(2)]
        a.setEnabled(.spots, false)
        a.exposure.ev = 1
        var b = Adjustments()
        b.spots.spots = [Self.spot(9, x: 0.8)]
        let copied = CopiedAdjustments(a, items: [.group(.spots), .group(.light)])
        #expect(copied.includesSpots)
        let same = copied.pasted(onto: b)
        #expect(same.spots == a.spots && !same.isEnabled(.spots))
        let other = copied.pasted(onto: b, pastingSpots: false)
        #expect(other.spots == b.spots && other.isEnabled(.spots))
        // The other copied groups still apply.
        #expect(other.exposure.ev == 1)
        // A source with no spots resets them on a photo of the same size only.
        let reset = CopiedAdjustments(Adjustments(), items: [.group(.spots)])
        #expect(reset.pasted(onto: b).spots.isIdentity)
        #expect(reset.pasted(onto: b, pastingSpots: false).spots == b.spots)
        // Never more than the source had, and the source is within the limit.
        #expect(SpotLimits.allows(same.spots))
    }

    @Test("R8: spots go only onto a frame of the same size, both known, in whole pixels")
    func sameSizeRule() {
        let frame = CGSize(width: 6000, height: 4000)
        #expect(CopiedAdjustments.pastesSpots(sourceFrame: frame, targetFrame: CGSize(width: 6000, height: 4000)))
        #expect(CopiedAdjustments.pastesSpots(sourceFrame: frame, targetFrame: CGSize(width: 6000.2, height: 3999.9)))
        // Turned (portrait) is another size: no remapping.
        #expect(!CopiedAdjustments.pastesSpots(sourceFrame: frame, targetFrame: CGSize(width: 4000, height: 6000)))
        #expect(!CopiedAdjustments.pastesSpots(sourceFrame: frame, targetFrame: CGSize(width: 6016, height: 4000)))
        #expect(!CopiedAdjustments.pastesSpots(sourceFrame: nil, targetFrame: frame))
        #expect(!CopiedAdjustments.pastesSpots(sourceFrame: frame, targetFrame: nil))
    }

    @Test("R8: the frame size is the oriented decode of the whole sensor, read from the header")
    func maskFrameSizeMatchesTheDecode() async throws {
        try await offCooperativePool {
            try await RepositoryFiles.withTemporaryDirectory { folder in
                let upright = folder.appending(path: "upright.jpg")
                try SyntheticImages.writeJPEG(to: upright, width: 300, height: 200, seed: 1)
                let turned = folder.appending(path: "turned.jpg")
                try SyntheticImages.writeJPEG(to: turned, width: 300, height: 200, seed: 2,
                                              exif: SyntheticImages.Exif(orientation: 6))
                let raw = folder.appending(path: "raw.dng")
                try SyntheticDNG.write(to: raw, options: SyntheticDNG.Options(width: 320, height: 240, seed: 3))
                #expect(PreviewGenerator.maskFrameSize(of: upright) == CGSize(width: 300, height: 200))
                #expect(PreviewGenerator.maskFrameSize(of: turned) == CGSize(width: 200, height: 300))
                var settings = RAWDecodeSettings()
                settings.fullFrame = true
                for url in [upright, turned, raw] {
                    // The frame spots are placed in: the renderer's input with the whole sensor decoded.
                    let decoded = try PreviewGenerator.decode(url, longEdge: nil, draft: false, settings: settings)
                    #expect(PreviewGenerator.maskFrameSize(of: url) == decoded.image.extent.size, "\(url.lastPathComponent)")
                }
                #expect(PreviewGenerator.maskFrameSize(of: folder.appending(path: "missing.jpg")) == nil)
            }
        }
    }

    // MARK: AC7: one step, History once per photo

    @Test("AC7: a selective paste on three photos writes each once, labelled Paste Adjustments, and undoes as one")
    func batchPasteHistory() async throws {
        let fixture = try await CatalogFixture.make()
        let ids = try await fixture.addMasters((1...3).map { CatalogFixture.master($0) })
        for (index, id) in ids.enumerated() {
            try await fixture.catalog.setEditStack(Self.everything(Double(index + 2)).editStack, forVersion: id,
                                                   historyLabel: "Edit")
        }
        let original = try await fixture.catalog.editStacks(forVersions: ids)
        let copied = CopiedAdjustments(Self.everything(1), items: [.group(.colorGrade), .crop])
        let change = try await fixture.catalog.changeEditStacks(ofVersions: ids, historyLabel: "Paste Adjustments") {
            copied.pasted(onto: $0)
        }
        for id in ids {
            #expect(try await fixture.catalog.editHistory(forVersion: id).map(\.label) == ["Paste Adjustments", "Edit"])
            let after = Adjustments(stack: try #require(change.after[id]))
            #expect(after.colorGrade == Self.everything(1).colorGrade && after.crop == Self.everything(1).crop)
        }
        // Undo writes the stacks from before, every photo at once.
        try await fixture.catalog.setEditStacks(change.before, historyLabel: "Undo Paste Adjustments")
        let stored = try await fixture.catalog.editStacks(forVersions: ids)
        for id in ids {
            #expect(try #require(stored.stacks[id]).hasSameContent(as: try #require(original.stacks[id])))
            #expect(try #require(stored.stacks[id]) != change.after[id])
        }
    }

    // MARK: The announcement

    @Test("The summary names a heading for all its groups, in row order")
    func summary() {
        var sheet = CopySheetState(source: Adjustments())
        sheet.set([.group(.grain), .group(.whiteBalance), .group(.light), .group(.presence), .crop, .group(.sharpening)], true)
        #expect(sheet.summary == [.item(.crop), .row(.section(.develop)), .item(.group(.sharpening)), .item(.group(.grain))])
        #expect(sheet.copied().summary == sheet.summary)
    }
}
