import AppKit
import SwiftUI
import VoiceCore

/// The in-place submenus of the popover: Library, Dictation options and Tools.
struct MenuSubmenuView: View {
    let model: AppModel
    let submenu: MenuSubmenu
    let highlight: MenuHighlight
    let back: () -> Void
    let close: () -> Void

    var body: some View {
        header
        switch submenu {
        case .library: library
        case .dictationOptions: dictationOptions
        case .tools: tools
        }
    }

    private var header: some View {
        HStack(spacing: LayoutTokens.spacing[1]) {
            Button(action: back) {
                Text("‹ Back").bvFont(.body).foregroundStyle(.bvAccent).fixedSize()
                    .padding(.horizontal, LayoutTokens.spacing[1]).padding(.vertical, LayoutTokens.spacing[0] / 2)
                    .background(highlight.isOn(.back) ? AnyShapeStyle(.bvHover) : AnyShapeStyle(.clear),
                                in: RoundedRectangle(cornerRadius: LayoutTokens.controlRadius))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover(perform: highlight.hover(.back))
            Text(title).bvFont(.bodyStrong)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, LayoutTokens.spacing[0])
        .padding(.vertical, LayoutTokens.spacing[0])
    }

    private var title: String {
        switch submenu {
        case .library: "Library"
        case .dictationOptions: "Dictation options"
        case .tools: "Tools"
        }
    }

    // MARK: Library

    @ViewBuilder private var library: some View {
        row("meetings", "Meetings") {
            close()
            model.openMainWindow(.meetings)
        }
        row("scratchpad", "Scratchpad") {
            close()
            model.openMainWindow(.notes)
        }
        row("floating", "Floating scratchpad", hint: "⌃⌥\(model.settings.shortcuts.letter(for: .newNote))") {
            close()
            Task { await model.openScratchpadWindow(newNote: false) }
        }
    }

    // MARK: Tools

    @ViewBuilder private var tools: some View {
        row("permissions", "Permissions…") {
            close()
            model.openPermissionsWindow()
        }
        row("dataFolder", "Open data folder") {
            close()
            NSWorkspace.shared.open(model.paths.root)
        }
    }

    // MARK: Dictation options

    @ViewBuilder private var dictationOptions: some View {
        @Bindable var model = model
        MenuSwitchRow(title: "Clean up with the text model", isOn: $model.settings.cleanupEnabled,
                      highlighted: highlight.isOn(.item("cleanup")),
                      onHover: highlight.hover(.item("cleanup")))
        MenuSwitchRow(title: "Hands-free (double-tap the hotkey)", isOn: $model.settings.handsFreeEnabled,
                      highlighted: highlight.isOn(.item("handsFree")),
                      onHover: highlight.hover(.item("handsFree")))
        MenuGroupHeader(title: "Language")
        language("lang.auto", "Auto", .auto)
        language("lang.vi", "Vietnamese", .vi)
        language("lang.en", "English", .en)
        MenuGroupHeader(title: "Text model")
        ForEach(model.settings.models.connections) { connection in
            engine("engine.\(connection.id)", connection.name, .connection(connection.id))
        }
        if model.appleIntelligenceAvailable {
            engine("engine.apple", "Apple Intelligence", .appleIntelligence)
        }
        engine("engine.none", "None", .none)
    }

    private func language(_ id: String, _ title: String, _ value: SpeechLanguage) -> some View {
        MenuCheckRow(title: title, checked: model.settings.speech.language == value,
                     highlighted: highlight.isOn(.item(id)), onHover: highlight.hover(.item(id))) {
            model.settings.speech.language = value
        }
    }

    private func engine(_ id: String, _ title: String, _ value: ModelEngine) -> some View {
        MenuCheckRow(title: title, checked: model.settings.models.dictation.engine == value,
                     highlighted: highlight.isOn(.item(id)), onHover: highlight.hover(.item(id))) {
            model.settings.models.dictation.engine = value
        }
    }

    private func row(_ id: String, _ title: String, hint: String? = nil,
                     action: @escaping () -> Void) -> some View {
        MenuRow(title: title, hint: hint, highlighted: highlight.isOn(.item(id)),
                onHover: highlight.hover(.item(id)), action: action)
    }
}
