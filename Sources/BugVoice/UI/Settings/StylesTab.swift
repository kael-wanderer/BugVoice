import AppKit
import SwiftUI
import VoiceCore

struct StylesTab: View {
    @Bindable var model: AppModel
    @State private var editing: Style = .document

    var body: some View {
        Form {
            Section("Clean up with the text model") {
                ForEach(Style.allCases, id: \.self) { style in
                    Toggle(style.rawValue.capitalized, isOn: Binding(
                        get: { model.settings.styles.isCleanupEnabled(for: style) },
                        set: { model.settings.styles.cleanupEnabled[style.rawValue] = $0 }
                    ))
                }
            }
            Section("App overrides") {
                ForEach(model.settings.styles.appOverrides.keys.sorted(), id: \.self) { bundleID in
                    HStack {
                        Text(bundleID).font(.system(.body, design: .monospaced))
                        Spacer()
                        Picker("", selection: Binding(
                            get: { model.settings.styles.appOverrides[bundleID] ?? .other },
                            set: { model.settings.styles.appOverrides[bundleID] = $0 }
                        )) { ForEach(Style.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }
                        .labelsHidden().frame(width: 140)
                        Button("Remove") { model.settings.styles.appOverrides[bundleID] = nil }
                    }
                }
                Button("Add app override…") { addOverride() }
            }
            Section("Rules") {
                Picker("Style", selection: $editing) {
                    ForEach(Style.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                .pickerStyle(.segmented)
                TextEditor(text: Binding(
                    get: { model.settings.styles.customRules[editing.rawValue] ?? PromptBuilder.defaultRules(for: editing) },
                    set: { model.settings.styles.customRules[editing.rawValue] = $0 == PromptBuilder.defaultRules(for: editing) ? nil : $0 }
                ))
                .font(.system(.callout, design: .monospaced))
                .frame(minHeight: 80)
                Button("Reset to default") { model.settings.styles.customRules[editing.rawValue] = nil }
                Text(PromptBuilder(customRules: model.settings.styles.customRules).systemPrompt(style: editing, vocabulary: model.vocabulary, focus: .unknown))
                    .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
    }

    func addOverride() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier else { return }
        model.settings.styles.appOverrides[id] = StyleRouter.defaultApps[id] ?? .document
    }
}
