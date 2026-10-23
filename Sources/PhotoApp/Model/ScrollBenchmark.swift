import AppKit
import PhotoCore
import QuartzCore

/// `--benchmark-scroll <report.json>`: scrolls the grid at fixed speeds and cell sizes, records
/// frame intervals from a display link and how many visible cells already show
/// their thumbnail, then writes a JSON report and quits.
@MainActor
final class ScrollBenchmark: NSObject {
    struct Configuration: Codable {
        var cellSize: Double
        var pointsPerSecond: Double
    }

    struct Result: Codable {
        var configuration: Configuration
        var frames: Int
        var refreshInterval: Double
        var meanFrameMilliseconds: Double
        var p50FrameMilliseconds: Double
        var p95FrameMilliseconds: Double
        var p99FrameMilliseconds: Double
        var maxFrameMilliseconds: Double
        /// Frames that took longer than 1.5 refresh intervals.
        var hitches: Int
        /// Share of visible cells that had their image, averaged over frames.
        var meanVisibleFilled: Double
        var minVisibleFilled: Double
        var scrolledPoints: Double
    }

    struct Report: Codable {
        var itemCount: Int
        var screenScale: Double
        var maximumFramesPerSecond: Int
        var results: [Result]
    }

    private static var running: ScrollBenchmark?

    static func startIfRequested(model: LibraryModel) {
        let options = LaunchOptions.current
        guard options.benchmarkScroll, running == nil else { return }
        let benchmark = ScrollBenchmark(model: model, output: options.benchmarkReport)
        running = benchmark
        Task { await benchmark.run() }
    }

    private let model: LibraryModel
    private let output: URL?
    /// Cell size × scroll speed pairs. `SCROLL_BENCHMARK_RUNS="160x12000,120x3000"`
    /// in the environment overrides them (environment, not arguments, so AppKit
    /// does not see them).
    private let configurations: [Configuration] = {
        let defaults = [
            Configuration(cellSize: 120, pointsPerSecond: 3000),
            Configuration(cellSize: 200, pointsPerSecond: 3000),
            Configuration(cellSize: 320, pointsPerSecond: 3000),
            Configuration(cellSize: 160, pointsPerSecond: 12000),
        ]
        guard let spec = ProcessInfo.processInfo.environment["SCROLL_BENCHMARK_RUNS"] else { return defaults }
        let parsed = spec.split(separator: ",").compactMap { pair -> Configuration? in
            let parts = pair.split(separator: "x").compactMap { Double($0) }
            return parts.count == 2 ? Configuration(cellSize: parts[0], pointsPerSecond: parts[1]) : nil
        }
        return parsed.isEmpty ? defaults : parsed
    }()
    private let secondsPerRun = Double(ProcessInfo.processInfo.environment["SCROLL_BENCHMARK_SECONDS"] ?? "") ?? 6

    private var link: CADisplayLink?
    private var grid: GridController?
    private var lastTimestamp: CFTimeInterval = 0
    private var intervals: [Double] = []
    private var filled: [Double] = []
    private var direction: CGFloat = 1
    private var speed: Double = 0
    private var scrolled: Double = 0
    private var refreshInterval: Double = 1 / 60
    private var finishRun: CheckedContinuation<Void, Never>?
    private var runEnds: CFTimeInterval = 0

    init(model: LibraryModel, output: URL?) {
        self.model = model
        self.output = output
    }

    private func run() async {
        for _ in 0..<300 where model.itemCount == 0 || model.observer == nil {
            try? await Task.sleep(for: .milliseconds(200))
        }
        guard let grid = model.observer as? GridController else {
            finish(Report(itemCount: 0, screenScale: 0, maximumFramesPerSecond: 0, results: []))
            return
        }
        self.grid = grid
        NSApp.activate()
        grid.scrollView.window?.makeKeyAndOrderFront(nil)

        var results: [Result] = []
        let originalSize = model.thumbnailSize
        log("starting with \(model.itemCount) items")
        for configuration in configurations {
            log("measuring \(configuration)")
            model.thumbnailSize = configuration.cellSize
            try? await Task.sleep(for: .milliseconds(300))
            grid.scrollView.contentView.scroll(to: .zero)
            grid.scrollView.reflectScrolledClipView(grid.scrollView.contentView)
            // Let the first screen of thumbnails arrive before measuring.
            try? await Task.sleep(for: .seconds(1.5))
            results.append(await measure(configuration))
        }
        // The size is a saved preference; leave it the way it was.
        model.thumbnailSize = originalSize
        let screen = grid.scrollView.window?.screen
        finish(Report(itemCount: model.itemCount, screenScale: Double(screen?.backingScaleFactor ?? 0),
                      maximumFramesPerSecond: screen?.maximumFramesPerSecond ?? 0, results: results))
    }

    private func measure(_ configuration: Configuration) async -> Result {
        intervals = []
        filled = []
        lastTimestamp = 0
        direction = 1
        scrolled = 0
        speed = configuration.pointsPerSecond
        await withCheckedContinuation { continuation in
            finishRun = continuation
            let link = grid!.scrollView.displayLink(target: self, selector: #selector(tick(_:)))
            link.add(to: .main, forMode: .common)
            self.link = link
        }
        let sorted = intervals.sorted()
        func percentile(_ p: Double) -> Double {
            sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count) * p))] * 1000
        }
        return Result(
            configuration: configuration, frames: intervals.count, refreshInterval: refreshInterval,
            meanFrameMilliseconds: intervals.isEmpty ? 0 : intervals.reduce(0, +) / Double(intervals.count) * 1000,
            p50FrameMilliseconds: percentile(0.5), p95FrameMilliseconds: percentile(0.95),
            p99FrameMilliseconds: percentile(0.99), maxFrameMilliseconds: (sorted.last ?? 0) * 1000,
            hitches: intervals.filter { $0 > refreshInterval * 1.5 }.count,
            meanVisibleFilled: filled.isEmpty ? 0 : filled.reduce(0, +) / Double(filled.count),
            minVisibleFilled: filled.min() ?? 0, scrolledPoints: scrolled)
    }

    @objc private func tick(_ link: CADisplayLink) {
        guard let grid else { return }
        if lastTimestamp == 0 {
            lastTimestamp = link.timestamp
            refreshInterval = link.targetTimestamp - link.timestamp
            runEnds = link.timestamp + secondsPerRun
            return
        }
        let elapsed = link.timestamp - lastTimestamp
        lastTimestamp = link.timestamp
        intervals.append(elapsed)

        let clip = grid.scrollView.contentView
        let maxY = max(0, grid.collectionView.frame.height - clip.bounds.height)
        var origin = clip.bounds.origin
        origin.y += direction * CGFloat(speed * elapsed)
        if origin.y >= maxY { origin.y = maxY; direction = -1 }
        if origin.y <= 0 { origin.y = 0; direction = 1 }
        scrolled += speed * elapsed
        clip.scroll(to: origin)
        grid.scrollView.reflectScrolledClipView(clip)

        let visible = grid.collectionView.visibleItems().compactMap { $0 as? PhotoCell }
        if !visible.isEmpty {
            filled.append(Double(visible.filter(\.hasImage).count) / Double(visible.count))
        }

        if link.timestamp >= runEnds {
            link.invalidate()
            self.link = nil
            finishRun?.resume()
            finishRun = nil
        }
    }

    private func log(_ message: String) {
        FileHandle.standardError.write(Data("scroll-benchmark: \(message)\n".utf8))
    }

    private func finish(_ report: Report) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(report) {
            if let output {
                try? data.write(to: output)
            } else {
                FileHandle.standardOutput.write(data)
            }
        }
        NSApp.terminate(nil)
    }
}
