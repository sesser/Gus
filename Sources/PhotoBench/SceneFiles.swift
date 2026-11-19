import CoreGraphics
import Foundation
import PhotoCore
import PhotoFixtures
import UniformTypeIdentifiers

/// Writes the chromatic aberration test scenes as photo files, for checks in
/// the app (docs/features/chromatic-aberration: scenes (a)–(c), and the
/// manual checks M2 and the debug-script checks that need them), and the
/// dusty sky of the spots (docs/features/healing) as a TIFF, a JPEG and a DNG.
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
            ("dusty-sky", TestScene.dustySky.image(width: width, height: height)),
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
        // The dusty sky through each kind of decode: ImageIO (JPEG) and the system RAW decoder (DNG).
        let dusty = TestScene.dustySky.image(width: width, height: height)
        if let cgImage = dusty.cgImage(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!) {
            let jpeg = folder.appending(path: "dusty-sky.jpg")
            try SyntheticImages.write(cgImage, to: jpeg, type: .jpeg)
            written.append(jpeg.lastPathComponent)
        }
        let dustyDNG = folder.appending(path: "dusty-sky.dng")
        try SyntheticDNG.write(to: dustyDNG, options: .init(width: width, height: height, seed: 2, scene: .testScene(.dustySky)))
        written.append(dustyDNG.lastPathComponent)
        print("Wrote \(written.joined(separator: ", ")) to \(folder.path)")
        return ["files": written]
    }
}
