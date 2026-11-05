import AppKit
import SwiftUI

/// A vertical AppKit scroll view around SwiftUI content, sized to the content's
/// height at the scroll view's width.
///
/// The app supports macOS 15, so macOS 26 and later run it with the earlier
/// design. There, a SwiftUI `ScrollView` that sits under the toolbar (as the
/// inspector's does) hit-tests every click to its own content container, and
/// buttons, text fields and AppKit views inside it never see the click. An
/// AppKit scroll view hit-tests normally.
struct AppKitScrollView<Content: View>: NSViewRepresentable {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.contentView = FlippedClipView()
        scrollView.contentView.drawsBackground = false

        let host = NSHostingView(rootView: Measured(content: content, coordinator: context.coordinator))
        host.sizingOptions = []
        host.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = host
        let clip = scrollView.contentView
        let height = host.heightAnchor.constraint(equalToConstant: 0)
        context.coordinator.height = height
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
            host.topAnchor.constraint(equalTo: clip.topAnchor),
            height,
        ])
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        (scrollView.documentView as? NSHostingView<Measured>)?.rootView =
            Measured(content: content, coordinator: context.coordinator)
    }

    @MainActor
    final class Coordinator {
        var height: NSLayoutConstraint?

        func contentHeightChanged(_ value: CGFloat) {
            guard let height, abs(height.constant - value) > 0.5 else { return }
            height.constant = value
        }
    }

    /// The content at its ideal height for the width it is given, top-aligned,
    /// reporting that height so the document view can follow it.
    struct Measured: View {
        let content: Content
        let coordinator: Coordinator

        var body: some View {
            content
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { coordinator.contentHeightChanged($0) }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}

final class FlippedClipView: NSClipView {
    override var isFlipped: Bool { true }
}

/// Scrolls the view it is the background of into view in the enclosing
/// `AppKitScrollView` when `isRequested` turns true, then calls `done`.
/// Animated, or a jump with Reduce Motion. A SwiftUI `ScrollViewReader`
/// can't reach an AppKit scroll view, hence a view of its own.
struct InspectorRevealAnchor: NSViewRepresentable {
    let isRequested: Bool
    let done: () -> Void

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        guard isRequested else { return }
        let done = done
        // The request often comes with the inspector, tab or heading that
        // shows this view: scroll once that layout has settled.
        Task { @MainActor [weak view] in
            await Task.yield()
            await Task.yield()
            guard let view else { return }
            done()
            Self.reveal(view)
        }
    }

    static func reveal(_ view: NSView) {
        guard let scrollView = view.enclosingScrollView, let document = scrollView.documentView else { return }
        document.layoutSubtreeIfNeeded()
        let clip = scrollView.contentView
        let margin = InspectorMetrics.padding
        let target = view.convert(view.bounds, to: document).insetBy(dx: 0, dy: -margin)
        let visible = clip.bounds
        var origin = visible.origin
        // The clip view and the hosting view are flipped: y grows downward.
        if target.minY < visible.minY {
            origin.y = target.minY
        } else if target.maxY > visible.maxY {
            origin.y = min(target.minY, target.maxY - visible.height)
        } else {
            return
        }
        origin = clip.constrainBoundsRect(NSRect(origin: origin, size: visible.size)).origin
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            clip.scroll(to: origin)
            scrollView.reflectScrolledClipView(clip)
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                clip.animator().setBoundsOrigin(origin)
            }
            scrollView.reflectScrolledClipView(clip)
        }
    }
}
