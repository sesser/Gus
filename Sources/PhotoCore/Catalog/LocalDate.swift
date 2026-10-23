import Foundation

/// The calendar day a photo was taken, as the photographer saw it.
public enum LocalDate {
    private static let utc = TimeZone(secondsFromGMT: 0)!

    /// `YYYY-MM-DD` for a capture date in its own time zone: shifted by the
    /// offset when the file has one, otherwise a floating local time stored as
    /// UTC (see `ImageMetadata.captureDate`). Files without a capture date use
    /// `fallback` (the modification date) in `timeZone`.
    public static func string(captureDate: Date?, offset: Int?, fallback: Date, timeZone: TimeZone = .current) -> String {
        if let captureDate {
            return format(captureDate.addingTimeInterval(TimeInterval(offset ?? 0)), in: utc)
        }
        return format(fallback, in: timeZone)
    }

    /// `YYYY-MM-DD` of `date` in `timeZone`.
    public static func format(_ date: Date, in timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
