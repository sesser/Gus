import AppKit
import PhotoCore

/// Debug-script commands for machine learning noise reduction (ml-denoise
/// design §11):
///
/// - `ml on` / `ml off`: the check box's command (one undo step).
/// - `ml decoder <version>`: a pick in the Decoder pop-up.
/// - `ml override available|notOnThisMac|cameraNotSupported|fail|clear`:
///   replaces this Mac's answer for every file (`fail`: available, and the
///   machine learning decode fails), then reloads the open photo, so one Mac
///   can show every state.
/// - `ml wait`: waits (up to 30 s) until no machine learning frame is pending.
/// - `print ml`: the state the inspector, pop-up, caption and badge show,
///   read from the AppKit controls where there is one.
@MainActor
enum DebugMachineLearningCommands {
    static func run(_ words: [String], model: LibraryModel) async {
        let editor = model.editor
        switch words.first {
        case "on": editor.setMachineLearning(true)
        case "off": editor.setMachineLearning(false)
        case "decoder":
            if let version = words.dropFirst().first { editor.chooseDecoder(version) }
        case "override":
            let override: MachineLearningNoiseReduction.Override? = switch words.dropFirst().first {
            case "fail": .init(availability: .available, failsDecode: true)
            case let name?: MachineLearningNoiseReduction.Availability(rawValue: name).map { .init(availability: $0) }
            case nil: nil
            }
            MachineLearningNoiseReduction.setOverride(override)
            editor.reload()
            for _ in 0..<100 where editor.state != .ready {
                try? await Task.sleep(for: .milliseconds(50))
            }
        case "wait":
            try? await Task.sleep(for: .milliseconds(100))
            for _ in 0..<300 {
                if !editor.isAwaitingMachineLearningFrame, editor.frame?.adjustments == editor.adjustments { break }
                try? await Task.sleep(for: .milliseconds(100))
            }
        default:
            print("debug-script: ml expects on, off, decoder <version>, override <value> or wait")
        }
    }

    static func printState(model: LibraryModel, window: NSWindow?) {
        let editor = model.editor
        guard let status = editor.machineLearning else {
            print("debug-script: ml none (editor \(editor.state)) badge \(badge(editor))")
            return
        }
        print("debug-script: ml state \(status.state) asks \(status.asks) groupOn \(status.groupIsOn)"
              + " availability \(status.availability?.rawValue ?? "unknown") applied \(status.isApplied)"
              + " colorAvailable \(status.colorIsAvailable)")
        let caption = MachineLearningText.caption(status.state)
        print("debug-script: ml caption '\(caption ?? "-")' triangle \(MachineLearningText.showsTriangle(status.state))")
        let root = window?.contentView?.superview
        if let root, let box = find(NSButton.self, in: root, where: { $0.title == MachineLearningText.checkBoxTitle }) {
            print("debug-script: ml checkbox \(box.state == .on ? "on" : "off") enabled \(box.isEnabled)"
                  + " tip '\(box.toolTip ?? "-")'")
        } else {
            print("debug-script: ml checkbox not shown")
        }
        if let root, let row = find(SliderRow.self, in: root, where: { $0.accessibilityLabel() == String(localized: "Color") }) {
            print("debug-script: ml color \(row.debugState)")
        } else {
            print("debug-script: ml color not shown")
        }
        let versions = editor.rawDefaults?.decoderVersions ?? []
        if let root, !versions.isEmpty, let decoder = find(NSPopUpButton.self, in: root, where: { popUp in
            popUp.itemTitles.contains { title in versions.contains { title.hasPrefix($0) } }
        }) {
            print("debug-script: ml decoder '\(decoder.titleOfSelectedItem ?? "-")' enabled \(decoder.isEnabled)"
                  + " items [\(decoder.itemTitles.joined(separator: ", "))] tip '\(decoder.toolTip ?? "-")'")
        } else {
            print("debug-script: ml decoder not shown")
        }
        let frame = editor.frame.map { "\($0.machineLearning)" + ($0.adjustments == editor.adjustments ? "" : " (other values)") }
        print("debug-script: ml badge \(badge(editor)) spinner \(editor.isAwaitingMachineLearningFrame)"
              + " frame \(frame ?? "none")")
    }

    private static func badge(_ editor: AdjustmentEditor) -> String {
        guard let reason = editor.machineLearningNotApplied else { return "none" }
        return "'\(MachineLearningText.badge)' help '\(MachineLearningText.badgeHelp(reason))'"
    }

    private static func find<V: NSView>(_ type: V.Type, in view: NSView, where test: (V) -> Bool) -> V? {
        if let match = view as? V, test(match) { return match }
        for subview in view.subviews {
            if let match = find(type, in: subview, where: test) { return match }
        }
        return nil
    }
}
