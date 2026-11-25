import Foundation

/// Which version of a gain-map photo the loupe, review or a comparison pane
/// shows, and why (issue #282, R4, design §4 and §5): what its one version
/// badge says. The texts are the app's (`HDRText`); the rule is here.
public enum HDRVersionBadge: Equatable, Sendable {
    /// No version badge: not a gain-map photo (or not known to be one while
    /// offline with the choice off, RI-3), or a map is shown (RI-4).
    case none
    /// The HDR version is on screen. `fileHeadroom`: how far the file goes;
    /// `allowedNow`: what the display allows now, when known (design §18.2).
    case hdr(fileHeadroom: Float?, allowedNow: Float?)
    /// The choice is off: the SDR version, a normal state. `offline`: the
    /// original is offline, so the cached SDR preview is shown and the
    /// choice can't be turned on (design §19.1).
    case sdr(offline: Bool)
    /// The choice is on and the HDR version is not on screen yet.
    case loading
    /// The choice is on and HDR can't be shown, for the first reason that applies (design §5).
    case blocked(HDRBlockReason)

    /// The badge for one shown photo. `hasGainMap`: the file is known to
    /// have a gain map (its header was read, or its choice is on).
    /// `extendedRange`: the display reports extended range at all (its
    /// potential above 1; a low current headroom is not a reason, RI-7).
    /// `shown`: the version on screen; `isMap`: a sharpening or fringe map
    /// is shown in place of the photo.
    public init(hasGainMap: Bool, choice: Bool, offline: Bool, viewSetting: Bool, extendedRange: Bool,
                failed: Bool, shown: ShownVersion?, isMap: Bool, fileHeadroom: Float?, allowedNow: Float?) {
        guard !isMap, hasGainMap || choice else {
            self = .none
            return
        }
        guard choice else {
            self = .sdr(offline: offline)
            return
        }
        if let reason = HDRBlockReason(offline: offline, viewSetting: viewSetting, extendedRange: extendedRange,
                                       failed: failed) {
            self = .blocked(reason)
        } else if shown == .hdr {
            self = .hdr(fileHeadroom: fileHeadroom, allowedNow: allowedNow)
        } else {
            self = .loading
        }
    }

    /// The HDR picture is fitted to the display (design §4): what the
    /// display allows now is below the file's headroom, compared at the one
    /// decimal the help tag shows. Unknown counts as not fitted.
    public var isFitted: Bool {
        guard case .hdr(let file?, let allowed?) = self else { return false }
        return Self.oneDecimal(allowed) < Self.oneDecimal(file)
    }

    static func oneDecimal(_ value: Float) -> Float { (value * 10).rounded() / 10 }

    /// The words the debug script prints.
    public var name: String {
        switch self {
        case .none: "none"
        case .hdr: isFitted ? "hdr fitted" : "hdr"
        case .sdr(let offline): offline ? "sdr cached" : "sdr"
        case .loading: "loading"
        case .blocked(let reason): "sdr \(reason.rawValue)"
        }
    }
}

/// Why a photo with the HDR choice on shows SDR, in the order they are
/// checked (design §5): the first that applies is the one shown.
public enum HDRBlockReason: String, Sendable, CaseIterable {
    case offline, hidden, noHDRDisplay, failed

    public init?(offline: Bool, viewSetting: Bool, extendedRange: Bool, failed: Bool) {
        if offline {
            self = .offline
        } else if !viewSetting {
            self = .hidden
        } else if !extendedRange {
            self = .noHDRDisplay
        } else if failed {
            self = .failed
        } else {
            return nil
        }
    }
}
