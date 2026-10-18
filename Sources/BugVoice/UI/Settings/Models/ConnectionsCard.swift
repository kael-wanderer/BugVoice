import SwiftUI
import VoiceCore

struct ConnectionsCard: View {
    @Bindable var model: AppModel
    @State private var editing: ConnectionDraft?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Connections").bvFont(.bodyStrong)
                Spacer()
                Text("Each keeps its own API key on this Mac.").bvFont(.footnote).foregroundStyle(.bvSecondary)
            }
            .padding(.bottom, LayoutTokens.spacing[1])
            if model.settings.models.connections.isEmpty {
                Text("No connections yet.").foregroundStyle(.bvSecondary).padding(.vertical, LayoutTokens.spacing[1])
            }
            ForEach(model.settings.models.connections) { connection in
                Divider()
                HStack(spacing: LayoutTokens.spacing[2]) {
                    VStack(alignment: .leading, spacing: LayoutTokens.spacing[0]) {
                        Text(connection.name).fontWeight(.semibold)
                        Text(addressLine(connection)).bvCode(.footnote).foregroundStyle(.bvSecondary).lineLimit(1)
                    }
                    Spacer()
                    Text(keyState(connection)).bvFont(.footnote).foregroundStyle(.bvSecondary)
                    StatusDot(status: model.connectionStatus[connection.id])
                    Button("Edit") { editing = ConnectionDraft(connection: connection, isNew: false) }
                }
                .padding(.vertical, LayoutTokens.spacing[1])
            }
            Divider()
            HStack {
                Menu("+ Add connection") {
                    Section("On this Mac") { presetButtons(.local) }
                    Section("Cloud") { presetButtons(.cloud) }
                    Section("Custom") { presetButtons(.custom) }
                }
                .fixedSize()
                Text("Apple Intelligence is always listed when this Mac supports it.").bvFont(.footnote).foregroundStyle(.bvSecondary)
            }
            .padding(.top, LayoutTokens.spacing[1])
        }
        .insightsCard()
        .sheet(item: $editing) { ConnectionSheet(model: model, draft: $0) }
    }

    @ViewBuilder
    private func presetButtons(_ group: ConnectionPreset.Group) -> some View {
        ForEach(ConnectionPreset.all.filter { $0.group == group }, id: \.name) { preset in
            Button(preset.name) {
                let connection = ModelConnection(
                    id: ModelConnection.newID(for: preset.kind), name: preset.name, kind: preset.kind,
                    baseURL: preset.baseURL, model: ""
                )
                editing = ConnectionDraft(connection: connection, isNew: true)
            }
        }
    }

    private func addressLine(_ c: ModelConnection) -> String {
        let address = ConnectionAddress.fixedURL(for: c.kind)?.absoluteString ?? c.baseURL
        return c.model.isEmpty ? address : "\(address) · \(c.model)"
    }

    private func keyState(_ c: ModelConnection) -> String {
        let local = ConnectionAddress.baseURL(for: c).map(ConnectionAddress.isLocal) ?? false
        let hasKey = !(model.credentials.read(c.credentialAccount) ?? "").isEmpty
        if hasKey { return "\(c.kind.isCloud ? "Cloud" : c.kind.title) · key saved" }
        return local ? "Local · no key needed" : "\(c.kind.isCloud ? "Cloud" : c.kind.title) · no key yet"
    }
}

struct ConnectionDraft: Identifiable {
    var id: String { connection.id }
    var connection: ModelConnection
    var isNew: Bool
}
