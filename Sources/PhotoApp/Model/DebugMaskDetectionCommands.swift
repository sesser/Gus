import AppKit
import PhotoCore

/// A detector for scripted checks only (ai-masks design §15): Vision, or a
/// fixed answer, so states a synthetic photo can't produce can be checked.
/// Never a setting: only `adjust mask detector` sets it.
struct DebugMaskDetector: MaskDetecting {
    enum Mode: String, CaseIterable {
        case real, empty, fail, unavailable
        /// Keeps the detection pending until it is cancelled.
        case hang
        /// A disc in the middle of the frame, one instance (or two people), for
        /// checks of the overlay and captions on any photo.
        case disc
    }

    let mode: Mode

    func detect(_ request: MaskRaster.Request, in image: CGImage) async throws(MaskDetectionError) -> MaskRaster {
        switch mode {
        case .real:
            return try await VisionMaskDetector().detect(request, in: image)
        case .empty:
            return .empty(request)
        case .fail:
            throw .failed("The debug script's detector failed on purpose.")
        case .unavailable:
            throw .unavailable("The debug script's detector says it can't run here.")
        case .hang:
            while !Task.isCancelled { try? await Task.sleep(for: .milliseconds(20)) }
            throw .failed("Cancelled.")
        case .disc:
            let (width, height) = request == .person ? (image.width >= image.height ? (512, 384) : (384, 512)) : (512, 512)
            let levels = (0..<(width * height)).map { index -> UInt8 in
                let x = Double(index % width) / Double(width) - 0.5, y = Double(index / width) / Double(height) - 0.5
                return hypot(x, y) < 0.25 ? 255 : 0
            }
            do {
                return try MaskRaster(levels: levels, width: width, height: height,
                                      instances: request == .person ? 2 : 1, request: request)
            } catch {
                throw .failed("\(error)")
            }
        }
    }
}

/// The debug script's detection commands (ai-masks design §15), under `adjust mask`:
///
///     adjust mask detect subject|people|background            (New Mask ▸ …; waits for the result to land)
///     adjust mask detectcomponent <kind> [add|subtract|intersect]   (Add to Mask; into the selected mask)
///     adjust mask detector real|empty|fail|unavailable|hang|disc   (what detections run with; real by default)
///     adjust mask update [<component>]   (Update Detection on the selected mask, or one component's button)
///     adjust mask cancel                 (the pending line's Cancel)
///     adjust mask raster delete|corrupt  (deletes or damages the rows the selected mask's detections name, then
///                                        reloads the photo: the missing state, AC13)
///     print masks                        (each mask, its components' kinds, states, instances, digests and
///                                        captions as shown, the pending detection, the overlay and its flash)
///
/// Each command that starts a detection waits for it to land, inside the
/// command's undo group, unless the detector is `hang`.
@MainActor
enum DebugMaskDetectionCommands {
    static let verbs: Set<String> = ["detect", "detectcomponent", "detector", "update", "cancel", "raster"]

    static func handles(_ arguments: [String]) -> Bool {
        arguments.first == "mask" && verbs.contains(arguments.dropFirst().first ?? "")
    }

    /// A detection is under way that a scripted command should wait for.
    static func isWaiting(_ editor: AdjustmentEditor) -> Bool {
        editor.pendingDetection != nil && (editor.maskDetector as? DebugMaskDetector)?.mode != .hang
    }

    static func run(_ arguments: [String], editor: AdjustmentEditor) async {
        let words = Array(arguments.dropFirst())
        let rest = Array(words.dropFirst())
        switch words.first {
        case "detect":
            guard let kind = MaskDetectionKind(rawValue: rest.first ?? "") else { break }
            editor.addDetectionMask(kind)
            await waitForLanding(editor)
        case "detectcomponent":
            guard let kind = MaskDetectionKind(rawValue: rest.first ?? "") else { break }
            editor.addDetectionComponent(kind)
            await waitForLanding(editor)
            // The operation, as the row's pop-up sets it, in the same group.
            if let operation = MaskOperation(rawValue: rest.dropFirst().first ?? ""), operation != .add,
               let mask = editor.selectedMask {
                editor.setComponent(mask.components.count - 1, String(localized: "Mask Operation"), phase: .committed) {
                    $0.operation = operation
                }
            }
        case "detector":
            let mode = DebugMaskDetector.Mode(rawValue: rest.first ?? "") ?? .real
            editor.maskDetector = mode == .real ? VisionMaskDetector() : DebugMaskDetector(mode: mode)
            print("debug-script: mask detector \(mode.rawValue)")
            return
        case "update":
            guard let id = editor.selectedMaskID else { break }
            editor.updateDetection(mask: id, index: rest.first.flatMap(Int.init))
            await waitForLanding(editor)
        case "cancel":
            editor.cancelDetection()
        case "raster":
            await damage(rest.first == "corrupt", editor: editor)
        default:
            break
        }
        printMasks(editor)
    }

    /// Waits until the detection lands or is cancelled (at most 30 s).
    static func waitForLanding(_ editor: AdjustmentEditor) async {
        for _ in 0..<600 where isWaiting(editor) {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    /// Deletes or damages the rows the selected mask's detections name, and
    /// shows the photo again without its cached renditions.
    private static func damage(_ corrupt: Bool, editor: AdjustmentEditor) async {
        guard let library = editor.library, let mask = editor.selectedMask else { return }
        let digests = Set(mask.components.compactMap { $0.shape.detection?.raster })
        for digest in digests {
            do {
                if corrupt {
                    try await library.catalog.damageMaskRasterForChecks(digest: digest)
                } else {
                    try await library.catalog.deleteMaskRasterForChecks(digest: digest)
                }
            } catch {
                print("debug-script: mask raster \(corrupt ? "corrupt" : "delete") failed: \(error)")
            }
            editor.forgetDetectionResult(digest)
        }
        if let item = editor.item {
            for tier in PreviewTier.allCases {
                if let key = PreviewCacheKey(contentHash: item.contentHash, editStackHash: item.editStackHash, tier: tier) {
                    library.previews.cache.remove(key)
                }
            }
        }
        let selected = editor.selectedMaskID
        editor.reload()
        for _ in 0..<200 where editor.state != .ready {
            try? await Task.sleep(for: .milliseconds(50))
        }
        editor.selectedMaskID = selected
        // The captions' rows are read off the main actor.
        try? await Task.sleep(for: .milliseconds(300))
        print("debug-script: mask raster \(corrupt ? "corrupted" : "deleted") \(digests.count)")
    }

    static func printMasks(_ editor: AdjustmentEditor) {
        let pending = editor.pendingDetection.map { pending -> String in
            switch pending.target {
            case .newMask: "new \(pending.kind.rawValue)"
            case .component(let mask): "component \(pending.kind.rawValue) into \(mask.uuidString.prefix(8))"
            case .update(let mask, let components): "update \(components) of \(mask.uuidString.prefix(8))"
            }
        } ?? "none"
        print("debug-script: masks \(editor.adjustments.local.masks.count) pending \(pending)"
              + " overlay \(editor.showsMaskOverlay) flash \(editor.isFlashingOverlay)"
              + " canDetect \(editor.canDetectMask) canDetectComponent \(editor.canDetectComponent)"
              + " canUpdate \(editor.canUpdateDetection(of: editor.selectedMask))"
              + " unavailable \(editor.unavailableRequests.map(\.rawValue).sorted())")
        for (number, mask) in editor.adjustments.local.masks.enumerated() {
            print("debug-script:   mask \(number) '\(mask.name)'\(mask.id == editor.selectedMaskID ? " selected" : "")"
                  + " exposure \(mask.adjustments.exposure) amount \(mask.amount)")
            for (index, component) in mask.components.enumerated() {
                guard let detection = component.shape.detection else {
                    print("debug-script:     \(index) \(component.shape.name) \(component.operation.rawValue)")
                    continue
                }
                let state = editor.detectionState(of: component, mask: mask.id, index: index)
                let instances: String = if case .found(let count)? = state { " instances \(count)" } else { "" }
                let shown = editor.pendingDetection?.updates(mask: mask.id, index: index) == true
                    ? MaskDetectionText.detecting : editor.caption(of: component, mask: mask.id, index: index)
                print("debug-script:     \(index) \(detection.kind.rawValue) \(component.operation.rawValue)"
                      + (component.invert ? " inverted" : "")
                      + " state \(state.map { "\($0)" } ?? "-")\(instances)"
                      + " raster \(detection.raster.map { String($0.prefix(12)) } ?? "none")"
                      + " update \(state?.offersUpdate ?? false) caption \"\(shown)\"")
            }
        }
    }
}
