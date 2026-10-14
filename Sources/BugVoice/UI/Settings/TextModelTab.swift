import SwiftUI
import VoiceCore

struct TextModelTab: View {
    @Bindable var model: AppModel
    @State private var models: [String] = []
    @State private var reachable: Bool?
    @State private var preset = Self.custom
    @State private var test: (input: String, output: String, seconds: Double)?
    @State private var testError: String?
    @State private var testing = false

    static let custom = "Custom"
    static let presets: [(name: String, url: String)] = [
        ("LM Studio", "http://localhost:1234"),
        ("Ollama", "http://localhost:11434"),
        ("MLX server", "http://localhost:8080"),
    ]
    static let sample = "ờ thì mình cần, à không, mình muốn deploy cái API lên staging vào thứ sáu"

    var isHTTP: Bool {
        model.settings.textModel.provider == .openAICompatible || model.settings.textModel.provider == .anthropicCompatible
    }

    var keyAccount: String {
        model.settings.textModel.provider == .anthropicCompatible ? "anthropic" : "openai"
    }

    var body: some View {
        Form {
            Picker("Provider", selection: $model.settings.textModel.provider) {
                Text("OpenAI-compatible").tag(TextModelProvider.openAICompatible)
                Text("Anthropic-compatible").tag(TextModelProvider.anthropicCompatible)
                Text("Apple Intelligence (on device)").tag(TextModelProvider.appleIntelligence)
                Text("None (raw text only)").tag(TextModelProvider.none)
            }
            if isHTTP {
                Picker("Preset", selection: presetBinding) {
                    ForEach(Self.presets, id: \.name) { Text($0.name).tag($0.name) }
                    Text(Self.custom).tag(Self.custom)
                }
                LabeledContent("Base URL") {
                    HStack {
                        TextField("", text: $model.settings.textModel.baseURL)
                            .labelsHidden()
                            .onSubmit { Task { await refresh() } }
                        if let reachable {
                            Text(reachable ? "Reachable" : "Not reachable").foregroundStyle(reachable ? .green : .orange)
                        }
                    }
                }
                LabeledContent("Model") {
                    HStack {
                        TextField("", text: $model.settings.textModel.model).labelsHidden()
                        Menu("Choose") { ForEach(models, id: \.self) { id in Button(id) { model.settings.textModel.model = id } } }
                            .disabled(models.isEmpty)
                        Button("Refresh") { Task { await refresh() } }
                    }
                }
                KeyField(model: model, title: "API key (stored in Keychain)", account: keyAccount) {
                    Task { await refresh() }
                }
            }
            Picker("Timeout", selection: $model.settings.textModel.timeoutSeconds) {
                Text("3 seconds").tag(3.0)
                Text("5 seconds").tag(5.0)
                Text("8 seconds").tag(8.0)
            }
            Text("After this, raw text is pasted.").font(.caption).foregroundStyle(.secondary)
            Toggle("Disable thinking (adds /no_think for Qwen, strips <think> blocks)", isOn: $model.settings.textModel.disableThinking)

            Section("Test") {
                Button(testing ? "Sending…" : "Send test sentence") { Task { await runTest() } }.disabled(testing)
                if let test {
                    LabeledContent("Input", value: test.input)
                    LabeledContent("Output", value: test.output)
                    LabeledContent("Latency", value: String(format: "%.2f s", test.seconds))
                }
                if let testError { Text(testError).foregroundStyle(.red) }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            preset = Self.presets.first { $0.url == model.settings.textModel.baseURL }?.name ?? Self.custom
        }
        .task { await refresh() }
    }

    /// Picking a named preset sets the base URL; Custom leaves it as typed.
    var presetBinding: Binding<String> {
        Binding(
            get: { preset },
            set: { name in
                preset = name
                if let match = Self.presets.first(where: { $0.name == name }) {
                    model.settings.textModel.baseURL = match.url
                    Task { await refresh() }
                }
            }
        )
    }

    func refresh() async {
        guard isHTTP, let url = URL(string: model.settings.textModel.baseURL) else { reachable = nil; return }
        let anthropic = model.settings.textModel.provider == .anthropicCompatible
        do {
            models = try await ModelCatalog.list(baseURL: url, apiKey: model.keychain.read(keyAccount), anthropic: anthropic)
            reachable = true
        } catch {
            models = []
            reachable = false
        }
    }

    func runTest() async {
        testing = true
        defer { testing = false }
        testError = nil
        guard let textModel = ProviderFactory.textModel(model.settings.textModel, keychain: model.keychain) else {
            testError = "Provider is None."
            return
        }
        let request = PromptBuilder(customRules: model.settings.styles.customRules).request(
            raw: Self.sample, style: .document, focus: .unknown, vocabulary: model.vocabulary,
            modelID: model.settings.textModel.model, disableThinking: model.settings.textModel.disableThinking
        )
        let start = Date()
        do {
            let output = try await textModel.clean(request)
            let shown: String = switch OutputSanitizer.sanitize(output, raw: Self.sample) {
            case .accepted(let text): text
            case .rejected(let reason): "Rejected (\(reason.rawValue)): \(output)"
            }
            test = (Self.sample, shown, Date().timeIntervalSince(start))
        } catch {
            testError = String(describing: error)
        }
    }
}
