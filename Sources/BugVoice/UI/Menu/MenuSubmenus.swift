import AppKit
import SwiftUI
import VoiceCore

/// The in-place submenus of the popover: Library, Dictation options and Tools.
struct MenuSubmenuView: View {
    let model: AppModel
    let submenu: MenuSubmenu
    let highlight: MenuHighlight

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
            Button(action: highlight.action(.back)) {
                Text("‹ Back").bvFont(.body).foregroundStyle(.bvAccent).fixedSize()
                    .padding(.horizontal, LayoutTokens.spacing[1]).padding(.vertical, LayoutTokens.spacing[0] / 2)
                    .background(highlight.isOn(.back) ? AnyShapeStyle(.bvHover) : AnyShapeStyle(.clear),
                                in: RoundedRectangle(cornerRadius: LayoutTokens.controlRadius))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover(perform: highlight.hover(.back))
            .accessibilityLabel("Back")
            .id(MenuControl.back)
            Text(submenu.title).bvFont(.bodyStrong).accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, LayoutTokens.spacing[0])
        .padding(.vertical, LayoutTokens.spacing[0])
    }

    // MARK: Library

    @ViewBuilder private var library: some View {
        row("meetings", "Meetings")
        row("scratchpad", "Scratchpad")
        row("floating", "Floating scratchpad", hint: "⌃⌥\(model.settings.shortcuts.letter(for: .newNote))")
    }

    // MARK: Tools

    @ViewBuilder private var tools: some View {
        row("permissions", "Permissions…")
        row("dataFolder", "Open data folder")
    }

    // MARK: Dictation options

    @ViewBuilder private var dictationOptions: some View {
        MenuSwitchRow(id: .item("cleanup"), title: "Clean up with the text model",
                      isOn: model.settings.cleanupEnabled, highlight: highlight)
        MenuSwitchRow(id: .item("handsFree"), title: "Hands-free (double-tap the hotkey)",
                      isOn: model.settings.handsFreeEnabled, highlight: highlight)
        MenuGroupHeader(title: "Language")
        ForEach(MenuSubmenuItems.languages(for: model), id: \.id) { language in
            MenuCheckRow(id: .item(language.id), title: language.title,
                         checked: model.settings.speech.language == language.value, highlight: highlight)
        }
        MenuGroupHeader(title: "Text model")
        ForEach(MenuSubmenuItems.engines(for: model), id: \.id) { engine in
            MenuCheckRow(id: .item(engine.id), title: engine.title,
                         checked: model.settings.models.dictation.engine == engine.value, highlight: highlight)
        }
    }

    private func row(_ id: String, _ title: String, hint: String? = nil) -> some View {
        MenuRow(id: .item(id), title: title, hint: hint, highlight: highlight)
    }
}

extension MenuSubmenu {
    var title: String {
        switch self {
        case .library: "Library"
        case .dictationOptions: "Dictation options"
        case .tools: "Tools"
        }
    }
}

/// Row ids and actions of the submenus, shared by clicks and the keyboard.
@MainActor
struct MenuSubmenuItems {
    let model: AppModel
    let close: () -> Void

    /// Auto, then the dictation languages in the Settings order (Vietnamese, English, Spanish).
    static func languages(for model: AppModel) -> [(id: String, title: String, value: SpeechLanguage)] {
        [("lang.auto", "Auto", .auto)] + DictationLanguages.settingsOrder(model.settings.speech.dictationLanguages)
            .map { ("lang.\($0.rawValue)", $0.displayName, $0) }
    }

    static func engines(for model: AppModel) -> [(id: String, title: String, value: ModelEngine)] {
        model.settings.models.connections.map { ("engine.\($0.id)", $0.name, .connection($0.id)) }
            + (model.appleIntelligenceAvailable ? [("engine.apple", "Apple Intelligence", .appleIntelligence)] : [])
            + [("engine.none", "None", .none)]
    }

    /// The rows of `submenu` in reading order, without Back.
    func ids(_ submenu: MenuSubmenu) -> [String] {
        switch submenu {
        case .library: ["meetings", "scratchpad", "floating"]
        case .tools: ["permissions", "dataFolder"]
        case .dictationOptions: ["cleanup", "handsFree"] + Self.languages(for: model).map(\.id) + Self.engines(for: model).map(\.id)
        }
    }

    func run(_ id: String) {
        switch id {
        case "meetings":
            close()
            model.openMainWindow(.meetings)
        case "scratchpad":
            close()
            model.openMainWindow(.notes)
        case "floating":
            close()
            Task { await model.openScratchpadWindow(newNote: false) }
        case "permissions":
            close()
            model.openPermissionsWindow()
        case "dataFolder":
            close()
            NSWorkspace.shared.open(model.paths.root)
        case "cleanup":
            model.settings.cleanupEnabled.toggle()
        case "handsFree":
            model.settings.handsFreeEnabled.toggle()
        default:
            if let language = Self.languages(for: model).first(where: { $0.id == id }) {
                model.settings.speech.language = language.value
            } else if let engine = Self.engines(for: model).first(where: { $0.id == id }) {
                model.settings.models.dictation.engine = engine.value
            }
        }
    }
}
