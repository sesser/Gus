import CoreGraphics
import Foundation
import ImageIO

/// The metadata an exported file gets: ImageIO properties (EXIF, TIFF, GPS,
/// IPTC) and an XMP packet, chosen by `ExportSettings.Metadata`.
///
/// Camera and capture data come from the master; the descriptive fields
/// (creator and job title, copyright, usage terms, contact, title, caption,
/// accessibility texts, keywords) come from the
/// library, which is the source of truth for them. Rating, flag and color label
/// are never written: they only mean something inside the app.
struct ExportMetadata {
    var properties: [CFString: Any]
    var xmp: CGImageMetadata?

    /// IPTC fields that name a place.
    static var iptcLocationKeys: [CFString] { [
        kCGImagePropertyIPTCCity, kCGImagePropertyIPTCSubLocation, kCGImagePropertyIPTCProvinceState,
        kCGImagePropertyIPTCCountryPrimaryLocationCode, kCGImagePropertyIPTCCountryPrimaryLocationName,
        kCGImagePropertyIPTCContentLocationCode, kCGImagePropertyIPTCContentLocationName,
    ] }

    /// IPTC fields the library owns; the master's values are replaced.
    private static var iptcLibraryKeys: [CFString] { [
        kCGImagePropertyIPTCKeywords, kCGImagePropertyIPTCCaptionAbstract, kCGImagePropertyIPTCByline,
        kCGImagePropertyIPTCCopyrightNotice, kCGImagePropertyIPTCRightsUsageTerms,
        kCGImagePropertyIPTCCreatorContactInfo, kCGImagePropertyIPTCStarRating, kCGImagePropertyIPTCObjectName,
        kCGImagePropertyIPTCBylineTitle,
    ] }

    /// Camera and capture fields of the TIFF dictionary worth keeping; the
    /// rest describes the master's encoding.
    private static var tiffKeptKeys: [CFString] {
        [kCGImagePropertyTIFFMake, kCGImagePropertyTIFFModel, kCGImagePropertyTIFFDateTime]
    }

    /// EXIF fields that describe the master's pixels rather than the photo.
    private static var exifDroppedKeys: [CFString] { [
        kCGImagePropertyExifPixelXDimension, kCGImagePropertyExifPixelYDimension, kCGImagePropertyExifColorSpace,
        kCGImagePropertyExifComponentsConfiguration, kCGImagePropertyExifCompressedBitsPerPixel,
        kCGImagePropertyExifSubjectArea, kCGImagePropertyExifSubjectLocation, kCGImagePropertyExifMakerNote,
    ] }

    /// - Parameters:
    ///   - source: The master's ImageIO properties (`CGImageSourceCopyPropertiesAtIndex`).
    ///   - values: The library's descriptive fields and keywords for the exported version.
    static func make(source: [CFString: Any], values: SidecarValues, settings: ExportSettings) -> ExportMetadata {
        var properties: [CFString: Any] = [:]
        let mode = settings.metadata

        if mode == .all || mode == .noLocation {
            if var exif = source[kCGImagePropertyExifDictionary] as? [CFString: Any] {
                for key in exifDroppedKeys { exif[key] = nil }
                if !exif.isEmpty { properties[kCGImagePropertyExifDictionary] = exif }
            }
            if let aux = source[kCGImagePropertyExifAuxDictionary] as? [CFString: Any], !aux.isEmpty {
                properties[kCGImagePropertyExifAuxDictionary] = aux
            }
            if mode == .all, let gps = source[kCGImagePropertyGPSDictionary] as? [CFString: Any], !gps.isEmpty {
                properties[kCGImagePropertyGPSDictionary] = gps
            }
            let sourceTIFF = source[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
            var tiff: [CFString: Any] = [:]
            for key in tiffKeptKeys { tiff[key] = sourceTIFF[key] }
            tiff[kCGImagePropertyTIFFImageDescription] = text(values.caption)
            properties[kCGImagePropertyTIFFDictionary] = tiff

            var iptc = source[kCGImagePropertyIPTCDictionary] as? [CFString: Any] ?? [:]
            for key in iptcLibraryKeys { iptc[key] = nil }
            if mode == .noLocation {
                for key in iptcLocationKeys { iptc[key] = nil }
            }
            if !values.keywords.isEmpty { iptc[kCGImagePropertyIPTCKeywords] = values.keywords }
            iptc[kCGImagePropertyIPTCCaptionAbstract] = text(values.caption)
            iptc[kCGImagePropertyIPTCObjectName] = text(values.title)
            properties[kCGImagePropertyIPTCDictionary] = iptc
        }

        if mode != .none {
            var tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
            tiff[kCGImagePropertyTIFFArtist] = text(values.creator)
            tiff[kCGImagePropertyTIFFCopyright] = text(values.rights)
            properties[kCGImagePropertyTIFFDictionary] = tiff
            var iptc = properties[kCGImagePropertyIPTCDictionary] as? [CFString: Any] ?? [:]
            iptc[kCGImagePropertyIPTCByline] = text(values.creator).map { [$0] }
            iptc[kCGImagePropertyIPTCBylineTitle] = text(values.jobTitle).map { [$0] }
            iptc[kCGImagePropertyIPTCCopyrightNotice] = text(values.rights)
            iptc[kCGImagePropertyIPTCRightsUsageTerms] = text(values.usageTerms)
            properties[kCGImagePropertyIPTCDictionary] = iptc
        }
        for key in [kCGImagePropertyTIFFDictionary, kCGImagePropertyIPTCDictionary] {
            if (properties[key] as? [CFString: Any])?.isEmpty == true { properties[key] = nil }
        }

        // The rendered pixels are already upright.
        properties[kCGImagePropertyOrientation] = 1
        properties[kCGImagePropertyDPIWidth] = max(settings.ppi, 1)
        properties[kCGImagePropertyDPIHeight] = max(settings.ppi, 1)
        return ExportMetadata(properties: properties, xmp: mode == .none ? nil : xmp(values, mode: mode))
    }

    /// The library's fields as XMP, nil when there are none.
    private static func xmp(_ values: SidecarValues, mode: ExportSettings.Metadata) -> CGImageMetadata? {
        let document = XMPDocument.empty()
        typealias Namespace = XMPDocument.Namespace
        document.setArray(Namespace.dc, "creator", .seq, text(values.creator).map { [$0] } ?? [])
        document.setSimple(Namespace.photoshop, "AuthorsPosition", text(values.jobTitle))
        document.setAlternative(Namespace.dc, "rights", text(values.rights))
        document.setAlternative(Namespace.rights, "UsageTerms", text(values.usageTerms))
        document.setStruct(Namespace.iptcCore, "CreatorContactInfo", fieldNamespace: Namespace.iptcCore,
                           fields: XMPDocument.contactFields.map { ($0.field, values.contact?[keyPath: $0.path]) })
        if mode != .copyright {
            document.setAlternative(Namespace.dc, "title", text(values.title))
            document.setAlternative(Namespace.dc, "description", text(values.caption))
            document.setAlternative(Namespace.iptcCore, "AltTextAccessibility", text(values.altText))
            document.setAlternative(Namespace.iptcCore, "ExtDescrAccessibility", text(values.extendedDescription))
            document.setArray(Namespace.dc, "subject", .bag, values.keywords)
        }
        guard document.hasProperties else { return nil }
        return CGImageMetadataCreateFromXMPData(document.rootElementData() as CFData)
    }

    private static func text(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}

extension XMPDocument {
    /// Whether any description holds a property (child element or attribute
    /// other than `rdf:about`).
    var hasProperties: Bool {
        descriptions.contains { description in
            (description.children ?? []).contains { $0.kind == .element }
                || (description.attributes ?? []).contains { $0.localName != "about" }
        }
    }
}
