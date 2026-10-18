import SwiftUI
import VoiceCore

struct SearchCard: View {
    @Bindable var model: AppModel
    /// The model name as typed. Saved on Return or when the field loses focus: each saved change
    /// rebuilds the index, so a keystroke must not.
    @State private var modelNameDraft = ""
    @FocusState private var modelNameFocused: Bool

    private var connections: [ModelConnection] {
        model.settings.models.connections.filter {
            $0.kind == .openAICompatible && ConnectionAddress.baseURL(for: $0).map(ConnectionAddress.isLocal) == true
        }
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: LayoutTokens.spacing[2]) {
                Picker("Embedding model", selection: $model.settings.models.search.embeddingConnectionID) {
                    Text("None").tag(String?.none)
                    ForEach(connections) { Text($0.name).tag(Optional($0.id)) }
                }
                if model.settings.models.search.embeddingConnectionID != nil {
                    TextField("Model name", text: $modelNameDraft)
                        .focused($modelNameFocused)
                        .onSubmit(commitModelName)
                        .onChange(of: modelNameFocused) { wasFocused, isFocused in
                            if wasFocused && !isFocused { commitModelName() }
                        }
                }
                Stepper(value: $model.settings.models.search.askContextTokens, in: 4_096...262_144, step: 4_096) {
                    HStack {
                        Text("Ask context size")
                        Spacer()
                        Text("\(model.settings.models.search.askContextTokens.formatted()) tokens").monospacedDigit()
                    }
                }
                switch model.searchIndexer.status {
                case .off: EmptyView()
                case .upToDate: Text("Index up to date").foregroundStyle(.bvSecondary)
                case .unavailable: Text("Embedding model unavailable").foregroundStyle(.bvSecondary)
                case .indexing(let done, let total):
                    Text("Indexing \(done) of \(total) items…").foregroundStyle(.bvSecondary)
                    ProgressView(value: Double(done), total: Double(max(1, total)))
                }
                Text("Embeddings are saved on this Mac. Without an embedding model, Ask uses word search.")
                    .bvFont(.footnote).foregroundStyle(.bvSecondary)
            }.padding(LayoutTokens.spacing[1])
        } label: { Text("Search").bvFont(.bodyStrong) }
        .onAppear { modelNameDraft = model.settings.models.search.embeddingModel }
        .onChange(of: model.settings.models.search.embeddingModel) { _, saved in
            if !modelNameFocused { modelNameDraft = saved }
        }
        .onDisappear(perform: commitModelName)
    }

    private func commitModelName() {
        let name = modelNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name != model.settings.models.search.embeddingModel else { return }
        model.settings.models.search.embeddingModel = name
    }
}
