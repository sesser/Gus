import AppKit
import SwiftUI

/// Hands the window a SwiftUI view is in to `onChange`, when it joins one.
struct WindowReader: NSViewRepresentable {
    let onChange: (NSWindow?) -> Void

    func makeNSView(context: Context) -> ReaderView {
        let view = ReaderView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: ReaderView, context: Context) {
        view.onChange = onChange
    }

    final class ReaderView: NSView {
        var onChange: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
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
