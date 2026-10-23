import Foundation

/// An XMP packet (a sidecar file) as XML, edited in place: the app changes only
/// the properties it owns and leaves everything else (other apps' develop
/// settings, history, hierarchical keywords it did not touch) as it was.
///
/// Properties can appear as attributes or child elements of any of the packet's
/// `rdf:Description` elements; both are read, and a property is removed from
/// every place before it is written to the first description.
final class XMPDocument {
    enum Namespace {
        static let rdf = "http://www.w3.org/1999/02/22-rdf-syntax-ns#"
        static let meta = "adobe:ns:meta/"
        static let xmp = "http://ns.adobe.com/xap/1.0/"
        static let dc = "http://purl.org/dc/elements/1.1/"
        static let rights = "http://ns.adobe.com/xap/1.0/rights/"
        static let iptcCore = "http://iptc.org/std/Iptc4xmpCore/1.0/xmlns/"
        static let lightroom = "http://ns.adobe.com/lightroom/1.0/"
        static let xml = "http://www.w3.org/XML/1998/namespace"
        static let app = AppBranding.sidecarNamespace

        static let preferredPrefixes: [String: String] = [
            xmp: "xmp", dc: "dc", rights: "xmpRights", iptcCore: "Iptc4xmpCore", lightroom: "lr",
            app: AppBranding.sidecarNamespacePrefix,
        ]
    }

    enum ArrayKind: String {
        case bag = "Bag"
        case seq = "Seq"
        case alt = "Alt"
    }

    struct ParseError: Error {}

    let document: XMLDocument

    init(data: Data) throws {
        document = try XMLDocument(data: data, options: [.nodePreserveNamespaceOrder, .nodePreserveAttributeOrder])
        guard !descriptions.isEmpty else { throw ParseError() }
    }

    /// A new packet with one empty description.
    static func empty() -> XMPDocument {
        let text = """
            <?xpacket begin="\u{FEFF}" id="W5M0MpCehiHzreSzNTczkc9d"?>
            <x:xmpmeta xmlns:x="adobe:ns:meta/">
             <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
              <rdf:Description rdf:about=""/>
             </rdf:RDF>
            </x:xmpmeta>
            <?xpacket end="w"?>
            """
        // The template is well formed.
        return try! XMPDocument(data: Data(text.utf8))
    }

    /// The packet's processing instructions and root element, without an XML
    /// declaration: sidecars written by other apps start with the packet itself.
    func data() -> Data {
        let parts = (document.children ?? []).map { $0.xmlString(options: [.nodePrettyPrint, .nodeCompactEmptyElement]) }
        return Data((parts.joined(separator: "\n") + "\n").utf8)
    }

    // MARK: Reading

    var descriptions: [XMLElement] {
        (try? document.nodes(forXPath: "//*[local-name()='Description']"))?
            .compactMap { $0 as? XMLElement }
            .filter { $0.uri == Namespace.rdf } ?? []
    }

    private func elements(_ namespace: String, _ name: String) -> [XMLElement] {
        descriptions.flatMap { $0.elements(forLocalName: name, uri: namespace) }
    }

    /// A simple property: an attribute, or an element holding text.
    func simple(_ namespace: String, _ name: String) -> String? {
        for description in descriptions {
            if let value = description.attribute(forLocalName: name, uri: namespace)?.stringValue { return value }
        }
        return elements(namespace, name).first { $0.children?.allSatisfy { $0.kind == .text } ?? true }?
            .stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The items of an `rdf:Bag`, `rdf:Seq` or `rdf:Alt` (or a lone simple value).
    func array(_ namespace: String, _ name: String) -> [String] {
        for element in elements(namespace, name) {
            if let container = element.elements(forLocalName: ArrayKind.bag.rawValue, uri: Namespace.rdf).first
                ?? element.elements(forLocalName: ArrayKind.seq.rawValue, uri: Namespace.rdf).first
                ?? element.elements(forLocalName: ArrayKind.alt.rawValue, uri: Namespace.rdf).first {
                return container.elements(forLocalName: "li", uri: Namespace.rdf)
                    .compactMap { $0.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
        }
        return simple(namespace, name).map { [$0] } ?? []
    }

    /// A language alternative: the `x-default` item, or the first one.
    func alternative(_ namespace: String, _ name: String) -> String? {
        for element in elements(namespace, name) {
            guard let alt = element.elements(forLocalName: ArrayKind.alt.rawValue, uri: Namespace.rdf).first else { continue }
            let items = alt.elements(forLocalName: "li", uri: Namespace.rdf)
            let preferred = items.first { $0.attribute(forLocalName: "lang", uri: Namespace.xml)?.stringValue == "x-default" }
            return (preferred ?? items.first)?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return simple(namespace, name)
    }

    /// A field of a struct property, written as child elements (parseType
    /// Resource), a nested description, or attributes.
    func structField(_ namespace: String, _ name: String, field: String, fieldNamespace: String) -> String? {
        for element in elements(namespace, name) {
            let holders = [element] + element.elements(forLocalName: "Description", uri: Namespace.rdf)
            for holder in holders {
                if let value = holder.attribute(forLocalName: field, uri: fieldNamespace)?.stringValue { return value }
                if let value = holder.elements(forLocalName: field, uri: fieldNamespace).first?.stringValue {
                    return value.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
        return nil
    }

    // MARK: Writing

    /// Removes the property from every description.
    func remove(_ namespace: String, _ name: String) {
        for description in descriptions {
            if let attribute = description.attribute(forLocalName: name, uri: namespace), let attributeName = attribute.name {
                description.removeAttribute(forName: attributeName)
            }
            for element in description.elements(forLocalName: name, uri: namespace) {
                element.detach()
            }
        }
    }

    func setSimple(_ namespace: String, _ name: String, _ value: String?) {
        remove(namespace, name)
        guard let value, let target = descriptions.first else { return }
        let qualified = qualifiedName(namespace, name, declaringOn: target)
        let element = XMLElement(name: qualified, uri: namespace)
        element.stringValue = value
        target.addChild(element)
    }

    func setArray(_ namespace: String, _ name: String, _ kind: ArrayKind, _ values: [String]) {
        remove(namespace, name)
        guard !values.isEmpty, let target = descriptions.first else { return }
        let element = XMLElement(name: qualifiedName(namespace, name, declaringOn: target), uri: namespace)
        let container = XMLElement(name: rdfName(kind.rawValue, on: target), uri: Namespace.rdf)
        for value in values {
            let item = XMLElement(name: rdfName("li", on: target), uri: Namespace.rdf)
            item.stringValue = value
            if kind == .alt {
                item.addAttribute(XMLNode.attribute(withName: "xml:lang", uri: Namespace.xml, stringValue: "x-default") as! XMLNode)
            }
            container.addChild(item)
        }
        element.addChild(container)
        target.addChild(element)
    }

    func setAlternative(_ namespace: String, _ name: String, _ value: String?) {
        setArray(namespace, name, .alt, value.map { [$0] } ?? [])
    }

    func setStruct(_ namespace: String, _ name: String, fieldNamespace: String, fields: [(String, String?)]) {
        remove(namespace, name)
        let present = fields.compactMap { field, value in value.flatMap { $0.isEmpty ? nil : (field, $0) } }
        guard !present.isEmpty, let target = descriptions.first else { return }
        let element = XMLElement(name: qualifiedName(namespace, name, declaringOn: target), uri: namespace)
        element.addAttribute(XMLNode.attribute(withName: rdfName("parseType", on: target), uri: Namespace.rdf,
                                               stringValue: "Resource") as! XMLNode)
        for (field, value) in present {
            let child = XMLElement(name: qualifiedName(fieldNamespace, field, declaringOn: target), uri: fieldNamespace)
            child.stringValue = value
            element.addChild(child)
        }
        target.addChild(element)
    }

    /// `prefix:name`, declaring a prefix for `namespace` on `element` when no
    /// ancestor already binds one.
    private func qualifiedName(_ namespace: String, _ name: String, declaringOn element: XMLElement) -> String {
        if let prefix = element.resolvePrefix(forNamespaceURI: namespace) {
            return prefix.isEmpty ? name : "\(prefix):\(name)"
        }
        var prefix = Namespace.preferredPrefixes[namespace] ?? "ns"
        var counter = 1
        while let bound = element.resolveNamespace(forName: "\(prefix):\(name)")?.stringValue, bound != namespace {
            prefix = (Namespace.preferredPrefixes[namespace] ?? "ns") + String(counter)
            counter += 1
        }
        element.addNamespace(XMLNode.namespace(withName: prefix, stringValue: namespace) as! XMLNode)
        return "\(prefix):\(name)"
    }

    private func rdfName(_ name: String, on element: XMLElement) -> String {
        let prefix = element.resolvePrefix(forNamespaceURI: Namespace.rdf) ?? "rdf"
        return prefix.isEmpty ? name : "\(prefix):\(name)"
    }
}

// MARK: - Values

extension XMPDocument {
    // Computed: key paths are not Sendable, so they cannot live in a static let.
    private static var contactFields: [(field: String, path: WritableKeyPath<CreatorContact, String?>)] {
        [("CiEmailWork", \.email), ("CiTelWork", \.phone), ("CiUrlWork", \.url), ("CiAdrExtadr", \.address),
         ("CiAdrCity", \.city), ("CiAdrRegion", \.region), ("CiAdrPcode", \.postalCode), ("CiAdrCtry", \.country)]
    }

    /// The synced values this packet holds. The standard properties win over the
    /// app's own copies when they disagree, since only they can be changed by
    /// other apps: a reject is `xmp:Rating` -1, labels are color names.
    func values() -> SidecarValues {
        var values = SidecarValues()
        let appRating = simple(Namespace.app, "Rating").flatMap(Int.init)
        let appFlag = simple(Namespace.app, "Flag").flatMap(Int.init).flatMap(Flag.init(rawValue:))
        let appLabel = simple(Namespace.app, "Label").flatMap(Int.init).flatMap(ColorLabel.init(rawValue:))
        let xmpRating = simple(Namespace.xmp, "Rating").flatMap(Double.init).map { Int($0) }

        let ownRating = Rating(clamping: appRating ?? 0)
        let ownFlag = appFlag ?? .none
        let expected = ownFlag == .rejected ? -1 : ownRating.rawValue
        if let xmpRating, appRating == nil || xmpRating != expected {
            values.rating = xmpRating < 0 ? ownRating : Rating(clamping: xmpRating)
            values.flag = xmpRating < 0 ? .rejected : (ownFlag == .rejected ? .none : ownFlag)
        } else {
            values.rating = ownRating
            values.flag = ownFlag
        }

        // The app always writes xmp:Label with its own label, so a missing one
        // means there is none (or another app removed it). A name outside the
        // color set (a custom label set) keeps the app's own label.
        if let labelText = simple(Namespace.xmp, "Label") {
            values.colorLabel = ColorLabel(xmpName: labelText) ?? appLabel ?? .none
        } else {
            values.colorLabel = .none
        }

        values.keywords = ImageMetadata.uniqueKeywords(array(Namespace.dc, "subject"))
        values.creator = array(Namespace.dc, "creator").joined(separator: ", ").trimmedNonEmpty
        values.rights = alternative(Namespace.dc, "rights")?.trimmedNonEmpty
        values.caption = alternative(Namespace.dc, "description")?.trimmedNonEmpty
        values.usageTerms = alternative(Namespace.rights, "UsageTerms")?.trimmedNonEmpty
        var contact = CreatorContact()
        for (field, path) in Self.contactFields {
            contact[keyPath: path] = structField(Namespace.iptcCore, "CreatorContactInfo", field: field,
                                                 fieldNamespace: Namespace.iptcCore)?.trimmedNonEmpty
        }
        values.contact = contact.isEmpty ? nil : contact
        return values
    }

    /// Writes `values`. Keywords removed since `previous` are also taken out of
    /// `lr:hierarchicalSubject`, so another app does not bring them back.
    func apply(_ values: SidecarValues, previous: SidecarValues?) {
        let xmpRating: String? = values.flag == .rejected ? "-1" : (values.rating == .unrated ? nil : String(values.rating.rawValue))
        if xmpRating != nil || simple(Namespace.xmp, "Rating") != nil {
            setSimple(Namespace.xmp, "Rating", xmpRating ?? "0")
        }
        setSimple(Namespace.xmp, "Label", values.colorLabel.xmpName)
        let ownDefault = values.rating == .unrated && values.flag == .none && values.colorLabel == .none
        setSimple(Namespace.app, "Rating", ownDefault ? nil : String(values.rating.rawValue))
        setSimple(Namespace.app, "Flag", ownDefault ? nil : String(values.flag.rawValue))
        setSimple(Namespace.app, "Label", ownDefault ? nil : String(values.colorLabel.rawValue))

        setArray(Namespace.dc, "subject", .bag, values.keywords)
        if let previous {
            let kept = Set(values.keywords.map { $0.lowercased() })
            let removed = Set(previous.keywords.map { $0.lowercased() }).subtracting(kept)
            let hierarchical = array(Namespace.lightroom, "hierarchicalSubject")
            if !removed.isEmpty, !hierarchical.isEmpty {
                let remaining = hierarchical.filter { path in
                    !removed.contains((path.split(separator: "|").last.map(String.init) ?? path).lowercased())
                }
                if remaining.count != hierarchical.count {
                    setArray(Namespace.lightroom, "hierarchicalSubject", .bag, remaining)
                }
            }
        }
        setArray(Namespace.dc, "creator", .seq, values.creator.map { [$0] } ?? [])
        setAlternative(Namespace.dc, "rights", values.rights)
        setAlternative(Namespace.dc, "description", values.caption)
        setAlternative(Namespace.rights, "UsageTerms", values.usageTerms)
        setStruct(Namespace.iptcCore, "CreatorContactInfo", fieldNamespace: Namespace.iptcCore,
                  fields: Self.contactFields.map { ($0.field, values.contact?[keyPath: $0.path]) })
    }
}
