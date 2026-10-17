import AppKit
import SwiftUI
import VoiceCore

/// Settings › Agents: the MCP server switch, what agents may change, how to
/// connect Claude Code and Codex, and the calls made since launch.
struct AgentsSettings: View {
    @Bindable var model: AppModel
    @State private var copied: String?
    @State private var copiedReset: Task<Void, Never>?

    private var enabled: Bool { model.settings.agents.mcpEnabled }

    var body: some View {
        SettingsScroll {
            SettingsCard {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("MCP server").fontWeight(.semibold)
                        Text(
                            "Lets coding agents on this Mac, such as Claude Code and Codex, read and search your notes, meetings and dictations. Agents send what they read to their own model provider."
                        )
                        .font(.caption).foregroundStyle(.secondary)
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
                        Text("No agent has connected yet.").foregroundStyle(.secondary)
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
            if status.hasPrefix("Could not start") { (status, .orange) }
            else if !enabled { ("Off", .secondary) }
            else { (status, status == "Listening" ? .green : .secondary) }
        return HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).font(.caption).foregroundStyle(color == .secondary ? .secondary : .primary)
        }
        .padding(.top, 2)
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
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).fontWeight(.semibold)
                Spacer()
                Button(copied == title ? "Copied" : "Copy") { copy(text, as: title) }
            }
            if let caption { Text(caption).font(.caption).foregroundStyle(.secondary) }
            Text(text)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
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
                    Text(Self.timeFormat.string(from: entry.time)).monospacedDigit().foregroundStyle(.secondary)
                    Text(entry.client).foregroundStyle(.secondary)
                    Text(entry.tool).font(.system(.callout, design: .monospaced))
                    if let error = entry.error {
                        Text(error).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("OK").foregroundStyle(.green)
                    }
                }
            }
        }
        .font(.callout)
    }
}
