import Foundation
@testable import VoiceCore

struct FakeTranscriber: Transcriber {
    var text: String = "hello world"
    var error: Error?
    func transcribe(_ clip: AudioClip, options: TranscriptionOptions) async throws -> Transcript {
        if let error { throw error }
        return Transcript(text: text, language: "en")
    }
}

struct FakeModel: TextModel {
    var output: String = "Hello world."
    var error: Error?
    var delay: Double = 0
    func clean(_ request: CleanupRequest) async throws -> String {
        if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
        if let error { throw error }
        return output
    }
}

/// Records every request and echoes the raw dictation back, or sleeps and
/// notes whether it was cancelled.
actor RecordingModel: TextModel {
    private(set) var requests: [CleanupRequest] = []
    private(set) var wasCancelled = false
    let output: String?
    let delay: Double
    init(output: String? = nil, delay: Double = 0) {
        self.output = output
        self.delay = delay
    }
    func clean(_ request: CleanupRequest) async throws -> String {
        requests.append(request)
        if delay > 0 {
            do { try await Task.sleep(for: .seconds(delay)) } catch {
                wasCancelled = true
                throw error
            }
        }
        if let output { return output }
        // Echo the text inside <dictation> tags.
        let user = request.user
        guard let open = user.range(of: "<dictation>\n"), let close = user.range(of: "\n</dictation>") else { return user }
        return String(user[open.upperBound..<close.lowerBound])
    }
}

actor RecordingInsertion: InsertionTarget {
    var outcome: InsertOutcome = .pasted
    private(set) var inserted: [String] = []
    private(set) var copied: [String] = []
    init(outcome: InsertOutcome = .pasted) { self.outcome = outcome }
    func insert(_ text: String) async -> InsertOutcome { inserted.append(text); return outcome }
    func copy(_ text: String) async { copied.append(text) }
}

struct FixedFocus: FocusProvider {
    var focus: FocusSnapshot
    var same: Bool? = nil
    func isSameTarget() async -> Bool? { same }
    func snapshot() async -> FocusSnapshot { focus }
}

/// 1 s of a 440 Hz tone at amplitude 0.3 — loud enough to pass the silence gate.
let speechClip = AudioClip(samples: (0..<16_000).map { 0.3 * sin(Float($0) * 2 * .pi * 440 / 16_000) })
let terminalFocus = FocusSnapshot(appName: "Terminal", bundleID: "com.apple.Terminal")
let notionFocus = FocusSnapshot(appName: "Notion", bundleID: "notion.id")
