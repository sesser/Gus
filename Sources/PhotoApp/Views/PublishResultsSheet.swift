import PhotoCore
import PhotoUI
import SwiftUI

/// Publish Results (issue #28, design §10.2): every reason, and Retry Failed.
/// Runs are kept until the app quits; the Run pop-up reaches earlier ones.
struct PublishResultsSheet: View {
    let model: LibraryModel

    private var publish: PublishModel { model.publish }

    var body: some View {
        VStack(spacing: 0) {
            if let run = publish.resultsRun {
                header(run)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                Divider()
                Form {
                    counts(run)
                    lists(run)
                }
                .formStyle(.grouped)
                Divider()
                buttons(run)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
            }
        }
        .onExitCommand { model.showsPublishResults = false }
        .frame(width: 520)
        .frame(minHeight: 360, idealHeight: 520)
        .presentationSizing(.fitted)
    }

    private func header(_ run: PublishRun) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(PublishText.jobTitle(run.service.name))
                .font(.system(size: 13, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            Text(subtitle(run))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            if publish.runs.count > 1 {
                Picker("Run", selection: Binding(get: { run.id }, set: { publish.resultsRunID = $0 })) {
                    ForEach(publish.runs.reversed()) { candidate in
                        Text("\((candidate.endedAt ?? candidate.startedAt).formatted(date: .omitted, time: .shortened)), \(candidate.service.name)")
                            .tag(candidate.id)
                    }
                }
                .fixedSize()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func subtitle(_ run: PublishRun) -> String {
        let time = (run.endedAt ?? run.startedAt).formatted(date: .omitted, time: .shortened)
        guard let first = PublishText.activityLines(run).first, run.ending?.stop != nil else { return time }
        return "\(time) · \(first)"
    }

    @ViewBuilder private func counts(_ run: PublishRun) -> some View {
        let counts = run.counts
        Section {
            row(String(localized: "Published", comment: "Publish results count"), counts.published)
            row(String(localized: "Already on the server", comment: "Publish results count"), counts.alreadyOnServer)
            ForEach(AlreadyThereReason.allCases, id: \.self) { reason in
                if let count = counts.alreadyThere[reason], count > 0 {
                    row(PublishText.alreadyThereCount(reason), count).padding(.leading, 16)
                }
            }
            row(String(localized: "Skipped", comment: "Publish results count"), counts.skipped)
            row(String(localized: "Stacked", comment: "Publish results count"), counts.stacked)
            row(String(localized: "Not stacked", comment: "Publish results count"), counts.notStacked)
            row(String(localized: "Videos left out", comment: "Publish results count"), counts.videos)
            row(String(localized: "Failed", comment: "Publish results count"), counts.failed)
            row(String(localized: "Not finished", comment: "Publish results count"), counts.notFinished)
            row(String(localized: "Not published", comment: "Publish results count"), counts.notPublished)
        }
    }

    @ViewBuilder private func row(_ title: String, _ value: Int) -> some View {
        if value > 0 {
            LabeledContent(title) { Text(value.formatted()).monospacedDigit() }
        }
    }

    @ViewBuilder private func lists(_ run: PublishRun) -> some View {
        let album = run.album.name ?? run.choices.album.name ?? ""
        let failed = run.items.filter(\.hasFailed)
        if !failed.isEmpty {
            Section(String(localized: "Failed", comment: "Publish results section")) {
                ForEach(failed) { item in
                    ForEach(Array(item.failures.enumerated()), id: \.offset) { _, failure in
                        line(item.name, PublishText.failure(failure, already: item.isDuplicate))
                    }
                }
            }
        }
        let unfinished = run.items.filter(\.isUnfinished)
        if !unfinished.isEmpty {
            Section(String(localized: "Not Finished", comment: "Publish results section")) {
                ForEach(unfinished) { item in
                    if let left = item.left { line(item.name, PublishText.notFinished(left, album: album)) }
                }
            }
        }
        let unstacked = run.items.filter { if case .noOriginal = $0.stacking { true } else { false } }
        if !unstacked.isEmpty {
            Section(String(localized: "Not Stacked", comment: "Publish results section")) {
                ForEach(unstacked) { item in
                    if case .noOriginal(let reason)? = item.stacking { line(item.name, PublishText.reason(reason)) }
                }
            }
        }
        let alone = run.items.filter { $0.alreadyThere != nil }
        if !alone.isEmpty {
            Section(String(localized: "Already There, Nothing Else Done", comment: "Publish results section")) {
                ForEach(alone) { item in
                    if let reason = item.alreadyThere { line(item.name, PublishText.alreadyThereReason(reason)) }
                }
            }
        }
    }

    private func line(_ name: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(name).frame(width: 120, alignment: .leading).lineLimit(1).truncationMode(.middle)
            Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 11))
        .textSelection(.enabled)
        .accessibilityElement(children: .combine)
    }

    private func buttons(_ run: PublishRun) -> some View {
        HStack(spacing: 12) {
            if run.offersRetry {
                let refusal = publish.retryRefusal(run)
                Button(PublishText.retryFailed) { publish.retry(run.id) }
                    .disabled(refusal != nil)
                if let refusal {
                    Caption(text: PublishText.retryRefusal(refusal))
                } else if run.retryLeavesOutUnreached {
                    Caption(text: PublishText.retryLeavesOut)
                }
            }
            Spacer()
            // Done is the default, for Return and Esc alike (design §10.2).
            Button("Done") { model.showsPublishResults = false }
                .keyboardShortcut(.defaultAction)
        }
    }
}
