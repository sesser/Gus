import AppKit
import PhotoCore

/// Words for VoiceOver shared by the library grid and the import window.
public enum AccessibilityText {
    /// The file types of a shot or pair as spoken: "JPEG", "RAW plus JPEG".
    /// The badge abbreviations, so what is heard matches what is shown.
    public static func fileType(_ kinds: [FileKind]) -> String {
        let names = kinds.map(FileKindText.badge)
        guard let first = names.first else { return "" }
        return names.dropFirst().reduce(first) { spoken, next in
            String(localized: "\(spoken) plus \(next)", comment: "VoiceOver: the file types of a RAW+JPEG pair, as in “RAW plus JPEG”")
        }
    }

    /// Parts of a label or value, in order, without the empty ones.
    public static func list(_ parts: [String]) -> String {
        parts.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// The last text passed to `announce`, for debug scripts (which run
    /// without VoiceOver).
    @MainActor public private(set) static var lastAnnouncement: String?

    /// Speaks `text` when VoiceOver is on, without moving its focus.
    @MainActor
    public static func announce(_ text: String) {
        lastAnnouncement = text
        guard !text.isEmpty, NSWorkspace.shared.isVoiceOverEnabled else { return }
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested, userInfo: [
            .announcement: text,
            .priority: NSAccessibilityPriorityLevel.high.rawValue,
        ])
    }
}
