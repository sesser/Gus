import PhotoCore
import SwiftUI

/// One job the Activity item shows.
struct ActivityJob: Identifiable {
    let id: String
    let title: String
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
    @State private var showsPopover = false

    /// While a job runs, and while there are messages not yet read.
    static func isVisible(_ model: LibraryModel) -> Bool {
        !jobs(model).isEmpty || model.activity.unseenCount > 0
    }

    var body: some View {
        let jobs = Self.jobs(model)
        Button {
            showsPopover = true
            model.markActivitySeen()
        } label: {
            HStack(spacing: 6) {
                if let job = jobs.first {
                    if let progress = job.progress {
                        ProgressView(value: progress).frame(width: 100)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                    Text(job.title).lineLimit(1).monospacedDigit()
                } else if model.activity.unseenCount > 0 {
                    // Idle with unread messages: which kind, the popover says the rest.
                    Image(systemName: model.activity.unseenHasWarning ? "exclamationmark.triangle" : "info.circle")
                        .accessibilityLabel(model.activity.messages.last?.text ?? "")
                }
            }
        }
        .buttonStyle(.borderless)
        .help(jobs.isEmpty ? (model.activity.messages.last?.text ?? String(localized: "Activity")) : String(localized: "Activity"))
        .popover(isPresented: $showsPopover, arrowEdge: .bottom) {
            ActivityPopover(model: model)
        }
    }

    /// Running jobs, the most important first.
    static func jobs(_ model: LibraryModel) -> [ActivityJob] {
        _ = model.activityTick
        var jobs: [ActivityJob] = []
        if let progress = model.importProgress {
            let text = switch progress.phase {
            case .scanning: String(localized: "Looking for photos…")
            case .importing, .finished: String(localized: "Importing \(progress.filesProcessed) of \(progress.filesFound)")
            }
            let title = model.importBatch.map { batch in
                String(localized: "“\(batch.name)” (\(batch.index) of \(batch.count))") + " " + text
            } ?? text
            jobs.append(ActivityJob(id: "import", title: title,
                                    progress: progress.phase == .scanning ? nil
                                        : Double(progress.filesProcessed) / Double(max(progress.filesFound, 1)),
                                    stop: { model.cancelImport() }))
        }
        if let progress = model.export.progress {
            jobs.append(ActivityJob(id: "export", title: String(localized: "Exporting \(progress.done) of \(progress.total)"),
                                    progress: Double(progress.done) / Double(max(progress.total, 1)),
                                    stop: { model.export.cancel() }))
        }
        if let progress = model.batchAutoProgress {
            jobs.append(ActivityJob(id: "auto",
                                    title: String(localized: "Measuring exposure \(progress.done) of \(progress.total)",
                                                  comment: "Activity: batch Auto Exposure"),
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
