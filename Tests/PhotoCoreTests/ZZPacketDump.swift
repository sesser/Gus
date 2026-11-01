import Foundation
import ImageIO
import Testing
@testable import PhotoCore

/// Temporary: which XMP packets this OS's ImageIO parses. Prints only.
@Test func zzDiagnoseXMPParsing() {
    func packet(_ build: (XMPDocument) -> Void) -> Data {
        let document = XMPDocument.empty()
        build(document)
        return document.data()
    }
    typealias N = XMPDocument.Namespace
    let full = packet {
        $0.setArray(N.dc, "subject", .bag, ["dog", "beach"])
        $0.setAlternative(N.dc, "rights", "© Pat Doe")
        $0.setStruct(N.iptcCore, "CreatorContactInfo", fieldNamespace: N.iptcCore, fields: [("CiEmailWork", "pat@example.com")])
    }
    let text = String(decoding: full, as: UTF8.self)
    let noPI = text.split(separator: "\n").filter { !$0.hasPrefix("<?xpacket") }.joined(separator: "\n")
    let variants: [(String, Data)] = [
        ("full", full),
        ("no xpacket lines", Data(noPI.utf8)),
        ("subject only", packet { $0.setArray(N.dc, "subject", .bag, ["dog"]) }),
        ("rights only", packet { $0.setAlternative(N.dc, "rights", "Pat") }),
        ("struct only", packet { $0.setStruct(N.iptcCore, "CreatorContactInfo", fieldNamespace: N.iptcCore,
                                              fields: [("CiEmailWork", "pat@example.com")]) }),
        ("empty description", packet { _ in }),
        ("hand-written", Data(#"<x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"><rdf:Description rdf:about="" xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:subject><rdf:Bag><rdf:li>dog</rdf:li></rdf:Bag></dc:subject></rdf:Description></rdf:RDF></x:xmpmeta>"#.utf8)),
    ]
    print("XMPDIAG os \(ProcessInfo.processInfo.operatingSystemVersionString)")
    for (name, data) in variants {
        print("XMPDIAG \(name): \(CGImageMetadataCreateFromXMPData(data as CFData) != nil)")
    }
    print("XMPDIAG head \(full.prefix(64).map { String(format: "%02x", $0) }.joined())")
    print("XMPDIAG packet <<<\(text)>>>")
}
