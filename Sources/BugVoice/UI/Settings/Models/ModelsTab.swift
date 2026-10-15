import SwiftUI
import VoiceCore

struct ModelsTab: View {
    @Bindable var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                UseForCard(model: model)
                ConnectionsCard(model: model)
                CLIsCard(model: model)
            }
            .padding(.vertical, 4)
        }
        .task {
            await model.refreshCLIs()
            for connection in model.settings.models.connections { await model.testConnection(connection) }
        }
    }
}

/// Green when the last test reached the server, orange when it failed, grey before a test.
struct StatusDot: View {
    let status: ConnectionStatus?

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 9, height: 9)
            .help(help)
    }

    private var color: Color {
        switch status {
        case .reachable: .green
        case .failed: .orange
        case nil: Color.secondary.opacity(0.35)
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
