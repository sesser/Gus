import AppKit
import PhotoCore
import PhotoUI
import QuartzCore

/// Debug-script commands for side by side comparison
/// (docs/features/side-by-side-comparison design §13); `DebugScript` lists them.
@MainActor
enum DebugComparisonCommands {
    static func controller(in window: NSWindow?) -> ComparisonController? {
        func find(_ view: NSView?) -> ComparisonHostView? {
            guard let view else { return nil }
            if let host = view as? ComparisonHostView { return host }
            for subview in view.subviews {
                if let host = find(subview) { return host }
            }
            return nil
        }
        return find(window?.contentView)?.controller
    }

    /// `compare on|off|toggle` (the menu command's path, alerts included),
    /// `compare active left|right|switch`, `compare link on|off`,
    /// `compare panbench [<seconds>] [walking]`.
    static func run(_ words: [String], model: LibraryModel, window: NSWindow?) async {
        switch words.first {
        case "on":
            model.enterComparison()
        case "off":
            model.stopComparing()
        case "toggle", nil:
            model.toggleComparison()
        case "active":
            switch words.dropFirst().first {
            case "left": model.setComparisonActive(.left)
            case "right": model.setComparisonActive(.right)
            default: model.switchComparisonSide()
            }
        case "link":
            model.setComparisonLinked(words.dropFirst().first != "off")
        case "animate":
            // Off: zoom, refits, entering and leaving happen at once (a check
            // that must not wait, or a display that is asleep).
            ComparisonController.debugAnimates = words.dropFirst().first != "off"
            return
        case "panbench":
            await panBenchmark(seconds: Double(words.dropFirst().first ?? "") ?? 6, walking: words.contains("walking"),
                               model: model, window: window)
            return
        default:
            print("debug-script: unknown compare command")
        }
        try? await Task.sleep(for: .milliseconds(700))
    }

    /// `compareclick left|right [<x> <y>]`: a click on a pane, at unit
    /// coordinates of its photo from the top left (the pane's middle
    /// without them), through the pane's own mouse methods, so it takes a
    /// real click's path without the app being active (a posted click on a
    /// window that is not key only brings it forward). Waits out the
    /// double-click interval, as a click's zoom does.
    static func click(_ words: [String], model: LibraryModel, window: NSWindow?) async {
        guard let window, let controller = controller(in: window) else {
            print("debug-script: not comparing")
            return
        }
        let pane = controller.panes[words.first == "right" ? 1 : 0]
        var point = pane.view.convert(NSPoint(x: pane.view.bounds.midX, y: pane.view.bounds.midY), to: nil)
        if words.count >= 3, let x = Double(words[1]), let y = Double(words[2]) {
            let size = pane.imageView.bounds.size
            point = pane.imageView.convert(NSPoint(x: x * size.width, y: (1 - y) * size.height), to: nil)
        }
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            guard let event = NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
                pressure: type == .leftMouseDown ? 1 : 0) else { continue }
            if type == .leftMouseDown { pane.scrollView.mouseDown(with: event) } else { pane.scrollView.mouseUp(with: event) }
        }
        try? await Task.sleep(for: .seconds(NSEvent.doubleClickInterval + 0.5))
    }

    /// `print compare`: the two versions, the active side, the link, each
    /// pane's magnification and visible unit rect, the ring, and what each
    /// caption shows (its content; how it fits its width is SwiftUI's).
    static func printState(model: LibraryModel, window: NSWindow?) {
        guard let state = model.comparison else {
            print("debug-script: compare off leaving \(model.comparisonLeaving != nil) mode \(model.mode)"
                  + " selection \(model.selection.map(String.init).joined(separator: ",")) focus \(model.focusIndex.map(String.init) ?? "-")")
            return
        }
        for line in controller(in: window)?.debugState ?? ["compare has no view"] { print("debug-script: \(line)") }
        print("debug-script: compare selection \(model.selection.map(String.init).joined(separator: ","))"
              + " focus \(model.focusIndex.map(String.init) ?? "-") title '\(model.windowTitle)' subtitle '\(model.windowSubtitle)'"
              + " zoom \(model.loupeZoom) review \(model.isReviewing) adjust \(model.editor.state)")
        for side in ComparisonSide.allCases {
            guard let item = model.comparisonItem(side), let index = model.indexOfVersion(item.versionID) else { continue }
            var badges: [String] = []
            if side == .right, model.isFiltered { badges.append("Filtered") }
            if model.comparisonHDRHeadroom[side] != nil { badges.append("HDR") }
            if model.isOffline(item) { badges.append("Offline") }
            print("debug-script: compare caption \(side) '\(item.fileName)' \(state.active == side ? "active" : "inactive")"
                  + " position '\(PhotoAccessibility.position(index, of: model.items.count))'"
                  + " marks '\(PhotoAccessibility.value(for: item, offline: false))' badges [\(badges.joined(separator: ", "))]")
        }
    }

    // MARK: Pan benchmark (AC7)

    /// `compare panbench [<seconds>] [walking]`: both panes to 100%, the
    /// time until both show their full-resolution render, then a pan of the
    /// active pane on the display link for `seconds`, the other pane
    /// following through the link as it does under a drag. Reports frame
    /// intervals (a hitch is a frame longer than 1.5 refresh intervals, as
    /// in `ScrollBenchmark`), the main-thread time of each step, and memory.
    /// `walking`: the active side also moves to the next photo once a
    /// second, so full-resolution renders run while the panes pan.
    private static func panBenchmark(seconds: Double, walking: Bool, model: LibraryModel, window: NSWindow?) async {
        guard let controller = controller(in: window), let pane = controller.activePane else {
            print("debug-script: panbench not comparing")
            return
        }
        let before = footprint()
        let started = CACurrentMediaTime()
        controller.setZoom(.actualSize, on: pane)
        var waited = 0.0
        while !controller.panes.allSatisfy({ $0.rendition.isFullResolution }), waited < 120 {
            try? await Task.sleep(for: .milliseconds(50))
            waited += 0.05
        }
        let sharp = CACurrentMediaTime() - started
        let sizes = controller.panes.map { pane in
            pane.item.flatMap(\.orientedSize).map { "\(Int($0.width))x\(Int($0.height))" } ?? "-"
        }
        print(String(format: "debug-script: panbench photos %@ both sharp %@ after %.2f s, footprint %.0f MB before, %.0f MB at 100%%",
                     sizes.joined(separator: " and "), controller.panes.allSatisfy { $0.rendition.isFullResolution } ? "yes" : "no",
                     sharp, Double(before) / 1_048_576, Double(footprint()) / 1_048_576))
        let run = PanRun(pane: pane, seconds: seconds)
        guard await run.displayLinkFires() else {
            // No frames to count: the display is asleep or the window is not on screen.
            print("debug-script: panbench the display link does not fire (display asleep, or the window not on screen); nothing measured")
            return
        }
        if walking {
            var forward = true
            run.everySecond = { [weak model] in
                guard let model else { return }
                if model.walkComparison(forward ? .next : .previous, announces: false) == nil {
                    forward.toggle()
                    model.walkComparison(forward ? .next : .previous, announces: false)
                }
            }
        }
        await run.measure()
        let intervals = run.intervals.sorted()
        let steps = run.stepSeconds.sorted()
        func percentile(_ values: [Double], _ p: Double) -> Double {
            values.isEmpty ? 0 : values[min(values.count - 1, Int(Double(values.count) * p))] * 1000
        }
        let mean = intervals.isEmpty ? 0 : intervals.reduce(0, +) / Double(intervals.count) * 1000
        let meanStep = steps.isEmpty ? 0 : steps.reduce(0, +) / Double(steps.count) * 1000
        if walking {
            // What the long frames came with: a photo's full-resolution render
            // arriving (its image goes to the layer), a walk (a new photo's
            // preview), or neither.
            print("debug-script: panbench walked \(run.walks) times while panning; long frames with a full render arriving"
                  + " \(run.hitchesAtArrival), with a walk \(run.hitchesAtWalk), other \(run.hitchesElsewhere)")
        }
        print(String(format: "debug-script: panbench linked %@ frames %d refresh %.2f ms frame mean %.2f p95 %.2f p99 %.2f max %.2f ms"
                         + " hitches %d step mean %.3f p95 %.3f max %.3f ms panned %.0f pt footprint %.0f MB",
                     model.linksComparison ? "yes" : "no", intervals.count, run.refreshInterval * 1000, mean,
                     percentile(intervals, 0.95), percentile(intervals, 0.99), (intervals.last ?? 0) * 1000,
                     intervals.filter { $0 > run.refreshInterval * 1.5 }.count, meanStep, percentile(steps, 0.95),
                     (steps.last ?? 0) * 1000, run.panned, Double(footprint()) / 1_048_576))
    }

    /// One pan on the display link: 1,500 pt of the photo a second, back
    /// and forth along both axes.
    @MainActor
    private final class PanRun: NSObject {
        let pane: ComparisonPane
        let seconds: Double
        private(set) var intervals: [Double] = []
        /// The main-thread time of each step: the scroll and the other pane's follow.
        private(set) var stepSeconds: [Double] = []
        private(set) var refreshInterval = 1.0 / 60
        private(set) var panned = 0.0
        private var link: CADisplayLink?
        private var last: CFTimeInterval = 0
        private var ends: CFTimeInterval = 0
        private var direction = CGVector(dx: 1, dy: 1)
        private var finish: CheckedContinuation<Void, Never>?
        /// Run once a second during the pan (the walking variant).
        var everySecond: (() -> Void)?
        private(set) var walks = 0
        private var nextSecond: CFTimeInterval = 0
        /// Long frames, by what happened since the frame before.
        private(set) var hitchesAtArrival = 0
        private(set) var hitchesAtWalk = 0
        private(set) var hitchesElsewhere = 0
        private var walkedSinceLastFrame = false
        private var sharpPanes = 0
        private static let speed = 1500.0

        init(pane: ComparisonPane, seconds: Double) {
            self.pane = pane
            self.seconds = seconds
        }

        /// Whether frames arrive at all: a display link never fires while
        /// the display sleeps, and a pan measured then would wait for ever.
        func displayLinkFires() async -> Bool {
            guard pane.view.window != nil else { return false }
            let probe = pane.view.displayLink(target: self, selector: #selector(probed(_:)))
            probe.add(to: .main, forMode: .common)
            for _ in 0..<20 where !didProbe { try? await Task.sleep(for: .milliseconds(100)) }
            probe.invalidate()
            return didProbe
        }

        private var didProbe = false

        @objc private func probed(_ link: CADisplayLink) {
            didProbe = true
        }

        func measure() async {
            guard pane.view.window != nil else { return }
            await withCheckedContinuation { continuation in
                finish = continuation
                let link = pane.view.displayLink(target: self, selector: #selector(tick(_:)))
                link.add(to: .main, forMode: .common)
                self.link = link
            }
        }

        @objc private func tick(_ link: CADisplayLink) {
            if last == 0 {
                last = link.timestamp
                refreshInterval = link.targetTimestamp - link.timestamp
                ends = link.timestamp + seconds
                nextSecond = link.timestamp + 1
                return
            }
            if let everySecond, link.timestamp >= nextSecond {
                nextSecond += 1
                walks += 1
                walkedSinceLastFrame = true
                everySecond()
            }
            let elapsed = link.timestamp - last
            last = link.timestamp
            intervals.append(elapsed)
            let sharp = pane.controller?.panes.filter { $0.rendition.isFullResolution }.count ?? 0
            if elapsed > refreshInterval * 1.5 {
                if sharp > sharpPanes { hitchesAtArrival += 1 } else if walkedSinceLastFrame { hitchesAtWalk += 1 } else { hitchesElsewhere += 1 }
            }
            sharpPanes = sharp
            walkedSinceLastFrame = false
            let began = CACurrentMediaTime()
            let clip = pane.scrollView.contentView
            let document = pane.imageView.frame.size
            var origin = clip.bounds.origin
            let distance = Self.speed * elapsed / Double(max(pane.magnification, 0.01))
            origin.x += direction.dx * distance
            origin.y += direction.dy * distance * 0.6
            let maxX = max(0, document.width - clip.bounds.width)
            let maxY = max(0, document.height - clip.bounds.height)
            if origin.x >= maxX { origin.x = maxX; direction.dx = -1 }
            if origin.x <= 0 { origin.x = 0; direction.dx = 1 }
            if origin.y >= maxY { origin.y = maxY; direction.dy = -1 }
            if origin.y <= 0 { origin.y = 0; direction.dy = 1 }
            panned += Self.speed * elapsed
            clip.scroll(to: origin)
            pane.scrollView.reflectScrolledClipView(clip)
            stepSeconds.append(CACurrentMediaTime() - began)
            if link.timestamp >= ends {
                link.invalidate()
                self.link = nil
                finish?.resume()
                finish = nil
            }
        }
    }

    /// The process's physical footprint, as Activity Monitor's Memory column.
    private static func footprint() -> Int64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Int64(info.phys_footprint) : 0
    }
}
