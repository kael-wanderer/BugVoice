import Foundation

/// Pure rules for showing and choosing built-in cleanup models: picker
/// entries, download state, readiness, and the text the screens show.
public enum BuiltInChoices {
    /// The fixed sentence the onboarding self-test cleans.
    public static let testSentence = "um so tomorrow mình họp lúc ba giờ nha, uh, with the design team"

    // MARK: Picker entries

    public static func pickerLabel(_ model: BuiltInModel) -> String { "Built-in · \(model.name)" }

    /// Downloaded models, in catalog order (small to large).
    public static func dictationChoices(installed: Set<String>) -> [BuiltInModel] {
        BuiltInCatalog.models.filter { installed.contains($0.id) }
    }

    /// Notes may use only the built-in model Dictation uses, and only once it is downloaded.
    public static func notesChoices(dictation: ModelEngine, installed: Set<String>) -> [BuiltInModel] {
        guard case .builtIn(let id) = dictation, installed.contains(id),
              let model = BuiltInCatalog.model(id: id) else { return [] }
        return [model]
    }

    // MARK: State

    public static func state(of id: String, installed: Set<String>,
                             downloads: [String: Double], failures: [String: String]) -> BuiltInState {
        if installed.contains(id) { return .ready }
        if let fraction = downloads[id] { return .downloading(fraction) }
        if let message = failures[id] { return .failed(message) }
        return .notDownloaded
    }

    /// The readiness check when Dictation uses a known built-in model; nil otherwise.
    public static func readinessCheck(dictation: ModelEngine, installed: Set<String>,
                                      downloads: [String: Double], failures: [String: String]) -> CleanupCheck? {
        guard case .builtIn(let id) = dictation, let model = BuiltInCatalog.model(id: id) else { return nil }
        return .builtIn(name: model.name, state: state(of: id, installed: installed, downloads: downloads, failures: failures))
    }

    // MARK: Choosing and deleting

    /// Sets Dictation's engine. Notes keeps its own engine unless it was a
    /// built-in model that no longer matches Dictation's.
    public static func chooseForDictation(_ engine: ModelEngine, in models: inout ModelSettings) {
        models.dictation.engine = engine
        if case .builtIn = engine { models.dictation.disableThinking = true }
        if case .builtIn(let notesID)? = models.notes?.engine, engine != .builtIn(notesID) {
            models.notes = nil
        }
    }

    public static func isInUse(_ id: String, models: ModelSettings) -> Bool {
        models.dictation.engine == .builtIn(id) || models.notes?.engine == .builtIn(id)
    }

    /// Before the model's file is deleted: Dictation turns cleanup off and
    /// Notes goes back to following Dictation.
    public static func forget(_ id: String, in models: inout ModelSettings) {
        if models.dictation.engine == .builtIn(id) { models.dictation.engine = .none }
        if models.notes?.engine == .builtIn(id) { models.notes = nil }
    }

    public static func deleteQuestion(_ model: BuiltInModel) -> String {
        "Delete \(model.name)? Dictation cleanup turns off until you choose another model."
    }

    // MARK: Text

    /// Decimal gigabytes with one decimal: "2.5 GB".
    public static func gigabytes(_ bytes: Int64) -> String {
        String(format: "%.1f GB", Double(bytes) / 1_000_000_000)
    }

    public static func downloadTitle(_ model: BuiltInModel) -> String { "Download \(gigabytes(model.bytes))" }

    /// "1.6 of 2.5 GB".
    public static func progress(_ fraction: Double, of model: BuiltInModel) -> String {
        let done = Double(model.bytes) * min(1, max(0, fraction)) / 1_000_000_000
        return String(format: "%.1f of %@", done, gigabytes(model.bytes))
    }

    /// Estimates from this session's rate. Nil until there is something to go on.
    public static func timeLeft(fraction: Double, startFraction: Double, elapsed: TimeInterval) -> String? {
        let gained = fraction - startFraction
        guard gained > 0, elapsed >= 2 else { return nil }
        let remaining = (1 - fraction) / (gained / elapsed)
        let seconds = Int(remaining.rounded())
        if seconds < 60 {
            return seconds <= 1 ? "About 1 second left." : "About \(seconds) seconds left."
        }
        let minutes = Int((remaining / 60).rounded())
        return minutes == 1 ? "About 1 minute left." : "About \(minutes) minutes left."
    }

    /// The 5b lead line, with this Mac's memory in whole GB.
    public static func memoryLine(physicalMemory: UInt64) -> String {
        let gb = Int((Double(physicalMemory) / 1_073_741_824).rounded())
        return "Bigger models clean better and take longer. This Mac has \(gb) GB of memory."
    }
}
