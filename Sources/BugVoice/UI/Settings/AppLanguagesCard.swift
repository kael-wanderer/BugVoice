import AppKit
import SwiftUI
import UniformTypeIdentifiers
import VoiceCore

struct AppLanguagesCard: View {
    @Bindable var model: AppModel
    @State private var showingWebsite = false
    @State private var website = ""
    @State private var websiteLanguage: SpeechLanguage = .vi

    /// New rules start on a ticked dictation language.
    private func newRuleLanguage(preferred: SpeechLanguage) -> SpeechLanguage {
        DictationLanguages.newRuleLanguage(preferred: preferred, in: model.settings.speech.dictationLanguages)
    }

    private var runningApps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .filter { $0.bundleIdentifier != nil }
            .sorted { ($0.localizedName ?? $0.bundleIdentifier ?? "") < ($1.localizedName ?? $1.bundleIdentifier ?? "") }
    }

    var body: some View {
        SettingsCard(title: "Language per app") {
            ForEach(model.settings.speech.appLanguages, id: \.key) { rule in
                HStack(spacing: LayoutTokens.spacing[1]) {
                    if let icon = icon(for: rule) {
                        Image(nsImage: icon).resizable().frame(width: 20, height: 20)
                    }
                    Text(name(for: rule)).lineLimit(1)
                    Spacer(minLength: LayoutTokens.spacing[1])
                    Picker("Language", selection: Binding(
                        get: { rule.language },
                        set: { language in
                            guard let index = model.settings.speech.appLanguages.firstIndex(where: { $0.key == rule.key }) else { return }
                            model.settings.speech.appLanguages[index].language = language
                        }
                    )) {
                        ForEach(pickerLanguages(keeping: rule.language), id: \.self) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                    .labelsHidden().fixedSize()
                    Button {
                        model.settings.speech.appLanguages.removeAll { $0.key == rule.key }
                    } label: {
                        Image(systemName: "xmark").bvFont(.footnote).foregroundStyle(.bvSecondary)
                    }
                    .buttonStyle(.plain).accessibilityLabel("Remove \(name(for: rule))")
                }
            }
            HStack {
                Menu {
                    ForEach(runningApps, id: \.processIdentifier) { app in
                        Button(app.localizedName ?? app.bundleIdentifier ?? "App") {
                            if let id = app.bundleIdentifier { add(kind: .app, id: id, language: newRuleLanguage(preferred: .en)) }
                        }
                    }
                    Divider()
                    Button("Choose app…", action: chooseApp)
                } label: {
                    Text("Add app…")
                }
                .fixedSize()
                Button("Add website…") {
                    websiteLanguage = newRuleLanguage(preferred: .vi)
                    showingWebsite = true
                }
            }
            Text("Apps not listed use Auto. The language switch overrides this list.")
                .bvFont(.footnote).foregroundStyle(.bvSecondary)
        }
        .sheet(isPresented: $showingWebsite) {
            VStack(alignment: .leading, spacing: LayoutTokens.spacing[2]) {
                Text("Add website").bvFont(.bodyStrong)
                TextField("chatgpt.com", text: $website)
                    .textFieldStyle(.roundedBorder)
                Picker("Language", selection: $websiteLanguage) {
                    ForEach(pickerLanguages(keeping: websiteLanguage), id: \.self) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                HStack {
                    Spacer()
                    Button("Cancel") { showingWebsite = false }
                    Button("Add") {
                        if let host = Self.normalizedHost(website) {
                            add(kind: .website, id: host, language: websiteLanguage)
                            website = ""
                            showingWebsite = false
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(LayoutTokens.spacing[3])
            .frame(width: 360)
        }
    }

    /// The ticked dictation languages, plus `language` when a rule still uses one that is no longer ticked.
    private func pickerLanguages(keeping language: SpeechLanguage) -> [SpeechLanguage] {
        let ticked = model.settings.speech.dictationLanguages
        return ticked.contains(language) ? ticked : DictationLanguages.choices.filter { ticked.contains($0) || $0 == language }
    }

    private func add(kind: AppLanguageRule.Kind, id: String, language: SpeechLanguage) {
        guard !model.settings.speech.appLanguages.contains(where: { $0.kind == kind && $0.id == id }) else { return }
        model.settings.speech.appLanguages.append(AppLanguageRule(kind: kind, id: id, language: language))
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK, let url = panel.url,
              let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { return }
        add(kind: .app, id: id, language: newRuleLanguage(preferred: .en))
    }

    private func name(for rule: AppLanguageRule) -> String {
        switch rule.kind {
        case .website: return rule.id
        case .terminalPanel:
            return rule.id == "com.microsoft.VSCode" || rule.id == "com.microsoft.VSCodeInsiders" ? "VS Code terminal" : "Cursor terminal"
        case .app:
            if let running = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == rule.id }),
               let name = running.localizedName { return name }
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: rule.id),
               let name = Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String { return name }
            return Self.knownNames[rule.id] ?? rule.id
        }
    }

    /// Names for default entries whose app is not installed.
    private static let knownNames = [
        "com.googlecode.iterm2": "iTerm2",
        "dev.warp.Warp-Stable": "Warp",
        "com.stablyai.orca": "Orca",
        "com.mitchellh.ghostty": "Ghostty",
        "com.anthropic.claudefordesktop": "Claude",
    ]

    private func icon(for rule: AppLanguageRule) -> NSImage? {
        guard rule.kind != .website,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: rule.id) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    private static func normalizedHost(_ value: String) -> String? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        let address = value.contains("://") ? value : "https://" + value
        guard let host = URLComponents(string: address)?.host?.lowercased() else { return nil }
        let trimmed = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension AppLanguageRule {
    /// Rows are keyed by kind and ID; `add` keeps that pair unique.
    var key: String { "\(kind.rawValue):\(id)" }
}
