import Foundation
import VoiceCore

// bugvoice-bench --cleanup-bench --history <history.jsonl> --llm-base <url> --llm-model <id>
//   [--llm-key-env VAR] [--runs N] [--show-text]
// Sends each history dictation (raw text) and the fixed sentences below through the
// dictation cleanup path: PromptBuilder request, OpenAICompatibleModel (.local,
// thinking off), OutputSanitizer, FidelityCheck. stdout carries counts and timings
// only; text goes to stderr and only with --show-text. The history file is read only.

private struct BenchInput {
    var raw: String
    var style: Style
    var language: SpeechLanguage
    var keepEnglishWords: Bool
}

/// Short dictations in the shape the pipeline sees: lowercase, fillers, no punctuation.
/// Most are 10 to 20 words so the gate bucket has enough samples.
private let fixedSentences: [(String, SpeechLanguage)] = [
    ("um so can you check the build log and tell me why the tests failed this morning", .en),
    ("please move the meeting with the design team to thursday at three in the afternoon", .en),
    ("i think we should uh rename this function to load settings and add a test for it", .en),
    ("send the invoice to anna by friday and copy the finance team on the email", .en),
    ("ok so the new version is faster but it still crashes when the window closes", .en),
    ("ừm hôm nay mình cần sửa lỗi đăng nhập trước rồi mới làm phần giao diện mới", .vi),
    ("anh nhớ gửi báo cáo tuần này cho chị lan trước năm giờ chiều thứ sáu nhé", .vi),
    ("cuộc họp sáng mai dời sang mười giờ vì nhóm thiết kế chưa chuẩn bị xong", .vi),
    ("em check giúp anh cái pull request này rồi merge vào main nếu test pass hết nhé", .vi),
    ("mình cần update cái API key trong file config rồi restart lại server là được", .vi),
    ("ờ cái dashboard bị chậm quá em xem lại query database giúp anh với", .vi),
    ("ok vậy deploy lên staging trước rồi mình review lại với team vào chiều nay", .vi),
]

func runCleanupBench() async -> Int32 {
    func fail(_ message: String) -> Int32 { log(message); return 2 }
    guard let historyPath = argument("--history"), !historyPath.hasPrefix("--"),
          let baseText = argument("--llm-base"), let base = URL(string: baseText),
          base.scheme == "http" || base.scheme == "https",
          let modelID = argument("--llm-model"), !modelID.hasPrefix("--")
    else {
        return fail("Usage: bugvoice-bench --cleanup-bench --history <history.jsonl> --llm-base <url> --llm-model <id> [--llm-key-env VAR] [--runs N] [--show-text]")
    }
    let runs = argument("--runs").flatMap(Int.init) ?? 1
    guard (1...20).contains(runs) else { return fail("--runs must be 1 to 20.") }
    var apiKey: String?
    if let variable = argument("--llm-key-env") {
        guard let value = ProcessInfo.processInfo.environment[variable], !value.isEmpty else {
            return fail("Environment variable \(variable) is empty or not set.")
        }
        apiKey = value
    }
    let showText = CommandLine.arguments.contains("--show-text")

    let url = URL(fileURLWithPath: (historyPath as NSString).expandingTildeInPath)
    guard FileManager.default.isReadableFile(atPath: url.path) else {
        log("Cannot read history file.")
        return 1
    }
    var inputs: [BenchInput] = []
    for entry in await HistoryLog(url: url).load() {
        // Command mode rewrites on purpose and is never fidelity checked.
        guard entry.command == nil else { continue }
        let raw = entry.raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { continue }
        let language = SpeechLanguage(rawValue: entry.language ?? "") ?? .auto
        inputs.append(BenchInput(raw: raw, style: entry.style, language: language, keepEnglishWords: language == .vi))
    }
    let historyCount = inputs.count
    for (raw, language) in fixedSentences {
        inputs.append(BenchInput(raw: raw, style: .document, language: language, keepEnglishWords: language == .vi))
    }

    let model = OpenAICompatibleModel(baseURL: base, model: modelID, apiKey: apiKey, flavor: .local)
    func request(_ input: BenchInput) -> CleanupRequest {
        var built = PromptBuilder().request(
            raw: input.raw, style: input.style, focus: .unknown, vocabulary: Vocabulary(),
            modelID: modelID, disableThinking: true,
            language: input.language, keepEnglishWords: input.keepEnglishWords
        )
        built.maxTokens = min(1024, 2 * input.raw.count + 50)
        return built
    }

    // Discarded warm-up so timed rows exclude prompt-cache and first-token costs.
    do {
        _ = try await model.clean(request(BenchInput(raw: "hello there", style: .document, language: .en, keepEnglishWords: false)))
    } catch {
        // Error text can echo server output; keep it generic.
        log("Warm-up request failed. Check the server URL, model id and key.")
        return 1
    }

    var seconds = Array(repeating: [Double](), count: inputs.count)
    var flaggedPerRun: [Double] = []
    var rejectedPerRun: [Double] = []
    var errorsPerRun: [Double] = []
    for run in 1...runs {
        log("Run \(run) of \(runs)")
        var flagged = 0, rejected = 0, errors = 0
        for (index, input) in inputs.enumerated() {
            let start = Date()
            do {
                let output = try await model.clean(request(input))
                seconds[index].append(Date().timeIntervalSince(start))
                switch OutputSanitizer.sanitize(output, raw: input.raw) {
                case .accepted(let cleaned):
                    let issues = FidelityCheck.issues(raw: input.raw, cleaned: cleaned)
                    if !issues.isEmpty { flagged += 1 }
                    if showText {
                        log("[\(index + 1)] raw: \(input.raw)\n[\(index + 1)] cleaned: \(cleaned)"
                            + (issues.isEmpty ? "" : "\n[\(index + 1)] flagged: " + issues.map { "\($0.kind.rawValue) \($0.direction.rawValue) \($0.token)" }.joined(separator: ", ")))
                    }
                case .rejected(let reason):
                    rejected += 1
                    if showText { log("[\(index + 1)] rejected \(reason.rawValue): \(output)") }
                }
            } catch {
                errors += 1
                log("[\(index + 1)] request failed")
            }
        }
        flaggedPerRun.append(Double(flagged))
        rejectedPerRun.append(Double(rejected))
        errorsPerRun.append(Double(errors))
    }

    let perInput = seconds.map { LatencyStats.median($0) }
    let bucket = inputs.indices.filter {
        (10...20).contains(InsightsDelta.wordCount(inputs[$0].raw)) && !seconds[$0].isEmpty
    }.map { perInput[$0] }
    let all = inputs.indices.filter { !seconds[$0].isEmpty }.map { perInput[$0] }

    print("Model: \(modelID)")
    print("Entries run: \(inputs.count) (history \(historyCount), fixed \(fixedSentences.count)), runs: \(runs)")
    print("10-20 word inputs: \(bucket.count)")
    print(String(format: "Median cleanup s (10-20 words): %.3f", LatencyStats.median(bucket)))
    print(String(format: "P90 cleanup s (10-20 words): %.3f", LatencyStats.percentile(bucket, 90)))
    print(String(format: "Overall median cleanup s: %.3f", LatencyStats.median(all)))
    print(String(format: "Fidelity flagged (median over runs): %.1f", LatencyStats.median(flaggedPerRun)))
    print("Fidelity flagged per run: \(flaggedPerRun.map { Int($0) })")
    print(String(format: "Sanitizer rejected (median over runs): %.1f", LatencyStats.median(rejectedPerRun)))
    print(String(format: "Request errors (median over runs): %.1f", LatencyStats.median(errorsPerRun)))
    return 0
}
