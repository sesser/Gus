import CoreImage
import Foundation
import Synchronization

/// Machine learning noise reduction for RAW files: the macOS RAW decoder's
/// version 9 (macOS 27 and later), an on-device model that demosaics and
/// reduces noise in one step. Nothing is bundled or downloaded by the app;
/// the decoder is used only for files whose `supportedDecoderVersions` list
/// it.
///
/// A stack asks for it with `NoiseReduction.machineLearning`. Whether it
/// renders is decided per file and per render (`Outcome`); when it cannot,
/// the photo renders with the classical decoder and the stack is kept.
public enum MachineLearningNoiseReduction {
    /// The decoder's major version that is the machine learning model.
    public static let decoderMajorVersion = 9

    /// Whether this Mac's RAW decoder offers it for a file.
    public enum Availability: String, Hashable, Sendable, CaseIterable {
        case available
        /// This macOS has no machine learning decoder (before macOS 27).
        case notOnThisMac
        /// The decoder does not list version 9 for this file's camera.
        case cameraNotSupported
        /// Not a RAW file: the control is not offered and this is never shown as a reason.
        case notRaw
    }

    /// Why a stack that asks for it was rendered without it.
    public enum Reason: String, Hashable, Sendable, CaseIterable {
        case notOnThisMac
        case cameraNotSupported
        /// The file's decoder lists version 9 but decoding with it failed.
        case failed

        /// In English, for `photocli`'s JSON (the app has its own strings).
        public var message: String {
            switch self {
            case .notOnThisMac: "this Mac needs macOS 27 or later"
            case .cameraNotSupported: "this camera is not supported"
            case .failed: "could not be applied to this photo"
            }
        }

        init?(_ availability: Availability) {
            switch availability {
            case .notOnThisMac: self = .notOnThisMac
            case .cameraNotSupported: self = .cameraNotSupported
            case .available, .notRaw: return nil
            }
        }
    }

    /// What one decode did with the request.
    public enum Outcome: Hashable, Sendable {
        /// The stack did not ask for it (or its Noise Reduction group is off), or the file is not RAW.
        case notRequested
        case applied
        /// Asked for and not applied: the classical decoder rendered instead.
        case notApplied(Reason)

        public var isApplied: Bool { self == .applied }

        public var reason: Reason? {
            if case .notApplied(let reason) = self { return reason }
            return nil
        }
    }

    // MARK: Decoder versions

    /// The leading number of a decoder version ("9" for "9" and "9.dng"), nil for "None".
    public static func majorVersion(of version: String) -> Int? {
        Int(version.prefix { $0.isNumber })
    }

    /// True for the machine learning decoder: "9" for camera raws, "9.dng" for DNG files.
    public static func isMachineLearningVersion(_ version: String) -> Bool {
        majorVersion(of: version) == decoderMajorVersion
    }

    /// The machine learning version among a file's `supportedDecoderVersions`, if any.
    public static func machineLearningVersion(in versions: [String]) -> String? {
        versions.first(where: isMachineLearningVersion)
    }

    /// The version a raw that does not ask for machine learning decodes with
    /// when it has no decoder choice of its own (owner ruling RI-7): nil to
    /// leave the decoder's default, which is the case while that default is
    /// older than version 9. Should a later macOS make version 9 (or newer)
    /// the default, the newest older version the file supports is used
    /// instead, so untouched photos keep their rendering.
    ///
    /// - Parameter supported: `supportedDecoderVersions`, oldest first.
    public static func pinnedVersion(default current: String, supported: [String]) -> String? {
        guard let major = majorVersion(of: current), major >= decoderMajorVersion else { return nil }
        return supported.last { (majorVersion(of: $0) ?? .max) < decoderMajorVersion }
    }

    // MARK: Availability

    /// macOS 27 and later have the machine learning decoder; macOS 27 runs
    /// only on Apple silicon, so the Neural Engine is always there.
    public static var systemSupportsMachineLearning: Bool {
        if #available(macOS 27, *) { true } else { false }
    }

    /// The availability rule (design §11): one place the inspector, the
    /// loupe, export and `photocli` read.
    public static func availability(isRaw: Bool, systemSupports: Bool, decoderVersions: [String]) -> Availability {
        guard isRaw else { return .notRaw }
        guard systemSupports else { return .notOnThisMac }
        return machineLearningVersion(in: decoderVersions) == nil ? .cameraNotSupported : .available
    }

    /// The availability for `source` on this Mac, `decoderVersions` being its
    /// decoder's `supportedDecoderVersions` (read from the file when nil).
    /// Overrides (`setOverride`) come first.
    public static func availability(for source: URL, decoderVersions: [String]? = nil) -> Availability {
        let isRaw = SupportedFormats.isRaw(pathExtension: source.pathExtension)
        guard isRaw else { return .notRaw }
        if let forced = override(for: source)?.availability { return forced }
        guard systemSupportsMachineLearning else { return .notOnThisMac }
        let versions = decoderVersions ?? CIRAWFilter(imageURL: source)?.supportedDecoderVersions.map(\.rawValue) ?? []
        return availability(isRaw: true, systemSupports: true, decoderVersions: versions)
    }

    // MARK: Overrides (tests and the debug script)

    /// Replaces what this Mac would decide, for tests and the debug script
    /// only (design §11: a debug-only override lets one Mac show every
    /// state). Never set in normal use.
    public struct Override: Hashable, Sendable {
        /// Reported instead of this Mac's own answer (never for files that are not RAW).
        public var availability: Availability?
        /// Every decode with the machine learning version fails, as a failed
        /// model run would (AC7a).
        public var failsDecode: Bool

        public init(availability: Availability? = nil, failsDecode: Bool = false) {
            self.availability = availability
            self.failsDecode = failsDecode
        }
    }

    private static let overrides = Mutex<[String: Override]>([:])
    private static let everySource = "*"

    /// Sets (or with nil removes) the override for one file, or for every
    /// file when `source` is nil. Tests use one file each, so tests running
    /// in parallel do not see each other's.
    public static func setOverride(_ override: Override?, for source: URL? = nil) {
        let key = source.map(key(for:)) ?? everySource
        overrides.withLock { $0[key] = override }
    }

    /// The override for `source`: its own, else the one for every file.
    public static func override(for source: URL) -> Override? {
        let key = key(for: source)
        return overrides.withLock { $0[key] ?? $0[everySource] }
    }

    private static func key(for source: URL) -> String {
        source.standardizedFileURL.path
    }
}

extension Adjustments {
    /// The stack asks for machine learning noise reduction (PRD R3), whether
    /// or not the Noise Reduction group is on and whether or not it can apply.
    public var asksForMachineLearning: Bool { noiseReduction.machineLearning }

    /// The Decoder pop-up's choice (PRD R3, design §4): the machine learning
    /// version turns machine learning on; any other turns it off and becomes
    /// the Profile group's decoder (nil for `defaultVersion`).
    public mutating func chooseDecoder(_ version: String, defaultVersion: String) {
        if MachineLearningNoiseReduction.isMachineLearningVersion(version) {
            noiseReduction.machineLearning = true
        } else {
            noiseReduction.machineLearning = false
            decode.decoderVersion = version == defaultVersion ? nil : version
        }
    }

    /// These values for a file that is not RAW: machine learning noise
    /// reduction never applies to one, so it is never stored on one (PRD R10).
    public func forNonRawFile() -> Adjustments {
        guard asksForMachineLearning || decode.legacyMachineLearningVersion != nil else { return self }
        var copy = self
        let before = copy.isEnabled(.noiseReduction)
        copy.noiseReduction.machineLearning = false
        copy.decode.legacyMachineLearningVersion = nil
        // A group left with nothing in it is on, as `setEnabled` keeps it.
        copy.setEnabled(.noiseReduction, before)
        return copy
    }
}

extension MachineLearningNoiseReduction {
    /// What the inspector, the Decoder pop-up and the loupe show for one
    /// photo's values (design §3 and §11): every surface reads this one rule.
    public struct Status: Hashable, Sendable {
        /// The values ask for it (`Adjustments.asksForMachineLearning`).
        public var asks: Bool
        /// The Noise Reduction group is on.
        public var groupIsOn: Bool
        /// Nil while it cannot be told (an offline original on a Mac that has
        /// the decoder: the camera is not known).
        public var availability: Availability?
        /// The frame on screen for these values was a failed machine learning decode.
        public var renderFailed: Bool

        public init(asks: Bool, groupIsOn: Bool, availability: Availability?, renderFailed: Bool = false) {
            self.asks = asks
            self.groupIsOn = groupIsOn
            self.availability = availability
            self.renderFailed = renderFailed
        }

        /// The design's states.
        public enum State: Hashable, Sendable {
            /// No control: the file is not RAW.
            case notOffered
            /// S1: off, available.
            case off
            /// S2: on and applied.
            case applied
            /// S3, S4: off, and it cannot be turned on here (the reason).
            case unavailable(Reason)
            /// S5, S6, S8: asked for and not applied (the reason).
            case notApplied(Reason)
            /// S7: asked for while the group is off; what the caption would
            /// say with the group on (`applied` or `notApplied`).
            indirect case groupOff(State)
            /// An offline original: the camera's support is not known.
            case unknown
        }

        public var state: State {
            guard availability != .notRaw else { return .notOffered }
            guard groupIsOn || !asks else {
                var on = self
                on.groupIsOn = true
                return .groupOff(on.state)
            }
            switch (asks, availability) {
            case (_, nil): return .unknown
            case (false, .available?): return .off
            case (false, let availability?): return Reason(availability).map(State.unavailable) ?? .off
            case (true, .available?): return renderFailed ? .notApplied(.failed) : .applied
            case (true, let availability?): return Reason(availability).map(State.notApplied) ?? .unknown
            }
        }

        /// The stack's request renders (design §11 *applied*).
        public var isApplied: Bool { state == .applied }

        /// Color is unavailable exactly while machine learning applies (PRD R4).
        public var colorIsAvailable: Bool { !isApplied }

        /// The check box can be changed: always while it is asked for (only the
        /// person turns it off, R6), otherwise only where it would apply.
        public var checkBoxIsEnabled: Bool { asks || availability == .available }

        /// The loupe's Machine Learning Not Applied badge and its reason: the
        /// values ask for it, the group is on, and it did not apply.
        public var notAppliedReason: Reason? {
            if case .notApplied(let reason) = state { return reason }
            return nil
        }

        /// The Decoder pop-up is dimmed while machine learning is asked for and
        /// not applied (design §4), so only the check box turns it off.
        public var decoderChoiceIsEnabled: Bool { notAppliedReason == nil }
    }
}
