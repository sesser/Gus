import SwiftUI

/// Spacing for custom toolbar items (the thumbnail slider, the Activity
/// item, the import window's progress): on macOS 26 each sits in a glass
/// capsule whose rounded ends clip content placed flush against them.
public enum ToolbarMetrics {
    /// Inside the capsule, on the leading and trailing sides.
    public static let capsuleInset: CGFloat = 8
    /// Status text truncates (with an ellipsis) beyond this width rather
    /// than run into the capsule's end.
    public static let maxStatusTextWidth: CGFloat = 260
}

extension View {
    /// The shared inset inside a toolbar item's capsule. On macOS 15, which
    /// has no capsule, it is plain space between items.
    public func toolbarCapsuleInset() -> some View {
        padding(.horizontal, ToolbarMetrics.capsuleInset)
    }

    /// One line of toolbar status text: truncated at the end with an
    /// ellipsis past `ToolbarMetrics.maxStatusTextWidth`.
    public func toolbarStatusText() -> some View {
        lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: ToolbarMetrics.maxStatusTextWidth, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}
