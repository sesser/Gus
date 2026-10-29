import Foundation

/// What a template can refer to for one file.
public struct TemplateContext: Sendable {
    /// Capture instant (see `ImageMetadata.captureDate`), or nil.
    public var captureDate: Date?
    public var captureOffsetSeconds: Int?
    /// When the file has no capture date, its modification date stands in.
    public var fileDate: Date
    public var importDate: Date
    public var make: String?
    public var model: String?
    public var serial: String?
    public var lens: String?
    /// Original file name, with extension.
    public var originalName: String
    /// 1-based position of the shot in this import (both files of a pair share it).
    public var sequence: Int
    /// The persistent counter's value for this shot.
    public var counter: Int
    public var jobCode: String
    /// When exporting: the export's date, for `{export:<pattern>}`.
    public var exportDate: Date?

    public init(captureDate: Date?, captureOffsetSeconds: Int?, fileDate: Date, importDate: Date, make: String?,
                model: String?, serial: String?, lens: String?, originalName: String, sequence: Int, counter: Int,
                jobCode: String, exportDate: Date? = nil) {
        self.captureDate = captureDate
        self.captureOffsetSeconds = captureOffsetSeconds
        self.fileDate = fileDate
        self.importDate = importDate
        self.make = make
        self.model = model
        self.serial = serial
        self.lens = lens
        self.originalName = originalName
        self.sequence = sequence
        self.counter = counter
        self.jobCode = jobCode
        self.exportDate = exportDate
    }
}

/// Folder and file name templates for copying imports, in the spirit of tools
/// such as Rapid Photo Downloader. Tokens:
///
///     {capture:<date pattern>}   capture date, e.g. {capture:yyyy}/{capture:yyyy-MM-dd}
///     {import:<date pattern>}    today, e.g. {import:yyyy-MM-dd}
///     {make} {model} {serial} {lens}
///     {name}                     original name without extension
///     {number}                   the digits in the original name (IMG_0412 → 0412)
///     {ext} {ext:lower} {ext:upper}
///     {seq:4}                    this import's shot number, zero-padded
///     {counter:5}                a number that keeps counting across imports
///     {job}                      the job code typed for this import
///     {export:<date pattern>}    when exporting: today
///
/// Date patterns are Unicode patterns (yyyy, MM, MMM, MMMM, dd, HH, mm, ss…).
/// Unknown tokens are left as typed. `/` in the folder template makes folders;
/// values never do (slashes and colons in values become dashes).
public struct ImportTemplate: Codable, Hashable, Sendable {
    public var folder: String
    public var fileName: String

    public init(folder: String = "{capture:yyyy}/{capture:yyyy-MM-dd}", fileName: String = "{name}") {
        self.folder = folder
        self.fileName = fileName
    }

    /// Folder path components and file name (with extension) for a file.
    public func render(_ context: TemplateContext) -> (folders: [String], fileName: String) {
        let folders = folder.split(separator: "/", omittingEmptySubsequences: true)
            .map { Self.sanitize(Self.expand(String($0), context)) }
            .filter { !$0.isEmpty }
        var stem = Self.sanitize(Self.expand(fileName, context))
        if stem.isEmpty { stem = (context.originalName as NSString).deletingPathExtension }
        // The extension stays the original's unless the template already ends with one.
        let ext = (context.originalName as NSString).pathExtension
        let hasExtension = !ext.isEmpty && stem.lowercased().hasSuffix("." + ext.lowercased())
        return (folders, hasExtension || ext.isEmpty ? stem : stem + "." + ext)
    }

    /// The template with an example file, for showing next to the fields.
    public func example(_ context: TemplateContext) -> String {
        let result = render(context)
        return (result.folders + [result.fileName]).joined(separator: "/")
    }

    // MARK: Expansion

    static func expand(_ template: String, _ context: TemplateContext) -> String {
        var output = ""
        var rest = Substring(template)
        while let open = rest.firstIndex(of: "{") {
            output += rest[..<open]
            guard let close = rest[open...].firstIndex(of: "}") else {
                output += rest[open...]
                return output
            }
            let token = rest[rest.index(after: open)..<close]
            output += value(of: token, context) ?? String(rest[open...close])
            rest = rest[rest.index(after: close)...]
        }
        return output + rest
    }

    private static func value(of token: Substring, _ context: TemplateContext) -> String? {
        let parts = token.split(separator: ":", maxSplits: 1).map(String.init)
        let name = parts.first ?? ""
        let argument = parts.count > 1 ? parts[1] : nil
        let original = context.originalName as NSString
        switch name {
        case "capture":
            guard let argument else { return nil }
            if let date = context.captureDate {
                return format(date, argument, TimeZone(secondsFromGMT: context.captureOffsetSeconds ?? 0)!)
            }
            return format(context.fileDate, argument, .current)
        case "import":
            return argument.map { format(context.importDate, $0, .current) }
        case "export":
            guard let argument, let date = context.exportDate else { return nil }
            return format(date, argument, .current)
        case "make": return context.make ?? ""
        case "model": return context.model ?? ""
        case "serial": return context.serial ?? ""
        case "lens": return context.lens ?? ""
        case "name": return original.deletingPathExtension
        case "number":
            return String(original.deletingPathExtension.reversed().drop { !$0.isNumber }.prefix { $0.isNumber }.reversed())
        case "ext":
            switch argument {
            case "lower": return original.pathExtension.lowercased()
            case "upper": return original.pathExtension.uppercased()
            default: return original.pathExtension
            }
        case "seq": return padded(context.sequence, argument)
        case "counter": return padded(context.counter, argument)
        case "job": return context.jobCode
        default: return nil
        }
    }

    private static func padded(_ value: Int, _ width: String?) -> String {
        let digits = String(value)
        let width = min(Int(width ?? "") ?? 0, 12)
        return String(repeating: "0", count: max(0, width - digits.count)) + digits
    }

    private static func format(_ date: Date, _ pattern: String, _ timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        // Month names follow the person's language; digits stay ASCII for paths.
        formatter.locale = Locale(identifier: Locale.current.identifier + "@numbers=latn")
        formatter.timeZone = timeZone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }

    /// Makes a value safe as one path component.
    static func sanitize(_ text: String) -> String {
        var cleaned = text.unicodeScalars.map { scalar -> String in
            if CharacterSet.controlCharacters.contains(scalar) { return "" }
            if scalar == "/" || scalar == ":" || scalar == "\\" { return "-" }
            return String(scalar)
        }.joined()
        cleaned = cleaned.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        // Leading dots would hide the file; trailing dots and spaces trip up FAT and SMB.
        while cleaned.hasPrefix(".") { cleaned.removeFirst() }
        while cleaned.hasSuffix(".") || cleaned.hasSuffix(" ") { cleaned.removeLast() }
        return String(cleaned.prefix(200))
    }
}
