import Foundation

/// What the Merge to HDR sheet shows and decides, without the views (issue
/// #150; design §5.5 to §5.8, §6.4): the frozen frames, the reference the
/// person chose in the table, the Auto-align and De-ghost boxes, the disk's
/// answers, and from them the message, the flagged rows, the Name line and
/// whether Merge is on.
///
/// Made new every time the sheet opens, so the reference is R3's default and
/// both boxes are on (AC3c, AC9a); nothing here is stored.
public struct MergeSheetState: Sendable, Equatable {
    public private(set) var selection: MergeSelection
    /// Auto-align and De-ghost: on when the sheet opens, independent, never stored.
    public var options: MergeOptions = .standard

    /// Case 8 (a master that can't be read): nil while the disk is asked, then
    /// the first unreadable frame's version, or `.some(nil)` when every one can be read.
    public private(set) var unreadable: Int64??
    /// Whether each folder asked so far can be written to, by `folderKey`.
    /// Asked once per folder for the life of the sheet (§5.8).
    public private(set) var writableFolders: [String: Bool] = [:]
    /// Folders being asked now, so a reference that comes back to one doesn't ask twice.
    public private(set) var askingFolders: Set<String> = []
    /// The last Name answer: for which reference and format, and the name.
    public private(set) var nameAnswer: NameAnswer?

    public struct NameAnswer: Sendable, Equatable {
        public var reference: Int64
        public var format: MergeFormat
        public var name: String
    }

    /// The sheet as it opens: the frames, the default reference (R3), both
    /// boxes on. `selection` has at least one frame (the sheet opens for two
    /// targets or more; the app closes it when none could be read).
    public init(selection: MergeSelection) {
        let reference = selection.frames.isEmpty ? nil : selection.frames[selection.defaultReference].versionID
        self.selection = reference.flatMap { selection.choosingReference($0) } ?? selection
    }

    // MARK: The reference

    public var referenceID: Int64 { selection.referenceFrame.versionID }
    public var reference: MergeFrame { selection.referenceFrame }

    /// A row chosen in the table (a click, an arrow key, VO-Space). `nil` (a
    /// ⌘-click on the chosen row, a click below the rows) and an id that is
    /// not a frame leave the reference where it was: the table always has
    /// exactly one row chosen (§5.5). True when the reference changed.
    @discardableResult
    public mutating func chooseReference(_ versionID: Int64?) -> Bool {
        guard let versionID, versionID != referenceID, let next = selection.choosingReference(versionID) else {
            return false
        }
        selection = next
        return true
    }

    // MARK: The disk

    /// How folders are told apart: the standardized path.
    public static func folderKey(_ folder: URL) -> String { folder.standardizedFileURL.path }

    /// The reference's folder when nobody has asked about it yet, else nil.
    public var folderToAsk: URL? {
        let key = Self.folderKey(reference.folder)
        guard writableFolders[key] == nil, !askingFolders.contains(key) else { return nil }
        return reference.folder
    }

    /// The folder is being asked now.
    public mutating func asking(_ folder: URL) {
        askingFolders.insert(Self.folderKey(folder))
    }

    /// The disk's answer for `folder`. Kept for the life of the sheet, as a
    /// fact about the folder; true when it decides the current reference's
    /// folder, false when the reference has moved to another folder since it
    /// was asked (an answer for a superseded reference: shown nowhere).
    @discardableResult
    public mutating func record(folder: URL, writable: Bool) -> Bool {
        let key = Self.folderKey(folder)
        askingFolders.remove(key)
        writableFolders[key] = writable
        return key == Self.folderKey(reference.folder)
    }

    /// The answer to case 8, asked once when the sheet opens.
    public mutating func record(unreadable frame: Int64?) {
        unreadable = .some(frame)
    }

    /// The reference's folder has been asked and answered.
    public var isFolderChecked: Bool { writableFolders[Self.folderKey(reference.folder)] != nil }

    /// Every disk answer the current reference needs is in.
    public var isDiskChecked: Bool { unreadable != nil && isFolderChecked }

    /// The first refusal from the disk (case 8, then case 9 for the current
    /// reference), with the frame it flags; nil while unanswered or clear.
    public var diskRefusal: (refusal: MergeRefusal, flagged: Int64)? {
        if case .some(.some(let id)) = unreadable, let frame = selection.frames.first(where: { $0.versionID == id }) {
            return (.unreadable(name: frame.displayName), id)
        }
        if writableFolders[Self.folderKey(reference.folder)] == false {
            return (MergePreflight.unwritable(reference), referenceID)
        }
        return nil
    }

    // MARK: The small spinner

    /// The small spinner by the buttons (design §5.4, §5.8): hidden while the
    /// disk has answered for the current reference; otherwise shown only once
    /// a half-second wait started for this check has ended with no answer.
    public enum Spinner: Sendable, Equatable {
        case hidden
        /// The wait with this number runs; only it may show the spinner.
        case waiting(Int)
        case shown
    }

    public private(set) var spinner: Spinner = .hidden
    private var spinnerWaits = 0

    /// Decides the spinner again after the disk was asked or answered, or the
    /// reference changed (`restart`: the half second starts again for the new
    /// reference's check, the rule of the first open applied again, §5.8).
    /// Returns the number of a new wait the caller times, or nil when none is
    /// needed: the disk has answered (hidden), the spinner already shows, or a
    /// wait runs and `restart` is false.
    public mutating func decideSpinner(restart: Bool) -> Int? {
        if isDiskChecked {
            spinner = .hidden
            return nil
        }
        switch spinner {
        case .shown: return nil
        case .waiting where !restart: return nil
        case .hidden, .waiting:
            spinnerWaits += 1
            spinner = .waiting(spinnerWaits)
            return spinnerWaits
        }
    }

    /// The half-second wait `number` has ended: the spinner shows if that wait
    /// is still the current one and the disk hasn't answered. A wait that a
    /// newer one replaced, or that an answer ended, changes nothing.
    public mutating func spinnerWaitEnded(_ number: Int) {
        guard spinner == .waiting(number) else { return }
        spinner = isDiskChecked ? .hidden : .shown
    }

    // MARK: What the sheet shows

    /// The message in the header, the first that applies (§6): the
    /// selection's, then the disk's.
    public var refusal: MergeRefusal? { selection.refusal ?? diskRefusal?.refusal }

    /// The rows the message is about.
    public var flagged: Set<Int64> {
        if selection.refusal != nil { return selection.flagged }
        return diskRefusal.map { [$0.flagged] } ?? []
    }

    /// Merge is on: the disk answered for this reference and nothing refuses.
    public func canStart(isMerging: Bool) -> Bool {
        isDiskChecked && refusal == nil && !isMerging
    }

    public var framesInSeveralFolders: Bool {
        Set(selection.frames.map { Self.folderKey($0.folder) }).count > 1
    }

    // MARK: The Name line

    /// The answer for the name now, once it is known. A late answer for
    /// another reference or format is ignored.
    public mutating func record(name: String, reference: Int64, format: MergeFormat) {
        nameAnswer = NameAnswer(reference: reference, format: format, name: name)
    }

    /// The Name line for `format`: the numbered name once the disk has
    /// answered for this reference and format (`isFinal`), else the
    /// unnumbered candidate, shown in secondary color meanwhile (§5.8).
    public func name(format: MergeFormat) -> (text: String, isFinal: Bool) {
        if let nameAnswer, nameAnswer.reference == referenceID, nameAnswer.format == format {
            return (nameAnswer.name, true)
        }
        let stem = (reference.fileName as NSString).deletingPathExtension
        return (MergeNaming.name(stem: stem, format: format, masters: MasterFiles.none.names(in: reference.folder),
                                 files: []), false)
    }

    // MARK: VoiceOver

    /// What the announcement after a change of reference says beyond the
    /// reference and the result's name (design §11): the message when one now
    /// shows that didn't (or another one), "Merge is available." when one has
    /// just gone, nothing when the message is as it was.
    public enum MessageChange: Sendable, Equatable {
        case none
        case refusal(MergeRefusal)
        case available
    }

    public static func messageChange(from before: MergeRefusal?, to after: MergeRefusal?) -> MessageChange {
        switch (before, after) {
        case (_, .some(let now)) where now != before: .refusal(now)
        case (.some, nil): .available
        default: .none
        }
    }
}
