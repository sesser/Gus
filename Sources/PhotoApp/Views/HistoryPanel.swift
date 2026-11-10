import AppKit
import PhotoCore
import PhotoUI
import SwiftUI

/// The loupe's History panel (edit-history design §3): docked at the bottom
/// of the inspector column, collapsed by default, one row per saved change,
/// newest first. The list is an AppKit table in an AppKit scroll view and the
/// header is AppKit buttons: a SwiftUI `ScrollView` or `List` here would face
/// the click problem of the inspector under the toolbar (CLAUDE.md).
struct HistoryPanel: View {
    static let headerHeight = InspectorMetrics.headerHeight
    static let rowHeight: CGFloat = 24

    @Bindable var model: LibraryModel
    /// The inspector column's height: the list takes 40 % of it, within limits.
    let columnHeight: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The expanded body's height: 40 % of the column, 96 to 192 pt.
    static func bodyHeight(columnHeight: CGFloat) -> CGFloat {
        min(192, max(96, columnHeight * 0.4))
    }

    var body: some View {
        let state = model.historyPanelState
        VStack(spacing: 0) {
            if state != .absent {
                Divider()
                header(state)
                // Always in the hierarchy, so the frame animates (growing upward from the header) and
                // the list is not faded in; collapsed, it is clipped away and out of the key loop.
                content(state)
                    .frame(height: model.showsHistory ? Self.bodyHeight(columnHeight: columnHeight) : 0)
                    .clipped()
                    .allowsHitTesting(model.showsHistory)
                    .accessibilityHidden(!model.showsHistory)
            }
        }
        .animation(reduceMotion ? nil : model.showsHistory ? .easeOut(duration: 0.25) : .easeIn(duration: 0.2),
                   value: model.showsHistory)
        .task(id: Reload(version: model.mode == .loupe && !model.isReviewing ? model.focusedItem?.versionID : nil,
                         revision: model.historyRevision)) {
            guard let version = model.mode == .loupe && !model.isReviewing ? model.focusedItem?.versionID : nil else { return }
            await model.loadHistory(forVersion: version)
        }
        .onChange(of: model.focusedItem?.versionID) { model.historyWantsKeyboard = false }
        .onChange(of: state) {
            // A keyboard request only makes sense for a list that is, or is about to be, there.
            switch state {
            case .entries, .loading: break
            default: model.historyWantsKeyboard = false
            }
        }
    }

    private struct Reload: Equatable {
        var version: Int64?
        var revision: Int
    }

    // MARK: Header

    private func header(_ state: EditHistoryPanelState) -> some View {
        let help = model.showsHistory ? String(localized: "Collapse") : String(localized: "Expand")
        // While the next photo's list loads the count stays, so it does not blink between photos.
        let count: Int? = switch state {
        case .entries(let count): count
        case .loading: model.history.entries.isEmpty ? nil : model.history.entries.count
        default: nil
        }
        let countText = count.map { String(localized: "\($0) entries", comment: "History panel: how many entries the list holds") }
        return HStack(spacing: 0) {
            AppKitDisclosure(isExpanded: $model.showsHistory, help: help)
                .frame(width: InspectorMetrics.disclosureSlot)
                .accessibilityHidden(true)
            AppKitButton(title: String(localized: "History", comment: "History panel header, and the toolbar palette item"),
                         style: .borderless, font: .systemFont(ofSize: 13, weight: .semibold), help: help,
                         accessibilityValue: model.showsHistory ? String(localized: "expanded") : String(localized: "collapsed"),
                         accessibilityHint: countText, leadingAligned: true) {
                model.showsHistory.toggle()
            }
            .padding(.leading, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            if let count {
                Text("\(count)")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, InspectorMetrics.padding)
        .frame(height: Self.headerHeight)
    }

    // MARK: Body

    @ViewBuilder
    private func content(_ state: EditHistoryPanelState) -> some View {
        switch state {
        case .entries:
            HistoryTable(entries: model.history.entries, time: model.history.time,
                         isEnabled: state.allowsRevert(isCropping: model.editor.cropSession != nil),
                         isCollapsed: !model.showsHistory,
                         wantsKeyboard: model.historyWantsKeyboard,
                         tookKeyboard: { model.historyWantsKeyboard = false },
                         revert: { model.revertHistory(to: $0) },
                         leave: { NotificationCenter.default.post(name: .browserShouldTakeFocus, object: model) })
                .accessibilityLabel(Text("Edit History", comment: "VoiceOver: the History list"))
        case .empty:
            VStack(spacing: 2) {
                Text("No Edits Yet").font(.system(size: 11, weight: .semibold))
                Text("Each change you make to this photo is listed here.").font(.system(size: 11))
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, InspectorMetrics.padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .unavailable(let reason):
            Text(Self.reason(reason))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, InspectorMetrics.padding)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loading, .absent:
            Color.clear
        }
    }

    static func reason(_ reason: EditHistoryPanelState.Reason) -> String {
        switch reason {
        case .video: String(localized: "Videos have no edit history.")
        case .offline: String(localized: "History is unavailable while the original is offline.")
        case .unreadable: String(localized: "History is unavailable. This version can't read this photo's edits.")
        case .failed: String(localized: "History is unavailable. It could not be read from the library.")
        }
    }
}

// MARK: - The list

/// The entries as an `NSTableView`: one column, 24 pt rows, a check mark on
/// the current (newest) entry. Arrow keys move a cursor without changing the
/// photo; a click, Return or Space reverts; Esc hands the keyboard back.
struct HistoryTable: NSViewRepresentable {
    let entries: [EditHistoryEntry]
    let time: EditHistoryTime
    /// False during a crop session: the rows are dimmed and do nothing.
    let isEnabled: Bool
    /// The panel is collapsed: the list stays but takes no keyboard.
    let isCollapsed: Bool
    let wantsKeyboard: Bool
    let tookKeyboard: () -> Void
    let revert: (EditHistoryEntry) -> Void
    let leave: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let table = KeyTableView()
        table.headerView = nil
        let column = NSTableColumn(identifier: .init("entry"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.style = .plain
        table.rowHeight = HistoryPanel.rowHeight
        table.intercellSpacing = .zero
        table.gridStyleMask = []
        table.usesAlternatingRowBackgroundColors = false
        table.backgroundColor = .clear
        table.selectionHighlightStyle = .regular
        table.allowsEmptySelection = true
        table.allowsMultipleSelection = false
        table.focusRingType = .none
        table.dataSource = context.coordinator
        table.delegate = context.coordinator
        table.target = context.coordinator
        table.action = #selector(Coordinator.clicked)
        table.setAccessibilityLabel(String(localized: "Edit History", comment: "VoiceOver: the History list"))
        context.coordinator.table = table
        table.onActivate = { [weak coordinator = context.coordinator] in coordinator?.activateCursorRow() }
        table.onEscape = { [weak coordinator = context.coordinator] in coordinator?.leaveList() }

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.automaticallyAdjustsContentInsets = false
        // Keeps the last row off the pane's rounded corner (design §3).
        scroll.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: InspectorMetrics.padding, right: 0)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.revert = revert
        coordinator.leave = leave
        coordinator.time = time
        let enabledChanged = coordinator.isEnabled != isEnabled
        coordinator.isEnabled = isEnabled
        coordinator.update(entries: entries)
        if enabledChanged { coordinator.table?.reloadData() }
        scroll.alphaValue = isEnabled ? 1 : 0.5
        coordinator.table?.refusesFirstResponder = isCollapsed
        if wantsKeyboard, !isCollapsed, let table = coordinator.table {
            // Not inside the view update: the request is cleared once the list has the keyboard.
            Task { @MainActor [weak table] in
                tookKeyboard()
                guard let table, let window = table.window else { return }
                window.makeFirstResponder(table)
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        weak var table: KeyTableView?
        var entries: [EditHistoryEntry] = []
        var time = EditHistoryTime()
        var isEnabled = true
        var revert: (EditHistoryEntry) -> Void = { _ in }
        var leave: () -> Void = {}

        /// Shows new entries: when the new list is the old one with entries added on
        /// top (and the oldest dropped at the cap), rows slide in; otherwise it reloads.
        func update(entries new: [EditHistoryEntry]) {
            let old = entries
            guard new != old else { return }
            entries = new
            guard let table else { return }
            if let first = old.first, let added = new.firstIndex(where: { $0.id == first.id }),
               Array(new[added...]) == Array(old.prefix(new.count - added)) {
                let kept = new.count - added
                let animation: NSTableView.AnimationOptions = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                    ? [] : .slideDown
                table.beginUpdates()
                if kept < old.count { table.removeRows(at: IndexSet(kept..<old.count), withAnimation: []) }
                if added > 0 { table.insertRows(at: IndexSet(0..<added), withAnimation: animation) }
                table.endUpdates()
                // The old current row is no longer the newest: it loses its check mark.
                if added > 0, added < new.count {
                    table.reloadData(forRowIndexes: IndexSet(integer: added), columnIndexes: IndexSet(integer: 0))
                }
            } else {
                table.reloadData()
            }
            // Newest on top: the new current row is at the scroll origin.
            if added(in: new, over: old) { table.scrollRowToVisible(0) }
        }

        private func added(in new: [EditHistoryEntry], over old: [EditHistoryEntry]) -> Bool {
            new.first?.id != old.first?.id
        }

        func numberOfRows(in tableView: NSTableView) -> Int { entries.count }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            let id = NSUserInterfaceItemIdentifier("historyCell")
            let cell = tableView.makeView(withIdentifier: id, owner: nil) as? HistoryCell ?? HistoryCell(identifier: id)
            let entry = entries[row]
            cell.configure(entry: entry, isCurrent: row == 0, time: time, isEnabled: isEnabled)
            cell.onPress = { [weak self] in self?.activate(entryID: entry.id) }
            return cell
        }

        /// Type-to-select is off: letters belong to the loupe's keys, not to this list.
        func tableView(_ tableView: NSTableView, typeSelectStringFor tableColumn: NSTableColumn?, row: Int) -> String? { nil }

        @objc func clicked() {
            guard let table, table.clickedRow >= 0 else { return }
            // A click that changes nothing (the current row, dimmed rows) still gives the keyboard back.
            if !activate(row: table.clickedRow) { leaveList() }
        }

        func activateCursorRow() {
            guard let table, table.selectedRow >= 0 else { return }
            activate(row: table.selectedRow)
        }

        /// Reverts to the row's entry (a no-op for the current one, A5) and, when it
        /// did, hands the keyboard back to the loupe.
        @discardableResult
        private func activate(row: Int) -> Bool {
            guard entries.indices.contains(row) else { return false }
            return activate(entryID: entries[row].id)
        }

        /// True when it asked for a revert.
        @discardableResult
        private func activate(entryID: Int64) -> Bool {
            guard isEnabled, let row = entries.firstIndex(where: { $0.id == entryID }), row > 0 else { return false }
            revert(entries[row])
            leaveList()
            return true
        }

        func leaveList() {
            table?.deselectAll(nil)
            leave()
        }
    }

    /// Return and Space revert the row under the cursor, Esc leaves the list; the
    /// first row is the cursor's start when the list gains the keyboard.
    final class KeyTableView: NSTableView {
        var onActivate: () -> Void = {}
        var onEscape: () -> Void = {}

        override var acceptsFirstResponder: Bool { true }

        override func becomeFirstResponder() -> Bool {
            let accepted = super.becomeFirstResponder()
            if accepted, selectedRow < 0, numberOfRows > 0 { selectRowIndexes([0], byExtendingSelection: false) }
            return accepted
        }

        private var pageSize: Int { max(1, rows(in: visibleRect).length - 1) }

        /// Moves the cursor (not the photo) to `row`, kept within the list and in view.
        private func moveCursor(to row: Int) {
            guard numberOfRows > 0 else { return }
            let target = min(max(row, 0), numberOfRows - 1)
            selectRowIndexes([target], byExtendingSelection: false)
            scrollRowToVisible(target)
        }

        override func keyDown(with event: NSEvent) {
            switch event.keyCode {
            case 36, 76, 49: onActivate()    // Return, keypad Enter, Space
            case 53: onEscape()              // Escape
            case 115: moveCursor(to: 0)                       // Home
            case 119: moveCursor(to: numberOfRows - 1)        // End
            case 116: moveCursor(to: selectedRow - pageSize)  // Page Up
            case 121: moveCursor(to: selectedRow + pageSize)  // Page Down
            default: super.keyDown(with: event)
            }
        }
    }
}

/// One row: a check mark slot, the label, the time.
final class HistoryCell: NSTableCellView {
    private let marker = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let timeField = NSTextField(labelWithString: "")
    var onPress: (() -> Void)?

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        marker.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .regular))
        marker.contentTintColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        timeField.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        timeField.textColor = .secondaryLabelColor
        timeField.alignment = .right
        timeField.setContentCompressionResistancePriority(.required, for: .horizontal)
        textField = label
        for view in [marker, label, timeField] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            marker.leadingAnchor.constraint(equalTo: leadingAnchor, constant: InspectorMetrics.padding),
            marker.widthAnchor.constraint(equalToConstant: 16),
            marker.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(equalTo: marker.trailingAnchor, constant: 4),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            timeField.leadingAnchor.constraint(greaterThanOrEqualTo: label.trailingAnchor, constant: 8),
            timeField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -InspectorMetrics.padding),
            timeField.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.cell)
        // One element per row: its text fields and image are not read again.
        setAccessibilityChildren([])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Selected rows (key window) draw the time in the selection's text color.
    override var backgroundStyle: NSView.BackgroundStyle {
        didSet {
            timeField.textColor = backgroundStyle == .emphasized ? .alternateSelectedControlTextColor : .secondaryLabelColor
            marker.contentTintColor = backgroundStyle == .emphasized ? .alternateSelectedControlTextColor : .labelColor
        }
    }

    func configure(entry: EditHistoryEntry, isCurrent: Bool, time: EditHistoryTime, isEnabled: Bool) {
        label.stringValue = entry.label
        label.font = .systemFont(ofSize: 11, weight: isCurrent ? .semibold : .regular)
        timeField.stringValue = time.short(entry.createdAt)
        marker.isHidden = !isCurrent
        // The full label and the exact time (a view-based table asks no delegate for tooltips).
        let tip = entry.label + "\n" + time.exactText(entry.createdAt)
        toolTip = isEnabled ? tip : tip + "\n" + String(localized: "Finish cropping to go back to an earlier state.")
        let spoken = time.spokenText(entry.createdAt)
        setAccessibilityLabel(entry.label)
        setAccessibilityValue(isCurrent
            ? AccessibilityText.list([spoken, String(localized: "current state", comment: "VoiceOver: value suffix of the History list's current entry")])
            : spoken)
        setAccessibilityEnabled(isEnabled)
        setAccessibilityHelp(isEnabled ? nil : String(localized: "Finish cropping to go back to an earlier state."))
        // The default action (VO-Space) is the press; this names it for the actions menu.
        setAccessibilityCustomActions(isEnabled && !isCurrent ? [
            NSAccessibilityCustomAction(name: String(localized: "Revert to This State",
                                                     comment: "VoiceOver: the History row's action")) { [weak self] in
                self?.onPress?()
                return true
            },
        ] : [])
    }

    /// For the debug script: the row as shown ("✓ Exposure | 2:41 PM").
    var debugText: String {
        (marker.isHidden ? "  " : "✓ ") + label.stringValue + " | " + timeField.stringValue
            + (accessibilityHelp()?.isEmpty == false ? " (dimmed)" : "")
    }

    override func accessibilityPerformPress() -> Bool {
        guard let onPress else { return false }
        onPress()
        return true
    }
}
