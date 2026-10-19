import Foundation

/// Text for the unified log and the Copy diagnostics report. Never carries
/// what the user said or wrote: only outcomes, counts, timings and settings.
public enum Diagnostics {
    public struct Entry: Sendable, Equatable {
        public var date: Date
        public var level: String
        public var category: String
        public var message: String

        public init(date: Date, level: String, category: String, message: String) {
            self.date = date
            self.level = level
            self.category = category
            self.message = message
        }
    }

    public static func dictationSummary(_ result: DictationResult) -> String {
        var parts = ["outcome=\(result.outcome.rawValue)"]
        if let reason = result.rawReason { parts.append("raw=\(reason.rawValue)") }
        if let bundleID = result.bundleID { parts.append("app=\(bundleID)") }
        parts.append("style=\(result.style.rawValue)")
        if let language = result.language { parts.append("lang=\(language)") }
        parts.append("words=\(result.finalText.split(whereSeparator: \.isWhitespace).count)")
        let t = result.timings
        parts.append("rec=\(seconds(t.recording)) stt=\(seconds(t.transcribe)) clean=\(seconds(t.clean)) insert=\(seconds(t.insert))")
        return parts.joined(separator: " ")
    }

    /// Engines and model names only: no server addresses, keys or rules.
    public static func facts(_ settings: AppSettings) -> [String: String] {
        let speech = settings.speech
        let models = settings.models
        return [
            "Speech": "\(speech.engine.rawValue) \(speech.whisperModel), language \(speech.language.rawValue)",
            "Dictation model": describe(models.dictation, connections: models.connections),
            "Notes model": models.notes.map { describe($0, connections: models.connections) } ?? "same as Dictation",
            "Meetings model": describe(models.meetings, connections: models.connections),
            "Hotkey": settings.hotkey.rawValue,
        ]
    }

    private static func describe(_ use: ModelUse, connections: [ModelConnection]) -> String {
        switch use.engine {
        case .connection(let id):
            guard let connection = connections.first(where: { $0.id == id }) else { return "missing connection \(id)" }
            let model = use.model.isEmpty ? connection.model : use.model
            return "\(connection.name) (\(connection.kind.rawValue)) \(model)"
        case .cli(let tool): return "\(tool.rawValue) CLI"
        case .appleIntelligence: return "Apple Intelligence"
        case .none: return "none"
        }
    }

    /// Facts are sorted by name; entries are written oldest first.
    public static func report(
        appVersion: String, system: String, hardware: String,
        facts: [String: String], entries: [Entry], timeZone: TimeZone = .current
    ) -> String {
        var lines = ["BugVoice diagnostics", "App: \(appVersion)", "System: \(system) (\(hardware))"]
        lines += facts.keys.sorted().map { "\($0): \(facts[$0] ?? "")" }
        lines.append("")
        lines.append("Log (this launch, \(entries.count) \(entries.count == 1 ? "entry" : "entries"))")
        if entries.isEmpty {
            lines.append("No entries.")
        } else {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = timeZone
            formatter.dateFormat = "HH:mm:ss"
            lines += entries.sorted { $0.date < $1.date }.map {
                "\(formatter.string(from: $0.date)) \($0.level) \($0.category): \($0.message)"
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func seconds(_ value: Double) -> String {
        String(format: "%.2fs", value)
    }
}
