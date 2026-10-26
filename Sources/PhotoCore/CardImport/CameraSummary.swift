import Foundation

/// The camera behind the newest photo on a card or in a folder, with its
/// shutter count when the file records one. The import window shows it in its
/// status bar.
public struct CameraSummary: Hashable, Sendable {
    /// Make and model as people write them: "Sony ILCE-7M3", "Canon EOS R5".
    public var name: String
    /// Shutter actuations when the photo was taken.
    public var shutterCount: Int?
    /// The file both were read from.
    public var fileName: String

    public init(name: String, shutterCount: Int?, fileName: String) {
        self.name = name
        self.shutterCount = shutterCount
        self.fileName = fileName
    }

    /// From the newest shot that names a camera, photos before videos. A
    /// RAW+JPEG pair is read from its RAW.
    public init?(newestOf shots: [SourceShot]) {
        let newestFirst = shots.sorted { ($0.date, $0.primary.name) > ($1.date, $1.primary.name) }
        let ordered = newestFirst.filter { $0.primary.kind != .video } + newestFirst.filter { $0.primary.kind == .video }
        for shot in ordered {
            let file = shot.primary
            if let name = Self.displayName(make: file.metadata.cameraMake, model: file.metadata.cameraModel) {
                self.init(name: name, shutterCount: file.metadata.shutterCount, fileName: file.name)
                return
            }
        }
        return nil
    }

    /// "SONY" + "ILCE-7M3" → "Sony ILCE-7M3"; "NIKON CORPORATION" + "NIKON Z 6"
    /// → "Nikon Z 6"; "Canon" + "Canon EOS R5" → "Canon EOS R5".
    public static func displayName(make: String?, model: String?) -> String? {
        let make = make.map(cleanMake)?.trimmedNonEmpty
        guard let model = model?.trimmedNonEmpty else { return make }
        guard let make else { return model }
        let makeWord = make.prefix { $0 != " " }
        let modelWord = model.prefix { $0 != " " }
        if modelWord.caseInsensitiveCompare(makeWord) == .orderedSame {
            return String(makeWord) + model.dropFirst(modelWord.count)
        }
        return make + " " + model
    }

    /// Company suffixes cameras write into Make, longest first.
    private static let companySuffixes = [
        " imaging company, ltd.", " imaging corp.", " camera ag", " corporation", " co., ltd.", ", ltd.", " ltd.",
        " corp.", " corp", " inc.", " ag",
    ]

    /// Drops company suffixes and gives all-capital or all-lowercase names
    /// ordinary capitals ("FUJIFILM" → "Fujifilm"). Short names such as "DJI" stay.
    static func cleanMake(_ make: String) -> String {
        var name = make.trimmingCharacters(in: .whitespaces)
        var stripped = true
        while stripped {
            stripped = false
            for suffix in companySuffixes where name.count > suffix.count && name.lowercased().hasSuffix(suffix) {
                name = String(name.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
                stripped = true
            }
        }
        guard name == name.uppercased() || name == name.lowercased() else { return name }
        return name.split(separator: " ").map { word in
            word.count > 3 ? word.prefix(1).uppercased() + word.dropFirst().lowercased() : String(word)
        }.joined(separator: " ")
    }
}
