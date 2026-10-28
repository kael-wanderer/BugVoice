import AppKit
import SwiftUI
import VoiceCore

struct CLIsCard: View {
    @Environment(AppearanceStore.self) private var store
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Coding CLIs").bvFont(.bodyStrong)
                Spacer()
                Text("Run with their own login. BugVoice stores no key for them.").bvFont(.footnote).foregroundStyle(.bvSecondary)
            }
            .padding(.bottom, LayoutTokens.spacing[1])
            ForEach(CLITool.allCases, id: \.self) { tool in
                Divider()
                VStack(alignment: .leading, spacing: LayoutTokens.spacing[1]) {
                    Text(tool.rawValue).bvCode(.body).fontWeight(.semibold).frame(width: store.scaled(70), alignment: .leading)
                    if let info = model.cliInfo[tool] {
                        Text(info.version.isEmpty ? info.path : "\(info.path) · \(info.version)")
                            .bvCode(.footnote).foregroundStyle(.bvSecondary).lineLimit(1).truncationMode(.middle).help(info.path)
                        Text("Found · \(Self.isolation(tool))").bvFont(.footnote).foregroundStyle(.bvSecondary)
                        HStack(spacing: LayoutTokens.spacing[1]) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(store.theme.success).accessibilityHidden(true)
                            Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: info.path)]) }
                        }
                    } else {
                        Text("Not found").foregroundStyle(.bvSecondary)
                    }
                }
                .padding(.vertical, LayoutTokens.spacing[1])
            }
        }
        .insightsCard()
    }

    static func isolation(_ tool: CLITool) -> String {
        switch tool {
        case .claude: "tools and MCP servers turned off"
        case .codex: "read-only sandbox"
        case .pi: "extensions and tools turned off"
        }
    }
}
