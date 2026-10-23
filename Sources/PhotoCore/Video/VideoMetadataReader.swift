import AVFoundation
import CoreGraphics
import Foundation

/// Reads videos' metadata with AVFoundation: duration, display size, creation
/// date, camera and location.
public struct VideoMetadataReader: MetadataReader {
    public var concurrency: Int

    public init(concurrency: Int = 4) {
        self.concurrency = max(1, concurrency)
    }

    public func metadata(for urls: [URL]) async throws -> [URL: ImageMetadata] {
        try await withThrowingTaskGroup(of: (URL, ImageMetadata?).self) { group in
            var result: [URL: ImageMetadata] = [:]
            var iterator = urls.makeIterator()
            for _ in 0..<concurrency {
                guard let url = iterator.next() else { break }
                group.addTask { (url, await Self.read(url)) }
            }
            while let (url, metadata) = try await group.next() {
                try Task.checkCancellation()
                result[url] = metadata
                if let next = iterator.next() {
                    group.addTask { (next, await Self.read(next)) }
                }
            }
            return result
        }
    }

    public static func read(_ url: URL) async -> ImageMetadata? {
        let asset = AVURLAsset(url: url)
        guard let (duration, tracks, items) = try? await asset.load(.duration, .tracks, .metadata) else { return nil }
        var metadata = ImageMetadata()
        metadata.duration = duration.seconds.isFinite ? duration.seconds : nil
        if let track = tracks.first(where: { $0.mediaType == .video }),
           let (size, transform) = try? await track.load(.naturalSize, .preferredTransform) {
            // Frames are shown with the track's transform applied, so the size is oriented.
            let shown = size.applying(transform)
            metadata.pixelWidth = Int(abs(shown.width).rounded())
            metadata.pixelHeight = Int(abs(shown.height).rounded())
        }
        func value(_ identifier: AVMetadataIdentifier) async -> String? {
            guard let item = AVMetadataItem.metadataItems(from: items, filteredByIdentifier: identifier).first else { return nil }
            return (try? await item.load(.stringValue))?.trimmedNonEmpty
        }
        // Creation dates are instants; keep the zone the Mac is in, so the clip
        // files under the day it was filmed here.
        if let date = (try? await asset.load(.creationDate)).flatMap({ $0 }),
           let instant = try? await date.load(.dateValue) {
            metadata.captureDate = instant
            metadata.captureOffsetSeconds = TimeZone.current.secondsFromGMT(for: instant)
        }
        metadata.cameraMake = await value(.quickTimeMetadataMake)
        metadata.cameraModel = await value(.quickTimeMetadataModel)
        if let location = await value(.quickTimeMetadataLocationISO6709) {
            (metadata.latitude, metadata.longitude) = Self.coordinates(iso6709: location)
        }
        return metadata
    }

    /// "+37.3317-122.0302+012.000/" → (37.3317, -122.0302).
    static func coordinates(iso6709 text: String) -> (Double?, Double?) {
        var numbers: [Double] = []
        var current = ""
        for character in text {
            if (character == "+" || character == "-"), !current.isEmpty {
                numbers.append(Double(current) ?? .nan)
                current = ""
            }
            if character == "/" { break }
            current.append(character)
        }
        if !current.isEmpty { numbers.append(Double(current) ?? .nan) }
        guard numbers.count >= 2, numbers[0].isFinite, numbers[1].isFinite else { return (nil, nil) }
        return (numbers[0], numbers[1])
    }
}

/// Sends videos to one reader and everything else to another.
public struct MediaMetadataReader: MetadataReader {
    public let photos: any MetadataReader
    public let videos: any MetadataReader

    public init(photos: any MetadataReader, videos: any MetadataReader = VideoMetadataReader()) {
        self.photos = photos
        self.videos = videos
    }

    public func metadata(for urls: [URL]) async throws -> [URL: ImageMetadata] {
        let isVideo = { (url: URL) in FileKind(pathExtension: url.pathExtension) == .video }
        let videoURLs = urls.filter(isVideo)
        var result = try await photos.metadata(for: urls.filter { !isVideo($0) })
        if !videoURLs.isEmpty {
            result.merge(try await videos.metadata(for: videoURLs)) { first, _ in first }
        }
        return result
    }
}
