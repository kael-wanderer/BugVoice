import SwiftUI
import VoiceCore

/// Top of Settings › General: each thing dictation needs, with a fix button.
struct ReadinessCard: View {
    @Environment(AppearanceStore.self) private var store
    @Bindable var model: AppModel

    var body: some View {
        let rows = model.readinessRows
        SettingsCard(title: Readiness.summary(rows)) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 { Divider() }
                HStack(alignment: .firstTextBaseline, spacing: LayoutTokens.spacing[2]) {
                    Circle().fill(color(row.tone)).frame(width: 9, height: 9)
                        .accessibilityLabel(label(row.tone))
                    VStack(alignment: .leading, spacing: 0) {
                        Text(row.title)
                        Text(row.detail).bvFont(.footnote).foregroundStyle(.bvSecondary).textSelection(.enabled)
                    }
                    Spacer(minLength: LayoutTokens.spacing[2])
                    if let action = row.action, let title = row.actionTitle {
                        Button(title) { model.runReadinessAction(action) }
                    }
                }
            }
        }
        // Check the cleanup connection once when the card first shows.
        .task {
            if let connection = model.dictationConnection, model.connectionStatus[connection.id] == nil {
                await model.testConnection(connection)
            }
        }
    }

    private func color(_ tone: ReadinessTone) -> Color {
        switch tone {
        case .ok: store.theme.success
        case .waiting: store.theme.secondaryText.opacity(0.5)
        case .problem: store.theme.warning
        case .off: store.theme.secondaryText.opacity(0.35)
        }
    }

    /// The dot's meaning for VoiceOver, since color alone carries it.
    private func label(_ tone: ReadinessTone) -> String {
        switch tone {
        case .ok: "Ready"
        case .waiting: "Not ready yet"
        case .problem: "Needs attention"
        case .off: "Off"
        }
    }
}
