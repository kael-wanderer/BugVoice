import SwiftUI
import VoiceCore

struct UseForCard: View {
    @Environment(AppearanceStore.self) private var store
    @Bindable var model: AppModel
    @State private var testOutput: String?
    @State private var testing = false

    static let sample = "ờ thì mình cần, à không, mình muốn deploy cái API lên staging vào thứ sáu"

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutTokens.spacing[2]) {
            HStack(alignment: .firstTextBaseline) {
                Text("Use for").bvFont(.bodyStrong)
                Spacer()
                Text("Which model each feature uses.").bvFont(.footnote).foregroundStyle(.bvSecondary)
            }
            VStack(alignment: .leading, spacing: LayoutTokens.spacing[3]) {
                row(.dictation, use: $model.settings.models.dictation)
                notesRow
                row(.meetings, use: $model.settings.models.meetings)
            }
            HStack {
                Button(testing ? "Sending…" : "Send test sentence") { Task { await runTest() } }.disabled(testing)
                if let testOutput { Text(testOutput).bvFont(.body).foregroundStyle(.bvSecondary).lineLimit(2) }
            }
            Text("Coding CLIs take several seconds per call, so they are offered for Meeting notes only. Text goes to a cloud service only when a feature uses a cloud connection.")
                .bvFont(.footnote).foregroundStyle(.bvSecondary)
        }
        .insightsCard()
    }

    private func subtitle(_ feature: ModelFeature) -> String {
        switch feature {
        case .dictation: "Answer within \(Int(model.settings.models.dictationTimeoutSeconds)) s, plus 0.1 s per word, or raw text is pasted"
        case .notes: "Same time limit"
        case .meetings: "Summary and action items. No time limit."
        }
    }

    private func label(_ feature: ModelFeature) -> some View {
        VStack(alignment: .leading, spacing: LayoutTokens.spacing[0]) {
            Text(feature.title).fontWeight(.semibold)
            Text(subtitle(feature)).bvFont(.footnote).foregroundStyle(.bvSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Each feature stacks its controls so the settings column can stay narrow.
    private func row(_ feature: ModelFeature, use: Binding<ModelUse>) -> some View {
        VStack(alignment: .leading, spacing: LayoutTokens.spacing[1]) {
            label(feature)
            enginePicker(feature == .dictation ? dictationEngine : use.engine, feature: feature, label: "\(feature.title) model")
            TextField(placeholder(use.wrappedValue), text: use.model).textFieldStyle(.roundedBorder)
                .accessibilityLabel("\(feature.title) model name")
            thinkingOrEffort(use, feature: feature)
            if feature == .dictation {
                Picker("Dictation time limit", selection: $model.settings.models.dictationTimeoutSeconds) {
                    Text("3 s").tag(3.0)
                    Text("5 s").tag(5.0)
                    Text("8 s").tag(8.0)
                }
                .labelsHidden().frame(width: store.scaled(70))
            }
            StatusDot(status: status(use.wrappedValue.engine))
        }
    }

    private var notesRow: some View {
        VStack(alignment: .leading, spacing: LayoutTokens.spacing[1]) {
            label(.notes)
            Picker("\(ModelFeature.notes.title) model", selection: Binding<ModelEngine?>(
                get: { model.settings.models.notes?.engine },
                set: { engine in
                    model.settings.models.notes = engine.map { ModelUse(engine: $0, disableThinking: true) }
                }
            )) {
                Text("Same as Dictation").tag(ModelEngine?.none)
                Divider()
                ForEach(model.settings.models.connections) { Text($0.name).tag(ModelEngine?.some(.connection($0.id))) }
                if model.appleIntelligenceAvailable { Text("Apple Intelligence").tag(ModelEngine?.some(.appleIntelligence)) }
                let builtIn = BuiltInChoices.notesChoices(dictation: model.settings.models.dictation.engine, installed: model.builtInInstalled)
                ForEach(builtIn) { Text(BuiltInChoices.pickerLabel($0)).tag(ModelEngine?.some(.builtIn($0.id))) }
                Text("None (raw text)").tag(ModelEngine?.some(.none))
                if case .builtIn(let id)? = model.settings.models.notes?.engine, !builtIn.contains(where: { $0.id == id }) {
                    Text(unlistedBuiltInLabel(id)).tag(ModelEngine?.some(.builtIn(id)))
                }
            }
            .labelsHidden()
            if model.settings.models.notes != nil {
                TextField("Connection default", text: Binding(
                    get: { model.settings.models.notes?.model ?? "" },
                    set: { model.settings.models.notes?.model = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("\(ModelFeature.notes.title) model name")
            } else {
                Text("—").foregroundStyle(.bvSecondary)
            }
            StatusDot(status: status((model.settings.models.notes ?? model.settings.models.dictation).engine))
        }
    }

    /// Dictation's engine; choosing one also keeps a Notes built-in model in step.
    private var dictationEngine: Binding<ModelEngine> {
        Binding(
            get: { model.settings.models.dictation.engine },
            set: { BuiltInChoices.chooseForDictation($0, in: &model.settings.models) }
        )
    }

    /// A built-in model that is chosen but cannot run: not downloaded, or not Dictation's.
    private func unlistedBuiltInLabel(_ id: String) -> String {
        guard let item = BuiltInCatalog.model(id: id) else { return "Choose a model" }
        let reason = model.builtInInstalled.contains(id) ? "not the Dictation model" : "not downloaded"
        return "\(BuiltInChoices.pickerLabel(item)), \(reason)"
    }

    /// `label` is hidden on screen but names the picker for VoiceOver.
    private func enginePicker(_ engine: Binding<ModelEngine>, feature: ModelFeature, label: String) -> some View {
        Picker(label, selection: engine) {
            Section("Connections") {
                ForEach(model.settings.models.connections) { Text($0.name).tag(ModelEngine.connection($0.id)) }
                if model.appleIntelligenceAvailable { Text("Apple Intelligence").tag(ModelEngine.appleIntelligence) }
            }
            let builtIn = feature == .dictation ? BuiltInChoices.dictationChoices(installed: model.builtInInstalled) : []
            if !builtIn.isEmpty {
                Section("Built-in") {
                    ForEach(builtIn) { Text(BuiltInChoices.pickerLabel($0)).tag(ModelEngine.builtIn($0.id)) }
                }
            }
            if feature == .meetings {
                Section("Coding CLIs") {
                    ForEach(CLITool.allCases, id: \.self) { tool in
                        Text("\(tool.title) (\(tool.rawValue))").tag(ModelEngine.cli(tool))
                    }
                }
            }
            Text("None (raw text)").tag(ModelEngine.none)
            if case .connection(let id) = engine.wrappedValue, !model.settings.models.connections.contains(where: { $0.id == id }) {
                Text("Choose a model").tag(engine.wrappedValue)
            }
            if case .builtIn(let id) = engine.wrappedValue, !builtIn.contains(where: { $0.id == id }) {
                Text(unlistedBuiltInLabel(id)).tag(engine.wrappedValue)
            }
        }
        .labelsHidden()
    }

    @ViewBuilder
    private func thinkingOrEffort(_ use: Binding<ModelUse>, feature: ModelFeature) -> some View {
        if case .cli(let tool) = use.wrappedValue.engine {
            Picker("\(feature.title) effort", selection: use.effort) {
                Text("Effort: default").tag("")
                ForEach(CLIArguments.efforts(for: tool), id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden().frame(width: store.scaled(130))
        } else {
            Picker("\(feature.title) thinking", selection: use.disableThinking) {
                Text("Thinking off").tag(true)
                Text("Thinking on").tag(false)
            }
            .labelsHidden().frame(width: store.scaled(130))
            .disabled(!thinkingApplies(use.wrappedValue.engine))
        }
    }

    /// Apple Intelligence has no switch, and built-in models always run with thinking off.
    private func thinkingApplies(_ engine: ModelEngine) -> Bool {
        switch engine {
        case .none, .appleIntelligence, .builtIn: false
        case .connection, .cli: true
        }
    }

    private func placeholder(_ use: ModelUse) -> String {
        switch use.engine {
        case .connection(let id):
            model.settings.models.connections.first { $0.id == id }
                .map { $0.model.isEmpty ? "Connection default" : "\($0.model) (connection default)" } ?? "Choose a model"
        case .cli: "CLI default"
        case .appleIntelligence, .builtIn, .none: "—"
        }
    }

    private func status(_ engine: ModelEngine) -> ConnectionStatus? {
        switch engine {
        case .connection(let id): model.connectionStatus[id]
        case .cli(let tool): model.cliInfo[tool] == nil ? .failed("\(tool.rawValue) was not found on this Mac.") : .reachable(models: [])
        case .appleIntelligence: model.appleIntelligenceAvailable ? .reachable(models: []) : .failed("Apple Intelligence is not available on this Mac")
        case .builtIn(let id):
            model.builtInInstalled.contains(id)
                ? .reachable(models: [])
                : .failed("\(BuiltInCatalog.model(id: id)?.name ?? "This model") is not downloaded.")
        case .none: nil
        }
    }

    private func runTest() async {
        testing = true
        defer { testing = false }
        guard let cleanup = ProviderFactory.cleanupModel(
            model.plan(for: .dictation), credentials: model.credentials, fallbackTimeout: model.settings.models.dictationTimeoutSeconds
        ) else {
            testOutput = "Dictation cleanup is set to None."
            return
        }
        let request = PromptBuilder(customRules: model.settings.styles.customRules).request(
            raw: Self.sample, style: .document, focus: .unknown, vocabulary: model.vocabulary,
            modelID: cleanup.modelID, disableThinking: cleanup.disableThinking
        )
        let start = Date()
        do {
            let output = try await cleanup.model.clean(request)
            let shown: String = switch OutputSanitizer.sanitize(output, raw: Self.sample) {
            case .accepted(let text): text
            case .rejected(let reason): "Rejected (\(reason.rawValue)): \(output)"
            }
            let elapsed = Date().timeIntervalSince(start)
            let limit = CleanupTimeout.limit(base: cleanup.timeoutSeconds, raw: Self.sample)
            // Dictation gives up after the limit and pastes raw text.
            let verdict = elapsed > limit ? String(format: "over the %.1f s limit, dictation would paste raw text", limit) : "within the time limit"
            testOutput = String(format: "%@ · %.2f s, %@", shown, elapsed, verdict)
        } catch {
            testOutput = error.localizedDescription
        }
    }
}
