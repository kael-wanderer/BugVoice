import SwiftUI
import VoiceCore

struct CLIsCard: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Coding CLIs").font(.headline)
                Spacer()
                Text("Run with their own login. BugVoice stores no key for them.").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.bottom, 8)
            ForEach(CLITool.allCases, id: \.self) { tool in
                Divider()
                HStack(spacing: 12) {
                    Text(tool.rawValue).font(.system(.body, design: .monospaced)).fontWeight(.semibold).frame(width: 70, alignment: .leading)
                    if let info = model.cliInfo[tool] {
                        Text(info.version.isEmpty ? info.path : "\(info.path) · \(info.version)")
                            .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
                        Spacer()
                        StatusDot(status: .reachable(models: []))
                        Text("Found · \(Self.isolation(tool))").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Not found").foregroundStyle(.secondary)
                        Spacer()
                    }
                }
                .padding(.vertical, 8)
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
