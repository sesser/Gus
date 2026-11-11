import AppKit
import SwiftUI

/// Hands the window a SwiftUI view is in to `onChange`, when it joins one.
public struct WindowReader: NSViewRepresentable {
    let onChange: (NSWindow?) -> Void

    public init(onChange: @escaping (NSWindow?) -> Void) {
        self.onChange = onChange
    }

    public func makeNSView(context: Context) -> ReaderView {
        let view = ReaderView()
        view.onChange = onChange
        return view
    }

    public func updateNSView(_ view: ReaderView, context: Context) {
        view.onChange = onChange
    }

    public final class ReaderView: NSView {
        var onChange: ((NSWindow?) -> Void)?

        override public func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            let window = self.window
            // After the current update: SwiftUI state changes here would
            // otherwise happen during a view update.
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated { self?.onChange?(window) }
            }
        }
    }
}
