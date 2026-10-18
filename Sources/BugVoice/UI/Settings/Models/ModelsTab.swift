import SwiftUI
import VoiceCore

struct ModelsTab: View {
    @Environment(AppearanceStore.self) private var store
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutTokens.spacing[3]) {
            VStack(alignment: .leading, spacing: LayoutTokens.spacing[3]) {
                UseForCard(model: model)
                ConnectionsCard(model: model)
                SearchCard(model: model)
                CLIsCard(model: model)
            }
            .padding(.vertical, LayoutTokens.spacing[0])
        }
        .task {
            await model.refreshCLIs()
            for connection in model.settings.models.connections { await model.testConnection(connection) }
        }
    }
}

/// Green when the last test reached the server, orange when it failed, grey before a test.
struct StatusDot: View {
    @Environment(AppearanceStore.self) private var store
    let status: ConnectionStatus?

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 9, height: 9)
            .help(help)
    }

    private var color: Color {
        switch status {
        case .reachable: store.theme.success
        case .failed: store.theme.warning
        case nil: store.theme.secondaryText.opacity(0.35)
        }
    }

    private var help: String {
        switch status {
        case .reachable(let models): models.count == 1 ? "Reachable · 1 model" : "Reachable · \(models.count) models"
        case .failed(let message): message
        case nil: "Not tested"
        }
    }
}
