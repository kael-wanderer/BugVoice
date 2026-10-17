import SwiftUI
import VoiceCore

struct SearchCard: View {
    @Bindable var model: AppModel

    private var connections: [ModelConnection] {
        model.settings.models.connections.filter {
            $0.kind == .openAICompatible && ConnectionAddress.baseURL(for: $0).map(ConnectionAddress.isLocal) == true
        }
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Embedding model", selection: $model.settings.models.search.embeddingConnectionID) {
                    Text("None").tag(String?.none)
                    ForEach(connections) { Text($0.name).tag(Optional($0.id)) }
                }
                if model.settings.models.search.embeddingConnectionID != nil {
                    TextField("Model name", text: $model.settings.models.search.embeddingModel)
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
                case .upToDate: Text("Index up to date").foregroundStyle(.secondary)
                case .unavailable: Text("Embedding model unavailable").foregroundStyle(.secondary)
                case .indexing(let done, let total):
                    Text("Indexing \(done) of \(total) items…").foregroundStyle(.secondary)
                    ProgressView(value: Double(done), total: Double(max(1, total)))
                }
                Text("Embeddings are saved on this Mac. Without an embedding model, Ask uses word search.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(8)
        } label: { Text("Search").font(.headline) }
    }
}
