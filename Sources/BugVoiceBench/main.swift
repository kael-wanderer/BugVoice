import Foundation
import VoiceCore
import WhisperEngine

// bugvoice-bench --clips bench/clips [--languages auto,vi,en,es]
//   [--model large-v3-v20240930_turbo] [--llm-base http://localhost:1234]
//   [--llm-model qwen3.8-27b-mlx] [--vocab path] [--no-llm]
// bugvoice-bench --fidelity-history <history.jsonl>
//   Prints counts and flagged raw/cleaned pairs to the terminal only, then exits.
// Each clip `name.wav` may have a reference transcript `name.txt`.
// In clip mode stdout carries markdown results; progress goes to stderr.

func log(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

func argument(_ name: String) -> String? {
    let args = CommandLine.arguments
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}

// This mode runs before any clip discovery, model loading or network request.
if CommandLine.arguments.contains("--fidelity-history") {
    guard let path = argument("--fidelity-history"), !path.hasPrefix("--") else {
        log("Usage: bugvoice-bench --fidelity-history <history.jsonl>")
        exit(2)
    }
    let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    guard FileManager.default.isReadableFile(atPath: url.path) else {
        log("Cannot read history file at \(url.path)")
        exit(1)
    }
    let entries = await HistoryLog(url: url).load()
    var checked = 0
    var flagged: [(index: Int, entry: HistoryEntry, issues: [FidelityIssue])] = []
    var counts: [FidelityIssue.Kind: Int] = [:]
    for (index, entry) in entries.enumerated() {
        // Command mode rewrites on purpose and is never checked live.
        guard entry.command == nil, let cleaned = entry.cleaned else { continue }
        checked += 1
        let issues = FidelityCheck.issues(raw: entry.raw, cleaned: cleaned)
        guard !issues.isEmpty else { continue }
        flagged.append((index + 1, entry, issues))
        for kind in Set(issues.map(\.kind)) { counts[kind, default: 0] += 1 }
    }
    let percent = checked == 0 ? 0 : Double(flagged.count) * 100 / Double(checked)
    print("History entries decoded: \(entries.count)")
    print("Entries checked (dictations with cleaned text): \(checked)")
    print(String(format: "Flagged: %d (%.2f%%)", flagged.count, percent))
    for kind in FidelityIssue.Kind.allCases {
        print("\(kind.rawValue): \(counts[kind, default: 0]) flagged entries")
    }
    for item in flagged {
        print("\n--- Entry \(item.index) (\(item.entry.id.uuidString)) ---")
        print("Raw: \(item.entry.raw)")
        print("Cleaned: \(item.entry.cleaned!)")
        for issue in item.issues { print("\(issue.kind.rawValue) \(issue.direction.rawValue): \(issue.token)") }
    }
    exit(0)
}

let clipsDir = URL(fileURLWithPath: argument("--clips") ?? "bench/clips")
let languages = (argument("--languages") ?? "auto,vi,en").split(separator: ",").compactMap { SpeechLanguage(rawValue: String($0)) }
let modelName = argument("--model") ?? "large-v3-v20240930_turbo"
let llmBase = URL(string: argument("--llm-base") ?? "http://localhost:1234")!
let llmModel = argument("--llm-model") ?? "qwen3.8-27b-mlx"
let useLLM = !CommandLine.arguments.contains("--no-llm")
let vocabulary = argument("--vocab").flatMap { try? String(contentsOfFile: $0, encoding: .utf8) }.map(Vocabulary.parse) ?? Vocabulary()

guard !languages.isEmpty else {
    log("No valid --languages. Use a comma list of auto, vi, en, es.")
    exit(1)
}
// The cleanup section feeds the model the transcript from this language.
let cleanupLanguage = languages[0]

let clips = (try FileManager.default.contentsOfDirectory(at: clipsDir, includingPropertiesForKeys: nil))
    .filter { ["wav", "m4a", "aiff"].contains($0.pathExtension.lowercased()) }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }
guard !clips.isEmpty else {
    log("No clips in \(clipsDir.path). See bench/clips/README.md.")
    exit(1)
}

let modelsDir = AppPaths.standard().models
try FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)
let engine = WhisperKitTranscriber(modelName: modelName, downloadBase: modelsDir)
log("Loading \(modelName)…")
let loadStart = Date()
try await engine.prepare { p in log(String(format: "  download %.0f%%", p * 100)) }
log(String(format: "Loaded in %.1f s\n", Date().timeIntervalSince(loadStart)))

// Warm-up run so the first clip's timing excludes first-inference costs.
_ = try await engine.transcribe(try AudioFileLoader.load(clips[0]), options: TranscriptionOptions())

print("## Speech to text — \(modelName)\n")
print("| Clip | Lang | Audio s | STT s | WER | Transcript |")
print("|---|---|---|---|---|---|")
var cleanupInput: [String: String] = [:]
for clip in clips {
    log("Transcribing \(clip.lastPathComponent)")
    let audio = try AudioFileLoader.load(clip)
    let refURL = clip.deletingPathExtension().appendingPathExtension("txt")
    let reference = try? String(contentsOf: refURL, encoding: .utf8)
    for language in languages {
        let start = Date()
        let result = try await engine.transcribe(audio, options: TranscriptionOptions(language: language, prompt: vocabulary.whisperPrompt()))
        let seconds = Date().timeIntervalSince(start)
        let wer = reference.map { String(format: "%.2f", WordErrorRate.compute(reference: $0, hypothesis: result.text)) } ?? "–"
        print("| \(clip.lastPathComponent) | \(language.rawValue) | \(String(format: "%.1f", audio.duration)) | \(String(format: "%.2f", seconds)) | \(wer) | \(result.text.replacingOccurrences(of: "|", with: "/")) |")
        if language == cleanupLanguage {
            cleanupInput[clip.lastPathComponent] = result.text
        }
    }
}

if useLLM {
    print("\n## Cleanup — \(llmModel) at \(llmBase.absoluteString), style document, input language \(cleanupLanguage.rawValue)\n")
    print("| Clip | LLM s | Raw chars | Result | Output |")
    print("|---|---|---|---|---|")
    let model = OpenAICompatibleModel(baseURL: llmBase, model: llmModel)
    // Discarded warm-up so the first timed row excludes model load.
    log("Warming up \(llmModel)")
    _ = try? await model.clean(PromptBuilder().request(raw: "hello", style: .document, focus: .unknown, vocabulary: vocabulary, modelID: llmModel, disableThinking: true))
    for clip in clips {
        guard let raw = cleanupInput[clip.lastPathComponent], !raw.isEmpty else { continue }
        log("Cleaning \(clip.lastPathComponent)")
        let request = PromptBuilder().request(raw: raw, style: .document, focus: .unknown, vocabulary: vocabulary, modelID: llmModel, disableThinking: true)
        let start = Date()
        do {
            let output = try await model.clean(request)
            let seconds = Date().timeIntervalSince(start)
            let verdict: String
            let text: String
            switch OutputSanitizer.sanitize(output, raw: raw) {
            case .accepted(let cleaned): verdict = "ok"; text = cleaned
            case .rejected(let reason): verdict = "rejected: \(reason.rawValue)"; text = output
            }
            print("| \(clip.lastPathComponent) | \(String(format: "%.2f", seconds)) | \(output.count) | \(verdict) | \(text.replacingOccurrences(of: "\n", with: " ⏎ ").replacingOccurrences(of: "|", with: "/")) |")
        } catch {
            print("| \(clip.lastPathComponent) | – | – | error | \(error) |")
        }
    }
}
