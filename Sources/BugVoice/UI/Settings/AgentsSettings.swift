import AppKit
import SwiftUI
import VoiceCore

/// Settings › Agents: the MCP server switch, what agents may change, how to
/// connect Claude Code and Codex, and the calls made since launch.
struct AgentsSettings: View {
    @Environment(AppearanceStore.self) private var store
    @Bindable var model: AppModel
    @State private var copied: String?
    @State private var copiedReset: Task<Void, Never>?

    private var enabled: Bool { model.settings.agents.mcpEnabled }

    var body: some View {
        SettingsScroll {
            SettingsCard {
                HStack(alignment: .top, spacing: LayoutTokens.spacing[2]) {
                    VStack(alignment: .leading, spacing: LayoutTokens.spacing[0]) {
                        Text("MCP server").fontWeight(.semibold)
                        Text(
                            "Lets coding agents on this Mac, such as Claude Code and Codex, read and search your notes, meetings and dictations. Agents send what they read to their own model provider."
                        )
                        .bvFont(.footnote).foregroundStyle(.bvSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        statusLine
                    }
                    Spacer(minLength: 16)
                    Toggle("MCP server", isOn: $model.settings.agents.mcpEnabled).labelsHidden().toggleStyle(.switch)
                }
                Divider()
                SettingsToggle(title: "Agents can create and edit notes", isOn: $model.settings.agents.allowNoteEdits)
                    .disabled(!enabled)
                    .opacity(enabled ? 1 : 0.45)
                Divider()
                SettingsToggle(title: "Agents can upload recordings", isOn: $model.settings.agents.allowUploads)
                    .disabled(!enabled)
                    .opacity(enabled ? 1 : 0.45)
            }
            if enabled {
                SettingsCard(title: "Set up an agent") {
                    setupRow("Claude Code", caption: nil, text: claudeCommand)
                    Divider()
                    setupRow("Codex", caption: "Add to ~/.codex/config.toml", text: codexConfig)
                }
                SettingsCard(title: "Recent activity") {
                    if model.mcp.activity.entries.isEmpty {
                        Text("No agent has connected yet.").foregroundStyle(.bvSecondary)
                    } else {
                        activityTable
                    }
                }
            }
        }
        .onDisappear { copiedReset?.cancel() }
    }

    // MARK: Status

    private var statusLine: some View {
        let status = model.mcp.status
        let (text, color): (String, Color) =
            if status.hasPrefix("Could not start") { (status, store.theme.warning) }
            else if !enabled { ("Off", .secondary) }
            else { (status, status == "Listening" ? store.theme.success : store.theme.secondaryText) }
        return HStack(spacing: LayoutTokens.spacing[0]) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).bvFont(.footnote).foregroundStyle(color == .secondary ? .secondary : .primary)
        }
        .padding(.top, LayoutTokens.spacing[0])
    }

    // MARK: Setup

    /// The running app's own bridge, so the commands are right for /Applications and the dev build.
    private var bridgePath: String {
        Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/bugvoice-mcp").path
    }

    private var claudeCommand: String {
        let path = bridgePath.contains(" ") ? "'\(bridgePath)'" : bridgePath
        return "claude mcp add bugvoice -- \(path)"
    }

    private var codexConfig: String {
        """
        [mcp_servers.bugvoice]
        command = "\(bridgePath)"
        tool_timeout_sec = 300
        """
    }

    private func setupRow(_ title: String, caption: String?, text: String) -> some View {
        VStack(alignment: .leading, spacing: LayoutTokens.spacing[0]) {
            HStack {
                Text(title).fontWeight(.semibold)
                Spacer()
                Button(copied == title ? "Copied" : "Copy") { copy(text, as: title) }
            }
            if let caption { Text(caption).bvFont(.footnote).foregroundStyle(.bvSecondary) }
            Text(text)
                .bvCode(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(LayoutTokens.spacing[1])
                .background(store.theme.background, in: RoundedRectangle(cornerRadius: LayoutTokens.controlRadius))
        }
    }

    private func copy(_ text: String, as title: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = title
        copiedReset?.cancel()
        copiedReset = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            copied = nil
        }
    }

    // MARK: Activity

    private static let timeFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f
    }()

    private var activityTable: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
            ForEach(Array(model.mcp.activity.entries.enumerated()), id: \.offset) { _, entry in
                GridRow {
                    Text(Self.timeFormat.string(from: entry.time)).monospacedDigit().foregroundStyle(.bvSecondary)
                    Text(entry.client).foregroundStyle(.bvSecondary)
                    Text(entry.tool).bvCode(.body)
                    if let error = entry.error {
                        Text(error).foregroundStyle(.bvWarning).fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("OK").foregroundStyle(.bvSuccess)
                    }
                }
            }
        }
        .bvFont(.body)
    }
}
