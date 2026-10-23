import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation

/// Short generated H.264 clips for tests: each frame is a `SyntheticImages`
/// pattern, so different seeds give different content.
public enum SyntheticVideo {
    public struct Options: Sendable {
        public var width: Int
        public var height: Int
        public var seconds: Double
        public var framesPerSecond: Int
        public var seed: UInt64
        /// ISO 8601, e.g. "2024-05-01T10:00:00+02:00".
        public var creationDate: String?
        public var make: String?
        public var model: String?

        public init(width: Int = 320, height: Int = 240, seconds: Double = 2, framesPerSecond: Int = 10, seed: UInt64 = 1,
                    creationDate: String? = nil, make: String? = nil, model: String? = nil) {
            self.width = width
            self.height = height
            self.seconds = seconds
            self.framesPerSecond = framesPerSecond
            self.seed = seed
            self.creationDate = creationDate
            self.make = make
            self.model = model
        }
    }

    public static func write(to url: URL, options: Options = Options()) async throws {
        try? FileManager.default.removeItem(at: url)
        let type: AVFileType = url.pathExtension.lowercased() == "mp4" ? .mp4 : .mov
        let writer = try AVAssetWriter(outputURL: url, fileType: type)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: options.width, AVVideoHeightKey: options.height,
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: options.width, kCVPixelBufferHeightKey as String: options.height,
        ])
        writer.add(input)
        writer.metadata = metadataItems(options)
        guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        writer.startSession(atSourceTime: .zero)

        let frames = max(1, Int(options.seconds * Double(options.framesPerSecond)))
        for index in 0..<frames {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)) }
            guard let pool = adaptor.pixelBufferPool else { throw CocoaError(.fileWriteUnknown) }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let buffer, let image = SyntheticImages.makeImage(width: options.width, height: options.height,
                                                                    seed: options.seed &+ UInt64(index)) else {
                throw CocoaError(.fileWriteUnknown)
            }
            CVPixelBufferLockBaseAddress(buffer, [])
            let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: options.width, height: options.height,
                                    bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
            context?.draw(image, in: CGRect(x: 0, y: 0, width: options.width, height: options.height))
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(index),
                                                                timescale: CMTimeScale(options.framesPerSecond)))
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
    }

    private static func metadataItems(_ options: Options) -> [AVMetadataItem] {
        var items: [AVMetadataItem] = []
        func add(_ identifier: AVMetadataIdentifier, _ value: String?) {
            guard let value else { return }
            let item = AVMutableMetadataItem()
            item.identifier = identifier
            item.value = value as NSString
            items.append(item)
        }
        add(.quickTimeMetadataCreationDate, options.creationDate)
        add(.commonIdentifierCreationDate, options.creationDate)
        add(.quickTimeMetadataMake, options.make)
        add(.quickTimeMetadataModel, options.model)
        return items
    }
}
