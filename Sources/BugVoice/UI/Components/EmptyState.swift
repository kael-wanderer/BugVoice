import SwiftUI
import VoiceCore

struct EmptyState<Actions: View>: View {
    @Environment(AppearanceStore.self) private var store

    let title: String
    let systemImage: String
    let message: String?
    @ViewBuilder let actions: Actions

    init(
        _ title: String,
        systemImage: String,
        message: String? = nil,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.systemImage = systemImage
        self.message = message
        self.actions = actions()
    }

    init(_ title: String, systemImage: String, message: String? = nil) where Actions == EmptyView {
        self.title = title
        self.systemImage = systemImage
        self.message = message
        self.actions = EmptyView()
    }

    var body: some View {
        VStack(spacing: LayoutTokens.spacing[2]) {
            Image(systemName: systemImage)
                .bvFont(.title2)
                .foregroundStyle(.bvSecondary)
            Text(title)
                .bvFont(.title3)
                .multilineTextAlignment(.center)
            if let message {
                Text(message)
                    .bvFont(.body)
                    .foregroundStyle(.bvSecondary)
                    .multilineTextAlignment(.center)
            }
            actions
        }
        .frame(maxWidth: store.readingWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
