import AppKit
import PhotoCore

/// Debug-script commands for machine learning noise reduction (ml-denoise
/// design §11):
///
/// - `ml on` / `ml off`: the check box's command (one undo step).
/// - `ml decoder <version>`: a pick in the Decoder pop-up.
/// - `ml override available|notOnThisMac|cameraNotSupported|fail|nomodel|nomodel-decode|macos26|clear`:
///   replaces this Mac's answer for every file, then reloads the open photo,
///   so one Mac can show every state. `fail`: available, and the machine
///   learning decode fails. `nomodel`: macOS lacks the decoder's model, known
///   before decoding; `nomodel-decode`: found out by the first decode, then
///   remembered. `macos26`: "not on this Mac" with the older texts. `clear`
///   also forgets a missing model learned from a decode.
/// - `ml ready`: waits (up to 5 s) until the editor has the focused photo ready, and no longer.
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
            // macOS 27 without the decoder's model, known before decoding or only from a decode.
            case "nomodel": .init(modelMissing: .known)
            case "nomodel-decode": .init(availability: .available, modelMissing: .learnedOnDecode)
            // "Not on this Mac" with the texts of macOS 15 or 26.
            case "macos26": .init(olderMacOS: true)
            case let name?: MachineLearningNoiseReduction.Availability(rawValue: name).map { .init(availability: $0) }
            case nil: nil
            }
            if override == nil { MachineLearningNoiseReduction.forgetMissingModel() }
            MachineLearningNoiseReduction.setOverride(override)
            editor.reload()
            for _ in 0..<100 where editor.state != .ready {
                try? await Task.sleep(for: .milliseconds(50))
            }
        case "ready":
            // The loupe hands the editor a new focus on its next update.
            for _ in 0..<500 where editor.state != .ready || editor.item?.versionID != model.focusedItem?.versionID {
                try? await Task.sleep(for: .milliseconds(10))
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
        printDecoder(editor, window: window)
        guard let status = editor.machineLearning else {
            print("debug-script: ml none (editor \(editor.state)) badge \(badge(editor))")
            return
        }
        print("debug-script: ml state \(status.state) asks \(status.asks) groupOn \(status.groupIsOn)"
              + " availability \(status.availability?.rawValue ?? "unknown") applied \(status.isApplied)"
              + " colorAvailable \(status.colorIsAvailable)")
        let caption = MachineLearningText.caption(status.state, fallbackDecoder: editor.usesFallbackDecoder)
        print("debug-script: ml caption '\(caption ?? "-")' triangle \(MachineLearningText.showsTriangle(status.state))")
        let root = window?.contentView?.superview
        if let root, let box = find(NSButton.self, in: root, where: { $0.title == MachineLearningText.checkBoxTitle }) {
            print("debug-script: ml checkbox \(box.state == .on ? "on" : "off") enabled \(box.isEnabled)"
                  + " tip '\(box.toolTip ?? "-")'")
        } else {
            print("debug-script: ml checkbox not shown")
        }
        // Noise Reduction's Color comes before Grain's; files that are not RAW have only Grain's.
        if editor.isRaw, let root,
           let row = find(SliderRow.self, in: root, where: { $0.accessibilityLabel() == String(localized: "Color") }) {
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
        if let item = editor.item, let key = model.previewRequest(for: item, tier: .preview)?.key {
            let cache = model.previews.cache
            print("debug-script: ml preview cached \(cache.contains(key)) onDisk "
                  + "\(FileManager.default.fileExists(atPath: cache.url(for: key).path))"
                  + " sessionReason \(cache.sessionOnlyReason(for: key).map(\.rawValue) ?? "none") hash \(key.editStackHash.prefix(12))")
        }
        let frame = editor.frame.map { "\($0.machineLearning)" + ($0.adjustments == editor.adjustments ? "" : " (other values)") }
        print("debug-script: ml badge \(badge(editor)) spinner \(editor.isAwaitingMachineLearningFrame)"
              + " frame \(frame ?? "none") undo '\(model.undoManager.undoActionName)'")
    }

    /// Which decoder gives the photo's image, and what the Adjust tab offers
    /// for it (`SystemRAWDecoder`): the white balance modes and the
    /// Temperature row (Kelvin for a raw the system decodes, relative otherwise).
    private static func printDecoder(_ editor: AdjustmentEditor, window: NSWindow?) {
        let decoder = editor.isRaw ? "system" : editor.usesFallbackDecoder ? "fallback" : "not raw"
        let root = window?.contentView?.superview
        let asShot = String(localized: "As Shot", comment: "White balance preset")
        let modes = root.flatMap { find(NSPopUpButton.self, in: $0, where: { $0.itemTitles.contains(asShot) }) }
        let temperature = root.flatMap {
            find(SliderRow.self, in: $0, where: { $0.accessibilityLabel() == String(localized: "Temperature") })
        }
        print("debug-script: decoder \(decoder) wb mode '\(modes?.titleOfSelectedItem ?? "-")'"
              + " modes [\(modes?.itemTitles.joined(separator: ", ") ?? "not shown")]"
              + " temperature \(temperature?.debugState ?? "not shown")"
              + " note \(editor.usesFallbackDecoder ? "'\(FallbackDecoderText.note)'" : "none")")
    }

    private static func badge(_ editor: AdjustmentEditor) -> String {
        guard let reason = editor.machineLearningNotApplied else { return "none" }
        return "'\(MachineLearningText.badge)' help '\(MachineLearningText.badgeHelp(reason, fallbackDecoder: editor.usesFallbackDecoder))'"
    }

    private static func find<V: NSView>(_ type: V.Type, in view: NSView, where test: (V) -> Bool) -> V? {
        if let match = view as? V, test(match) { return match }
        for subview in view.subviews {
            if let match = find(type, in: subview, where: test) { return match }
        }
        return nil
    }
}
