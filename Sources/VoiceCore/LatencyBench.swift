import Foundation

public enum LatencyStats {
    public static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    /// Least-squares intercept and slope. With no x variation, returns the mean y and zero slope.
    public static func linearFit(x: [Double], y: [Double]) -> (fixed: Double, perSecond: Double) {
        precondition(x.count == y.count)
        guard !x.isEmpty else { return (0, 0) }
        let meanX = x.reduce(0, +) / Double(x.count)
        let meanY = y.reduce(0, +) / Double(y.count)
        var covariance = 0.0
        var variance = 0.0
        for (x, y) in zip(x, y) {
            covariance += (x - meanX) * (y - meanY)
            variance += (x - meanX) * (x - meanX)
        }
        guard variance > 0 else { return (meanY, 0) }
        let slope = covariance / variance
        return (meanY - slope * meanX, slope)
    }
}

public struct ClipRun: Sendable, Equatable {
    public var name: String
    public var audioSeconds: Double
    public var baselineSeconds: Double
    public var incrementalSeconds: Double
    public var baselineWER: Double?
    public var incrementalWER: Double?

    public init(name: String, audioSeconds: Double, baselineSeconds: Double,
                incrementalSeconds: Double, baselineWER: Double?, incrementalWER: Double?) {
        self.name = name
        self.audioSeconds = audioSeconds
        self.baselineSeconds = baselineSeconds
        self.incrementalSeconds = incrementalSeconds
        self.baselineWER = baselineWER
        self.incrementalWER = incrementalWER
    }

    public var group: String {
        guard let separator = name.firstIndex(of: "-") else { return "other" }
        let prefix = String(name[..<separator])
        return IncrementalGate.groups.contains(prefix) ? prefix : "other"
    }
}

public enum IncrementalGate {
    public enum Failure: Sendable, Equatable {
        case missingBucket(group: String, bucket: String)
        case shortSlower(group: String, seconds: Double)
        case savingTooSmall(group: String, bucket: String, seconds: Double)
        case groupWER(group: String, delta: Double)
        case clipWER(name: String, delta: Double)
    }

    public static let groups = ["en", "vi", "mix"]

    public static func failures(_ runs: [ClipRun]) -> [Failure] {
        var failures: [Failure] = []
        for group in groups {
            let clips = runs.filter { $0.group == group }
            let short = clips.filter { $0.audioSeconds < 8 }
            // These buckets deliberately overlap: 30 s+ is also part of 15 s+.
            let long = clips.filter { $0.audioSeconds >= 15 }
            let longest = clips.filter { $0.audioSeconds >= 30 }
            for (bucket, clips) in [("under 8 s", short), ("15 s+", long), ("30 s+", longest)] {
                if clips.isEmpty { failures.append(.missingBucket(group: group, bucket: bucket)) }
            }
            if !short.isEmpty {
                let slower = LatencyStats.median(short.map { $0.incrementalSeconds - $0.baselineSeconds })
                if slower > 0.05 + 1e-9 { failures.append(.shortSlower(group: group, seconds: slower)) }
            }
            for (bucket, clips, threshold) in [("15 s+", long, 0.5), ("30 s+", longest, 1.0)] {
                guard !clips.isEmpty else { continue }
                let saving = LatencyStats.median(clips.map { $0.baselineSeconds - $0.incrementalSeconds })
                if saving < threshold - 1e-9 {
                    failures.append(.savingTooSmall(group: group, bucket: bucket, seconds: saving))
                }
            }
            let deltas = clips.compactMap { clip -> (name: String, delta: Double)? in
                guard let baseline = clip.baselineWER, let incremental = clip.incrementalWER else { return nil }
                return (clip.name, incremental - baseline)
            }
            if !deltas.isEmpty {
                let mean = deltas.reduce(0) { $0 + $1.delta } / Double(deltas.count)
                if mean > 0.02 + 1e-9 { failures.append(.groupWER(group: group, delta: mean)) }
            }
            for clip in deltas.sorted(by: { $0.name < $1.name }) where clip.delta > 0.05 + 1e-9 {
                failures.append(.clipWER(name: clip.name, delta: clip.delta))
            }
        }
        return failures
    }
}
