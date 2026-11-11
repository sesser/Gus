import PhotoCore
import PhotoUI
import SwiftUI

/// One job the Activity item shows.
struct ActivityJob: Identifiable {
    let id: String
    let title: String
    /// The title as the toolbar shows it: fitted by shortening its name in
    /// the middle (`Export to “Ex…ts”`); the popover shows `title`.
    var toolbarTitle: String?
    /// Under the title in the popover ("12 of 24").
    var detail: String?
    let progress: Double?
    /// Nil when the job cannot be stopped.
    let stop: (@MainActor () -> Void)?
}

/// The toolbar's Activity item (section 1 of docs/UI_REDESIGN.md): the
/// running job's progress and label, and a popover with every job (Stop) and
/// the recent messages that used to go to the status bar. Rendering previews
/// and suggesting keywords show only after they have run a few seconds.
struct ActivityToolbarItem: View {
    let model: LibraryModel

    /// While a job runs, while there are messages not yet read, and while the
    /// popover is open. Whether the popover is open is kept on the model's
    /// `activity`, not in this view, so that `LibraryToolbar` can read it
    /// here: the item it hides is the popover's anchor.
    static func isVisible(_ model: LibraryModel) -> Bool {
        model.activity.showsItem(jobsRunning: !jobs(model).isEmpty)
    }

    var body: some View {
        let jobs = Self.jobs(model)
        Button {
            model.setActivityPopoverShown(true)
        } label: {
            HStack(spacing: 6) {
                if let job = jobs.first {
                    if let progress = job.progress {
                        ProgressView(value: progress).frame(width: 100)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                    Text(job.toolbarTitle ?? job.title).monospacedDigit().toolbarStatusText()
                } else if model.activity.showsItem(jobsRunning: false) {
                    // Idle with unread messages: which kind, the popover says the rest.
                    // Also while the popover is open after its last job ended
                    // without a message: the item never stays without a label.
                    Image(systemName: model.activity.unseenHasWarning ? "exclamationmark.triangle" : "info.circle")
                        .accessibilityLabel(model.activity.messages.last?.text ?? String(localized: "Activity"))
                }
            }
            .toolbarCapsuleInset()
        }
        .buttonStyle(.borderless)
        .help(jobs.isEmpty ? (model.activity.messages.last?.text ?? String(localized: "Activity")) : String(localized: "Activity"))
        // The set is the popover closing (a click outside it, Escape).
        .popover(isPresented: Binding(get: { model.activity.isPopoverShown },
                                      set: { model.setActivityPopoverShown($0) }),
                 arrowEdge: .bottom) {
            ActivityPopover(model: model)
        }
    }

    /// Running jobs, the most important first.
    static func jobs(_ model: LibraryModel) -> [ActivityJob] {
        _ = model.activityTick
        var jobs: [ActivityJob] = []
        // A removal from the library that takes a moment: indeterminate, and
        // without Stop (library-ops design §6.3).
        if let removal = model.removalJob {
            jobs.append(ActivityJob(id: "removal", title: removal.title, detail: removal.detail, progress: nil, stop: nil))
        }
        if let progress = model.importProgress {
            // Add Folder “Trip” or Add 3 Folders; "Folder 1 of 3 · 12 of 412", no
            // plural on a second number (the strings cannot inflect it).
            let batch = model.importBatch
            let title = batch.map { ActivityTitle.addFolders($0.count, name: $0.name) } ?? ActivityTitle.addFolder(nil)
            let toolbarTitle = batch.flatMap { $0.count == 1 ? $0.name : nil }.map { name in
                ToolbarMetrics.statusLine(name: name) { ActivityTitle.addFolder($0) }
            }
            let several = batch.flatMap { $0.count > 1 ? $0 : nil }
            let detail = switch progress.phase {
            case .scanning: String(localized: "Looking for photos…")
            case .importing, .finished:
                several.map {
                    String(localized: "Folder \($0.index) of \($0.count) · \(progress.filesProcessed) of \(progress.filesFound)",
                           comment: "Activity: a batch of folders, then photos imported of found")
                } ?? String(localized: "\(progress.filesProcessed) of \(progress.filesFound)",
                            comment: "Activity: photos imported of found")
            }
            jobs.append(ActivityJob(id: "import", title: title, toolbarTitle: toolbarTitle, detail: detail,
                                    progress: progress.phase == .scanning ? nil
                                        : Double(progress.filesProcessed) / Double(max(progress.filesFound, 1)),
                                    stop: { model.cancelImport() }))
        }
        // A copy goes on when the import window closes (final review Q1).
        let copy = model.cardImport
        if let progress = copy.progress, let source = copy.source {
            jobs.append(ActivityJob(id: "copy", title: CardImportModel.activityTitle(source),
                                    toolbarTitle: ToolbarMetrics.statusLine(name: source.name) {
                                        CardImportModel.activityTitle(name: $0)
                                    },
                                    detail: copy.progressDetail,
                                    progress: Double(progress.bytesDone) / Double(max(progress.bytesTotal, 1)),
                                    stop: { copy.cancelImport() }))
        }
        if let progress = model.export.progress {
            let folder = model.export.destination.lastPathComponent
            jobs.append(ActivityJob(id: "export", title: ActivityTitle.exportTo(folder),
                                    toolbarTitle: ToolbarMetrics.statusLine(name: folder) { ActivityTitle.exportTo($0) },
                                    detail: String(localized: "\(progress.done) of \(progress.total)"),
                                    progress: Double(progress.done) / Double(max(progress.total, 1)),
                                    stop: { model.export.cancel() }))
        }
        if let progress = model.batchAutoProgress {
            // Paste or a preset measuring color alignment shows under the command's own title.
            let title = model.batchAutoTitle
                ?? String(localized: "Measuring exposure \(progress.done) of \(progress.total)",
                          comment: "Activity: batch Auto Exposure")
            let detail: String? = model.batchAutoTitle == nil ? nil
                : String(localized: "\(progress.done) of \(progress.total)")
            jobs.append(ActivityJob(id: "auto", title: title, toolbarTitle: model.batchAutoToolbarTitle, detail: detail,
                                    progress: Double(progress.done) / Double(max(progress.total, 1)),
                                    stop: { model.batchAutoTask?.cancel() }))
        }
        let now = Date()
        if let progress = model.warming, let start = model.warmingStarted,
           ActivityLog.shows(background: true, startedAt: start, now: now) {
            jobs.append(ActivityJob(id: "previews", title: String(localized: "Rendering previews \(progress.done) of \(progress.total)"),
                                    progress: Double(progress.done) / Double(max(progress.total, 1)), stop: nil))
        }
        if let progress = model.suggestionProgress, let start = model.suggestionStarted,
           ActivityLog.shows(background: true, startedAt: start, now: now) {
            jobs.append(ActivityJob(id: "suggestions",
                                    title: String(localized: "Suggesting keywords \(progress.done) of \(progress.total)"),
                                    progress: Double(progress.done) / Double(max(progress.total, 1)), stop: nil))
        }
        return jobs
    }
}

private struct ActivityPopover: View {
    let model: LibraryModel

    var body: some View {
        let jobs = ActivityToolbarItem.jobs(model)
        VStack(alignment: .leading, spacing: 10) {
            ForEach(jobs) { job in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(job.title).monospacedDigit()
                        Spacer()
                        if let stop = job.stop {
                            Button("Stop") { stop() }
                        }
                    }
                    if let detail = job.detail {
                        Text(detail).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    }
                    if let progress = job.progress {
                        ProgressView(value: progress)
                    }
                }
            }
            if !jobs.isEmpty, !model.activity.messages.isEmpty {
                Divider()
            }
            // The action's undo name, with the message as detail.
            ForEach(model.activity.messages.reversed()) { message in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: message.isWarning ? "exclamationmark.triangle" : "info.circle")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        if let title = message.title {
                            Text(title).fontWeight(.semibold)
                        }
                        Text(message.text)
                            .foregroundStyle(message.title == nil ? .primary : .secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                        Text(message.date, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            if jobs.isEmpty, model.activity.messages.isEmpty {
                Text("Nothing is running.")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(width: 320)
    }
}
