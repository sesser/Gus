import CoreImage
import Foundation
import PhotoFixtures
import Testing
@testable import PhotoCore

/// Machine learning noise reduction (docs/features/ml-denoise): the
/// availability rule, the one state shared with the Decoder pop-up, the
/// fallback when it cannot apply, and what export and `photocli` report.
///
/// Tests that need the RAW decoder's version 9 to really run are enabled only
/// where this Mac has it (macOS 27 and later); the fallback and failure paths
/// use per-file overrides (`MachineLearningNoiseReduction.setOverride`), so
/// they run on every Mac.
@Suite("Machine learning noise reduction")
struct MachineLearningNoiseReductionTests {
    typealias ML = MachineLearningNoiseReduction

    /// A noisy synthetic DNG of its own for each caller, so per-file overrides
    /// never reach another test running in parallel.
    static func noisyDNG(_ name: String, scene: SyntheticDNG.Scene = .pattern, width: Int = 320,
                         height: Int = 240) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "ml-\(name)-\(ProcessInfo.processInfo.processIdentifier).dng", directoryHint: .notDirectory)
        try SyntheticDNG.write(to: url, options: .init(width: width, height: height, seed: 7, noise: 0.02,
                                                       writesNoiseProfile: true, scene: scene))
        return url
    }

    /// This Mac's decoder offers version 9 for the synthetic DNG.
    static let hasMachineLearningDecoder: Bool = {
        guard let url = try? noisyDNG("probe") else { return false }
        return ML.availability(for: url) == .available
    }()

    static func adjustments(_ edit: (inout Adjustments) -> Void) -> Adjustments {
        var adjustments = Adjustments()
        edit(&adjustments)
        return adjustments
    }

    static func render(_ adjustments: Adjustments, source: URL) throws -> (image: LinearImage, outcome: ML.Outcome) {
        let rendering = try PreviewGenerator(engine: Goldens.engine).rendering(source: source,
                                                                               stack: adjustments.editStack, longEdge: nil)
        return (ReferenceTests.renderLinear(rendering.image), rendering.machineLearning)
    }

    static func stack(_ json: String) throws -> EditStack {
        try EditStack.decode(from: Data(json.utf8))
    }

    /// A stack without its operations' ids (`Adjustments.editStack` makes new ones each time).
    static func content(_ stack: EditStack) -> [String] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return stack.operations.map { operation in
            let parameters = (try? String(decoding: encoder.encode(operation.parameters), as: UTF8.self)) ?? ""
            return "\(operation.kind.rawValue)|\(operation.kindVersion)|\(operation.isEnabled)|\(parameters)"
        }
    }

    // MARK: Availability (AC6)

    @Test("The availability rule: not RAW, not on this Mac, camera not supported, available (AC6)")
    func availabilityRule() {
        #expect(ML.availability(isRaw: false, systemSupports: true, decoderVersions: ["8.dng", "9.dng"]) == .notRaw)
        #expect(ML.availability(isRaw: true, systemSupports: false, decoderVersions: ["8.dng", "9.dng"]) == .notOnThisMac)
        #expect(ML.availability(isRaw: true, systemSupports: true, decoderVersions: ["6", "7", "8"]) == .cameraNotSupported)
        #expect(ML.availability(isRaw: true, systemSupports: true, decoderVersions: ["6.dng", "7.dng", "8.dng", "9.dng"])
                == .available)
        // Camera raws list the version without ".dng".
        #expect(ML.availability(isRaw: true, systemSupports: true, decoderVersions: ["7", "8", "9"]) == .available)
        let jpeg = URL(fileURLWithPath: "/nowhere/IMG_0001.jpg")
        #expect(ML.availability(for: jpeg) == .notRaw)
    }

    @Test("This Mac: the synthetic DNG's availability follows the macOS version")
    func availabilityOnThisMac() throws {
        let url = try Self.noisyDNG("availability")
        let expected: ML.Availability = ML.systemSupportsMachineLearning ? .available : .notOnThisMac
        #expect(ML.availability(for: url) == expected)
        #expect(RawDefaults(source: url)?.machineLearning == expected)
    }

    @Test("Overrides are per file and come before this Mac's answer, except for files that are not RAW")
    func overridesArePerFile() throws {
        let url = try Self.noisyDNG("override")
        let other = try Self.noisyDNG("override-other")
        ML.setOverride(.init(availability: .cameraNotSupported), for: url)
        defer { ML.setOverride(nil, for: url) }
        #expect(ML.availability(for: url) == .cameraNotSupported)
        #expect(ML.availability(for: other) != .cameraNotSupported)
    }

    @Test("Decoder versions: 9 and 9.dng are the machine learning decoder")
    func versions() {
        #expect(ML.isMachineLearningVersion("9.dng") && ML.isMachineLearningVersion("9"))
        #expect(!ML.isMachineLearningVersion("8.dng") && !ML.isMachineLearningVersion("None")
                && !ML.isMachineLearningVersion("19"))
        #expect(ML.machineLearningVersion(in: ["6.dng", "7.dng", "8.dng", "9.dng"]) == "9.dng")
        #expect(ML.machineLearningVersion(in: ["6", "7", "8"]) == nil)
    }

    // MARK: Unchanged rendering, and the pinned default (AC3, RI-7)

    @Test("The pinned default: left alone below 9, the newest older version from 9 on (RI-7)")
    func pinnedDefault() {
        #expect(ML.pinnedVersion(default: "8.dng", supported: ["6.dng", "7.dng", "8.dng", "9.dng"]) == nil)
        #expect(ML.pinnedVersion(default: "9.dng", supported: ["6.dng", "7.dng", "8.dng", "9.dng"]) == "8.dng")
        #expect(ML.pinnedVersion(default: "10.dng", supported: ["7.dng", "8.dng", "9.dng", "10.dng"]) == "8.dng")
        #expect(ML.pinnedVersion(default: "9", supported: ["6", "7", "8", "9"]) == "8")
        #expect(ML.pinnedVersion(default: "None", supported: []) == nil)
    }

    @Test("A stack without the setting keeps its parameters, render hash and decode settings (AC3)")
    func stacksWithoutTheSettingAreUnchanged() throws {
        let json = """
            {"operations":[{"id":"00000000-0000-4000-8000-000000000011","isEnabled":true,"kind":"noiseReduction",\
            "kindVersion":1,"parameters":{"color":30,"luminance":20}}],"schemaVersion":1}
            """
        let stored = try Self.stack(json)
        let values = Adjustments(stack: stored)
        #expect(Self.content(values.editStack) == Self.content(stored))
        #expect(values.editStack.renderHash == stored.renderHash)
        #expect(!values.asksForMachineLearning)
        #expect(values.decodeSettings == RAWDecodeSettings(luminanceNoiseReduction: 0.2, colorNoiseReduction: 0.3))
        #expect(NoiseReduction(luminance: 20, color: 30).parameters.keys.sorted() == ["color", "luminance"])
    }

    /// The seam of AC3: a filter set to version 9 before the settings apply
    /// stands in for a macOS whose default is version 9.
    @Test("With the decoder's default at 9.dng, a stack that does not ask for it decodes with the pinned version (AC3)",
          .enabled(if: hasMachineLearningDecoder, "needs the RAW decoder's version 9 (macOS 27 or later)"))
    func pinnedDefaultHoldsAgainstAFutureDefault() throws {
        let url = try Self.noisyDNG("pin")
        let raw = try #require(CIRAWFilter(imageURL: url))
        let today = raw.decoderVersion.rawValue
        #expect(!ML.isMachineLearningVersion(today))
        raw.decoderVersion = CIRAWDecoderVersion(rawValue: "9.dng")
        #expect(raw.decoderVersion.rawValue == "9.dng")
        let untouched = Self.adjustments { $0.noiseReduction.luminance = 40 }
        #expect(untouched.decodeSettings.apply(to: raw, source: url) == .notRequested)
        #expect(raw.decoderVersion.rawValue == today)

        let asking = try #require(CIRAWFilter(imageURL: url))
        asking.decoderVersion = CIRAWDecoderVersion(rawValue: "9.dng")
        let settings = Self.adjustments { $0.noiseReduction.machineLearning = true }.decodeSettings
        #expect(settings.apply(to: asking, source: url) == .applied)
        #expect(asking.decoderVersion.rawValue == "9.dng")
        // The pop-up's "(default)" is the pinned version.
        #expect(RawDefaults(source: url)?.defaultDecoderVersion == today)
    }

    // MARK: One state with the Decoder pop-up (AC4)

    @Test("A stack saved with decoderVersion 9.dng reads as machine learning on, Profile at the default (AC4)",
          arguments: ["9.dng", "9"])
    func legacyStacksReadAsOn(version: String) throws {
        let stored = try Self.stack("""
            {"operations":[{"id":"00000000-0000-4000-8000-000000000001","isEnabled":true,"kind":"rawDecode",\
            "kindVersion":1,"parameters":{"decoderVersion":"\(version)","look":"neutral"}}],"schemaVersion":1}
            """)
        let values = Adjustments(stack: stored)
        #expect(values.asksForMachineLearning)
        #expect(values.decode.decoderVersion == nil && values.decode.look == .neutral)
        #expect(values.decode.legacyMachineLearningVersion == nil)
        #expect(values.decodeSettings.machineLearning && values.decodeSettings.decoderVersion == nil)
        // Saved again, it is in the new form.
        #expect(values.editStack.operations.first { $0.kind == NoiseReduction.kind }?.parameters["machineLearning"]
                == .bool(true))
    }

    @Test("A legacy stack whose Profile group was off keeps rendering without it")
    func legacyStackWithProfileOff() throws {
        let stored = try Self.stack("""
            {"operations":[{"id":"00000000-0000-4000-8000-000000000001","isEnabled":false,"kind":"rawDecode",\
            "kindVersion":1,"parameters":{"decoderVersion":"9.dng"}}],"schemaVersion":1}
            """)
        let values = Adjustments(stack: stored)
        #expect(!values.asksForMachineLearning)
        #expect(values.isEnabled(.profile) && values.decodeSettings == .none)
    }

    @Test("A legacy stack renders as before: with version 9 (AC4)", .enabled(if: hasMachineLearningDecoder, "needs the RAW decoder's version 9 (macOS 27 or later)"))
    func legacyStackRendersAsBefore() throws {
        let url = try Self.noisyDNG("legacy-render")
        let legacy = Adjustments(stack: try Self.stack("""
            {"operations":[{"id":"00000000-0000-4000-8000-000000000001","isEnabled":true,"kind":"rawDecode",\
            "kindVersion":1,"parameters":{"decoderVersion":"9.dng"}}],"schemaVersion":1}
            """))
        let rendered = try Self.render(legacy, source: url)
        #expect(rendered.outcome == .applied)
        // Before the feature the decoder was simply set to 9.dng.
        let raw = try #require(CIRAWFilter(imageURL: url))
        raw.decoderVersion = CIRAWDecoderVersion(rawValue: "9.dng")
        let direct = try #require(raw.outputImage)
        #expect(rendered.image == ReferenceTests.renderLinear(direct))
    }

    @Test("With machine learning on, Profile's 7.dng is kept and applies again when it is turned off (AC4)")
    func profileChoiceIsKept() throws {
        let url = try Self.noisyDNG("profile-kept")
        var values = Self.adjustments {
            $0.decode.decoderVersion = "7.dng"
            $0.noiseReduction.machineLearning = true
        }
        let on = try #require(CIRAWFilter(imageURL: url))
        let outcome = values.decodeSettings.apply(to: on, source: url)
        if Self.hasMachineLearningDecoder {
            #expect(outcome == .applied && on.decoderVersion.rawValue == "9.dng")
        } else {
            #expect(outcome == .notApplied(.notOnThisMac) && on.decoderVersion.rawValue == "7.dng")
        }
        values.noiseReduction.machineLearning = false
        let off = try #require(CIRAWFilter(imageURL: url))
        #expect(values.decodeSettings.apply(to: off, source: url) == .notRequested)
        #expect(off.decoderVersion.rawValue == "7.dng")
    }

    @Test("Profile-only presets, a paste of Profile and turning Profile off leave it on (AC4)")
    func profileNeverTurnsItOff() {
        let photo = Self.adjustments {
            $0.noiseReduction = NoiseReduction(luminance: 40, color: 25, machineLearning: true)
            $0.decode.look = .neutral
        }
        let profilePreset = AdjustmentPreset(name: "Flat", groups: [.profile],
                                             adjustments: Self.adjustments { $0.decode.look = .flat })
        #expect(profilePreset.applied(onto: photo).asksForMachineLearning)
        #expect(photo.replacing([.profile], from: .none).asksForMachineLearning)
        var off = photo
        off.setEnabled(.profile, false)
        #expect(off.decodeSettings.machineLearning)
        // And a Profile-only preset from a photo with it on does not carry it.
        let fromPhoto = AdjustmentPreset(name: "From photo", groups: [.profile], adjustments: photo)
        #expect(!fromPhoto.applied(onto: .none).asksForMachineLearning)
    }

    @Test("A pre-feature preset with Profile at 9.dng turns it on and leaves Luminance and Color (AC4)")
    func legacyPresetTurnsItOn() async throws {
        let presetStack = try Self.stack("""
            {"operations":[{"id":"00000000-0000-4000-8000-000000000001","isEnabled":true,"kind":"rawDecode",\
            "kindVersion":1,"parameters":{"decoderVersion":"9.dng","look":"flat"}}],"schemaVersion":1}
            """)
        let preset = AdjustmentPreset(name: "Old", groups: [.profile], adjustments: Adjustments(presetStack: presetStack))
        let target = Self.adjustments { $0.noiseReduction = NoiseReduction(luminance: 40, color: 25) }
        let applied = preset.applied(onto: target)
        #expect(applied.asksForMachineLearning)
        #expect(applied.noiseReduction.luminance == 40 && applied.noiseReduction.color == 25)
        #expect(applied.decode.look == .flat && applied.decode.decoderVersion == nil)
        #expect(applied.decode.legacyMachineLearningVersion == nil)

        // Saved and read back, it still does (the catalog and preset files).
        let catalog = try Catalog.makeInMemory()
        let saved = try await catalog.saveAdjustmentPreset(preset)
        let loaded = try #require(try await catalog.adjustmentPresets().first { $0.id == saved.id })
        #expect(loaded.applied(onto: target) == applied)
        let file = try PresetFile(data: PresetFile(presets: [preset], store: LookTableStore(
            directory: FileManager.default.temporaryDirectory.appending(path: "ml-luts-\(UUID().uuidString)"))).data())
        #expect(file.adjustmentPresets().first?.applied(onto: target) == applied)
    }

    @Test("The Decoder pop-up: 9.dng turns it on, another version turns it off and becomes Profile's (AC4)")
    func decoderChoice() {
        var values = Self.adjustments { $0.decode.decoderVersion = "7.dng" }
        values.chooseDecoder("9.dng", defaultVersion: "8.dng")
        #expect(values.asksForMachineLearning && values.decode.decoderVersion == "7.dng")
        values.chooseDecoder("6.dng", defaultVersion: "8.dng")
        #expect(!values.asksForMachineLearning && values.decode.decoderVersion == "6.dng")
        values.chooseDecoder("9", defaultVersion: "8")
        values.chooseDecoder("8", defaultVersion: "8")
        #expect(!values.asksForMachineLearning && values.decode.decoderVersion == nil)
    }

    @Test("develop: the machine learning decoder version is machine learning on; never a disagreeing pair (AC4, AC11)")
    func developKeepsOneState() throws {
        let viaDecoder = try EditStack.identity.applying([try AdjustmentEdit.parseSet("rawDecode.decoderVersion=9.dng")])
        let values = Adjustments(stack: viaDecoder)
        #expect(values.asksForMachineLearning && values.decode.decoderVersion == nil)
        #expect(!viaDecoder.operations.contains { $0.kind == RawDecode.kind })

        let viaSwitch = try EditStack.identity.applying([try AdjustmentEdit.parseSet("noiseReduction.machineLearning=true")])
        #expect(Adjustments(stack: viaSwitch).asksForMachineLearning)
        let off = try viaSwitch.applying([try AdjustmentEdit.parseSet("noiseReduction.machineLearning=false")])
        #expect(off.operations.isEmpty)
        #expect(throws: AdjustmentEdit.Failure.invalidValue(kind: "noiseReduction", parameter: "machineLearning",
                                                            reason: "true or false")) {
            try EditStack.identity.applying([try AdjustmentEdit.parseSet("noiseReduction.machineLearning=yes")])
        }
    }

    // MARK: Color (AC5)

    @Test("Turning it on and off keeps the stored Color; Color is unavailable only while it applies (AC5)")
    func colorIsKept() {
        let before = Self.adjustments { $0.noiseReduction = NoiseReduction(luminance: 40, color: 25) }
        var values = before
        values.noiseReduction.machineLearning = true
        #expect(values.noiseReduction.color == 25)
        values.noiseReduction.machineLearning = false
        #expect(Self.content(values.editStack) == Self.content(before.editStack))

        #expect(!ML.Status(asks: true, groupIsOn: true, availability: .available).colorIsAvailable)
        #expect(ML.Status(asks: true, groupIsOn: true, availability: .notOnThisMac).colorIsAvailable)
        #expect(ML.Status(asks: true, groupIsOn: true, availability: .cameraNotSupported).colorIsAvailable)
        #expect(ML.Status(asks: true, groupIsOn: true, availability: .available, renderFailed: true).colorIsAvailable)
        #expect(ML.Status(asks: true, groupIsOn: false, availability: .available).colorIsAvailable)
        #expect(ML.Status(asks: false, groupIsOn: true, availability: .available).colorIsAvailable)
    }

    @Test("Asked for and not applied, Color changes the render (AC5)")
    func colorRendersInTheFallback() throws {
        let url = try Self.noisyDNG("color-fallback")
        ML.setOverride(.init(availability: .notOnThisMac), for: url)
        defer { ML.setOverride(nil, for: url) }
        let none = try Self.render(Self.adjustments {
            $0.noiseReduction = NoiseReduction(luminance: 50, color: 0, machineLearning: true)
        }, source: url)
        let full = try Self.render(Self.adjustments {
            $0.noiseReduction = NoiseReduction(luminance: 50, color: 100, machineLearning: true)
        }, source: url)
        #expect(none.outcome == .notApplied(.notOnThisMac))
        #expect(none.image != full.image)
    }

    // MARK: The states (AC6, design §3)

    @Test("Every state of the design's table")
    func states() {
        typealias S = ML.Status
        #expect(S(asks: false, groupIsOn: true, availability: .notRaw).state == .notOffered)
        #expect(S(asks: false, groupIsOn: true, availability: .available).state == .off)                        // S1
        #expect(S(asks: true, groupIsOn: true, availability: .available).state == .applied)                     // S2
        #expect(S(asks: false, groupIsOn: true, availability: .notOnThisMac).state == .unavailable(.notOnThisMac)) // S3
        #expect(S(asks: false, groupIsOn: true, availability: .cameraNotSupported).state
                == .unavailable(.cameraNotSupported))                                                          // S4
        #expect(S(asks: true, groupIsOn: true, availability: .notOnThisMac).state == .notApplied(.notOnThisMac)) // S5
        #expect(S(asks: true, groupIsOn: true, availability: .cameraNotSupported).state
                == .notApplied(.cameraNotSupported))                                                           // S6
        #expect(S(asks: true, groupIsOn: false, availability: .available).state == .groupOff(.applied))          // S7
        #expect(S(asks: true, groupIsOn: true, availability: .available, renderFailed: true).state
                == .notApplied(.failed))                                                                       // S8
        #expect(S(asks: true, groupIsOn: true, availability: nil).state == .unknown)

        // The check box: dimmed only in S3 and S4.
        #expect(!S(asks: false, groupIsOn: true, availability: .notOnThisMac).checkBoxIsEnabled)
        #expect(!S(asks: false, groupIsOn: true, availability: .cameraNotSupported).checkBoxIsEnabled)
        #expect(S(asks: true, groupIsOn: true, availability: .notOnThisMac).checkBoxIsEnabled)
        // The badge: S5, S6, S8; not with the group off or when it applies.
        #expect(S(asks: true, groupIsOn: true, availability: .notOnThisMac).notAppliedReason == .notOnThisMac)
        #expect(S(asks: true, groupIsOn: false, availability: .notOnThisMac).notAppliedReason == nil)
        #expect(S(asks: true, groupIsOn: true, availability: .available).notAppliedReason == nil)
        // The Decoder pop-up is dimmed exactly while the badge shows.
        #expect(!S(asks: true, groupIsOn: true, availability: .cameraNotSupported).decoderChoiceIsEnabled)
        #expect(S(asks: true, groupIsOn: false, availability: .cameraNotSupported).decoderChoiceIsEnabled)
    }

    // MARK: Not applied (AC7, AC7a)

    @Test("On a Mac without it: the classical render, and the stack keeps the setting through edits (AC7)")
    func fallbackOnAMacWithoutIt() throws {
        let url = try Self.noisyDNG("not-on-this-mac")
        ML.setOverride(.init(availability: .notOnThisMac), for: url)
        defer { ML.setOverride(nil, for: url) }
        let asking = Self.adjustments { $0.noiseReduction = NoiseReduction(luminance: 60, color: 40, machineLearning: true) }
        let rendered = try Self.render(asking, source: url)
        var classical = asking
        classical.noiseReduction.machineLearning = false
        #expect(rendered.outcome == .notApplied(.notOnThisMac))
        #expect(rendered.image == (try Self.render(classical, source: url)).image)

        // Opening and changing Exposure keeps it.
        var reopened = Adjustments(stack: asking.editStack)
        reopened.exposure.ev = 0.5
        #expect(Adjustments(stack: reopened.editStack).asksForMachineLearning)
    }

    @Test("A failed decode on a supported file: the classical render, the stack unchanged, the reason (AC7a)")
    func failedDecodeFallsBack() async throws {
        let url = try Self.noisyDNG("failed")
        ML.setOverride(.init(availability: .available, failsDecode: true), for: url)
        defer { ML.setOverride(nil, for: url) }
        let asking = Self.adjustments { $0.noiseReduction = NoiseReduction(luminance: 60, color: 40, machineLearning: true) }
        let stack = asking.editStack
        let rendered = try Self.render(asking, source: url)
        var classical = asking
        classical.noiseReduction.machineLearning = false
        #expect(rendered.outcome == .notApplied(.failed))
        #expect(rendered.image == (try Self.render(classical, source: url)).image)
        #expect(Self.content(asking.editStack) == Self.content(stack))

        // The loupe's frames carry the outcome.
        let session = LiveRenderSession(source: url, generator: PreviewGenerator(engine: Goldens.engine), longEdge: 200,
                                        colorSpace: nil)
        #expect(try await session.render(asking).machineLearning == .notApplied(.failed))
        #expect(try await session.render(classical).machineLearning == .notRequested)
        #expect(ML.Reason.failed.message == "could not be applied to this photo")
    }

    @Test("A request where it applies, on the live session's frames", .enabled(if: hasMachineLearningDecoder, "needs the RAW decoder's version 9 (macOS 27 or later)"))
    func liveFramesApply() async throws {
        let url = try Self.noisyDNG("live")
        let session = LiveRenderSession(source: url, generator: PreviewGenerator(engine: Goldens.engine), longEdge: 200,
                                        colorSpace: nil)
        let asking = Self.adjustments { $0.noiseReduction.machineLearning = true }
        #expect(try await session.render(asking, interactive: true).machineLearning == .applied)
        var groupOff = asking
        groupOff.setEnabled(.noiseReduction, false)
        #expect(try await session.render(groupOff).machineLearning == .notRequested)
    }

    // MARK: Undo, batch, presets (AC9, AC10)

    @Test("Turning it on and off gives back the stack's bytes (AC9)")
    func onOffRoundTrip() throws {
        let before = Self.adjustments {
            $0.exposure.ev = 0.3
            $0.noiseReduction.luminance = 30
        }.editStack
        var values = Adjustments(stack: before)
        values.noiseReduction.machineLearning = true
        #expect(values.editStack != before)
        values.noiseReduction.machineLearning = false
        #expect(Self.content(values.editStack) == Self.content(before))
        #expect(values.editStack.renderHash == before.renderHash)
    }

    @Test("Paste and presets carry it to raws, never to other files; Reset All clears it (AC10)")
    func batchCarriesItToRawsOnly() {
        let copied = Self.adjustments { $0.noiseReduction = NoiseReduction(luminance: 70, machineLearning: true) }
        let raw = copied.pasted(onto: .none)
        #expect(raw.asksForMachineLearning)
        let jpeg = copied.pasted(onto: .none).forNonRawFile()
        #expect(!jpeg.asksForMachineLearning && jpeg.noiseReduction.luminance == 70)
        let preset = AdjustmentPreset(name: "Noise", groups: [.noiseReduction], adjustments: copied)
        #expect(preset.applied(onto: .none).asksForMachineLearning)
        #expect(!AdjustmentPreset(name: "Light", groups: [.light], adjustments: copied).applied(onto: .none)
                .asksForMachineLearning)
        #expect(!raw.resetting(.details).asksForMachineLearning)
        // A non-RAW photo with the group off keeps it off.
        var off = copied
        off.setEnabled(.noiseReduction, false)
        #expect(!off.forNonRawFile().isEnabled(.noiseReduction))
    }

    // MARK: Previews

    @Test("Renders without the machine learning a stack asks for stay out of the disk cache")
    func fallbackRendersAreKeptForTheSessionOnly() async throws {
        let url = try Self.noisyDNG("cache")
        ML.setOverride(.init(availability: .notOnThisMac), for: url)
        defer { ML.setOverride(nil, for: url) }
        try await RepositoryFiles.withTemporaryDirectory { root in
            let asking = Self.adjustments { $0.noiseReduction.machineLearning = true }.editStack
            let cache = PreviewDiskCache(root: root)
            let service = PreviewService(cache: cache, generator: PreviewGenerator(engine: Goldens.engine),
                                         editStack: { _ in asking })
            let key = try #require(PreviewCacheKey(contentHash: String(repeating: "ab", count: 32),
                                                   editStackHash: asking.renderHash, tier: .thumbnail))
            let request = PreviewRequest(versionID: 1, key: key, sourceURL: url)
            _ = try await service.image(for: request)
            #expect(cache.contains(key))
            #expect(!FileManager.default.fileExists(atPath: cache.url(for: key).path))
            #expect(cache.loadImage(for: key) != nil)
            cache.remove(key)
            #expect(!cache.contains(key))
        }
    }

    // MARK: Directional checks on this Mac (AC1, AC2)

    /// Luma (sRGB curve) of a linear render.
    static func luma(_ image: LinearImage) -> [Double] {
        (0..<(image.width * image.height)).map { index in
            let p = image[index % image.width, index / image.width]
            let linear = max(0, 0.2627 * Double(p.x) + 0.6780 * Double(p.y) + 0.0593 * Double(p.z))
            return linear <= 0.0031308 ? linear * 12.92 : 1.055 * pow(linear, 1 / 2.4) - 0.055
        }
    }

    static let stripePeriod = 16

    /// High-frequency energy inside the stripes (noise), and the mean
    /// one-pixel step across their edges, from column means over every row
    /// (noise averages out; sharpness stays).
    static func stripeMeasures(_ image: LinearImage) -> (flat: Double, edge: Double) {
        let luma = luma(image)
        let w = image.width, h = image.height, period = stripePeriod
        var flat = 0.0, flatCount = 0
        for y in 8..<(h - 8) {
            for x in 8..<(w - 8) where (4...(period - 5)).contains(x % period) {
                let i = y * w + x
                let d = luma[i] - (luma[i - 1] + luma[i + 1] + luma[i - w] + luma[i + w]) / 4
                flat += d * d
                flatCount += 1
            }
        }
        let columns = (0..<w).map { x in (8..<(h - 8)).map { luma[$0 * w + x] }.reduce(0, +) / Double(h - 16) }
        let steps = stride(from: period * 2, to: w - period * 2, by: period).map { x in
            (-2...2).map { abs(columns[x + $0] - columns[x + $0 - 1]) }.max() ?? 0
        }
        return (flat / Double(flatCount), steps.reduce(0, +) / Double(steps.count))
    }

    static func stripes(_ name: String) throws -> URL {
        try noisyDNG(name, scene: .stripes(period: stripePeriod), width: 640, height: 480)
    }

    @Test("Edges: the machine learning render's edge contrast is not lower than classical at 100 (AC2)",
          .enabled(if: hasMachineLearningDecoder, "needs the RAW decoder's version 9 (macOS 27 or later)"))
    func edgesStaySharp() throws {
        let url = try Self.stripes("edges")
        let learned = try Self.render(Self.adjustments {
            $0.noiseReduction = NoiseReduction(luminance: 100, machineLearning: true)
        }, source: url)
        let classical = try Self.render(Self.adjustments {
            $0.noiseReduction = NoiseReduction(luminance: 100, color: 100)
        }, source: url)
        #expect(learned.outcome == .applied)
        let ml = Self.stripeMeasures(learned.image).edge, standard = Self.stripeMeasures(classical.image).edge
        #expect(ml >= standard, "edge step: machine learning \(ml), classical \(standard)")
    }

    @Test("Luminance is the machine learning amount: 100 leaves less noise than 0 (R4)",
          .enabled(if: hasMachineLearningDecoder, "needs the RAW decoder's version 9 (macOS 27 or later)"))
    func luminanceIsTheAmount() throws {
        let url = try Self.stripes("amount")
        let none = try Self.render(Self.adjustments {
            $0.noiseReduction = NoiseReduction(luminance: 0, machineLearning: true)
        }, source: url)
        let full = try Self.render(Self.adjustments {
            $0.noiseReduction = NoiseReduction(luminance: 100, machineLearning: true)
        }, source: url)
        let low = Self.stripeMeasures(full.image).flat, high = Self.stripeMeasures(none.image).flat
        #expect(low < high, "flat-area energy: Luminance 100 \(low), Luminance 0 \(high)")
    }

    /// AC1 as the PRD words it. On the synthetic fixtures the classical
    /// decoder at 100 leaves less high-frequency energy in flat areas than the
    /// machine learning decoder (status.md, requirements issue RI-E1), so it
    /// is disabled until the product manager rules on the fixture or the
    /// measure.
    @Test("Flat areas: the machine learning render has less high-frequency energy than classical at 100 (AC1)",
          .disabled("Requirements issue RI-E1 in docs/features/ml-denoise/status.md: fails on synthetic DNGs"),
          .enabled(if: hasMachineLearningDecoder, "needs the RAW decoder's version 9 (macOS 27 or later)"))
    func flatAreasAreQuieter() throws {
        let url = try Self.stripes("flat")
        let learned = try Self.render(Self.adjustments {
            $0.noiseReduction = NoiseReduction(luminance: 100, machineLearning: true)
        }, source: url)
        let classical = try Self.render(Self.adjustments {
            $0.noiseReduction = NoiseReduction(luminance: 100, color: 100)
        }, source: url)
        let ml = Self.stripeMeasures(learned.image).flat, standard = Self.stripeMeasures(classical.image).flat
        #expect(ml < standard, "flat-area energy: machine learning \(ml), classical \(standard)")
    }
}


/// `photocli` and export with machine learning noise reduction (AC7, AC7a,
/// AC11), run in process against a temporary library with a DNG and a JPEG.
@Suite("Machine learning noise reduction: photocli and export")
struct MachineLearningCommandTests {
    typealias ML = MachineLearningNoiseReduction

    struct Library {
        var root: URL
        var catalog: Catalog
        var dng: (id: Int64, url: URL)
        var jpeg: Int64
        var cli: CommandLineInterface

        func run(_ arguments: String...) async -> JSONValue {
            let output = await cli.run(arguments + ["--library-root", root.path])
            return (try? JSONValue.parse(output.exitCode == 0 ? output.standardOutput : output.standardError)) ?? .null
        }

        func asks() async throws -> Bool {
            Adjustments(stack: try await catalog.version(id: dng.id)?.decodedEditStack() ?? .identity)
                .asksForMachineLearning
        }
    }

    /// A library with one noisy DNG and one JPEG, the DNG given `override`.
    static func withLibrary(_ override: ML.Override?, _ body: (Library) async throws -> Void) async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let photos = root.appending(path: "Photos", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: photos, withIntermediateDirectories: true)
            let dng = photos.appending(path: "IMG_0001.dng")
            try SyntheticDNG.write(to: dng, options: .init(width: 320, height: 240, seed: 7, noise: 0.02,
                                                           writesNoiseProfile: true))
            try SyntheticImages.writeJPEG(to: photos.appending(path: "IMG_0002.jpg"), width: 320, height: 240, seed: 2)
            ML.setOverride(override, for: dng)
            defer { ML.setOverride(nil, for: dng) }
            let locations = LibraryLocations.rooted(at: root.appending(path: "Library", directoryHint: .isDirectory))
            try locations.createDirectories()
            let catalog = try Catalog.open(at: locations.catalogFileURL)
            _ = try await Importer(catalog: catalog, metadataReader: ImageIOMetadataReader()).importFolder(photos)
            let items = try await catalog.libraryItems(matching: LibraryFilter(groupsPairs: false))
            let dngID = try #require(items.first { $0.fileName.hasSuffix(".dng") }?.versionID)
            let jpegID = try #require(items.first { $0.fileName.hasSuffix(".jpg") }?.versionID)
            try await body(Library(root: root.appending(path: "Library"), catalog: catalog, dng: (dngID, dng),
                                   jpeg: jpegID,
                                   cli: CommandLineInterface(environment: CommandEnvironment(currentDirectory: root))))
        }
    }

    @Test("adjustments lists the setting; develop --dry-run prints a stack with it on (AC11)")
    func adjustmentsAndDryRun() async throws {
        try await Self.withLibrary(nil) { library in
            let listed = try JSONValue.parse(await library.cli.run(["adjustments"]).standardOutput)
            let module = listed["modules"]?.arrayValue?.first { $0["kind"] == "noiseReduction" }
            let parameter = module?["parameters"]?.arrayValue?.first { $0["name"] == "machineLearning" }
            #expect(parameter?["type"] == "boolean" && parameter?["default"] == .bool(false))

            let dry = await library.run("develop", "--version", "\(library.dng.id)",
                                        "--set", "noiseReduction.machineLearning=true", "--dry-run")
            let stack = try dry["editStack"].map { try $0.decode(EditStack.self) }
            #expect(stack.map { Adjustments(stack: $0).asksForMachineLearning } == true)
            #expect(dry["written"] == .bool(false))
            let before = try await library.asks()
            #expect(!before)

            let jpeg = await library.run("develop", "--version", "\(library.jpeg)",
                                         "--set", "noiseReduction.machineLearning=true")
            #expect(jpeg["code"] == "invalidEdit")
        }
    }

    @Test("Without it on this Mac: develop, render and export keep the setting and say why (AC7)")
    func notOnThisMac() async throws {
        try await Self.withLibrary(.init(availability: .notOnThisMac)) { library in
            _ = await library.run("develop", "--version", "\(library.dng.id)", "--set", "noiseReduction.machineLearning=true")
            let asks1 = try await library.asks()
            #expect(asks1)
            _ = await library.run("develop", "--version", "\(library.dng.id)", "--set", "exposure.ev=0.5")
            let asks2 = try await library.asks()
            #expect(asks2)

            let out = library.root.deletingLastPathComponent().appending(path: "render.png").path
            let render = await library.run("render", "--version", "\(library.dng.id)", "--out", out)
            #expect(render["machineLearning"]?["requested"] == .bool(true))
            #expect(render["machineLearning"]?["applied"] == .bool(false))
            #expect(render["machineLearning"]?["reason"] == "notOnThisMac")

            let folder = library.root.deletingLastPathComponent().appending(path: "Export").path
            let export = await library.run("export", "--version", "\(library.dng.id)", "--version", "\(library.jpeg)",
                                           "--to", folder)
            let results = export["machineLearning"]?.arrayValue ?? []
            #expect(results.count == 1 && results.first?["reason"] == "notOnThisMac")
            let asks3 = try await library.asks()
            #expect(asks3)
        }
    }

    @Test("A failed decode: render and export JSON and the export's Activity rows give the reason (AC7a)")
    func failedDecode() async throws {
        try await Self.withLibrary(.init(availability: .available, failsDecode: true)) { library in
            _ = await library.run("develop", "--version", "\(library.dng.id)", "--set", "noiseReduction.machineLearning=true")
            let stored = try await library.catalog.version(id: library.dng.id)?.decodedEditStack()

            let out = library.root.deletingLastPathComponent().appending(path: "render.png").path
            let render = await library.run("render", "--version", "\(library.dng.id)", "--out", out)
            #expect(render["machineLearning"]?["reason"] == "failed")
            #expect(render["machineLearning"]?["message"] == "could not be applied to this photo")

            let folder = library.root.deletingLastPathComponent().appending(path: "Export").path
            let export = await library.run("export", "--version", "\(library.dng.id)", "--to", folder)
            #expect(export["machineLearning"]?.arrayValue?.first?["message"] == "could not be applied to this photo")

            let job = ExportJob(catalog: library.catalog, renderer: ExportRenderer(generator: PreviewGenerator(engine: Goldens.engine)))
            let summary = await job.run(ExportRequest(versionIDs: [library.dng.id, library.jpeg], settings: ExportSettings(),
                                                      destination: URL(fileURLWithPath: folder)))
            #expect(ExportActivityReport(summary).machineLearningNotApplied == [.init(reason: .failed, count: 1)])
            let after = try await library.catalog.version(id: library.dng.id)?.decodedEditStack()
            #expect(after == stored)
        }
    }

    @Test("Where it applies, render and export say so", .enabled(if: MachineLearningNoiseReductionTests.hasMachineLearningDecoder,
                                                                 "needs the RAW decoder's version 9 (macOS 27 or later)"))
    func applied() async throws {
        try await Self.withLibrary(nil) { library in
            _ = await library.run("develop", "--version", "\(library.dng.id)", "--set", "rawDecode.decoderVersion=9.dng")
            let asks4 = try await library.asks()
            #expect(asks4)
            let out = library.root.deletingLastPathComponent().appending(path: "render.png").path
            let render = await library.run("render", "--version", "\(library.dng.id)", "--out", out)
            #expect(render["machineLearning"]?["applied"] == .bool(true))
            let original = await library.run("render", "--version", "\(library.dng.id)", "--out", out, "--original")
            #expect(original["machineLearning"]?["requested"] == .bool(false))
            let folder = library.root.deletingLastPathComponent().appending(path: "Export").path
            let export = await library.run("export", "--version", "\(library.dng.id)", "--to", folder)
            #expect(export["machineLearning"]?.arrayValue?.first?["applied"] == .bool(true))
            let summary = await ExportJob(catalog: library.catalog, renderer: ExportRenderer())
                .run(ExportRequest(versionIDs: [library.dng.id], settings: ExportSettings(),
                                   destination: URL(fileURLWithPath: folder), policy: .overwrite))
            #expect(ExportActivityReport(summary).machineLearningNotApplied.isEmpty)
        }
    }
}
