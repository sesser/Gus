import Foundation
import os

/// Reads metadata through one long-lived `exiftool -stay_open` subprocess, so the
/// Perl start-up cost is paid once rather than per file.
///
/// Commands are written from the actor and their responses are read on a private
/// serial queue, queued in the same actor turn as the write, so overlapping calls
/// stay matched to their responses without blocking Swift's cooperative threads.
public actor ExifToolMetadataReader: MetadataReader {
    static let tags = [
        "SubSecDateTimeOriginal", "DateTimeOriginal", "CreateDate", "OffsetTimeOriginal",
        "ImageSize", "ImageWidth", "ImageHeight", "Orientation",
        "Make", "Model", "LensModel", "ISO", "ExposureTime", "FNumber", "FocalLength",
    ]

    public enum Failure: Error {
        case processExited
        case malformedResponse
    }

    private let executableURL: URL
    private var session: Session?
    private var commandNumber = 0
    private static let log = Logger(subsystem: AppBranding.bundleIdentifier, category: "exiftool")

    public init(executableURL: URL) {
        self.executableURL = executableURL
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

        let session = try currentSession()
        commandNumber += 1
        let number = commandNumber
        var arguments = ["-json", "-n", "-fast", "-charset", "filename=utf8"]
        arguments += Self.tags.map { "-\($0)" }
        arguments += usable.map(\.path)
        arguments.append("-execute\(number)")
        do {
            try session.input.write(contentsOf: Data((arguments.joined(separator: "\n") + "\n").utf8))
        } catch {
            self.session = nil
            throw Failure.processExited
        }

        let response: Data
        do {
            // The read is queued in this same actor turn as the write, so reads are
            // queued in command order even when calls overlap.
            let marker = Data("{ready\(number)}\n".utf8)
            response = try await withCheckedThrowingContinuation { continuation in
                session.enqueueRead(until: marker) { continuation.resume(with: $0) }
            }
        } catch {
            self.session = nil
            Self.log.error("exiftool session ended: \(String(describing: error), privacy: .public)")
            throw error
        }
        return Self.parse(response, requested: usable)
    }

    /// Asks the subprocess to exit. A later call starts a new one.
    public func shutdown() {
        session?.close()
        session = nil
    }

    private func currentSession() throws -> Session {
        if let session, session.process.isRunning { return session }
        let session = try Session(executableURL: executableURL)
        self.session = session
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
        return ImageMetadata(
            captureDate: parsed?.date, captureOffsetSeconds: parsed?.offsetSeconds,
            pixelWidth: width, pixelHeight: height, orientation: int("Orientation") ?? 1,
            cameraMake: string("Make"), cameraModel: string("Model"), lensModel: string("LensModel"),
            iso: int("ISO"), exposureTime: double("ExposureTime"), fNumber: double("FNumber"),
            focalLength: double("FocalLength"))
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
