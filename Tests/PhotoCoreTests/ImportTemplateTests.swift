import Foundation
import Testing
@testable import PhotoCore

@Suite("Import templates")
struct ImportTemplateTests {
    /// 2024-05-01 23:30 at +02:00, Nikon Z 6, IMG_0412.NEF, third shot, counter 41.
    func context(name: String = "IMG_0412.NEF", job: String = "Smith wedding") -> TemplateContext {
        let capture = ExifDate.parse("2024:05:01 23:30:15", offset: "+02:00")!
        return TemplateContext(captureDate: capture.date, captureOffsetSeconds: capture.offsetSeconds,
                               fileDate: Date(timeIntervalSince1970: 0),
                               importDate: Date(timeIntervalSince1970: 1_717_200_000), // 2024-06-01
                               make: "NIKON CORPORATION", model: "Z 6", serial: "6001234", lens: "NIKKOR Z 35mm f/1.8 S",
                               originalName: name, sequence: 3, counter: 41, jobCode: job)
    }

    @Test func defaultTemplateFilesByCaptureDay() {
        let result = ImportTemplate().render(context())
        // Captured late on May 1st where it was taken, which was already May 2nd in UTC.
        #expect(result.folders == ["2024", "2024-05-01"])
        #expect(result.fileName == "IMG_0412.NEF")
    }

    @Test func tokensExpand() {
        let template = ImportTemplate(folder: "{import:yyyy}/{job}/{model}",
                                      fileName: "{capture:yyyyMMdd-HHmmss}_{number}_{seq:4}_{counter:6}")
        let result = template.render(context())
        #expect(result.folders == ["2024", "Smith wedding", "Z 6"])
        #expect(result.fileName == "20240501-233015_0412_0003_000041.NEF")
        #expect(ImportTemplate(fileName: "{name}.{ext:lower}").render(context()).fileName == "IMG_0412.nef")
        #expect(ImportTemplate(fileName: "{serial}-{ext:upper}").render(context(name: "a.jpg")).fileName == "6001234-JPG.jpg")
    }

    @Test func valuesCannotMakeFoldersOrHideFiles() {
        let result = ImportTemplate(folder: "{lens}//{job}", fileName: "{job}").render(context(job: "../.secret: 1/2 "))
        #expect(result.folders == ["NIKKOR Z 35mm f-1.8 S", "-.secret- 1-2"])
        #expect(result.fileName == "-.secret- 1-2.NEF")
        #expect(ImportTemplate.sanitize("..hidden.") == "hidden")
    }

    @Test func emptyAndUnknownTokens() {
        // An empty result falls back to the original name; unknown tokens stay as typed.
        #expect(ImportTemplate(fileName: "{job}").render(context(job: "")).fileName == "IMG_0412.NEF")
        #expect(ImportTemplate(folder: "{nope}/{capture}", fileName: "{name").render(context()).folders == ["{nope}", "{capture}"])
        #expect(ImportTemplate(fileName: "{name").render(context()).fileName == "{name.NEF")
        // No capture date: the file's date stands in.
        var undated = context()
        undated.captureDate = nil
        #expect(ImportTemplate().render(undated).folders.first == LocalDate.format(Date(timeIntervalSince1970: 0), in: .current).prefix(4).description)
    }

    @Test func examplesJoinFoldersAndName() {
        #expect(ImportTemplate().example(context()) == "2024/2024-05-01/IMG_0412.NEF")
    }
}
