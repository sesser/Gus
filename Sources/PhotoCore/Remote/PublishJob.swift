import CryptoKit
import Foundation
import os

/// Publishes photos to one server (issue #28): renders each like an export,
/// uploads it, records it, then files it in the album and stacks it on its
/// original, each photo's steps right after its own upload (R21). Also runs
/// Retry Failed (R23) over a run it ran before.
///
/// Stopping is cancelling the task that runs it. An upload not fully sent is
/// cancelled at once; one fully sent waits for its answer until `endingBound`
/// after the run began to end, and is recorded if accepted (R17). A fault
/// (no server after the retries, a rejected key, a changed certificate, a
/// missing permission) stops the run the same way (R22).
public struct PublishJob: Sendable {
    public let catalog: Catalog
    public let renderer: ExportRenderer
    public let destination: any RemotePublishDestination
    /// The key's account, for finding originals (stacking only).
    public let accountID: String?
    public let folderMap: [PublishFolderMapping]
    public var retry: RemoteRetryPolicy
    /// How long an ending run waits for answers to fully sent files (R17;
    /// the quit wait import and merge use).
    public var endingBound: Duration
    /// Photos worked on at once: renders are large (`ExportJob`).
    public var concurrency: Int
    public var copyNaming: CopyNaming
    /// Where the run's rendered files and upload bodies go; removed when the
    /// run ends, however it ends (R24).
    public var temporaryRoot: URL
    public var timeZone: TimeZone
    /// Told when an upload's whole body went to the system (tests and the
    /// debug script stop a run at that point, R17, AC23).
    public var onFullySent: (@Sendable () -> Void)?
    /// Told, with the photo's version, as each accepted upload is recorded
    /// (the import window marks it In Library at once, design §11).
    public var onRecorded: (@Sendable (Int64) -> Void)?
    /// Tests: awaited once the job's own reads are done and before its first
    /// photo starts, so a Stop can land there (code review C12).
    var beforeFirstPhoto: (@Sendable () async -> Void)?
    /// Tests: replaces the ending's wait for its deadline (`RemoteUploadEnding`),
    /// to see when it is asked for and when it returns.
    var waitForEndingDeadline: (@Sendable (ContinuousClock.Instant) async -> Void)?

    private static let log = Logger(subsystem: AppBranding.bundleIdentifier, category: "publish")

    /// The folder every run's temporary folder is made in: this launch's
    /// own (`PublishTemporaryFolders`), so no other copy of the app removes it.
    public static var defaultTemporaryRoot: URL { PublishTemporaryFolders.launchFolder }

    public init(catalog: Catalog, renderer: ExportRenderer, destination: any RemotePublishDestination,
                accountID: String?, folderMap: [PublishFolderMapping], retry: RemoteRetryPolicy = .standard,
                endingBound: Duration = .seconds(10), concurrency: Int = 2, copyNaming: CopyNaming = .plain,
                temporaryRoot: URL = PublishJob.defaultTemporaryRoot, timeZone: TimeZone = .current) {
        self.catalog = catalog
        self.renderer = renderer
        self.destination = destination
        self.accountID = accountID
        self.folderMap = folderMap
        self.retry = retry
        self.endingBound = endingBound
        self.concurrency = max(1, concurrency)
        self.copyNaming = copyNaming
        self.temporaryRoot = temporaryRoot
        self.timeZone = timeZone
    }

    /// Removes the run folders of launches that have ended without cleaning
    /// up (a crash); another running copy's are left alone (code review C5).
    public static func removeLeftovers() {
        PublishTemporaryFolders.removeLeftovers()
    }

    // MARK: Running

    /// Runs `run` (fresh) or retries it (`retrying`), and returns it with
    /// each photo's steps and the ending.
    public func run(_ run: PublishRun, retrying: Bool = false,
                    progress: @escaping @Sendable (PublishProgress) -> Void = { _ in }) async -> PublishRun {
        await perform(run, retrying: retrying, progress: progress).run
    }

    /// Retry Failed over `run` (R23). Nil when it was stopped before it
    /// started on any photo: that Stop is not an ending, and the run stays as
    /// it was (PRD revision 7, design §10.3, review D-10).
    public func retry(_ run: PublishRun,
                      progress: @escaping @Sendable (PublishProgress) -> Void = { _ in }) async -> PublishRun? {
        let outcome = await perform(run, retrying: true, progress: progress)
        return outcome.calledOff ? nil : outcome.run
    }

    /// The run, and whether the person's Stop came before any photo was
    /// started (no request about a photo was made).
    private func perform(_ run: PublishRun, retrying: Bool,
                         progress: @escaping @Sendable (PublishProgress) -> Void) async -> (run: PublishRun, calledOff: Bool) {
        var run = run
        var versionIDs = run.items.map(\.versionID)
        if retrying {
            // A photo not uploaded that a later run published is left out
            // (R23), by the rule Retry Failed's button follows (review D-12).
            // A catalog that can't be read leaves nothing out.
            let later = (try? await catalog.laterPublications(of: run)) ?? []
            versionIDs = run.retryVersionIDs(laterPublished: later)
        }
        let folder = temporaryRoot.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        // Every photo as saved when the run starts (R2, R23).
        let exportJob = ExportJob(catalog: catalog, renderer: renderer, copyNaming: copyNaming)
        let exportItems = Dictionary(((try? await exportJob.items(for: versionIDs)) ?? []).map { ($0.versionID, $0) },
                                     uniquingKeysWith: { first, _ in first })
        let sources = (try? await catalog.publishSources(versionIDs: versionIDs, address: run.service.address)) ?? [:]
        let state = RunState(run: run)
        let albums = AlbumCoordinator(state: state, destination: destination, retry: retry)
        let sequencer = StackSequencer()
        let total = versionIDs.count
        let counter = ProgressCounter(total: total, report: progress)
        let ending = RemoteUploadEnding(bound: endingBound, onFullySent: onFullySent,
                                        onAwaitingChange: { counter.awaiting($0) },
                                        waitUntil: waitForEndingDeadline ?? RemoteUploadEnding.sleep(until:))

        if let beforeFirstPhoto { await beforeFirstPhoto() }

        let indexes = Dictionary(run.items.enumerated().map { ($1.versionID, $0) }, uniquingKeysWith: { first, _ in first })
        let work = versionIDs.compactMap { id in indexes[id].map { (order: $0, id: id) } }
        // The first photo starts at once: its step, never "0 of N"; a photo
        // whose upload is done finishes its steps under Uploading (review D-8).
        if let first = work.first {
            counter.step(run.items[first.order].isAccepted ? .uploading : .rendering, current: 1)
        } else {
            counter.step(.rendering)
        }
        let context = ItemContext(job: self, state: state, albums: albums, sequencer: sequencer, ending: ending,
                                  folder: folder, counter: counter, runDate: run.startedAt,
                                  service: run.service, choices: run.choices, description: run.description)
        var stop: PublishStop?
        /// Photos started so far, also their 1-based sequence.
        var sequence = 0
        // The person's Stop ends the run as a fault does: every later report
        // says so (design §9, review F2).
        await withTaskCancellationHandler {
            await withTaskGroup(of: PublishStop?.self) { group in
                var pending = work.makeIterator()
                var running = 0
                func startNext() -> Bool {
                    guard stop == nil, !Task.isCancelled, let next = pending.next() else { return false }
                    sequence += 1
                    let item = (order: next.order, id: next.id, sequence: sequence)
                    let exportItem = exportItems[next.id]
                    let source = sources[next.id]
                    group.addTask { await context.publish(order: item.order, versionID: item.id, sequence: item.sequence,
                                                          exportItem: exportItem, source: source, retrying: retrying) }
                    running += 1
                    return true
                }
                while running < concurrency, startNext() {}
                while let fault = await group.next() {
                    running -= 1
                    if let fault, stop == nil {
                        stop = fault
                        counter.stopping()
                        group.cancelAll()
                    }
                    _ = startNext()
                }
            }
        } onCancel: {
            counter.stopping()
        }
        let calledOff = stop == nil && Task.isCancelled && sequence == 0
        run = await state.run
        if let stop {
            run.ending = .stopped(stop)
        } else if Task.isCancelled {
            run.ending = .stopped(.stopped)
        } else {
            run.ending = .completed
        }
        run.endedAt = Date()
        return (run, calledOff)
    }

    // MARK: Values sent (R3, R4)

    /// The upload's date (R4, RI-V1): the capture's wall-clock time labelled
    /// UTC; with no capture date, the original file's modification date as
    /// local wall-clock time.
    public static func uploadDate(captureDate: Date?, offsetSeconds: Int?, modifiedAt: Date, timeZone: TimeZone) -> Date {
        if let captureDate { return captureDate.addingTimeInterval(TimeInterval(offsetSeconds ?? 0)) }
        return modifiedAt.addingTimeInterval(TimeInterval(timeZone.secondsFromGMT(for: modifiedAt)))
    }

    /// The library's values with the typed description in place of each
    /// photo's own (R5).
    public static func values(_ values: SidecarValues, description: String?) -> SidecarValues {
        guard let description else { return values }
        var values = values
        values.caption = description
        return values
    }

    static func sha256(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func sha256(file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// What decides the pixels (R17): the master, the edit stack, the render
    /// settings (names and metadata aside) and the pipeline.
    static func pictureDigest(_ item: ExportItem, settings: ExportSettings) -> String {
        var render = settings
        render.naming = .original
        render.fileNameTemplate = ""
        render.metadata = .all
        let json = (try? render.jsonString()) ?? ""
        return sha256("\(item.details.image.contentHash)|\(item.details.version.editStackHash)|\(json)|\(PreviewCacheKey.currentPipelineVersion)")
    }

    /// The values sent with the picture (R17).
    static func metadataDigest(values: SidecarValues, settings: ExportSettings, fields: PublishUploadBody.Fields) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let text = (try? encoder.encode(values)).map { String(decoding: $0, as: UTF8.self) } ?? ""
        return sha256("\(settings.metadata.rawValue)|\(text)|\(fields.fileName)|\(PublishUploadBody.isoUTC(fields.createdAt))|\(fields.visibility.rawValue)")
    }

    // MARK: Requests, tried again (R22)

    /// `request`, tried again after the policy's delays while it fails for a
    /// temporary condition. `waiting` is told true when the first wait
    /// begins and false when the request is over, however it ends.
    func retrying<T: Sendable>(_ waiting: @Sendable (Bool) -> Void = { _ in },
                               _ request: @Sendable () async throws(PublishFailure) -> T) async throws(PublishFailure) -> T {
        var attempt = 0
        var waited = false
        defer { if waited { waiting(false) } }
        while true {
            do throws(PublishFailure) {
                return try await request()
            } catch {
                guard error.isTransient, attempt < retry.delays.count, !Task.isCancelled else { throw error }
                if !waited {
                    waited = true
                    waiting(true)
                }
                do {
                    try await Task.sleep(for: retry.delays[attempt])
                } catch {
                    throw .remote(.cancelled)
                }
                attempt += 1
            }
        }
    }
}

/// The run's mutable state, shared by its photos.
actor RunState {
    private(set) var run: PublishRun

    init(run: PublishRun) {
        self.run = run
    }

    func item(_ order: Int) -> PublishItem { run.items[order] }

    func update(_ order: Int, _ change: @Sendable (inout PublishItem) -> Void) {
        change(&run.items[order])
    }

    var album: PublishAlbumState { run.album }

    func setAlbum(_ album: PublishAlbumState) { run.album = album }
}

/// Counts photos whose steps all ended, and reports the phase (design §9):
/// ending once the run began to end, whatever comes after (review F2);
/// waiting while any request is being tried again, then back to the step in
/// hand (review F15); else the newest step reported.
final class ProgressCounter: Sendable {
    private struct State {
        var done = 0
        var current = 0
        var step = PublishProgress.Phase.rendering
        var waiting = 0
        var ending = false
        var awaitsAnswer = false

        func progress(total: Int) -> PublishProgress {
            let phase: PublishProgress.Phase = ending ? .ending : waiting > 0 ? .waiting : step
            return PublishProgress(done: done, total: total, current: current, phase: phase,
                                   awaitsAnswer: ending && awaitsAnswer)
        }
    }

    private let total: Int
    private let state = OSAllocatedUnfairLock(initialState: State())
    private let reportTo: @Sendable (PublishProgress) -> Void

    init(total: Int, report: @escaping @Sendable (PublishProgress) -> Void) {
        self.total = total
        reportTo = report
    }

    /// Each report is delivered inside the lock, so reports reach the
    /// listener in the order of the states they describe (code review C9).
    /// The listener must not block or call back: the app's makes a task, the
    /// tests' append under a lock of their own.
    private func change(_ body: @Sendable (inout State) -> Void) {
        let total = self.total
        let reportTo = self.reportTo
        state.withLock { state in
            body(&state)
            reportTo(state.progress(total: total))
        }
    }

    /// A photo's step: rendering or uploading.
    func step(_ phase: PublishProgress.Phase, current: Int? = nil) {
        change { state in
            state.step = phase
            if let current { state.current = max(state.current, current) }
        }
    }

    /// A request started (true) or stopped (false) being tried again.
    func waiting(_ isWaiting: Bool) {
        change { state in state.waiting = max(0, state.waiting + (isWaiting ? 1 : -1)) }
    }

    /// The run began to end (a fault, or the person's Stop): it stays so.
    func stopping() {
        change { state in state.ending = true }
    }

    /// An answer to a fully sent file is awaited, or no longer.
    func awaiting(_ isAwaiting: Bool) {
        change { state in state.awaitsAnswer = isAwaiting }
    }

    func finished() {
        change { state in state.done += 1 }
    }
}

/// Stacks for one original are created one at a time, in grid order (R14;
/// status.md, item 11): a photo's stack step waits until every earlier photo
/// has either a different original or has ended its stack step.
actor StackSequencer {
    private enum Known: Equatable {
        case original(String?)
        case ended
    }

    private var known: [Int: Known] = [:]
    private var waiters: [(order: Int, original: String, continuation: CheckedContinuation<Void, Never>)] = []
    private var started: Set<Int> = []

    func start(_ order: Int) { started.insert(order) }

    /// The photo's original is known (nil: none, or the look failed).
    func resolved(_ order: Int, original: String?) {
        if known[order] != .ended { known[order] = .original(original) }
        wake()
    }

    func ended(_ order: Int) {
        known[order] = .ended
        wake()
    }

    func turn(_ order: Int, original: String) async {
        guard !isClear(order, original) else { return }
        await withCheckedContinuation { waiters.append((order, original, $0)) }
    }

    private func isClear(_ order: Int, _ original: String) -> Bool {
        started.filter { $0 < order }.allSatisfy { earlier in
            switch known[earlier] {
            case .ended?: true
            case .original(let other)?: other != original
            case nil: false
            }
        }
    }

    private func wake() {
        let ready = waiters.filter { isClear($0.order, $0.original) }
        waiters.removeAll { waiter in ready.contains { $0.order == waiter.order } }
        for waiter in ready { waiter.continuation.resume() }
    }
}

/// The run's album (R6, R22): made with the first photo that gets an album
/// step; a lost answer to the create is looked for among the account's
/// albums of that name holding that photo and not there before the create,
/// so an older album of the same name is never taken for it; made again only
/// when the server shows none. One album request at a time.
actor AlbumCoordinator {
    private let state: RunState
    private let destination: any RemotePublishDestination
    private let retry: RemoteRetryPolicy
    private var busy = false
    private var queue: [CheckedContinuation<Void, Never>] = []

    init(state: RunState, destination: any RemotePublishDestination, retry: RemoteRetryPolicy) {
        self.state = state
        self.destination = destination
        self.retry = retry
    }

    private func acquire() async {
        if !busy {
            busy = true
            return
        }
        await withCheckedContinuation { queue.append($0) }
    }

    private func release() {
        if queue.isEmpty { busy = false } else { queue.removeFirst().resume() }
    }

    enum Outcome: Sendable {
        case done
        case failed(PublishItemFailure, fault: PublishStop?)
        /// The run ended first: the step is left, not failed.
        case cutOff
    }

    /// Files `assetID` in the run's album.
    func add(_ assetID: String, job: PublishJob, waiting: @escaping @Sendable (Bool) -> Void) async -> Outcome {
        await acquire()
        defer { release() }
        if Task.isCancelled { return .cutOff }
        var album = await state.album
        let name = album.name ?? ""
        // A create is never sent again before the album it may have made was
        // looked for (R22); the whole cycle is tried as often as a request.
        var creates = 0
        do throws(PublishFailure) {
            while true {
                switch album {
                case .none:
                    return .done
                case .ready(let id, _, _):
                    let refused = try await job.retrying(waiting) { () async throws(PublishFailure) in
                        try await destination.addToAlbum(id, assetIDs: [assetID])
                    }
                    if let error = refused[assetID] {
                        return .failed(.addToAlbum(album: name, .itemRefused(error.isEmpty ? nil : error)), fault: nil)
                    }
                    return .done
                case .toMake(let name):
                    let before = try await job.retrying(waiting) { () async throws(PublishFailure) in
                        try await destination.ownAlbums(holding: nil)
                    }.filter { $0.name == name }.map(\.id)
                    creates += 1
                    do throws(PublishFailure) {
                        // Not through `retrying`: a repeat could make a second album.
                        let made = try await destination.createAlbum(named: name, assetIDs: [assetID])
                        album = .ready(id: made.id, name: name, madeByRun: true)
                        await state.setAlbum(album)
                        return .done
                    } catch where error.isTransient || error.isCancelled {
                        // The answer was lost: the album may have been made.
                        album = .unknown(name: name, before: Set(before), first: assetID)
                        await state.setAlbum(album)
                        if error.isCancelled { throw error }
                        if creates > job.retry.delays.count {
                            return .failed(.albumUnknown(album: name, PublishCause(error)), fault: .unreachable)
                        }
                        waiting(true)
                        defer { waiting(false) }
                        do {
                            try await Task.sleep(for: job.retry.delays[creates - 1])
                        } catch {
                            return .cutOff
                        }
                    } catch {
                        return .failed(.makeAlbum(album: name, PublishCause(error)), fault: error.stop)
                    }
                case .unknown(let name, let before, let first):
                    let holding: [RemoteAlbum]
                    do throws(PublishFailure) {
                        holding = try await job.retrying(waiting) { () async throws(PublishFailure) in
                            try await destination.ownAlbums(holding: first)
                        }
                    } catch {
                        if error.isCancelled { return .cutOff }
                        return .failed(.albumUnknown(album: name, PublishCause(error)), fault: error.stop)
                    }
                    // Made by this run: of that name, holding its first photo,
                    // and not among the albums of that name before the create.
                    let made = holding.filter { $0.name == name && !before.contains($0.id) }
                    if let found = made.first {
                        album = .ready(id: found.id, name: name, madeByRun: true)
                        await state.setAlbum(album)
                        if first == assetID { return .done }
                    } else {
                        album = .toMake(name: name)
                        await state.setAlbum(album)
                    }
                }
            }
        } catch {
            if error.isCancelled { return .cutOff }
            let failure: PublishItemFailure = switch album {
            case .unknown: .albumUnknown(album: name, PublishCause(error))
            case .toMake: .makeAlbum(album: name, PublishCause(error))
            default: .addToAlbum(album: name, PublishCause(error))
            }
            return .failed(failure, fault: error.stop)
        }
    }
}

/// What one photo's work needs from its run.
struct ItemContext: Sendable {
    let job: PublishJob
    let state: RunState
    let albums: AlbumCoordinator
    let sequencer: StackSequencer
    let ending: RemoteUploadEnding
    let folder: URL
    let counter: ProgressCounter
    let runDate: Date
    let service: RemoteServiceRecord
    let choices: PublishChoices
    let description: String?

    private var destination: any RemotePublishDestination { job.destination }

    private func waiting() -> @Sendable (Bool) -> Void {
        let counter = self.counter
        return { counter.waiting($0) }
    }

    /// One photo, every step that is left. Returns the fault that stops the
    /// run, if this photo met one.
    func publish(order: Int, versionID: Int64, sequence: Int, exportItem: ExportItem?, source: PublishSource?,
                 retrying: Bool) async -> PublishStop? {
        await sequencer.start(order)
        defer { counter.finished() }
        let result = await steps(order: order, versionID: versionID, sequence: sequence, exportItem: exportItem,
                                 source: source)
        await sequencer.ended(order)
        return result
    }

    private func steps(order: Int, versionID: Int64, sequence: Int, exportItem: ExportItem?,
                       source: PublishSource?) async -> PublishStop? {
        var item = await state.item(order)
        var original: OriginalMatch?
        var originalFailure: PublishFailure?

        if case .accepted = item.upload {
            // A retry: the upload is done; the rest follows, under Uploading
            // (design §9, review D-8).
            counter.step(.uploading, current: sequence)
        } else {
            guard let exportItem, (try? await job.catalog.version(id: versionID)) != nil else {
                await state.update(order) { $0.upload = .failed(.removedFromLibrary) }
                return nil
            }
            guard exportItem.isOnline else {
                await state.update(order) { $0.upload = .failed(.offline(volumeName: exportItem.details.volume.name)) }
                return nil
            }
            // The original is looked for first, so stacks for one original go
            // in grid order whatever order the uploads finish in (R14).
            if item.stacking == .pending, let source, let finder = finder() {
                do throws(PublishFailure) {
                    original = try await job.retrying(waiting()) { () async throws(PublishFailure) in
                        try await finder.find(source)
                    }
                } catch {
                    if error.isCancelled { return nil }
                    originalFailure = error
                }
            }
            await sequencer.resolved(order, original: original.flatMap { if case .found(let id) = $0 { id } else { nil } })
            let outcome = await upload(order: order, sequence: sequence, exportItem: exportItem)
            if let stop = outcome { return stop }
            item = await state.item(order)
            guard item.isAccepted else { return nil }
        }
        // An accepted upload that met the run's end gets no further step (design §9).
        if Task.isCancelled { return nil }
        guard let assetID = item.assetID else { return nil }

        // A record that failed is written again first (R17).
        if let record = item.unrecorded {
            if await Self.record(record, in: job.catalog) == nil {
                job.onRecorded?(versionID)
                await state.update(order) {
                    $0.unrecorded = nil
                    $0.recordFailure = nil
                }
            }
        }

        // Every duplicate is read before any album or stack step (R19).
        if item.isDuplicate, item.check != .usable {
            if case .alreadyThere = item.check { return nil }
            do throws(PublishFailure) {
                let asset = try await job.retrying(waiting()) { () async throws(PublishFailure) in
                    try await destination.asset(id: assetID)
                }
                let check: PublishItem.Check = if let asset {
                    asset.isTrashed ? .alreadyThere(.inTrash) : asset.isHidden ? .alreadyThere(.hidden) : .usable
                } else {
                    .alreadyThere(.unreadable)
                }
                await state.update(order) { $0.check = check }
                guard check == .usable else { return nil }
            } catch {
                if error.isCancelled { return nil }
                await state.update(order) { $0.check = .failed(.checkFailed(PublishCause(error))) }
                return error.stop
            }
        }
        if Task.isCancelled { return nil }

        // The album (R6).
        item = await state.item(order)
        if item.album != nil, item.album != .done {
            switch await albums.add(assetID, job: job, waiting: waiting()) {
            case .done:
                await state.update(order) { $0.album = .done }
            case .failed(let failure, let fault):
                await state.update(order) { $0.album = .failed(failure) }
                if let fault { return fault }
            case .cutOff:
                // Left as it was: not finished (design §10.1).
                await state.update(order) { $0.album = .pending }
                return nil
            }
        }
        if Task.isCancelled { return nil }

        // The stack (R10 to R15).
        item = await state.item(order)
        guard item.stacking != nil, item.stacking != .stacked else { return nil }
        if case .noOriginal = item.stacking { return nil }
        return await stack(order: order, assetID: assetID, source: source, original: original,
                           originalFailure: originalFailure)
    }

    private func finder() -> OriginalFinder? {
        guard let account = job.accountID else { return nil }
        return OriginalFinder(destination: destination, catalog: job.catalog, address: service.address,
                              accountID: account, folderMap: job.folderMap)
    }

    /// Renders, uploads and records one photo. Returns a fault that stops the run.
    private func upload(order: Int, sequence: Int, exportItem: ExportItem) async -> PublishStop? {
        counter.step(.rendering, current: sequence)
        let itemFolder = folder.appending(path: "\(order)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: itemFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: itemFolder) }
        let settings = choices.settings
        let context = exportItem.templateContext(sequence: sequence, exportDate: runDate)
        let fileName = ExportNaming.fileName(for: context, settings: settings)
        let file = itemFolder.appending(path: Self.safeFileName(fileName), directoryHint: .notDirectory)
        let values = PublishJob.values(exportItem.values, description: description)
        do {
            let stack = try exportItem.details.version.decodedEditStack()
            try job.renderer.export(source: exportItem.sourceURL, stack: stack, values: values, settings: settings,
                                    to: file, replacing: false)
        } catch ExportRenderer.Failure.missingWatermark {
            await state.update(order) { $0.upload = .failed(.missingWatermark) }
            return nil
        } catch PreviewGenerator.Failure.undecodable {
            await state.update(order) { $0.upload = .failed(.unreadable) }
            return nil
        } catch is CancellationError {
            return nil
        } catch {
            await state.update(order) { $0.upload = .failed(.render(error.localizedDescription)) }
            return nil
        }
        if Task.isCancelled { return nil }
        let image = exportItem.details.image
        let fields = PublishUploadBody.Fields(
            createdAt: PublishJob.uploadDate(captureDate: image.captureDate, offsetSeconds: image.captureOffsetSeconds,
                                             modifiedAt: image.modifiedAt, timeZone: job.timeZone),
            fileName: fileName, visibility: choices.visibility)
        let body = itemFolder.appending(path: "body.multipart", directoryHint: .notDirectory)
        let contentType: String
        let fileDigest: String
        do {
            contentType = try PublishUploadBody.write(file: file, fields: fields, to: body)
            fileDigest = try PublishJob.sha256(file: file)
            try? FileManager.default.removeItem(at: file)
        } catch {
            await state.update(order) { $0.upload = .failed(.render(error.localizedDescription)) }
            return nil
        }
        counter.step(.uploading, current: sequence)
        let outcome: RemoteUploadOutcome
        do throws(PublishFailure) {
            let ending = self.ending
            outcome = try await job.retrying(waiting()) { () async throws(PublishFailure) in
                try await destination.upload(bodyFile: body, contentType: contentType, ending: ending)
            }
        } catch {
            if error.isCancelled { return nil }
            if let stop = error.stop {
                // The photo that met the fault counts it as its failure.
                let failure: PublishItemFailure = if case .remote = error { .uploadInterrupted } else { .uploadRefused(PublishCause(error)) }
                await state.update(order) { $0.upload = .failed(failure) }
                return stop
            }
            let failure: PublishItemFailure = if case .remote = error { .uploadInterrupted } else { .uploadRefused(PublishCause(error)) }
            await state.update(order) { $0.upload = .failed(failure) }
            return nil
        }
        let record = RemotePublicationRecord(
            address: service.address, remoteId: outcome.assetID, versionId: exportItem.versionID, serviceId: service.id,
            answer: { if case .duplicate = outcome { .duplicate } else { .created } }(),
            pictureDigest: PublishJob.pictureDigest(exportItem, settings: settings),
            metadataDigest: PublishJob.metadataDigest(values: values, settings: settings, fields: fields),
            fileDigest: fileDigest)
        // Recorded even when the run is ending (R17): the catalog refuses a
        // write from a cancelled task, so it is made outside the run's task.
        let recordError = await Self.record(record, in: job.catalog)
        if recordError == nil { job.onRecorded?(exportItem.versionID) }
        await state.update(order) { item in
            item.upload = .accepted(outcome)
            if case .duplicate = outcome { item.check = .pending }
            if let recordError {
                item.unrecorded = record
                item.recordFailure = recordError
            }
        }
        return nil
    }

    /// The stack step: the original (looked for again if needed), its stack's
    /// primary as read just before, then the create naming the edit, that
    /// primary and the original, one at a time per original (R14).
    private func stack(order: Int, assetID: String, source: PublishSource?, original: OriginalMatch?,
                       originalFailure: PublishFailure?) async -> PublishStop? {
        var match = original
        if let originalFailure {
            await state.update(order) { $0.stacking = .failed(.findOriginal(PublishCause(originalFailure))) }
            return originalFailure.stop
        }
        if match == nil || match == .found(assetID: assetID) {
            guard let source, let finder = finder() else {
                await state.update(order) { $0.stacking = .failed(.findOriginal(.answerUnreadable)) }
                return nil
            }
            do throws(PublishFailure) {
                match = try await job.retrying(waiting()) { () async throws(PublishFailure) in try await finder.find(source) }
            } catch {
                if error.isCancelled { return nil }
                await state.update(order) { $0.stacking = .failed(.findOriginal(PublishCause(error))) }
                return error.stop
            }
            await sequencer.resolved(order, original: match.flatMap { if case .found(let id) = $0 { id } else { nil } })
        }
        guard case .found(let originalID)? = match, originalID != assetID else {
            let reason: NoOriginalReason = if case .none(let reason)? = match { reason } else { .noMappedFolder }
            await state.update(order) { $0.stacking = .noOriginal(reason) }
            return nil
        }
        await sequencer.turn(order, original: originalID)
        if Task.isCancelled { return nil }
        do throws(PublishFailure) {
            let read = try await job.retrying(waiting()) { () async throws(PublishFailure) in
                try await destination.asset(id: originalID)
            }
            guard let read else {
                await state.update(order) {
                    $0.stacking = .failed(.findOriginal(.server(status: 400, message: nil)))
                }
                return nil
            }
            var ids = [assetID]
            if let primary = read.stack?.primaryAssetID, primary != originalID, primary != assetID { ids.append(primary) }
            ids.append(originalID)
            let named = ids
            _ = try await job.retrying(waiting()) { () async throws(PublishFailure) in
                try await destination.createStack(named)
            }
            await state.update(order) { $0.stacking = .stacked }
            return nil
        } catch {
            if error.isCancelled { return nil }
            let failure: PublishItemFailure = if case .refused(400, let message) = error {
                .stackRefused(message: message)
            } else {
                .stack(PublishCause(error))
            }
            await state.update(order) { $0.stacking = .failed(failure) }
            return error.stop
        }
    }

    /// Writes `record` whatever the run's cancellation; nil when written,
    /// else the reason.
    static func record(_ record: RemotePublicationRecord, in catalog: Catalog) async -> String? {
        await Task.detached {
            do {
                try await catalog.recordPublication(record)
                return nil
            } catch {
                return error.localizedDescription
            }
        }.value
    }

    /// A name for the temporary file: the template's, with no separator.
    static func safeFileName(_ name: String) -> String {
        let cleaned = name.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
        return cleaned.isEmpty || cleaned == "." || cleaned == ".." ? "photo.jpg" : cleaned
    }
}
