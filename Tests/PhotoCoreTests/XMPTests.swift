import Foundation
import Testing
@testable import PhotoCore

@Suite("XMP")
struct XMPTests {
    /// A sidecar in the shape another raw editor writes: simple values as
    /// attributes, develop settings in its own namespace, hierarchical keywords.
    static let foreign = """
        <x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="XMP Core 6.0">
         <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
          <rdf:Description rdf:about=""
            xmlns:xmp="http://ns.adobe.com/xap/1.0/"
            xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/"
            xmlns:dc="http://purl.org/dc/elements/1.1/"
            xmlns:lr="http://ns.adobe.com/lightroom/1.0/"
           xmp:Rating="4"
           xmp:Label="Green"
           crs:Exposure2012="+0.35"
           crs:WhiteBalance="As Shot">
           <dc:subject><rdf:Bag><rdf:li>dog</rdf:li><rdf:li>beach</rdf:li></rdf:Bag></dc:subject>
           <lr:hierarchicalSubject><rdf:Bag><rdf:li>animals|dog</rdf:li><rdf:li>places|beach</rdf:li></rdf:Bag></lr:hierarchicalSubject>
           <crs:ToneCurvePV2012><rdf:Seq><rdf:li>0, 0</rdf:li><rdf:li>255, 255</rdf:li></rdf:Seq></crs:ToneCurvePV2012>
          </rdf:Description>
         </rdf:RDF>
        </x:xmpmeta>
        """

    private func roundTrip(_ document: XMPDocument) throws -> (XMPDocument, String) {
        let data = document.data()
        return (try XMPDocument(data: data), String(decoding: data, as: UTF8.self))
    }

    @Test func readsAttributesAndArrays() throws {
        let values = try XMPDocument(data: Data(Self.foreign.utf8)).values()
        #expect(values.rating == Rating(clamping: 4))
        #expect(values.flag == .none)
        #expect(values.colorLabel == .green)
        #expect(values.keywords == ["dog", "beach"])
        #expect(values.creator == nil)
    }

    @Test func editsOnlyWhatTheAppOwns() throws {
        let document = try XMPDocument(data: Data(Self.foreign.utf8))
        let before = document.values()
        var after = before
        after.rating = Rating(clamping: 2)
        after.keywords = ["dog", "sunset"]
        document.apply(after, previous: before)
        let (reread, text) = try roundTrip(document)

        #expect(reread.values() == after)
        // Other apps' settings are untouched.
        #expect(reread.simple("http://ns.adobe.com/camera-raw-settings/1.0/", "Exposure2012") == "+0.35")
        #expect(reread.array("http://ns.adobe.com/camera-raw-settings/1.0/", "ToneCurvePV2012") == ["0, 0", "255, 255"])
        // A removed keyword leaves the hierarchy too; the others stay.
        #expect(reread.array(XMPDocument.Namespace.lightroom, "hierarchicalSubject") == ["animals|dog"])
        // The rating moved from attribute to element; there is only one.
        #expect(text.components(separatedBy: "xmp:Rating>2<").count == 2)
        #expect(!text.contains(#"xmp:Rating="4""#))
        #expect(text.contains(AppBranding.sidecarNamespace))
    }

    @Test func rejectsUseMinusOneAndOtherAppsCanChangeThem() throws {
        let document = XMPDocument.empty()
        let rejected = SidecarValues(rating: Rating(clamping: 3), flag: .rejected, colorLabel: .red)
        document.apply(rejected, previous: nil)
        let (reread, text) = try roundTrip(document)
        #expect(text.contains("Rating>-1<"))
        #expect(reread.values() == rejected)

        // Another app gives it five stars: the standard property wins.
        reread.setSimple(XMPDocument.Namespace.xmp, "Rating", "5")
        let changed = reread.values()
        #expect(changed.rating == Rating(clamping: 5))
        #expect(changed.flag == .none)
        // And clears the label.
        reread.remove(XMPDocument.Namespace.xmp, "Label")
        #expect(reread.values().colorLabel == .none)
    }

    @Test func customLabelNamesKeepTheAppsLabel() throws {
        let document = XMPDocument.empty()
        document.apply(SidecarValues(colorLabel: .orange), previous: nil)
        document.setSimple(XMPDocument.Namespace.xmp, "Label", "Approved")
        #expect(document.values().colorLabel == .orange)
    }

    @Test func descriptiveFieldsAndContactRoundTrip() throws {
        let values = SidecarValues(
            keywords: ["golden hour"], creator: "Pat Doe", rights: "© 2024 Pat Doe", caption: "Beach at dusk",
            usageTerms: "All rights reserved",
            contact: CreatorContact(email: "pat@example.com", phone: "+1 555 0100", url: "https://example.com",
                                    city: "Moab", country: "USA"),
            title: "Dusk", altText: "Waves under an orange sky", extendedDescription: "Low waves roll in.\nNo people.",
            jobTitle: "Staff Photographer")
        let document = XMPDocument.empty()
        document.apply(values, previous: nil)
        let (reread, text) = try roundTrip(document)
        #expect(reread.values() == values)
        #expect(text.contains("<dc:title>") && text.contains("<Iptc4xmpCore:AltTextAccessibility>")
                && text.contains("<Iptc4xmpCore:ExtDescrAccessibility>") && text.contains("<photoshop:AuthorsPosition>"))

        // Clearing a field removes it.
        var cleared = values
        cleared.contact = nil
        cleared.caption = nil
        cleared.title = nil
        cleared.jobTitle = nil
        reread.apply(cleared, previous: values)
        #expect(try roundTrip(reread).0.values() == cleared)
    }

    @Test func comparesKeywordsIgnoringCaseAndOrder() {
        let a = SidecarValues(keywords: ["Dog", "beach"], creator: " Pat ")
        let b = SidecarValues(keywords: ["beach", "dog"], creator: "Pat")
        #expect(a.sameAs(b))
        #expect(a.differingFields(from: SidecarValues(rating: Rating(clamping: 1))) == [.rating, .keywords, .creator])
        #expect(SidecarValues().isEmpty)
        #expect(!b.taking([.keywords], from: SidecarValues()).sameAs(b))
    }

    @Test func rejectsWhatIsNotXMP() {
        #expect(throws: (any Error).self) { try XMPDocument(data: Data("not xml".utf8)) }
        #expect(throws: (any Error).self) { try XMPDocument(data: Data("<a><b/></a>".utf8)) }
    }
}
