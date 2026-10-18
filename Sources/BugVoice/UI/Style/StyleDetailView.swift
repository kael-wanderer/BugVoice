import AppKit
import SwiftUI
import VoiceCore

struct StyleDetailView: View {
    @Environment(AppearanceStore.self) private var store
    @Bindable var model: AppModel
    let style: Style

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutTokens.spacing[3]) {
            Text(style.title).bvFont(.title3)
            section("Apps and websites") {
                if style == .other { Text("Every app without a style uses Other.").foregroundStyle(.bvSecondary) }
                let entries = StyleApps.entries(for: style, overrides: model.settings.styles.appOverrides)
                if !entries.isEmpty { FlowLayout(spacing: LayoutTokens.spacing[0]) { ForEach(entries) { chip($0) } } }
                if style == .terminal {
                    Text("Also the terminal panel in VS Code and Cursor.").bvFont(.footnote).foregroundStyle(.bvSecondary)
                }
                if style != .other { Button { addApp() } label: { Label("Add app", systemImage: "plus") } }
            }
            Toggle("Clean up with the text model", isOn: Binding(
                get: { model.settings.styles.isCleanupEnabled(for: style) },
                set: { model.settings.styles.cleanupEnabled[style.rawValue] = $0 }
            ))
            section("Tone") {
                TextEditor(text: Binding(
                    get: { model.settings.styles.customRules[style.rawValue] ?? PromptBuilder.defaultRules(for: style) },
                    set: { model.settings.styles.customRules[style.rawValue] = $0 == PromptBuilder.defaultRules(for: style) ? nil : $0 }
                ))
                .bvFont(.body).frame(minHeight: 90)
                .overlay(RoundedRectangle(cornerRadius: LayoutTokens.controlRadius).strokeBorder(store.theme.separator))
                Button("Reset to default") { model.settings.styles.customRules[style.rawValue] = nil }
                    .disabled(model.settings.styles.customRules[style.rawValue] == nil)
            }
            section("Example") {
                let example = StyleExamples.example(for: style, hotkeyName: model.settings.hotkey.spokenName)
                Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 6) {
                    GridRow {
                        Text("You say").bvFont(.footnote).foregroundStyle(.bvSecondary)
                        Text(example.said).foregroundStyle(.bvSecondary)
                    }
                    GridRow {
                        Text("BugVoice writes").bvFont(.footnote).foregroundStyle(.bvSecondary)
                        Text(example.written)
                    }
                }
            }
        }
        .insightsCard()
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: LayoutTokens.spacing[1]) { Text(title).bvFont(.bodyStrong); content() }
    }

    @ViewBuilder
    private func chip(_ entry: StyleAppEntry) -> some View {
        if let bundleID = entry.bundleID {
            Menu {
                Menu("Move to…") {
                    ForEach(Style.allCases.filter { $0 != style }, id: \.self) { target in
                        Button(target.title) { move(bundleID, to: target) }
                    }
                }
                if entry.isOverride { Button("Reset") { model.settings.styles.appOverrides[bundleID] = nil } }
            } label: { Text(entry.name) }
                .menuStyle(.button).buttonStyle(.bordered).fixedSize()
        } else {
            Text(entry.name).bvFont(.body).padding(.horizontal, LayoutTokens.spacing[1]).padding(.vertical, LayoutTokens.spacing[0])
                .background(Capsule().fill(store.theme.text.opacity(0.07)))
        }
    }

    private func move(_ bundleID: String, to target: Style) {
        model.settings.styles.appOverrides[bundleID] = StyleRouter.defaultApps[bundleID] == target ? nil : target
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier else { return }
        move(id, to: style)
    }
}
