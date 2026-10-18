import SwiftUI
import VoiceCore

struct ComingSoonPage: View {
    @Environment(AppearanceStore.self) private var store
    let page: Page
    @Bindable var model: AppModel

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                Spacer().frame(height: proxy.size.height / 3)
                VStack(spacing: LayoutTokens.spacing[2]) {
                    Text(page.title).bvFont(.title2)
                    description
                        .bvFont(.body)
                        .foregroundStyle(.bvSecondary)
                        .multilineTextAlignment(.center)
                    Text("Coming soon")
                        .bvFont(.footnote)
                        .padding(.horizontal, LayoutTokens.spacing[2])
                        .padding(.vertical, LayoutTokens.spacing[0])
                        .background(.bvAccentSoft, in: Capsule())
                }
                .frame(maxWidth: store.readingWidth)
                .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    @ViewBuilder private var description: some View {
        switch page {
        case .integrations:
            VStack(spacing: 0) {
                Text("Calendar, export to Apple Notes and Notion, and the MCP server will live here.")
                HStack(spacing: 0) {
                    Text("The MCP server is in ")
                    Button("Settings › Agents") {
                        model.settingsTab = .agents
                        model.page = .settings
                    }
                    .buttonStyle(.link)
                    Text(" for now.")
                }
            }
        case .help:
            Text("Guides for getting started, shortcuts, styles, meetings, and coding agents, readable offline.")
        default:
            EmptyView()
        }
    }
}
