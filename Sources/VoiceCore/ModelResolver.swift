import Foundation

public enum ModelFeature: Sendable, CaseIterable {
    case dictation, notes, meetings

    public var title: String {
        switch self {
        case .dictation: "Dictation cleanup"
        case .notes: "Notes dictation"
        case .meetings: "Meeting notes"
        }
    }

    /// Dictation and Notes wait for the answer before pasting.
    var isFast: Bool { self != .meetings }
}

/// What a feature will call, decided from settings alone.
public enum ModelPlan: Equatable, Sendable {
    case none
    case unavailable(String)
    case connection(ModelConnection, baseURL: URL, modelID: String, disableThinking: Bool, timeout: TimeInterval)
    case appleIntelligence(timeout: TimeInterval)
    case cli(CLITool, path: String, model: String, effort: String, timeout: TimeInterval)

    /// For the HUD's *Cleaning (…)*.
    public var shortName: String? {
        switch self {
        case .none, .unavailable: nil
        case .connection(let c, _, let modelID, _, _): ModelNames.short(modelID) ?? c.name
        case .appleIntelligence: "Apple Intelligence"
        case .cli(let tool, _, _, _, _): tool.title
        }
    }
}

public enum ModelResolver {
    static let cloudTimeout: TimeInterval = 120
    static let localTimeout: TimeInterval = 600
    static let cliTimeout: TimeInterval = 600

    public static func plan(
        for feature: ModelFeature,
        settings: ModelSettings,
        cliPaths: [CLITool: String],
        appleIntelligenceAvailable: Bool
    ) -> ModelPlan {
        let use: ModelUse = switch feature {
        case .dictation: settings.dictation
        case .notes: settings.notes ?? settings.dictation
        case .meetings: settings.meetings
        }
        switch use.engine {
        case .none:
            return .none
        case .appleIntelligence:
            guard appleIntelligenceAvailable else { return .unavailable("Apple Intelligence is not available on this Mac") }
            return .appleIntelligence(timeout: feature.isFast ? settings.dictationTimeoutSeconds : cloudTimeout)
        case .cli(let tool):
            guard !feature.isFast else { return .none }
            guard let path = cliPaths[tool] else { return .unavailable("\(tool.rawValue) was not found on this Mac.") }
            return .cli(tool, path: path, model: use.model, effort: use.effort, timeout: cliTimeout)
        case .connection(let id):
            guard let connection = settings.connections.first(where: { $0.id == id }) else {
                return .unavailable("The connection for \(feature.title) was deleted. Choose another in Settings → Models.")
            }
            guard let url = ConnectionAddress.baseURL(for: connection) else {
                return .unavailable("The address of \(connection.name) is not valid.")
            }
            let override = use.model.trimmingCharacters(in: .whitespaces)
            let timeout = feature.isFast
                ? settings.dictationTimeoutSeconds
                : (ConnectionAddress.isLocal(url) ? localTimeout : cloudTimeout)
            return .connection(
                connection, baseURL: url, modelID: override.isEmpty ? connection.model : override,
                disableThinking: use.disableThinking, timeout: timeout
            )
        }
    }
}

/// The text model a dictation uses, with what the pipeline needs to call it.
public struct CleanupModel: Sendable {
    public var model: any TextModel
    public var modelID: String
    public var shortName: String?
    public var disableThinking: Bool
    public var timeoutSeconds: Double

    public init(model: any TextModel, modelID: String, shortName: String? = nil, disableThinking: Bool = false, timeoutSeconds: Double = 3) {
        self.model = model
        self.modelID = modelID
        self.shortName = shortName
        self.disableThinking = disableThinking
        self.timeoutSeconds = timeoutSeconds
    }
}

/// Applies a feature's thinking choice to callers that do not set it
/// (meeting notes).
public struct ThinkingOverride: TextModel {
    public var base: any TextModel
    public var disableThinking: Bool

    public init(base: any TextModel, disableThinking: Bool) {
        self.base = base
        self.disableThinking = disableThinking
    }

    public func clean(_ request: CleanupRequest) async throws -> String {
        var request = request
        request.disableThinking = disableThinking
        return try await base.clean(request)
    }
}
