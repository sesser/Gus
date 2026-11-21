import Foundation
import Testing

/// Issue #88, R10 and R16 (AC10), from the source tree: detection stays on
/// the Mac with Apple frameworks only, and the spike is gone.
@Suite("Detection masks: sources")
struct DetectionMaskSourceTests {
    static let detectionFiles = [
        "Sources/PhotoCore/Suggestions/MaskDetector.swift",
        "Sources/PhotoCore/Edits/Masks/MaskRaster.swift",
        "Sources/PhotoCore/Edits/Masks/MaskRasterStore.swift",
        "Sources/PhotoCore/Edits/Masks/GuidedMaskFilter.swift",
        "Sources/PhotoCore/Catalog/MaskRasters.swift",
        "Sources/PhotoApp/Model/MaskDetectionEditing.swift",
        "Sources/PhotoApp/Model/DebugMaskDetectionCommands.swift",
    ]

    @Test("The detection code uses no network API and no other package")
    func noNetwork() throws {
        let forbidden = ["URLSession", "import Network", "NWConnection", "URLRequest", "DownloadableAssets",
                         "import GRDB"]
        for file in Self.detectionFiles where !file.hasSuffix("MaskRasters.swift") {
            let text = try String(contentsOf: RepositoryFiles.url(file), encoding: .utf8)
            for word in forbidden {
                #expect(!text.contains(word), "\(file) contains \(word)")
            }
        }
    }

    @Test("No source names the downloadable iterative segmentation request or the spike")
    func noIterativeSegmentationOrSpike() throws {
        for file in RepositoryFiles.files(under: "Sources") where file.hasSuffix(".swift") {
            let text = try String(contentsOf: RepositoryFiles.url(file), encoding: .utf8)
            #expect(!text.contains("IterativeSegmentation"), "\(file)")
            #expect(!text.contains("aimask-spike") && !text.contains("AIMaskSpike"), "\(file)")
        }
        #expect(!FileManager.default.fileExists(atPath: RepositoryFiles.url("Sources/PhotoBench/AIMaskSpike.swift").path))
    }

    @Test("Package.swift depends on GRDB alone")
    func onePackage() throws {
        let manifest = try String(contentsOf: RepositoryFiles.url("Package.swift"), encoding: .utf8)
        let packages = manifest.components(separatedBy: ".package(url:").count - 1
        #expect(packages == 1)
        #expect(manifest.contains("groue/GRDB.swift"))
    }
}
