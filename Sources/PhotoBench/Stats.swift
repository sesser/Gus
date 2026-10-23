import Foundation

/// Summary statistics over a set of millisecond samples.
struct Stats {
    let samples: [Double]

    init(_ samples: [Double]) {
        self.samples = samples.sorted()
    }

    var count: Int { samples.count }
    var mean: Double { samples.isEmpty ? 0 : samples.reduce(0, +) / Double(samples.count) }
    var max: Double { samples.last ?? 0 }

    func percentile(_ p: Double) -> Double {
        guard !samples.isEmpty else { return 0 }
        return samples[Swift.min(samples.count - 1, Int(Double(samples.count) * p))]
    }

    var line: String {
        String(format: "n=%d  mean %.2f ms  p50 %.2f  p95 %.2f  p99 %.2f  max %.2f",
               count, mean, percentile(0.5), percentile(0.95), percentile(0.99), max)
    }

    var dictionary: [String: any Sendable] {
        ["count": count, "mean_ms": mean, "p50_ms": percentile(0.5), "p95_ms": percentile(0.95),
         "p99_ms": percentile(0.99), "max_ms": max]
    }
}

extension Duration {
    var milliseconds: Double {
        let (seconds, attoseconds) = components
        return Double(seconds) * 1000 + Double(attoseconds) / 1e15
    }

    var seconds: Double { milliseconds / 1000 }
}

func measure<T>(_ body: () async throws -> T) async rethrows -> (T, Duration) {
    let clock = ContinuousClock()
    let start = clock.now
    let value = try await body()
    return (value, clock.now - start)
}

func formatBytes(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

func machineDescription() -> [String: any Sendable] {
    var size = 0
    sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
    var brand = [CChar](repeating: 0, count: size)
    sysctlbyname("machdep.cpu.brand_string", &brand, &size, nil, 0)
    let brandString = String(decoding: brand.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    return [
        "cpu": brandString,
        "cores": ProcessInfo.processInfo.activeProcessorCount,
        "memory_gb": Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824,
        "os": ProcessInfo.processInfo.operatingSystemVersionString,
    ]
}
