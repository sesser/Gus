import Foundation

/// The app's version as the About window shows it ("Version 0.1.0 (build 1)").
public struct AppVersion: Equatable, Sendable {
    public var short: String
    public var build: String

    /// From a bundle's Info.plist: `CFBundleShortVersionString` and
    /// `CFBundleVersion`. Nil when there is no dictionary (no bundle, as
    /// with `swift run`) or either value is missing, not text, or empty,
    /// so the line is left out rather than shown with a hole in it (R4).
    public init?(infoDictionary: [String: Any]?) {
        func value(_ key: String) -> String? {
            guard let text = (infoDictionary?[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty
            else { return nil }
            return text
        }
        guard let short = value("CFBundleShortVersionString"), let build = value("CFBundleVersion") else { return nil }
        self.short = short
        self.build = build
    }
}

/// Everything the About window shows that depends on the bundle it runs
/// from, decided each time the window opens (design §5): the version line,
/// the acknowledged projects, and which license texts can be shown.
public struct AboutContent: Equatable, Sendable {
    public var version: AppVersion?
    public var entries: [Acknowledgement]
    public var availableLicenses: Set<LicenseDocument>

    public init(infoDictionary: [String: Any]?, licenses: BundledLicenses,
                entries: [Acknowledgement] = Acknowledgements.all) {
        version = AppVersion(infoDictionary: infoDictionary)
        self.entries = entries
        availableLicenses = licenses.available(among: entries)
    }

    /// Whether an entry gets a View License button.
    public func offersLicense(for entry: Acknowledgement) -> Bool {
        availableLicenses.contains(.project(entry.project))
    }

    /// Whether the footer gets one, for this project's own license.
    public var offersAppLicense: Bool {
        availableLicenses.contains(.app)
    }
}
