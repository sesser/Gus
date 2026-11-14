import AppKit
import PhotoCore
import SwiftUI

/// The About window and its license windows (issue #179 and its
/// design.md), shared by the library app and the standalone importer. Add after the app's main window scene: a
/// `Window` that comes first is the one shown at launch.
public struct AboutScenes: Scene {
    private let appName: String
    private let projectName: String

    /// - Parameters:
    ///   - appName: The running app's own name: the window's title and
    ///     header, as in its app menu.
    ///   - projectName: The name the dedication and the free-software
    ///     statement speak of. The project's, in both apps (owner ruling on
    ///     RI-A1, 2026-11-13): the importer is part of it.
    public init(appName: String, projectName: String = AppBranding.displayName) {
        self.appName = appName
        self.projectName = projectName
    }

    public var body: some Scene {
        Window(AboutText.aboutTitle(appName), id: AboutWindowID.about) {
            AboutView(appName: appName, projectName: projectName)
        }
        // Fixed width, height within the root view's limits.
        .windowResizability(.contentSize)
        .defaultSize(width: AboutMetrics.width, height: AboutMetrics.idealHeight)
        .defaultPosition(.center)
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.suppressed)
        // The title is not drawn, so the whole background moves the window.
        .windowBackgroundDragBehavior(.enabled)
        // No item for it in the Window menu: it has its own in two menus.
        .commandsRemoved()

        WindowGroup(id: AboutWindowID.license, for: LicenseDocument.self) { $document in
            if let document {
                LicenseView(document: document, appName: appName, projectName: projectName)
            }
        }
        .defaultSize(AboutMetrics.licenseDefaultSize)
        .defaultPosition(.center)
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.suppressed)
        // No File ▸ New Window for it.
        .commandsRemoved()
    }
}

/// App menu ▸ About ‹name› (in place of the system's panel) and Help ▸
/// About ‹name›: the same item twice, opening the one About window.
///
/// It reads no focused value: it has no state to follow and must work with
/// no key window, with a sheet up, and in the importer, which has no library.
public struct AboutCommands: Commands {
    private let appName: String
    @Environment(\.openWindow) private var openWindow

    /// - Parameter appName: The running app's own name, as in its app menu.
    public init(appName: String) {
        self.appName = appName
    }

    public var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button(AboutText.aboutTitle(appName)) { openWindow(id: AboutWindowID.about) }
        }
        // Replaces SwiftUI's "‹app› Help", which only says there is no help;
        // the Help menu and its search field stay.
        CommandGroup(replacing: .help) {
            Button(AboutText.aboutTitle(appName)) { openWindow(id: AboutWindowID.about) }
        }
    }
}

struct AboutView: View {
    let appName: String
    let projectName: String

    @State private var content = AboutContent.beforeAppearing
    @State private var headerHeight: CGFloat = 0
    @State private var bodyHeight: CGFloat = 0
    /// The title bar's height: the view is laid out under it, and the
    /// design's heights are the window's.
    @State private var titleBarHeight: CGFloat = 0
    @Environment(\.openWindow) private var openWindow

    private var minHeight: CGFloat { AboutMetrics.minHeight - titleBarHeight }

    /// The window can be stretched until everything shows, and no further.
    private var maxHeight: CGFloat {
        guard headerHeight > 0, bodyHeight > 0 else { return .infinity }
        return max(minHeight, (headerHeight + bodyHeight).rounded(.up))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { headerHeight = $0 }
            // A SwiftUI scroll view: this window has no toolbar, so the rule
            // against one under the toolbar doesn't apply (status.md, Q-E6).
            ScrollView(.vertical) {
                acknowledgements
                    .onGeometryChange(for: CGFloat.self, of: \.size.height) { bodyHeight = $0 }
            }
        }
        .frame(width: AboutMetrics.width)
        .frame(minHeight: minHeight, idealHeight: min(AboutMetrics.idealHeight - titleBarHeight, maxHeight),
               maxHeight: maxHeight)
        .onGeometryChange(for: CGFloat.self, of: \.safeAreaInsets.top) { titleBarHeight = $0 }
        // The header shows the name; the window keeps its title for
        // VoiceOver and Mission Control.
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .windowMinimizeBehavior(.disabled)
        .windowFullScreenBehavior(.disabled)
        .environment(\.openURL, AboutLinks.action)
        .background(WindowReader { AboutWindowRegistry.registerAbout($0) })
        .onAppear(perform: refresh)
    }

    /// Decided each time the window opens: nothing is kept between
    /// openings. Two small files in the bundle are read here, on the main
    /// actor (about 40 KB together).
    private func refresh() {
        content = .current
        AboutWindowRegistry.shown = (content, appName, projectName)
        let openWindow = openWindow
        AboutWindowRegistry.openLicense = { openWindow(id: AboutWindowID.license, value: $0) }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: AboutMetrics.iconSize, height: AboutMetrics.iconSize)
                .accessibilityHidden(true)
                .padding(.bottom, AboutMetrics.iconToName)
            Text(verbatim: appName)
                .font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            if let version = content.version {
                Text(verbatim: AboutText.version(version))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(.top, AboutMetrics.nameToVersion)
            }
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
        .padding(.top, AboutMetrics.headerTop)
        .padding(.bottom, AboutMetrics.headerBottom)
        .padding(.horizontal, AboutMetrics.bodySide)
        .overlay(alignment: .bottom) { Divider() }
    }

    // MARK: Dedication, entries, footer

    private var acknowledgements: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: AboutText.dedication(projectName))
                .font(.body)
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, AboutMetrics.dedicationToEntries)
            VStack(alignment: .leading, spacing: AboutMetrics.entrySpacing) {
                ForEach(content.entries) { entry in
                    AboutEntryView(entry: entry, offersLicense: content.offersLicense(for: entry)) {
                        openWindow(id: AboutWindowID.license, value: LicenseDocument.project(entry.project))
                    }
                }
            }
            Divider()
                .padding(.top, AboutMetrics.entriesToDivider)
                .padding(.bottom, AboutMetrics.dividerToFooter)
            footer
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AboutMetrics.bodySide)
        .padding(.vertical, AboutMetrics.bodyVertical)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: AboutText.copyright)
                .textSelection(.enabled)
            Text(verbatim: AboutText.freeSoftwareStatement(projectName))
                .padding(.top, AboutMetrics.copyrightToStatement)
            if content.offersAppLicense {
                Button(AboutText.viewLicense) {
                    openWindow(id: AboutWindowID.license, value: LicenseDocument.app)
                }
                .controlSize(.small)
                .accessibilityLabel(Text(verbatim: AboutText.viewLicenseLabel(projectName)))
                .padding(.top, AboutMetrics.statementToButton)
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }
}

/// One acknowledged project: its name and page, what it gave, its license
/// and, when the bundle has the text, View License.
private struct AboutEntryView: View {
    let entry: Acknowledgement
    let offersLicense: Bool
    let viewLicense: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AboutMetrics.entryLineSpacing) {
            // The page beside the name; under it when the two don't fit.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    name
                    Spacer(minLength: AboutMetrics.bodySide)
                    page
                }
                VStack(alignment: .leading, spacing: AboutMetrics.entryLineSpacing) {
                    name
                    page
                }
            }
            Text(verbatim: AboutText.summary(of: entry.project))
                .font(.body)
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: AboutText.name(of: entry.license))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer(minLength: AboutMetrics.bodySide)
                if offersLicense {
                    Button(AboutText.viewLicense, action: viewLicense)
                        .controlSize(.small)
                        .accessibilityLabel(Text(verbatim: AboutText.viewLicenseLabel(entry.name)))
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: entry.name))
    }

    /// A proper name, from the record: never translated.
    private var name: some View {
        Text(verbatim: entry.name)
            .font(.headline)
    }

    /// The link shows where it goes; the system opens it in the browser.
    private var page: some View {
        Link(destination: entry.page) {
            Text(verbatim: entry.displayAddress)
        }
        .font(.callout)
        .help(Text(verbatim: entry.page.absoluteString))
    }
}
