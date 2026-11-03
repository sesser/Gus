import AppKit
import PhotoCore
import SwiftUI

/// Spacing for custom toolbar items (the thumbnail slider, the Activity
/// item, the import window's copy and scan status, and the library's Import
/// split button, whose segments the system draws flush): on macOS 26 each sits in
/// a glass capsule whose rounded ends clip content placed flush against
/// them. Standard Button and Label items get their padding from the system
/// and take none of this.
public enum ToolbarMetrics {
    /// Inside the capsule, on the leading and trailing sides.
    public static let capsuleInset: CGFloat = 8
    /// A status line fits within this width; only its name shortens.
    public static let maxStatusTextWidth: CGFloat = 260

    /// The toolbar's status font (counts in monospaced digits).
    static var statusFont: NSFont {
        NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    }

    /// `line(name)` fitted into `maxStatusTextWidth` by shortening the name
    /// in the middle: `Export to “Ex…ts”`. Words, counts and quotation
    /// marks stay whole.
    @MainActor
    public static func statusLine(name: String, _ line: (String) -> String) -> String {
        let attributes: [NSAttributedString.Key: Any] = [.font: statusFont]
        return MiddleTruncation.fit(name, maxWidth: Double(maxStatusTextWidth), line: line) {
            Double(ceil(($0 as NSString).size(withAttributes: attributes).width))
        }
    }
}

extension View {
    /// The shared inset inside a custom toolbar item's capsule. On macOS 15,
    /// which has no capsule, it is plain space between items.
    public func toolbarCapsuleInset() -> some View {
        padding(.horizontal, ToolbarMetrics.capsuleInset)
    }

    /// One line of toolbar status text, already fitted
    /// (`ToolbarMetrics.statusLine`): shown whole, never cut.
    public func toolbarStatusText() -> some View {
        lineLimit(1)
            .fixedSize()
    }
}
