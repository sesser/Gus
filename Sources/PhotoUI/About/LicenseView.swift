import AppKit
import PhotoCore
import SwiftUI

/// A window showing one license text exactly as the bundle stores it: a
/// project's section of the notices file, or this project's `LICENSE`
/// (design §6). One window per license; View License on an open one brings
/// it forward.
struct LicenseView: View {
    let document: LicenseDocument
    let appName: String
    let projectName: String

    private enum Phase: Equatable {
        case reading
        case text(String)
        /// The file went missing after the About window offered it.
        case missing
    }

    @State private var phase = Phase.reading
    /// The title bar's height: the view is laid out under it, and the
    /// design's minimum is the window's.
    @State private var titleBarHeight: CGFloat = 0

    private var title: String {
        AboutText.licenseTitle(AboutText.owner(of: document, projectName: projectName))
    }

    var body: some View {
        Group {
            switch phase {
            case .reading:
                Color.clear
            case .text(let text):
                LicenseTextArea(text: text)
            case .missing:
                ContentUnavailableView {
                    // A label, so the title gets the title's style; the
                    // design names no symbol for this state.
                    Label {
                        Text(verbatim: AboutText.licenseMissingTitle)
                    } icon: {
                        EmptyView()
                    }
                } description: {
                    Text(verbatim: AboutText.licenseMissingDescription(appName))
                }
            }
        }
        .frame(minWidth: AboutMetrics.licenseMinSize.width, maxWidth: .infinity,
               minHeight: AboutMetrics.licenseMinSize.height - titleBarHeight, maxHeight: .infinity)
        .onGeometryChange(for: CGFloat.self, of: \.safeAreaInsets.top) { titleBarHeight = $0 }
        .navigationTitle(Text(verbatim: title))
        .background(WindowReader { AboutWindowRegistry.registerLicense($0, for: document) })
        .task(id: document) {
            // Read off the main actor, each time the window opens.
            let licenses = BundledLicenses.main
            let document = document
            let text = await Task.detached { licenses.text(for: document) }.value
            phase = text.map(Phase.text) ?? .missing
        }
    }
}

/// The license text in a read-only AppKit text view. SwiftUI has no
/// read-only, selectable text view that lays out a 35 KB text lazily and can
/// be searched; `NSTextView` does both.
private struct LicenseTextArea: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = LicenseTextView.scrollableTextView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        guard let textView = scrollView.documentView as? LicenseTextView else { return scrollView }
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = false
        // Shown as the characters it is: nothing is restyled or made a link.
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        // Licenses are hand-wrapped plain text laid out in columns.
        textView.font = .monospacedSystemFont(ofSize: AboutMetrics.licenseFontSize, weight: .regular)
        textView.textColor = .textColor
        textView.backgroundColor = .textBackgroundColor
        textView.drawsBackground = true
        textView.textContainerInset = NSSize(width: AboutMetrics.licenseTextInset, height: AboutMetrics.licenseTextInset)
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.string = text
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? LicenseTextView, textView.string != text else { return }
        textView.string = text
    }
}

/// Answers ⌘F, ⌘G and ⇧⌘G itself, with its find bar. The key window's views
/// are offered a key equivalent before the menu bar, so this neither needs
/// an Edit ▸ Find item nor meets the library window's own ⌘F, which is off
/// while another window is key.
final class LicenseTextView: NSTextView {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        // `characters`, as menu key equivalents are matched: with Command
        // down it is the Latin letter even on a layout whose own letter on
        // that key is another (Russian, Greek).
        switch (event.characters?.lowercased(), modifiers) {
        case ("f", [.command]):
            find(.showFindInterface)
        case ("g", [.command]):
            find(.nextMatch)
        case ("g", [.command, .shift]):
            find(.previousMatch)
        default:
            return super.performKeyEquivalent(with: event)
        }
        return true
    }

    /// One of the text finder's actions, as a menu item with its tag would ask.
    func find(_ action: NSTextFinder.Action) {
        // The find bar lies over the top of the text. Shown while the text
        // is at its start, it would cover the first lines: stay at the start.
        let clip = enclosingScrollView?.contentView
        let wasAtStart = clip.map { $0.bounds.minY <= -$0.contentInsets.top + 1 } ?? false
        let item = NSMenuItem()
        item.tag = action.rawValue
        performTextFinderAction(item)
        guard action == .showFindInterface, wasAtStart else { return }
        DispatchQueue.main.async { [weak self] in
            guard let scrollView = self?.enclosingScrollView else { return }
            let clip = scrollView.contentView
            clip.scroll(to: NSPoint(x: clip.bounds.minX, y: -clip.contentInsets.top))
            scrollView.reflectScrolledClipView(clip)
        }
    }
}
