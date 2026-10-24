import Foundation
import VoiceCore
import WhisperEngine

private struct LatencyClip: Sendable {
    var name: String
    var group: String
    var audio: AudioClip
    var reference: String?

    func options(vad: Bool = true, automatic: Bool = false) -> TranscriptionOptions {
        TranscriptionOptions(
            language: automatic ? .auto : (group == "en" ? .en : .vi),
            prompt: group == "mix" ? Vocabulary().whisperPrompt(example: Vocabulary.mixedExample) : "",
            vadChunking: vad
        )
    }
}

private struct LatencyMeasurement {
    var text: String
    var seconds: Double
}

private struct LatencyCombination {
    var pause: Double
    var shortest: Double
    var longest: Double
    var previous: Bool

    var parameters: SpeechChunker.Parameters {
        .init(pause: pause, shortestPart: shortest, longestPart: longest)
    }
}

private struct LatencyResult {
    var run: ClipRun
    var parts: Int
    var baseline: String
    var incremental: String
}

private struct LatencyCacheKey: Hashable {
    var clip: String
    var start: Int
    var end: Int
    var prompt: String
}

private enum LatencyBenchError: Error { case missingCache, noClips }

private func seconds(_ duration: Duration) -> Double {
    let c = duration.components
    return Double(c.seconds) + Double(c.attoseconds) / 1e18
}

private func number(_ value: Double) -> String { String(format: "%.6f", value) }
private func optionalNumber(_ value: Double?) -> String { value.map(number) ?? "–" }

/// Resolves only local files. Does not call WhisperKit's model-discovery/download APIs.
private func cachedEngine(name: String) throws -> WhisperKitTranscriber {
    let fm = FileManager.default
    let cache = AppPaths.standard().models.appendingPathComponent("models/argmaxinc/whisperkit-coreml")
    let canonical = name.hasPrefix("openai_whisper-") ? name : "openai_whisper-" + name
    let model = cache.appendingPathComponent(canonical)
    for component in ["AudioEncoder.mlmodelc", "TextDecoder.mlmodelc", "MelSpectrogram.mlmodelc"] {
        guard fm.fileExists(atPath: model.appendingPathComponent(component).path) else {
            log("Missing cached model component for \(name). No download attempted.")
            throw LatencyBenchError.missingCache
        }
    }
    // Turbo uses the large-v3 tokenizer; quantization suffixes do not change tokenizers.
    let variant = canonical.replacingOccurrences(of: "openai_whisper-", with: "")
    let tokenizerName = variant.hasPrefix("large-v3") ? "whisper-large-v3" : "whisper-" + String(variant.split(separator: "_")[0])
    let relative = "models/openai/" + tokenizerName
    let documents = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let candidates = [model, AppPaths.standard().models.appendingPathComponent(relative),
                      documents.appendingPathComponent("huggingface").appendingPathComponent(relative)]
    guard let tokenizer = candidates.first(where: { folder in
        ["tokenizer.json", "tokenizer_config.json"].allSatisfy {
            fm.fileExists(atPath: folder.appendingPathComponent($0).path)
        }
    }) else {
        log("Missing cached tokenizer for \(name). No download attempted.")
        throw LatencyBenchError.missingCache
    }
    return WhisperKitTranscriber(modelName: name, cachedModelFolder: model, cachedTokenizerFolder: tokenizer)
}

private final class LatencyRunner {
    let engine: WhisperKitTranscriber
    var cache: [LatencyCacheKey: LatencyMeasurement] = [:]
    let clock = ContinuousClock()

    init(engine: WhisperKitTranscriber) { self.engine = engine }

    func timed(_ audio: AudioClip, options: TranscriptionOptions) async throws -> LatencyMeasurement {
        let start = clock.now
        let transcript = try await engine.transcribe(audio, options: options)
        let elapsed = seconds(start.duration(to: clock.now))
        return LatencyMeasurement(text: IncrementalSimulation.clean(transcript.text), seconds: elapsed)
    }

    func median(_ audio: AudioClip, options: TranscriptionOptions) async throws -> LatencyMeasurement {
        var measurements: [LatencyMeasurement] = []
        for _ in 0..<3 { measurements.append(try await timed(audio, options: options)) }
        // Keep the text corresponding to the median timing, rather than pairing unrelated runs.
        return measurements.sorted { $0.seconds < $1.seconds }[1]
    }

    func incremental(_ clip: LatencyClip, combination: LatencyCombination,
                     automatic: Bool = false, useCache: Bool) async throws -> IncrementalSimulation.Outcome {
        let cuts = SpeechChunker.cuts(in: clip.audio.samples, parameters: combination.parameters)
        // Simulation skips silent parts; enumerate the same audible ranges for exact cache keys.
        var start = 0
        var ranges: [(Int, Int)] = []
        for end in cuts.map(\.sample) + [clip.audio.samples.count] {
            if AudioClip(samples: Array(clip.audio.samples[start..<end])).rms >= 0.003 {
                ranges.append((start, end))
            }
            start = end
        }
        var index = 0
        return try await IncrementalSimulation.run(
            samples: clip.audio.samples, cuts: cuts, previousTextInPrompt: combination.previous
        ) { audio, previous in
            let range = ranges[index]
            index += 1
            var options = clip.options(automatic: automatic)
            options.prompt = [options.prompt, previous].filter { !$0.isEmpty }.joined(separator: " ")
            let key = LatencyCacheKey(clip: clip.name, start: range.0, end: range.1, prompt: options.prompt)
            if useCache, let hit = self.cache[key] { return (hit.text, hit.seconds) }
            let measurement = try await self.timed(audio, options: options)
            if useCache { self.cache[key] = measurement }
            return (measurement.text, measurement.seconds)
        }
    }

    func result(_ clip: LatencyClip, combination: LatencyCombination, baseline: LatencyMeasurement,
                automatic: Bool = false, useCache: Bool) async throws -> LatencyResult {
        let outcome = try await incremental(clip, combination: combination, automatic: automatic, useCache: useCache)
        return LatencyResult(
            run: ClipRun(name: clip.name, audioSeconds: clip.audio.duration,
                         baselineSeconds: baseline.seconds, incrementalSeconds: outcome.releaseToTranscript,
                         baselineWER: clip.reference.map { WordErrorRate.compute(reference: $0, hypothesis: baseline.text) },
                         incrementalWER: clip.reference.map { WordErrorRate.compute(reference: $0, hypothesis: outcome.text) }),
            parts: outcome.parts, baseline: baseline.text, incremental: outcome.text
        )
    }
}

/// Awaits preview startup and drains cancellation on both success and failure.
/// Each clip gets its own loop, so no preview inference leaks into the next clip.
private func withPreview<T>(engine: WhisperKitTranscriber, clip: LatencyClip,
                            operation: () async throws -> T) async throws -> T {
    let audio = AudioClip(samples: Array(clip.audio.samples.suffix(15 * 16_000)))
    let (ready, continuation) = AsyncStream<Void>.makeStream()
    let task = Task {
        continuation.yield(())
        continuation.finish()
        while !Task.isCancelled {
            _ = try await engine.transcribe(audio, options: clip.options())
            try await Task.sleep(for: .milliseconds(600))
        }
    }
    for await _ in ready { break }
    do {
        let result = try await operation()
        task.cancel()
        do { try await task.value } catch is CancellationError {} // Surface genuine preview failures.
        return result
    } catch {
        task.cancel()
        _ = await task.result
        throw error
    }
}

private func saving(_ results: [LatencyResult]) -> Double {
    LatencyStats.median(results.filter { $0.run.audioSeconds >= 15 }.map {
        $0.run.baselineSeconds - $0.run.incrementalSeconds
    })
}

private func mean(_ values: [Double]) -> Double? {
    values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
}

private func failureLine(_ failure: IncrementalGate.Failure) -> String {
    switch failure {
    case let .missingBucket(group, bucket): return "\(group): missingBucket — no clips \(bucket)"
    case let .shortSlower(group, value): return "\(group): short clips slower by \(number(value)) s"
    case let .savingTooSmall(group, bucket, value): return "\(group): saving too small, \(bucket): \(number(value)) s"
    case let .groupWER(group, value): return "\(group): mean WER increase \(number(value))"
    case let .clipWER(name, value): return "\(name): WER increase \(number(value))"
    }
}

private func resultTables(_ results: [LatencyResult], applyGate: Bool) -> [String] {
    var lines = ["| Clip | Audio s | Parts | Baseline s | Incremental s | Saving s | Baseline WER | Incremental WER |",
                 "|---|---:|---:|---:|---:|---:|---:|---:|"]
    for result in results {
        let r = result.run
        lines.append("| \(r.name) | \(number(r.audioSeconds)) | \(result.parts) | \(number(r.baselineSeconds)) | \(number(r.incrementalSeconds)) | \(number(r.baselineSeconds - r.incrementalSeconds)) | \(optionalNumber(r.baselineWER)) | \(optionalNumber(r.incrementalWER)) |")
    }
    lines += ["", "| Group | Bucket | Clips | Baseline s | Incremental s | Saving s | Baseline WER | Incremental WER |",
              "|---|---|---:|---:|---:|---:|---:|---:|"]
    for group in IncrementalGate.groups {
        let grouped = results.map(\.run).filter { $0.group == group }
        for (label, bucket) in [("under 8 s", grouped.filter { $0.audioSeconds < 8 }),
                                ("15 s+", grouped.filter { $0.audioSeconds >= 15 }),
                                ("30 s+", grouped.filter { $0.audioSeconds >= 30 })] {
            guard !bucket.isEmpty else {
                lines.append("| \(group) | \(label) | 0 | – | – | – | – | – |")
                continue
            }
            lines.append("| \(group) | \(label) | \(bucket.count) | \(number(LatencyStats.median(bucket.map(\.baselineSeconds)))) | \(number(LatencyStats.median(bucket.map(\.incrementalSeconds)))) | \(number(LatencyStats.median(bucket.map { $0.baselineSeconds - $0.incrementalSeconds }))) | \(optionalNumber(mean(bucket.compactMap(\.baselineWER)))) | \(optionalNumber(mean(bucket.compactMap(\.incrementalWER)))) |")
        }
    }
    let failures = IncrementalGate.failures(results.map(\.run))
    lines.append("")
    if applyGate {
        lines += failures.isEmpty ? ["Gate: pass"] : failures.map { "- " + failureLine($0) }
    } else {
        lines.append("Automatic language is informational; gate not applied. Would-fail count: \(failures.count).")
        if !failures.isEmpty {
            lines.append("Phase 2 must fall back to the full clip for automatic language if these failures persist on the complete corpus.")
        }
    }
    return lines
}

func runLatencyBench(clipsDir: URL, modelName: String, showText: Bool) async throws {
    let clock = ContinuousClock()
    let began = clock.now
    let date = ISO8601DateFormatter().string(from: Date())
    let files = try FileManager.default.contentsOfDirectory(at: clipsDir, includingPropertiesForKeys: nil)
        .filter { ["wav", "m4a", "aiff"].contains($0.pathExtension.lowercased()) }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    var clips: [LatencyClip] = []
    for file in files {
        let group = String(file.lastPathComponent.split(separator: "-").first ?? "")
        guard IncrementalGate.groups.contains(group) else { log("Skipping unsupported clip prefix: \(file.lastPathComponent)"); continue }
        let referenceURL = file.deletingPathExtension().appendingPathExtension("txt")
        let reference = FileManager.default.fileExists(atPath: referenceURL.path)
            ? try String(contentsOf: referenceURL, encoding: .utf8) : nil
        clips.append(LatencyClip(name: file.lastPathComponent, group: group,
                                 audio: try AudioFileLoader.load(file), reference: reference))
    }
    guard let first = clips.first else { throw LatencyBenchError.noClips }
    log("Latency bench: \(clips.count) local clips; loading cached main model.")
    let engine = try cachedEngine(name: modelName)
    try await engine.prepare()
    let runner = LatencyRunner(engine: engine)
    _ = try await runner.timed(first.audio, options: first.options())

    log("Section 1: fixed cost")
    var sections = ["## 1. Fixed cost", "", "| Slice s | Median STT s | Clip measurements |", "|---:|---:|---:|"]
    var sliceMeasurements: [Int: [Double]] = [:]
    var fitX: [Double] = []
    var fitY: [Double] = []
    for clip in clips {
        let lengths = Set([1, 2, 4, 8, 15, 25].map { $0 * 16_000 }.filter { $0 <= clip.audio.samples.count } + [clip.audio.samples.count]).sorted()
        for length in lengths {
            let audio = AudioClip(samples: Array(clip.audio.samples.prefix(length)))
            let measured = try await runner.median(audio, options: clip.options())
            sliceMeasurements[length, default: []].append(measured.seconds)
            fitX.append(audio.duration)
            fitY.append(measured.seconds)
        }
    }
    for length in sliceMeasurements.keys.sorted() {
        let times = sliceMeasurements[length]!
        sections.append("| \(number(Double(length) / 16_000)) | \(number(LatencyStats.median(times))) | \(times.count) |")
    }
    let fit = LatencyStats.linearFit(x: fitX, y: fitY)
    sections += ["", "fixed \(number(fit.fixed)) s + \(number(fit.perSecond)) s per audio second", ""]

    log("Section 2: VAD lever")
    sections += ["## 2. Cheap levers", "", "| Group | VAD | Clips | Median STT s | Mean WER |", "|---|---|---:|---:|---:|"]
    var baseline: [String: LatencyMeasurement] = [:]
    for vad in [true, false] {
        var groupTimes: [String: [Double]] = [:]
        var groupWER: [String: [Double]] = [:]
        for clip in clips {
            let measured = try await runner.median(clip.audio, options: clip.options(vad: vad))
            if vad { baseline[clip.name] = measured }
            groupTimes[clip.group, default: []].append(measured.seconds)
            if let reference = clip.reference {
                groupWER[clip.group, default: []].append(WordErrorRate.compute(reference: reference, hypothesis: measured.text))
            }
        }
        for group in IncrementalGate.groups {
            let times = groupTimes[group] ?? []
            sections.append("| \(group) | \(vad ? "on" : "off") | \(times.count) | \(times.isEmpty ? "–" : number(LatencyStats.median(times))) | \(optionalNumber(mean(groupWER[group] ?? []))) |")
        }
    }
    sections += ["", "Other options tried: none", ""]

    log("Section 3: incremental parameter sweep")
    sections += ["## 3. Parameter sweep", "", "| Pause s | Shortest s | Longest s | Previous text | Gate failures | Median saving 15 s+ |", "|---:|---:|---:|---|---:|---:|"]
    var bestCombination: LatencyCombination?
    var bestResults: [LatencyResult] = []
    var bestFailures = Int.max
    var bestSaving = -Double.infinity
    for pause in [0.3, 0.5, 0.8] {
        for shortest in [2.0, 4.0, 6.0] {
            for longest in [15.0, 25.0] {
                for previous in [false, true] {
                    let combination = LatencyCombination(pause: pause, shortest: shortest, longest: longest, previous: previous)
                    var results: [LatencyResult] = []
                    for clip in clips {
                        results.append(try await runner.result(clip, combination: combination, baseline: baseline[clip.name]!, useCache: true))
                    }
                    let failures = IncrementalGate.failures(results.map(\.run)).count
                    let saved = saving(results)
                    sections.append("| \(number(pause)) | \(number(shortest)) | \(number(longest)) | \(previous ? "on" : "off") | \(failures) | \(number(saved)) |")
                    if failures < bestFailures || (failures == bestFailures && saved > bestSaving) {
                        bestCombination = combination
                        bestResults = results
                        bestFailures = failures
                        bestSaving = saved
                    }
                }
            }
        }
    }
    let best = bestCombination!
    sections += ["", "## 4. Best combination", "", "Pause \(number(best.pause)) s; shortest \(number(best.shortest)) s; longest \(number(best.longest)) s; previous text \(best.previous ? "on" : "off").", ""]
    sections += resultTables(bestResults, applyGate: true)

    log("Section 5: preview contention (cached preview model)")
    let preview = try cachedEngine(name: LivePreviewModel.name)
    try await preview.prepare()
    _ = try await preview.transcribe(AudioClip(samples: Array(first.audio.samples.suffix(15 * 16_000))), options: first.options())
    var loadedResults: [LatencyResult] = []
    for clip in clips {
        let result = try await withPreview(engine: preview, clip: clip) {
            let measured = try await runner.median(clip.audio, options: clip.options())
            return try await runner.result(clip, combination: best, baseline: measured, useCache: false)
        }
        loadedResults.append(result)
    }
    sections += ["", "## 5. With preview load", ""]
    sections += resultTables(loadedResults, applyGate: true)

    log("Section 6: automatic language")
    var autoResults: [LatencyResult] = []
    for clip in clips {
        let measured = try await runner.median(clip.audio, options: clip.options(automatic: true))
        autoResults.append(try await runner.result(clip, combination: best, baseline: measured, automatic: true, useCache: false))
    }
    sections += ["", "## 6. Automatic language (informational)", ""]
    sections += resultTables(autoResults, applyGate: false)
    if showText {
        for (label, results) in [("best", bestResults), ("preview", loadedResults), ("auto", autoResults)] {
            for result in results {
                log("\(label) \(result.run.name) baseline: \(result.baseline)")
                log("\(label) \(result.run.name) incremental: \(result.incremental)")
            }
        }
    }
    let counts = IncrementalGate.groups.map { group in "\(group)=\(clips.filter { $0.group == group }.count)" }.joined(separator: ", ")
    let header = ["# Incremental transcription latency bench", "", "Model: \(modelName)", "Date: \(date)",
                  "Clips: \(counts)", "Elapsed: \(number(seconds(began.duration(to: clock.now)))) s", "",
                  "Times: median of 3 runs; incremental passes: 1 run, cached across sweep combinations only.",
                  "Buckets overlap: 30 s+ clips also count in 15 s+. WER excludes absent references.", ""]
    print((header + sections).joined(separator: "\n"))
}
