import Testing
@testable import VoiceCore

struct LatencyBenchTests {
func run(_ name: String, _ audio: Double, base: Double, inc: Double, bw: Double? = 0.1, iw: Double? = 0.1) -> ClipRun {
    ClipRun(name: name, audioSeconds: audio, baselineSeconds: base,
            incrementalSeconds: inc, baselineWER: bw, incrementalWER: iw)
}
func passingCorpus() -> [ClipRun] {   // one clip per group per bucket, all passing
    IncrementalGate.groups.flatMap { g in [
        run("\(g)-1.wav", 6, base: 1.2, inc: 1.2), run("\(g)-2.wav", 16, base: 1.8, inc: 1.2), run("\(g)-3.wav", 40, base: 3.0, inc: 1.3)] }
}
@Test func medianAndFit() {
    #expect(LatencyStats.median([3, 1, 2]) == 2); #expect(LatencyStats.median([4, 1, 2, 3]) == 2.5); #expect(LatencyStats.median([]) == 0)
    let fit = LatencyStats.linearFit(x: [1, 2, 4, 8], y: [1.12, 1.14, 1.18, 1.26])
    #expect(abs(fit.fixed - 1.10) < 1e-9); #expect(abs(fit.perSecond - 0.02) < 1e-9)
}
@Test func groupFromName() { #expect(run("mix-2.wav", 1, base: 1, inc: 1).group == "mix"); #expect(run("test.wav", 1, base: 1, inc: 1).group == "other") }
@Test func passingCorpusPasses() { #expect(IncrementalGate.failures(passingCorpus()).isEmpty) }
@Test func missingBucketFails() {
    let today = ["en-1.wav", "mix-1.wav", "mix-2.wav", "vi-1.wav"].map { run($0, 15, base: 1.5, inc: 1.0) }
    #expect(IncrementalGate.failures(today).contains(.missingBucket(group: "en", bucket: "30 s+")))
}
@Test func shortSlowerFails() {
    var c = passingCorpus(); c[0].incrementalSeconds = 1.3
    let f = IncrementalGate.failures(c)
    #expect(f.count == 1)
    guard case .shortSlower("en", let s) = f.first else { Issue.record("expected shortSlower"); return }
    #expect(abs(s - 0.1) < 1e-9)
}
@Test func savingThresholds() {
    var c = passingCorpus()
    c[1].incrementalSeconds = 1.4   // en-2, 16 s: saving 0.4
    c[2].incrementalSeconds = 2.6   // en-3, 40 s: saving 0.4
    let f = IncrementalGate.failures(c)
    #expect(f.contains { if case .savingTooSmall("en", "15 s+", _) = $0 { true } else { false } })  // median 0.4 < 0.5
    #expect(f.contains { if case .savingTooSmall("en", "30 s+", _) = $0 { true } else { false } })  // 0.4 < 1.0
    #expect(!f.contains { if case .savingTooSmall("vi", _, _) = $0 { true } else { false } })
}
@Test func werChecks() {
    var c = passingCorpus(); c[4].incrementalWER = 0.16      // vi-2: +0.06, vi mean +0.02 (not above the limit)
    var f = IncrementalGate.failures(c)
    #expect(f.contains { if case .clipWER("vi-2.wav", _) = $0 { true } else { false } })
    #expect(!f.contains { if case .groupWER = $0 { true } else { false } })
    c[4].incrementalWER = 0.19                                // vi mean +0.03
    f = IncrementalGate.failures(c)
    #expect(f.contains { if case .groupWER("vi", _) = $0 { true } else { false } })
}
@Test func missingReferenceIgnoredForWER() {
    var c = passingCorpus(); c[4].baselineWER = nil; c[4].incrementalWER = nil
    #expect(IncrementalGate.failures(c).isEmpty)
}

}
