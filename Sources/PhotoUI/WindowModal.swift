import AppKit

/// Open and save panels and alerts attached to the window they act for
/// (section 8 of docs/UI_REDESIGN.md, "The rule"): the key window, which
/// is the sheet when one is up. App-modal only when there is no window.
@MainActor
public enum WindowModal {
    /// True when the person chose OK (Open, Save, the prompt).
    public static func run(_ panel: NSSavePanel, in window: NSWindow? = NSApp.keyWindow) async -> Bool {
        guard let window else { return panel.runModal() == .OK }
        return await withCheckedContinuation { continuation in
            panel.beginSheetModal(for: window) { response in
                continuation.resume(returning: response == .OK)
            }
        }
    }

    public static func run(_ alert: NSAlert, in window: NSWindow? = NSApp.keyWindow) async -> NSApplication.ModalResponse {
        guard let window else { return alert.runModal() }
        return await withCheckedContinuation { continuation in
            alert.beginSheetModal(for: window) { response in
                continuation.resume(returning: response)
            }
        }
    }
}
