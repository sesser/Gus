import CoreGraphics
import Foundation
import Vision

/// A keyword proposed for a photo by image analysis.
public struct SuggestedKeyword: Hashable, Sendable {
    public var name: String
    /// 0…1.
    public var confidence: Double

    public init(name: String, confidence: Double) {
        self.name = name
        self.confidence = confidence
    }
}

/// Proposes keywords for an image. Implementations run on-device.
public protocol KeywordSuggester: Sendable {
    /// Identifies the analysis; stored per photo so a better model or new
    /// thresholds can re-analyze what an older one looked at.
    var analysisVersion: Int { get }
    func suggestions(for image: CGImage) async throws -> [SuggestedKeyword]
}

/// Apple's on-device image classifier. Its labels are generic ("dog", "beach",
/// "sunset"); it does not know breeds, places or people.
public struct VisionKeywordSuggester: KeywordSuggester {
    /// Bump when the filtering below changes.
    public var analysisVersion: Int { 1 }
    public var minimumConfidence: Float
    public var maximumCount: Int

    /// The defaults come from the macOS sample pictures, analyzed from their
    /// 512 px thumbnails: the main subject scores 0.85–0.99 ("zebra", "eagle"),
    /// side labels 0.4–0.7 ("sky", "grass"), and below 0.3 are mostly wrong
    /// guesses ("rope", "tool", "bagel").
    public init(minimumConfidence: Float = 0.3, maximumCount: Int = 8) {
        self.minimumConfidence = minimumConfidence
        self.maximumCount = maximumCount
    }

    public func suggestions(for image: CGImage) async throws -> [SuggestedKeyword] {
        let observations = try await ClassifyImageRequest().perform(on: image)
        // hasMinimumPrecision(_:forRecall:) rejected all but near-certain labels on
        // sample photos, so the confidence floor does the filtering.
        return observations
            .filter { $0.confidence >= minimumConfidence }
            .sorted { $0.confidence > $1.confidence }
            .prefix(maximumCount)
            .map { SuggestedKeyword(name: Self.keywordName($0.identifier), confidence: Double($0.confidence)) }
    }

    /// Vision identifiers are lowercase with underscores ("sea_lion").
    static func keywordName(_ identifier: String) -> String {
        identifier.replacingOccurrences(of: "_", with: " ")
    }
}
