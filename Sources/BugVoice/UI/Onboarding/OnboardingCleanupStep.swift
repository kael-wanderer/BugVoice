import Observation
import SwiftUI
import VoiceCore

/// The apps the "An app I already run" choice offers.
enum OnboardingLocalApp: String, CaseIterable, Identifiable {
    case lmStudio, ollama, omlx, other
    var id: String { rawValue }
    var title: String {
        switch self {
        case .lmStudio: "LM Studio"
        case .ollama: "Ollama"
        case .omlx: "oMLX"
        case .other: "Other"
        }
    }
    /// Nil for Other: the person types the address.
    var address: String? {
        switch self {
        case .lmStudio: "http://localhost:1234/v1"
        case .ollama: "http://localhost:11434/v1"
        case .omlx: "http://localhost:8000"
        case .other: nil
        }
    }
}

enum OnboardingTestState: Equatable {
    case idle, testing
    case passed(String)
    case failed(String)
}

/// What the cleanup step has picked so far. Nothing is written to settings
/// until `commit`. `kind == nil` means the person has not chosen, and Continue
/// leaves the current settings alone.
@MainActor @Observable
final class OnboardingCleanupDraft {
    var kind: CleanupChoiceKind? { didSet { resetTest() } }
    var app: OnboardingLocalApp = .lmStudio { didSet { resetTest() } }
    var customAddress = "" { didSet { resetTest() } }
    var service: ConnectionKind = .openAI { didSet { resetTest() } }
    var key = "" { didSet { resetTest() } }
    var modelName = "" { didSet { resetTest() } }
    var state: OnboardingTestState = .idle

    static let services: [ConnectionKind] = [.openAI, .anthropic, .openRouter]
    @ObservationIgnored private let localID = ModelConnection.newID(for: .openAICompatible)
    @ObservationIgnored private var cloudIDs: [ConnectionKind: String] = [:]

    private func resetTest() {
        if state != .testing { state = .idle }
    }

    var localAddress: String { app.address ?? customAddress.trimmingCharacters(in: .whitespaces) }
    var addressProblem: String? { kind == .localApp ? ConnectionAddress.problem(localAddress) : nil }

    /// The connection the current fields describe.
    var connection: ModelConnection {
        let name = modelName.trimmingCharacters(in: .whitespaces)
        if kind == .cloud {
            let id = cloudIDs[service] ?? ModelConnection.newID(for: service)
            cloudIDs[service] = id
            return ModelConnection(id: id, name: service.title, kind: service, baseURL: "", model: name)
        }
        return ModelConnection(
            id: localID, name: app == .other ? "Local server" : app.title,
            kind: .openAICompatible, baseURL: localAddress, model: name)
    }

    var choice: CleanupChoice? {
        switch kind {
        case nil: nil
        case .appleIntelligence?: .appleIntelligence
        case .none?: CleanupChoice.none
        case .localApp?: .connection(connection, local: true)
        case .cloud?: .connection(connection, local: false)
        case .builtIn?: nil // Not offered until the built-in engine ships.
        }
    }

    var canContinue: Bool {
        switch kind {
        case .localApp?: addressProblem == nil && !modelName.trimmingCharacters(in: .whitespaces).isEmpty
        case .cloud?: !modelName.trimmingCharacters(in: .whitespaces).isEmpty
        default: true
        }
    }

    private var typedKey: String { key.trimmingCharacters(in: .whitespaces) }

    /// Saves the key and writes the choice into settings. False when the key could not be saved.
    func commit(to model: AppModel) -> Bool {
        guard let choice else { return true }
        if case .connection(let connection, _) = choice, !typedKey.isEmpty {
            guard model.saveKey(typedKey, account: connection.credentialAccount) else { return false }
        }
        OnboardingSetup.apply(choice, to: &model.settings.models)
        if case .connection(let connection, _) = choice {
            Task { await model.testConnection(connection) }
        }
        return true
    }

    /// Lists the server's models, then sends one sentence through the chosen model.
    func test(on model: AppModel) async {
        state = .testing
        var conn = connection
        guard let url = ConnectionAddress.baseURL(for: conn) else {
            state = .failed(ConnectionAddress.problem(conn.baseURL) ?? "The address is not valid.")
            return
        }
        if !typedKey.isEmpty, !model.saveKey(typedKey, account: conn.credentialAccount) {
            state = .failed("The key could not be saved.")
            return
        }
        await model.testConnection(conn)
        switch model.connectionStatus[conn.id] {
        case .reachable(let models)?:
            if conn.model.isEmpty, let first = models.first {
                modelName = first
                conn.model = first
            }
        case .failed(let message)?:
            state = .failed(message)
            return
        case nil:
            state = .failed("No answer.")
            return
        }
        guard !conn.model.isEmpty else {
            state = .failed("Choose a model, then test again.")
            return
        }
        let local = kind == .localApp
        let plan = ModelPlan.connection(conn, baseURL: url, modelID: conn.model, disableThinking: local, timeout: 15)
        guard let cleanup = ProviderFactory.cleanupModel(plan, credentials: model.credentials, fallbackTimeout: 15) else {
            state = .failed("The model could not be reached.")
            return
        }
        let sample = UseForCard.sample
        let request = PromptBuilder(customRules: model.settings.styles.customRules).request(
            raw: sample, style: .document, focus: .unknown, vocabulary: model.vocabulary,
            modelID: cleanup.modelID, disableThinking: cleanup.disableThinking)
        let start = Date()
        do {
            let output = try await cleanup.model.clean(request)
            let seconds = Date().timeIntervalSince(start)
            switch OutputSanitizer.sanitize(output, raw: sample) {
            case .accepted:
                state = .passed(String(format: "%@ answered in %.1f s", conn.model, seconds))
            case .rejected:
                state = .failed("The model answered, but its text was not usable. Try another model.")
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

struct OnboardingCleanupStep: View {
    @Bindable var model: AppModel
    @Bindable var draft: OnboardingCleanupDraft

    private var kinds: [CleanupChoiceKind] {
        OnboardingSetup.choices(appleIntelligence: model.appleIntelligenceAvailable, builtInEnabled: false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutTokens.spacing[2]) {
            VStack(alignment: .leading, spacing: LayoutTokens.spacing[1]) {
                Text("Choose how text gets cleaned up").bvFont(.title1)
                Text("Removes \"um\", fixes punctuation, keeps your words. You can change this any time in Settings › Models.")
                    .bvFont(.reading).foregroundStyle(.bvSecondary)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: LayoutTokens.spacing[1]) {
                    ForEach(kinds, id: \.self) { kind in
                        row(kind)
                        if draft.kind == kind, kind == .localApp { localForm }
                        if draft.kind == kind, kind == .cloud { cloudForm }
                    }
                }
            }
        }
    }

    private func text(_ kind: CleanupChoiceKind) -> (String, String) {
        switch kind {
        case .builtIn: ("Built-in model", "BugVoice downloads and runs a model by itself.")
        case .appleIntelligence: ("Apple Intelligence", "Already on this Mac. Fast, English works best.")
        case .localApp: ("An app I already run", "LM Studio, Ollama, oMLX or another local server. Enter its address.")
        case .cloud: ("A cloud service", "OpenAI, Anthropic or OpenRouter with your key. Text leaves this Mac.")
        case .none: ("No cleanup", "Paste exactly what the speech model heard.")
        }
    }

    private func row(_ kind: CleanupChoiceKind) -> some View {
        let selected = draft.kind == kind
        let (title, detail) = text(kind)
        return Button { draft.kind = kind } label: {
            HStack(alignment: .top, spacing: LayoutTokens.spacing[1]) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? .bvAccent : .bvSecondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).bvFont(.bodyStrong)
                    Text(detail).bvFont(.footnote).foregroundStyle(.bvSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(LayoutTokens.spacing[1])
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if selected { RoundedRectangle(cornerRadius: LayoutTokens.cardRadius).fill(.bvHover) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var localForm: some View {
        VStack(alignment: .leading, spacing: LayoutTokens.spacing[1]) {
            Picker("App", selection: $draft.app) {
                ForEach(OnboardingLocalApp.allCases) { Text($0.title).tag($0) }
            }
            .fixedSize()
            if draft.app == .other {
                TextField("Address", text: $draft.customAddress, prompt: Text("http://localhost:8000/v1"))
                    .textFieldStyle(.roundedBorder)
                if !draft.customAddress.isEmpty, let problem = draft.addressProblem {
                    Text(problem).bvFont(.footnote).foregroundStyle(.bvWarning)
                }
            } else {
                LabeledContent("Address", value: draft.localAddress)
            }
            SecureField("API key", text: $draft.key, prompt: Text("Only if the app needs one"))
                .textFieldStyle(.roundedBorder)
            modelField
            testRow(hint: draft.app == .other ? "Start the server, then test again." : "Open \(draft.app.title) and start its server, then test again.")
        }
        .formIndent()
    }

    private var cloudForm: some View {
        VStack(alignment: .leading, spacing: LayoutTokens.spacing[1]) {
            Picker("Service", selection: $draft.service) {
                ForEach(OnboardingCleanupDraft.services, id: \.self) { Text($0.title).tag($0) }
            }
            .fixedSize()
            SecureField("API key", text: $draft.key, prompt: Text("Paste the key"))
                .textFieldStyle(.roundedBorder)
            Text("Saved on this Mac only.").bvFont(.footnote).foregroundStyle(.bvSecondary)
            modelField
            testRow(hint: nil)
            Text("Your dictated text is sent to this service. Audio stays on this Mac.")
                .bvFont(.footnote).foregroundStyle(.bvSecondary)
        }
        .formIndent()
    }

    private var modelField: some View {
        HStack {
            TextField("Model", text: $draft.modelName, prompt: Text("Model name")).textFieldStyle(.roundedBorder)
            if case .reachable(let models)? = model.connectionStatus[draft.connection.id], !models.isEmpty {
                Menu("Choose…") { ForEach(models, id: \.self) { id in Button(id) { draft.modelName = id } } }
                    .fixedSize()
            }
        }
    }

    private func testRow(hint: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Button(draft.state == .testing ? "Testing…" : testLabel) { Task { await draft.test(on: model) } }
                    .disabled(draft.state == .testing || draft.addressProblem != nil)
                switch draft.state {
                case .passed(let line):
                    Label("Test passed · \(line)", systemImage: "checkmark.circle.fill")
                        .bvFont(.footnote).foregroundStyle(.bvSuccess)
                case .failed(let message):
                    Text(message).bvFont(.footnote).foregroundStyle(.bvWarning).lineLimit(3)
                default: EmptyView()
                }
            }
            if case .failed = draft.state, let hint {
                Text(hint).bvFont(.footnote).foregroundStyle(.bvSecondary)
            }
        }
    }

    private var testLabel: String {
        if case .failed = draft.state { return "Test again" }
        return "Test"
    }
}

private extension View {
    func formIndent() -> some View {
        padding(.leading, LayoutTokens.spacing[4]).padding(.trailing, LayoutTokens.spacing[1]).padding(.bottom, LayoutTokens.spacing[1])
    }
}
