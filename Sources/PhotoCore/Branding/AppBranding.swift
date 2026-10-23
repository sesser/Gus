import Foundation

/// Every brand-dependent value in the code base.
///
/// This is the only Swift file allowed to spell the product name. Everything else
/// (UI, file locations, URL handling, sidecars) reads from here, and
/// `BrandingTests` fails if the name leaks anywhere else in `Sources/` or if these
/// values drift from `Branding.xcconfig`. See RENAMING.md.
public enum AppBranding {
    /// Name shown to people: window titles, menus, dialogs.
    public static let displayName = "Gus"

    /// Must match `PRODUCT_BUNDLE_IDENTIFIER` in Branding.xcconfig.
    public static let bundleIdentifier = "me.sesser.gus"

    /// Folder under `~/Library/Application Support` that holds the catalog.
    public static let appSupportDirectoryName = "Gus"

    /// Folder under `~/Library/Caches` that holds generated previews.
    public static let cacheDirectoryName = "me.sesser.gus"

    /// XMP namespace URI for any custom sidecar properties. Once sidecars have been
    /// written, keep this stable across renames (see RENAMING.md).
    public static let sidecarNamespace = "http://ns.sesser.me/gus/1.0/"

    /// Preferred XMP prefix bound to `sidecarNamespace`.
    public static let sidecarNamespacePrefix = "gus"

    /// Custom URL scheme registered in Info.plist via `PRODUCT_URL_SCHEME`.
    public static let urlScheme = "gus"

    /// Earlier values of `appSupportDirectoryName`, newest first. On launch the
    /// data directory is moved from the first one that exists to the current name.
    public static let previousAppSupportDirectoryNames: [String] = []

    /// Earlier values of `cacheDirectoryName`. Old caches are deleted, not moved.
    public static let previousCacheDirectoryNames: [String] = []
}
