import Foundation

/// What a failed step came to, in words the UI can say (design §10.2). The
/// server's own message is kept; the key and URLs never are.
public enum PublishCause: Hashable, Sendable {
    /// The server answered `status`, in its own words if it gave any.
    case server(status: Int, message: String?)
    /// No answer: the system's sentence.
    case unreachable(String)
    case certificate
    /// The answer could not be read as Immich's.
    case answerUnreadable
    /// A failure here (rendering, the disk, the catalog): the system's sentence.
    case system(String)

    public init(_ failure: PublishFailure) {
        switch failure {
        case .refused(let status, let message): self = .server(status: status, message: message)
        case .remote(.unreachable(let reason)): self = .unreachable(reason)
        case .remote(.certificate): self = .certificate
        case .remote(.disk(let reason)): self = .system(reason)
        case .remote(.status(let status)): self = .server(status: status, message: nil)
        case .remote: self = .answerUnreadable
        }
    }
}

/// Why one photo's step failed (design §10.2's table).
public enum PublishItemFailure: Hashable, Sendable {
    case offline(volumeName: String)
    case unreadable
    case missingWatermark
    case render(String)
    case uploadRefused(PublishCause)
    case uploadInterrupted
    case removedFromLibrary
    /// The read of an already-there photo failed for a temporary condition or a fault (R19).
    case checkFailed(PublishCause)
    case makeAlbum(album: String, PublishCause)
    /// The create's answer was lost and the album couldn't be looked for (R22).
    case albumUnknown(album: String, PublishCause)
    case addToAlbum(album: String, PublishCause)
    /// Looking for the original, or reading its stack, failed (R14, R15).
    case findOriginal(PublishCause)
    /// The server refused the stack (a locked primary, say): its words only.
    case stackRefused(message: String?)
    case stack(PublishCause)
    case record(String)
}

/// Why an already-there photo had nothing else done (R19, design §10.1).
public enum AlreadyThereReason: Hashable, Sendable, CaseIterable {
    case inTrash
    case hidden
    /// The server refused to show it (a locked photo reads so; never called locked).
    case unreadable
}

/// One photo of a run and how far it got. Steps are `nil` until they apply.
public struct PublishItem: Hashable, Sendable, Identifiable {
    public enum Upload: Hashable, Sendable {
        case pending
        case accepted(RemoteUploadOutcome)
        case failed(PublishItemFailure)
    }

    /// The read of a duplicate answer (R19).
    public enum Check: Hashable, Sendable {
        case pending
        case usable
        case alreadyThere(AlreadyThereReason)
        case failed(PublishItemFailure)
    }

    public enum Step: Hashable, Sendable {
        case pending
        case done
        case failed(PublishItemFailure)
    }

    public enum Stacking: Hashable, Sendable {
        case pending
        case stacked
        case noOriginal(NoOriginalReason)
        case failed(PublishItemFailure)
    }

    public var versionID: Int64
    /// What reports call it: a copy's name or the file name.
    public var name: String
    public var upload: Upload = .pending
    /// Nil unless the upload was answered as a duplicate.
    public var check: Check?
    /// Nil without an album.
    public var album: Step?
    /// Nil with stacking off.
    public var stacking: Stacking?
    /// The record to write, kept when writing it failed (R17).
    public var unrecorded: RemotePublicationRecord?
    /// The step that met the fault which stopped the run, or failed on its own.
    public var recordFailure: String?

    public var id: Int64 { versionID }

    public init(versionID: Int64, name: String, album: Bool, stacking: Bool) {
        self.versionID = versionID
        self.name = name
        self.album = album ? .pending : nil
        self.stacking = stacking ? .pending : nil
    }

    public var assetID: String? {
        if case .accepted(let outcome) = upload { outcome.assetID } else { nil }
    }

    public var isAccepted: Bool { assetID != nil }

    public var isDuplicate: Bool {
        if case .accepted(.duplicate) = upload { true } else { false }
    }

    /// Already there and left alone (R19): trash, hidden or unreadable.
    public var alreadyThere: AlreadyThereReason? {
        if case .alreadyThere(let reason)? = check { reason } else { nil }
    }

    /// The failures of its steps, in step order.
    public var failures: [PublishItemFailure] {
        var failures: [PublishItemFailure] = []
        if case .failed(let failure) = upload { failures.append(failure) }
        if case .failed(let failure)? = check { failures.append(failure) }
        if let recordFailure { failures.append(.record(recordFailure)) }
        if case .failed(let failure)? = album { failures.append(failure) }
        if case .failed(let failure)? = stacking { failures.append(failure) }
        return failures
    }

    public var hasFailed: Bool { !failures.isEmpty }

    /// Accepted with steps that never ended and none failed: not finished (design §10.1).
    public var isUnfinished: Bool {
        guard isAccepted, !hasFailed, alreadyThere == nil else { return false }
        if check == .pending { return true }
        return album == .pending || stacking == .pending
    }

    /// What is left of an unfinished photo, for its sentence (design §10.2).
    public enum Left: Hashable, Sendable { case check, album, stack, albumAndStack }

    public var left: Left? {
        guard isUnfinished else { return nil }
        if check == .pending { return .check }
        switch (album == .pending, stacking == .pending) {
        case (true, true): return .albumAndStack
        case (true, false): return .album
        default: return .stack
        }
    }

    /// Nothing more to do on a retry: accepted and every step ended well,
    /// already there and left alone, or not reached.
    public var needsRetry: Bool { hasFailed || isUnfinished }
}

/// The album of a run, as it stands (R22).
public enum PublishAlbumState: Hashable, Sendable {
    case none
    /// An album of the account's, or one the run made.
    case ready(id: String, name: String, madeByRun: Bool)
    /// To be made with the first photo that gets an album step.
    case toMake(name: String)
    /// The create's answer was lost: the account's albums of that name before
    /// it (never taken for the run's) and the photo it was made with.
    case unknown(name: String, before: Set<String>, first: String)

    public var name: String? {
        switch self {
        case .none: nil
        case .ready(_, let name, _), .toMake(let name), .unknown(let name, _, _): name
        }
    }
}

/// How a run (or its latest retry) ended.
public enum PublishEnding: Hashable, Sendable {
    case completed
    case stopped(PublishStop)

    public var stop: PublishStop? {
        if case .stopped(let stop) = self { stop } else { nil }
    }

    public var isFault: Bool { stop?.isFault ?? false }
}

/// One publish run and its retries (R23): kept until the app quits.
public struct PublishRun: Sendable, Identifiable {
    public var id = UUID()
    /// The server as it was when the run started.
    public var service: RemoteServiceRecord
    public var choices: PublishChoices
    /// Typed for this run; nil when empty (R5).
    public var description: String?
    public var startedAt: Date
    public var items: [PublishItem]
    public var album: PublishAlbumState
    /// Photos the person chose to skip (R18).
    public var skipped: Int
    public var videos: Int
    /// The latest ending, a retry's included (R23).
    public var ending: PublishEnding?
    public var endedAt: Date?

    public init(service: RemoteServiceRecord, choices: PublishChoices, description: String?, items: [PublishItem],
                skipped: Int = 0, videos: Int = 0, startedAt: Date = Date()) {
        self.service = service
        self.choices = choices
        let typed = description?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.description = typed?.isEmpty == false ? typed : nil
        self.items = items
        self.skipped = skipped
        self.videos = videos
        self.startedAt = startedAt
        album = switch choices.album {
        case .none: .none
        case .existing(let id, let name): .ready(id: id, name: name, madeByRun: false)
        case .new(let name): .toMake(name: name)
        }
    }

    public var counts: PublishCounts { PublishCounts(self) }

    /// The photos a retry covers (R23): failed or unfinished ones, and the
    /// ones not reached when the latest ending was a fault. Photos already
    /// there and left alone never; those a later run published are removed
    /// by the job.
    public var retryCandidates: [Int64] {
        let includesUnreached = ending?.isFault == true
        return items.filter { item in
            if item.needsRetry { return true }
            return includesUnreached && item.upload == .pending
        }.map(\.versionID)
    }

    /// Retry Failed is offered (design §10.3).
    public var offersRetry: Bool { !retryCandidates.isEmpty }

    /// After the person's own Stop, photos not yet uploaded are left out of
    /// a retry, and the sheet says so.
    public var retryLeavesOutUnreached: Bool {
        ending == .stopped(.stopped) && items.contains { $0.upload == .pending }
    }
}

/// The result's counts (R23, design §10.1).
public struct PublishCounts: Hashable, Sendable {
    public var published = 0
    public var alreadyOnServer = 0
    public var alreadyThere: [AlreadyThereReason: Int] = [:]
    public var skipped = 0
    public var stacked = 0
    public var notStacked = 0
    public var videos = 0
    public var failed = 0
    public var notFinished = 0
    public var notPublished = 0

    public init() {}

    init(_ run: PublishRun) {
        skipped = run.skipped
        videos = run.videos
        for item in run.items {
            switch item.upload {
            case .accepted(.created): published += 1
            case .accepted(.duplicate): alreadyOnServer += 1
            case .pending: notPublished += 1
            case .failed: break
            }
            if let reason = item.alreadyThere {
                alreadyThere[reason, default: 0] += 1
                continue
            }
            if item.hasFailed {
                failed += 1
            } else if item.isUnfinished {
                notFinished += 1
                continue
            }
            switch item.stacking {
            case .stacked?: stacked += 1
            case .noOriginal?: notStacked += 1
            default: break
            }
        }
    }

    /// A warning row (design §10.1): something failed, or a fault stopped the run.
    public func isWarning(ending: PublishEnding?) -> Bool { failed > 0 || ending?.isFault == true }
}

/// Where a run is (design §9).
public struct PublishProgress: Hashable, Sendable {
    public enum Phase: Hashable, Sendable {
        case rendering
        case uploading
        /// A request is being tried again.
        case waiting
        /// Stopping: waiting for answers to fully sent files.
        case ending
    }

    public var done: Int
    public var total: Int
    /// The newest photo started, 1-based.
    public var current: Int
    public var phase: Phase

    public init(done: Int, total: Int, current: Int, phase: Phase) {
        self.done = done
        self.total = total
        self.current = current
        self.phase = phase
    }
}
