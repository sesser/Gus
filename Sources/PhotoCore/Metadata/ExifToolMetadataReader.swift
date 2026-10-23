import Foundation
import os

/// Reads metadata through a few long-lived `exiftool -stay_open` subprocesses, so
/// the Perl start-up cost is paid once rather than per file. ExifTool handles one
/// file at a time, so each batch is split across the processes.
///
/// Commands are written from the actor and their responses are read on each
/// process's private serial queue, queued in the same actor turn as the write, so
/// overlapping calls stay matched to their responses without blocking Swift's
/// cooperative threads.
public actor ExifToolMetadataReader: MetadataReader {
    static let tags = [
        "SubSecDateTimeOriginal", "DateTimeOriginal", "CreateDate", "OffsetTimeOriginal",
        "ImageSize", "ImageWidth", "ImageHeight", "Orientation",
        "Make", "Model", "LensModel", "ISO", "ExposureTime", "FNumber", "FocalLength",
        "Keywords", "Subject", "Rating", "Label",
        "Artist", "Creator", "Copyright", "Rights", "ImageDescription", "Description", "Caption-Abstract",
        "SerialNumber", "InternalSerialNumber", "Composite:GPSLatitude", "Composite:GPSLongitude",
        "Flash", "ExposureCompensation", "WhiteBalance", "ExposureProgram", "MeteringMode", "FocalLengthIn35mmFormat",
        "UsageTerms", "CreatorWorkEmail", "CreatorWorkTelephone", "CreatorWorkURL", "CreatorAddress", "CreatorCity",
        "CreatorRegion", "CreatorPostalCode", "CreatorCountry",
    ]

    public enum Failure: Error {
        case processExited
        case malformedResponse
    }

    /// Up to four processes, leaving most cores for hashing and decoding.
    public static var defaultProcessCount: Int {
        min(4, max(1, ProcessInfo.processInfo.activeProcessorCount / 3))
    }

    private let executableURL: URL
    private var sessions: [Session?]
    private var commandNumber = 0
    private static let log = Logger(subsystem: AppBranding.bundleIdentifier, category: "exiftool")

    public init(executableURL: URL, processCount: Int = ExifToolMetadataReader.defaultProcessCount) {
        self.executableURL = executableURL
        self.sessions = Array(repeating: nil, count: max(1, processCount))
    }

    /// Finds `exiftool` on `PATH` or in the usual Homebrew and system locations.
    /// Apps launched from Finder do not inherit the shell's `PATH`, hence the extras.
    public static func locateExecutable(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL? {
        let pathEntries = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        let candidates = pathEntries + ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]
        for directory in candidates {
            let path = (directory as NSString).appendingPathComponent("exiftool")
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }

    public func metadata(for urls: [URL]) async throws -> [URL: ImageMetadata] {
        // The argument file is line-based, so a path containing a newline cannot be
        // passed; those files are left for the fallback reader.
        let usable = urls.filter { !$0.path.contains("\n") && !$0.path.contains("\r") }
        guard !usable.isEmpty else { return [:] }
        try Task.checkCancellation()

        // Small batches are not worth splitting.
        let groupCount = min(sessions.count, max(1, usable.count / 8))
        let groups = (0..<groupCount).map { group in
            Swift.stride(from: group, to: usable.count, by: groupCount).map { usable[$0] }
        }

        // Every write and its read are queued before the first suspension point.
        var pending: [(slot: Int, files: [URL], response: PendingResponse)] = []
        for (slot, files) in groups.enumerated() {
            let session = try session(at: slot)
            commandNumber += 1
            var arguments = ["-json", "-n", "-fast", "-charset", "filename=utf8"]
            arguments += Self.tags.map { "-\($0)" }
            arguments += files.map(\.path)
            arguments.append("-execute\(commandNumber)")
            do {
                try session.input.write(contentsOf: Data((arguments.joined(separator: "\n") + "\n").utf8))
            } catch {
                sessions[slot] = nil
                throw Failure.processExited
            }
            let response = PendingResponse()
            session.enqueueRead(until: Data("{ready\(commandNumber)}\n".utf8)) { response.fulfill($0) }
            pending.append((slot, files, response))
        }

        var result: [URL: ImageMetadata] = [:]
        for (slot, files, response) in pending {
            do {
                result.merge(Self.parse(try await response.value(), requested: files)) { first, _ in first }
            } catch {
                sessions[slot] = nil
                Self.log.error("exiftool session ended: \(String(describing: error), privacy: .public)")
                throw error
            }
        }
        return result
    }

    /// Asks the subprocesses to exit. A later call starts new ones.
    public func shutdown() {
        for session in sessions { session?.close() }
        sessions = sessions.map { _ in nil }
    }

    private func session(at slot: Int) throws -> Session {
        if let session = sessions[slot], session.process.isRunning { return session }
        let session = try Session(executableURL: executableURL)
        sessions[slot] = session
        return session
    }

    // MARK: Parsing

    static func parse(_ data: Data, requested: [URL]) -> [URL: ImageMetadata] {
        let trimmed = data.drop { $0 == UInt8(ascii: " ") || $0 == UInt8(ascii: "\n") }
        guard !trimmed.isEmpty,
              let entries = try? JSONSerialization.jsonObject(with: Data(trimmed)) as? [[String: Any]]
        else { return [:] }
        let byPath = Dictionary(requested.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        var result: [URL: ImageMetadata] = [:]
        for entry in entries {
            guard let source = entry["SourceFile"] as? String, let url = byPath[source] else { continue }
            result[url] = metadata(from: entry)
        }
        return result
    }

    static func metadata(from entry: [String: Any]) -> ImageMetadata {
        func string(_ key: String) -> String? {
            switch entry[key] {
            case let value as String: value.trimmedNonEmpty
            case let value as NSNumber: value.stringValue
            default: nil
            }
        }
        func double(_ key: String) -> Double? {
            switch entry[key] {
            case let value as NSNumber: value.doubleValue
            case let value as String: Double(value)
            default: nil
            }
        }
        func int(_ key: String) -> Int? { double(key).flatMap { $0.isFinite ? Int($0) : nil } }
        // List tags are arrays, or a plain value when there is only one entry.
        func strings(_ key: String) -> [String] {
            switch entry[key] {
            case let values as [Any]: values.compactMap { ($0 as? String) ?? ($0 as? NSNumber)?.stringValue }
            case let value as String: [value]
            case let value as NSNumber: [value.stringValue]
            default: []
            }
        }

        let offset = string("OffsetTimeOriginal")
        let parsed = (string("SubSecDateTimeOriginal") ?? string("DateTimeOriginal") ?? string("CreateDate"))
            .flatMap { ExifDate.parse($0, offset: offset) }

        var width = int("ImageWidth")
        var height = int("ImageHeight")
        if let size = string("ImageSize") {
            let parts = size.split(whereSeparator: { $0 == "x" || $0 == " " }).compactMap { Int($0) }
            if parts.count == 2 {
                width = parts[0]
                height = parts[1]
            }
        }
        var metadata = ImageMetadata(
            captureDate: parsed?.date, captureOffsetSeconds: parsed?.offsetSeconds,
            pixelWidth: width, pixelHeight: height, orientation: int("Orientation") ?? 1,
            cameraMake: string("Make"), cameraModel: string("Model"), lensModel: string("LensModel"),
            iso: int("ISO"), exposureTime: double("ExposureTime"), fNumber: double("FNumber"),
            focalLength: double("FocalLength"), keywords: strings("Keywords") + strings("Subject"),
            rating: int("Rating"), label: string("Label"))
        // XMP Creator is a list; the EXIF Artist is one string.
        metadata.artist = string("Artist") ?? strings("Creator").joined(separator: ", ").trimmedNonEmpty
        metadata.copyright = string("Copyright") ?? string("Rights")
        metadata.caption = string("Description") ?? string("Caption-Abstract") ?? string("ImageDescription")
        metadata.cameraSerial = string("SerialNumber") ?? string("InternalSerialNumber")
        metadata.latitude = double("GPSLatitude")
        metadata.longitude = double("GPSLongitude")
        metadata.flashFired = int("Flash").map { $0 & 1 == 1 }
        metadata.exposureCompensation = double("ExposureCompensation")
        metadata.whiteBalance = int("WhiteBalance")
        metadata.exposureProgram = int("ExposureProgram")
        metadata.meteringMode = int("MeteringMode")
        metadata.focalLength35mm = double("FocalLengthIn35mmFormat")
        metadata.usageTerms = string("UsageTerms")
        let contact = CreatorContact(email: string("CreatorWorkEmail"), phone: string("CreatorWorkTelephone"),
                                     url: string("CreatorWorkURL"), address: string("CreatorAddress"),
                                     city: string("CreatorCity"), region: string("CreatorRegion"),
                                     postalCode: string("CreatorPostalCode"), country: string("CreatorCountry"))
        metadata.creatorContact = contact.isEmpty ? nil : contact
        return metadata
    }
}

/// A response that may arrive before or after someone starts waiting for it.
final class PendingResponse: @unchecked Sendable {
    // @unchecked: state is guarded by `lock`.
    private let lock = NSLock()
    private var result: Result<Data, any Error>?
    private var continuation: CheckedContinuation<Data, any Error>?

    func fulfill(_ value: Result<Data, any Error>) {
        lock.lock()
        if let continuation {
            self.continuation = nil
            lock.unlock()
            continuation.resume(with: value)
        } else {
            result = value
            lock.unlock()
        }
    }

    func value() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if let result {
                lock.unlock()
                continuation.resume(with: result)
            } else {
                self.continuation = continuation
                lock.unlock()
            }
        }
    }
}

extension ExifToolMetadataReader {
    /// The subprocess and its pipes. The output side is only touched on `readQueue`.
    final class Session: @unchecked Sendable {
        let process: Process
        let input: FileHandle
        private let output: FileHandle
        private var buffer = Data()
        private let readQueue = DispatchQueue(label: "metadata.exiftool.read")

        init(executableURL: URL) throws {
            let process = Process()
            // exiftool keeps polling its argument file after EOF, so it would outlive
            // a crashed app. A small sh watchdog stops it once this process is gone.
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", Self.watchdogScript, "sh", executableURL.path,
                                 String(ProcessInfo.processInfo.processIdentifier)]
            let inputPipe = Pipe()
            let outputPipe = Pipe()
            process.standardInput = inputPipe
            process.standardOutput = outputPipe
            // Warnings go to stderr; an undrained pipe would eventually block exiftool.
            process.standardError = FileHandle.nullDevice
            try process.run()
            self.process = process
            self.input = inputPipe.fileHandleForWriting
            self.output = outputPipe.fileHandleForReading
        }

        static let watchdogScript = """
            exec 3<&0
            "$1" -stay_open True -@ - <&3 &
            child=$!
            trap 'kill $child 2>/dev/null; exit 0' TERM INT
            while kill -0 "$2" 2>/dev/null && kill -0 $child 2>/dev/null; do sleep 2; done
            kill $child 2>/dev/null
            """

        /// Reads on the private queue until `marker`, then calls `completion` with
        /// everything before it. Calls are served in the order they are made.
        func enqueueRead(until marker: Data, completion: @escaping @Sendable (Result<Data, any Error>) -> Void) {
            readQueue.async { [self] in
                while true {
                    if let range = buffer.range(of: marker) {
                        let response = Data(buffer[buffer.startIndex..<range.lowerBound])
                        buffer.removeSubrange(buffer.startIndex..<range.upperBound)
                        completion(.success(response))
                        return
                    }
                    let chunk = output.availableData
                    if chunk.isEmpty {
                        completion(.failure(Failure.processExited))
                        return
                    }
                    buffer.append(chunk)
                }
            }
        }

        func close() {
            try? input.write(contentsOf: Data("-stay_open\nFalse\n".utf8))
            try? input.close()
        }

        deinit {
            close()
        }
    }
}
