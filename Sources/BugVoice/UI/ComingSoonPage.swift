import SwiftUI
import VoiceCore

struct ComingSoonPage: View {
    let page: Page
    @Bindable var model: AppModel

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: LayoutTokens.spacing[2]) {
                    Text(page.title).bvFont(.title2)
                    Text(description).bvFont(.body).foregroundStyle(.bvSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Coming soon").bvFont(.footnote)
                        .padding(.horizontal, LayoutTokens.spacing[2]).padding(.vertical, LayoutTokens.spacing[0])
                        .background(.bvAccentSoft, in: Capsule())
                }
                .padding(.top, max(0, proxy.size.height / 3 - LayoutTokens.spacing[5]))
                .bvPageColumn(.wide)
            }
        }
        .environment(\.openURL, OpenURLAction { url in
            guard url.absoluteString == "bugvoice://settings/agents" else { return .discarded }
            model.settingsTab = .agents
            model.page = .settings
            return .handled
        })
    }
    private var description: AttributedString {
        if page == .integrations {
            var text = AttributedString("Calendar, export to Apple Notes and Notion, and the MCP server will live here. The MCP server is in ")
            var link = AttributedString("Settings › Agents")
            link.link = URL(string: "bugvoice://settings/agents")
            text += link
            text += AttributedString(" for now.")
            return text
        }
        return AttributedString("Guides for getting started, shortcuts, styles, meetings, and coding agents, readable offline.")
    }
}
