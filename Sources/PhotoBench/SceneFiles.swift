import CoreGraphics
import Foundation
import PhotoCore
import PhotoFixtures
import UniformTypeIdentifiers

/// Writes the chromatic aberration test scenes as photo files, for checks in
/// the app (docs/features/chromatic-aberration: scenes (a)–(c), and the
/// manual checks M2 and the debug-script checks that need them).
enum SceneFiles {
    static func run(_ arguments: Arguments) async throws -> [String: any Sendable] {
        guard let output = arguments.values["output"] else { throw BenchError("scenes needs --output DIR") }
        let folder = URL(fileURLWithPath: (output as NSString).expandingTildeInPath, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let (width, height) = arguments.size("size", default: (1536, 1152))
        // Rec. 2020 with its own curve: sRGB would clip the scenes' colored edges,
        // which moves lateral color between channels.
        let space = CGColorSpace(name: CGColorSpace.itur_2020)!
        var written: [String] = []
        let scenes: [(String, LinearImage)] = [
            ("fringes", TestScene.fringes.image(width: width, height: height)),
            ("fringe-subjects", TestScene.fringeSubjects.image(width: width, height: height)),
            ("lateral-color", TestScene.lateralColor(width: width, height: height)),
            ("lateral-color-2", TestScene.lateralColor(width: width, height: height, red: -0.002, blue: 0.0025)),
            ("pixel-grid", TestScene.pixelGrid.image(width: width, height: height)),
        ]
        for (name, image) in scenes {
            guard let cgImage = image.cgImage(colorSpace: space) else { continue }
            let url = folder.appending(path: "\(name).tif")
            try SyntheticImages.write(cgImage, to: url, type: .tiff)
            written.append(url.lastPathComponent)
        }
        let dng = folder.appending(path: "fringes.dng")
        try SyntheticDNG.write(to: dng, options: .init(width: width, height: height, seed: 1, scene: .testScene(.fringes)))
        written.append(dng.lastPathComponent)
        print("Wrote \(written.joined(separator: ", ")) to \(folder.path)")
        return ["files": written]
    }
}
