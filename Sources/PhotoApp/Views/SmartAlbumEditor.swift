import PhotoCore
import SwiftUI

/// Shows the right sheet for a `SidebarSheet`.
struct SidebarSheetView: View {
    let model: LibraryModel
    let sheet: SidebarSheet

    var body: some View {
        switch sheet {
        case .renameKeyword(let keyword):
            NameSheet(title: String(localized: "Rename Keyword"), initialName: keyword.name,
                      note: String(localized: "Using the name of another keyword merges the two."),
                      action: String(localized: "Rename")) { name, _, _ in
                model.renameKeyword(keyword.id, to: name)
            }
        case .renameAlbum(let album):
            NameSheet(title: String(localized: "Rename Album"), initialName: album.album.name,
                      action: String(localized: "Rename")) { name, _, _ in
                model.renameAlbum(album.id, to: name)
            }
        case .newAlbum(let projectID):
            NameSheet(title: String(localized: "New Album"), initialName: String(localized: "Untitled Album"),
                      action: String(localized: "Create"), model: model, projectID: projectID,
                      selectionCount: model.actionTargetVersionIDs.count) { name, project, addSelection in
                model.createAlbum(named: name, projectID: project,
                                  adding: addSelection ? model.actionTargetVersionIDs : [])
            }
        case .smartAlbum(let album, let projectID):
            SmartAlbumEditor(model: model, album: album, projectID: projectID)
        }
    }
}

/// A name field, optionally with where the album goes and whether to add the
/// selected photos.
struct NameSheet: View {
    let title: String
    let initialName: String
    var note: String?
    let action: String
    var model: LibraryModel?
    var projectID: Int64?
    var selectionCount = 0
    let onSave: (String, Int64?, Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var project: Int64?
    @State private var addSelection = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 320)
                .onSubmit(save)
            if let note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let model {
                ProjectPicker(model: model, project: $project)
                if selectionCount > 0 {
                    Toggle("Add the \(selectionCount) selected photos", isOn: $addSelection)
                }
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(action, action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(Catalog.normalizedKeywordName(name) == nil)
            }
        }
        .padding(20)
        .onAppear {
            name = initialName
            project = projectID
        }
    }

    private func save() {
        guard Catalog.normalizedKeywordName(name) != nil else { return }
        onSave(name, project, addSelection)
        dismiss()
    }
}

private struct ProjectPicker: View {
    let model: LibraryModel
    @Binding var project: Int64?

    var body: some View {
        Picker("In", selection: $project) {
            Text("Whole library").tag(Int64?.none)
            ForEach(model.projects) { summary in
                Text(summary.project.name).tag(Int64?.some(summary.id))
            }
        }
        .frame(width: 320)
    }
}

/// Name, scope and rules of a smart album, with a live count of what matches.
struct SmartAlbumEditor: View {
    let model: LibraryModel
    let album: SmartAlbum?
    let projectID: Int64?

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var project: Int64?
    @State private var rules = SmartAlbumRules()
    @State private var matchCount: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(album == nil ? String(localized: "New Smart Album") : String(localized: "Edit Smart Album"))
                .font(.headline)
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 320)
            ProjectPicker(model: model, project: $project)
            HStack {
                Picker("Match", selection: $rules.match) {
                    Text("all of the rules").tag(SmartAlbumRules.Match.all)
                    Text("any of the rules").tag(SmartAlbumRules.Match.any)
                }
                .fixedSize()
                Spacer()
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach($rules.rules) { $rule in
                    RuleRow(model: model, rule: $rule) {
                        rules.rules.removeAll { $0.id == rule.id }
                    }
                }
                Button {
                    rules.rules.append(SmartRule(field: .rating, comparison: .atLeast, value: RuleValue(number: 3)))
                } label: {
                    Label("Add Rule", systemImage: "plus")
                }
            }
            .padding(10)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
            HStack {
                if let matchCount {
                    Text("\(matchCount) photos match")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(album == nil ? String(localized: "Create") : String(localized: "Save"), action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(Catalog.normalizedKeywordName(name) == nil)
            }
        }
        .padding(20)
        .frame(minWidth: 620)
        .onAppear {
            name = album?.name ?? String(localized: "Untitled Smart Album")
            project = album?.projectID ?? projectID
            rules = album?.rules ?? SmartAlbumRules(match: .all, rules: [
                SmartRule(field: .rating, comparison: .atLeast, value: RuleValue(number: 3)),
            ])
        }
        .task(id: CountKey(rules: rules, project: project)) {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            matchCount = await model.countMatching(rules, projectID: project)
        }
    }

    private struct CountKey: Equatable {
        var rules: SmartAlbumRules
        var project: Int64?
    }

    private func save() {
        if var edited = album {
            edited.name = name
            edited.projectID = project
            edited.rules = rules
            model.saveSmartAlbum(edited)
        } else {
            model.createSmartAlbum(named: name, projectID: project, rules: rules)
        }
        dismiss()
    }
}

/// One rule: field, comparison and a value editor that fits the field.
private struct RuleRow: View {
    let model: LibraryModel
    @Binding var rule: SmartRule
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Picker("Field", selection: Binding(get: { rule.field }, set: changeField)) {
                ForEach(SmartRule.Field.allCases, id: \.self) { field in
                    Text(RuleText.field(field)).tag(field)
                }
            }
            .labelsHidden()
            .frame(width: 170)
            Picker("Comparison", selection: $rule.comparison) {
                ForEach(rule.field.kind.comparisons, id: \.self) { comparison in
                    Text(RuleText.comparison(comparison, for: rule.field)).tag(comparison)
                }
            }
            .labelsHidden()
            .frame(width: 150)
            ValueEditor(model: model, rule: $rule)
            Spacer(minLength: 0)
            Button(action: onRemove) {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help("Remove this rule")
        }
    }

    /// A new field starts with its first comparison and a sensible value.
    private func changeField(_ field: SmartRule.Field) {
        guard field != rule.field else { return }
        rule.field = field
        rule.comparison = field.kind.comparisons[0]
        rule.value = switch field.kind {
        case .number: RuleValue(number: field == .rating ? 3 : nil)
        case .date: RuleValue(number: 30, text: LocalDate.format(Date(), in: .current))
        case .choice:
            field == .project ? RuleValue(id: model.projects.first?.id) : RuleValue(text: SmartRule.choices(for: field).first)
        case .keyword: RuleValue(id: model.keywords.first?.id)
        case .text, .flag: RuleValue()
        }
    }
}

private struct ValueEditor: View {
    let model: LibraryModel
    @Binding var rule: SmartRule

    var body: some View {
        switch rule.field.kind {
        case .number:
            if rule.field == .rating {
                stars(\.number)
                if rule.comparison == .between { stars(\.upperNumber) }
            } else {
                number(\.number)
                if rule.comparison == .between {
                    Text("and")
                    number(\.upperNumber)
                }
                if let unit = RuleText.unit(rule.field) {
                    Text(unit).foregroundStyle(.secondary)
                }
            }
        case .text:
            if rule.comparison != .isEmpty, rule.comparison != .isNotEmpty {
                TextField("Text", text: Binding(get: { rule.value.text ?? "" }, set: { rule.value.text = $0 }))
                    .frame(width: 180)
            }
        case .date:
            switch rule.comparison {
            case .inLastDays, .notInLastDays:
                number(\.number)
                Text("days").foregroundStyle(.secondary)
            case .between:
                day(\.text)
                Text("and")
                day(\.upperText)
            default:
                day(\.text)
            }
        case .choice:
            if rule.field == .project {
                Picker("Project", selection: Binding(get: { rule.value.id }, set: { rule.value.id = $0 })) {
                    ForEach(model.projects) { summary in
                        Text(summary.project.name).tag(Int64?.some(summary.id))
                    }
                }
                .labelsHidden()
                .frame(width: 180)
            } else {
                Picker("Value", selection: Binding(get: { rule.value.text ?? "" }, set: { rule.value.text = $0 })) {
                    ForEach(SmartRule.choices(for: rule.field), id: \.self) { choice in
                        Text(RuleText.choice(choice, for: rule.field)).tag(choice)
                    }
                }
                .labelsHidden()
                .frame(width: 150)
            }
        case .keyword:
            Picker("Keyword", selection: Binding(get: { rule.value.id }, set: { rule.value.id = $0 })) {
                ForEach(model.keywords) { keyword in
                    Text(keyword.name).tag(Int64?.some(keyword.id))
                }
            }
            .labelsHidden()
            .frame(width: 180)
        case .flag:
            EmptyView()
        }
    }

    private func number(_ path: WritableKeyPath<RuleValue, Double?>) -> some View {
        TextField("Value", value: Binding(get: { rule.value[keyPath: path] }, set: { rule.value[keyPath: path] = $0 }),
                  format: .number)
            .frame(width: 80)
    }

    private func stars(_ path: WritableKeyPath<RuleValue, Double?>) -> some View {
        Picker("Stars", selection: Binding(get: { Int(rule.value[keyPath: path] ?? 0) },
                                            set: { rule.value[keyPath: path] = Double($0) })) {
            Text("No stars").tag(0)
            ForEach(1...5, id: \.self) { count in
                Text(RatingText.stars(count)).tag(count)
            }
        }
        .labelsHidden()
        .frame(width: 110)
    }

    private func day(_ path: WritableKeyPath<RuleValue, String?>) -> some View {
        DatePicker("Day", selection: Binding(
            get: { Self.date(from: rule.value[keyPath: path]) },
            set: { rule.value[keyPath: path] = LocalDate.format($0, in: .current) }
        ), displayedComponents: .date)
        .labelsHidden()
        .datePickerStyle(.field)
    }

    static func date(from day: String?) -> Date {
        let parts = (day ?? "").split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
              let date = Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
        else { return Date() }
        return date
    }
}

/// Names of rule fields, comparisons and choices.
enum RuleText {
    static func field(_ field: SmartRule.Field) -> String {
        switch field {
        case .rating: String(localized: "Rating", comment: "Smart album rule field")
        case .flag: String(localized: "Flag", comment: "Smart album rule field")
        case .colorLabel: String(localized: "Color Label", comment: "Smart album rule field")
        case .keyword: String(localized: "Keyword", comment: "Smart album rule field")
        case .hasKeywords: String(localized: "Keywords", comment: "Smart album rule field: whether a photo has any")
        case .fileType: String(localized: "File Type", comment: "Smart album rule field")
        case .fileName: String(localized: "File Name", comment: "Smart album rule field")
        case .captureDate: String(localized: "Capture Date", comment: "Smart album rule field")
        case .importDate: String(localized: "Import Date", comment: "Smart album rule field")
        case .project: String(localized: "Project", comment: "Smart album rule field")
        case .camera: String(localized: "Camera", comment: "Smart album rule field")
        case .lens: String(localized: "Lens", comment: "Smart album rule field")
        case .cameraSerial: String(localized: "Camera Serial Number", comment: "Smart album rule field")
        case .iso: String(localized: "ISO", comment: "Smart album rule field")
        case .aperture: String(localized: "Aperture", comment: "Smart album rule field")
        case .shutterSpeed: String(localized: "Shutter Speed", comment: "Smart album rule field")
        case .focalLength: String(localized: "Focal Length", comment: "Smart album rule field")
        case .exposureCompensation: String(localized: "Exposure Compensation", comment: "Smart album rule field")
        case .flash: String(localized: "Flash", comment: "Smart album rule field")
        case .whiteBalance: String(localized: "White Balance", comment: "Smart album rule field")
        case .hasLocation: String(localized: "Location", comment: "Smart album rule field")
        case .artist: String(localized: "Artist", comment: "Smart album rule field")
        case .copyright: String(localized: "Copyright", comment: "Smart album rule field")
        case .caption: String(localized: "Caption", comment: "Smart album rule field")
        }
    }

    static func comparison(_ comparison: SmartRule.Comparison, for field: SmartRule.Field) -> String {
        switch comparison {
        case .equals: String(localized: "is", comment: "Smart album rule comparison")
        case .notEquals: String(localized: "is not", comment: "Smart album rule comparison")
        case .atLeast: String(localized: "is at least", comment: "Smart album rule comparison")
        case .atMost: String(localized: "is at most", comment: "Smart album rule comparison")
        case .between: String(localized: "is between", comment: "Smart album rule comparison")
        case .contains: String(localized: "contains", comment: "Smart album rule comparison")
        case .doesNotContain: String(localized: "does not contain", comment: "Smart album rule comparison")
        case .beginsWith: String(localized: "begins with", comment: "Smart album rule comparison")
        case .endsWith: String(localized: "ends with", comment: "Smart album rule comparison")
        case .isEmpty: String(localized: "is empty", comment: "Smart album rule comparison")
        case .isNotEmpty: String(localized: "is not empty", comment: "Smart album rule comparison")
        case .on: String(localized: "is on", comment: "Smart album rule comparison (date)")
        case .before: String(localized: "is before", comment: "Smart album rule comparison (date)")
        case .after: String(localized: "is after", comment: "Smart album rule comparison (date)")
        case .inLastDays: String(localized: "is in the last", comment: "Smart album rule comparison, followed by a number of days")
        case .notInLastDays: String(localized: "is not in the last", comment: "Smart album rule comparison, followed by a number of days")
        case .has: String(localized: "is", comment: "Smart album rule comparison")
        case .doesNotHave: String(localized: "is not", comment: "Smart album rule comparison")
        case .isTrue:
            switch field {
            case .hasKeywords: String(localized: "are assigned", comment: "Smart album rule: Keywords are assigned")
            case .flash: String(localized: "fired", comment: "Smart album rule: Flash fired")
            default: String(localized: "is known", comment: "Smart album rule: Location is known")
            }
        case .isFalse:
            switch field {
            case .hasKeywords: String(localized: "are not assigned", comment: "Smart album rule: Keywords are not assigned")
            case .flash: String(localized: "did not fire", comment: "Smart album rule: Flash did not fire")
            default: String(localized: "is unknown", comment: "Smart album rule: Location is unknown")
            }
        }
    }

    static func choice(_ choice: String, for field: SmartRule.Field) -> String {
        switch field {
        case .flag:
            switch choice {
            case "picked": String(localized: "Picked")
            case "rejected": String(localized: "Rejected")
            default: String(localized: "Unflagged")
            }
        case .colorLabel:
            ColorLabelText.name(Int(choice).flatMap(ColorLabel.init(rawValue:)) ?? .none)
        case .fileType:
            FileKind(rawValue: choice).map(FileKindText.badge) ?? choice
        case .whiteBalance:
            choice == "manual" ? String(localized: "Manual", comment: "White balance") : String(localized: "Auto", comment: "White balance")
        default:
            choice
        }
    }

    static func unit(_ field: SmartRule.Field) -> String? {
        switch field {
        case .shutterSpeed: String(localized: "seconds", comment: "Unit after a shutter speed value")
        case .focalLength: String(localized: "mm", comment: "Unit after a focal length value")
        case .exposureCompensation: String(localized: "EV", comment: "Unit after an exposure compensation value")
        default: nil
        }
    }
}
