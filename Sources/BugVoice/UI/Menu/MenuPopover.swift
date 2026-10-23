import AppKit
import BugVoiceMac
import SwiftUI
import VoiceCore
import WhisperEngine

enum MenuSubmenu: Hashable { case library, dictationOptions, tools }

/// Every highlightable control in the popover.
enum MenuControl: Hashable, Sendable {
    case statusAction, meetingPause, meetingMark, meetingStop
    case newNote, meeting, upload, pasteLast, copyLast, retryLast, rawLast, redoLast
    case suggestions
    case submenu(MenuSubmenu), openApp, settings, quit
    case back, item(String)
}

/// How a control asks whether it is highlighted, reports hover and runs its action.
struct MenuHighlight {
    let isOn: (MenuControl) -> Bool
    let set: (MenuControl, Bool) -> Void
    let activate: (MenuControl) -> Void

    func hover(_ id: MenuControl) -> (Bool) -> Void { { set(id, $0) } }
    func action(_ id: MenuControl) -> () -> Void { { activate(id) } }
}

/// The menu bar popover (spec: docs/superpowers/specs/2026-10-18-menu-popover-design.md).
struct MenuPopover: View {
    let model: AppModel
    let maxHeight: CGFloat
    let close: () -> Void
    @State private var submenu: MenuSubmenu?
    @State private var nav = MenuNavigator<MenuControl>()
    @State private var contentHeight: CGFloat = 0
    @FocusState private var focused: Bool

    init(model: AppModel, maxHeight: CGFloat, close: @escaping () -> Void) {
        self.model = model
        self.maxHeight = maxHeight
        self.close = close
    }

    var body: some View {
        let radius = LayoutTokens.largeCardRadius
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    if let submenu {
                        MenuSubmenuView(model: model, submenu: submenu, highlight: highlight)
                    } else {
                        mainList
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(LayoutTokens.spacing[1])
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { contentHeight = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            .onChange(of: nav.highlighted) { _, id in
                if let id { proxy.scrollTo(id) }
            }
        }
        .frame(width: 330, height: min(contentHeight, maxHeight))
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        .onKeyPress(phases: .down, action: handleKey)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(submenu?.title ?? "BugVoice menu")
        .background(.bvCard, in: RoundedRectangle(cornerRadius: radius))
        .overlay(RoundedRectangle(cornerRadius: radius).stroke(.bvSeparator, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: radius))
    }

    private var highlight: MenuHighlight {
        MenuHighlight(isOn: { nav.highlighted == $0 }, set: { id, inside in
            if inside { nav.hover(id) } else if nav.highlighted == id { nav.clear() }
        }, activate: activate)
    }

    private var items: MenuSubmenuItems { MenuSubmenuItems(model: model, close: close) }

    private var hasLast: Bool { !(model.lastResult?.finalText.isEmpty ?? true) }

    private var meetingRunning: Bool { model.meetings?.isRecording == true || model.meetings?.isPaused == true }

    /// The enabled controls of the visible list, in reading order.
    func controls() -> [MenuControl] {
        if let submenu { return [.back] + items.ids(submenu).map(MenuControl.item) }
        var ids: [MenuControl] = []
        if status.action != nil { ids.append(.statusAction) }
        if meetingRunning, model.meetings?.isTranscribing != true { ids += [.meetingPause, .meetingMark, .meetingStop] }
        ids.append(.newNote)
        if meetingRunning || model.meetings?.isTranscribing != true { ids.append(.meeting) }
        ids.append(.upload)
        if hasLast {
            ids += model.lastResult?.command != nil
                ? [.pasteLast, .copyLast, .rawLast]
                : [.pasteLast, .copyLast, .retryLast, .rawLast, .redoLast]
        }
        if !model.suggestions.pending.isEmpty { ids.append(.suggestions) }
        ids += [.submenu(.library), .submenu(.dictationOptions), .openApp, .settings, .submenu(.tools), .quit]
        return ids
    }

    /// Runs the same action as a click on `control`.
    func activate(_ control: MenuControl) {
        switch control {
        case .suggestions:
            close()
            model.dictionaryTab = .words
            model.openMainWindow(.dictionary)
        case .statusAction:
            if let action = status.action { runStatusAction(action) }
        case .meetingPause:
            guard let meetings = model.meetings else { return }
            Task { if meetings.isPaused { await meetings.resume() } else { await meetings.pause() } }
        case .meetingMark:
            guard let meetings = model.meetings else { return }
            Task { await meetings.mark() }
        case .meetingStop:
            close()
            Task { await model.meetings?.stop() }
        case .newNote:
            close()
            Task { await model.openScratchpadWindow(newNote: true) }
        case .meeting:
            close()
            if meetingRunning {
                Task { await model.meetings?.stop() }
            } else {
                Task { await model.meetings?.start() }
            }
        case .upload:
            close()
            model.openMainWindow(.upload)
        case .pasteLast:
            close()
            Task {
                try? await Task.sleep(for: .milliseconds(60))
                model.dictation?.pasteLast()
            }
        case .copyLast:
            guard let text = model.lastResult?.finalText else { return }
            close()
            model.dictation?.copy(text)
        case .retryLast:
            close()
            model.dictation?.retryLast()
        case .rawLast:
            close()
            model.dictation?.pasteRaw()
        case .redoLast:
            close()
            model.dictation?.redoInOtherLanguage()
        case .submenu(let target):
            submenu = target
            nav.clear()
        case .openApp:
            close()
            model.openMainWindow(.dictation)
        case .settings:
            close()
            model.openMainWindow(.settings)
        case .quit:
            NSApp.terminate(nil)
        case .back:
            guard let current = submenu else { return }
            submenu = nil
            nav.hover(.submenu(current))
        case .item(let id):
            items.run(id)
        }
    }

    // MARK: Keys

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        // The panel never activates BugVoice, so the main menu's ⌘, and ⌘Q may not fire.
        if press.modifiers.contains(.command) {
            switch press.key.character.lowercased() {
            case ",": activate(.settings)
            case "q": activate(.quit)
            default: return .ignored
            }
            return .handled
        }
        switch press.key {
        case .downArrow: nav.next(in: controls())
        case .upArrow: nav.previous(in: controls())
        case .tab:
            if press.modifiers.contains(.shift) { nav.previous(in: controls()) } else { nav.next(in: controls()) }
        case .return, .space:
            guard let current = nav.highlighted, controls().contains(current) else { return .handled }
            activate(current)
        case .rightArrow:
            guard case .submenu(let target)? = nav.highlighted else { return .ignored }
            submenu = target
            if let first = items.ids(target).first { nav.hover(.item(first)) } else { nav.hover(.back) }
        case .leftArrow:
            guard submenu != nil else { return .ignored }
            activate(.back)
        case .escape:
            if submenu != nil { activate(.back) } else { close() }
        default:
            // Shift-Tab arrives as back-tab (U+0019) on macOS.
            guard press.characters == "\u{19}" else { return .ignored }
            nav.previous(in: controls())
        }
        return .handled
    }

    // MARK: Main list

    @ViewBuilder private var mainList: some View {
        MenuStatusLine(status: status, hotkey: model.settings.hotkey.displayName,
                       spokenHotkey: model.settings.hotkey.spokenName,
                       unavailableShortcuts: model.unavailableShortcuts, highlight: highlight)
        if let meetings = model.meetings, meetings.isRecording || meetings.isPaused || meetings.isTranscribing {
            MenuMeetingStrip(meetings: meetings, highlight: highlight)
        }
        MenuActionGrid(model: model, highlight: highlight)
        if model.settings.speech.showLanguageSwitch {
            HStack {
                Text("Language").bvFont(.body)
                Spacer()
                Picker("Language", selection: Binding(
                    get: { model.settings.speech.language },
                    set: { model.settings.speech.language = $0 }
                )) {
                    Text("Auto").tag(SpeechLanguage.auto)
                    ForEach(model.settings.speech.dictationLanguages, id: \.self) { language in
                        Text(language.shortCode).tag(language)
                    }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
            }
            .padding(.horizontal, LayoutTokens.spacing[1])
            .padding(.bottom, LayoutTokens.spacing[0])
        }
        MenuSeparator()
        if let last = model.lastResult, !last.finalText.isEmpty {
            MenuLastDictation(
                result: last,
                redoLanguage: (model.redoChain ?? RedoChain(original: last.language)).peek(languages: model.settings.speech.dictationLanguages),
                shortcuts: model.settings.shortcuts, highlight: highlight
            )
            MenuSeparator()
        }
        if !model.suggestions.pending.isEmpty {
            MenuRow(id: .suggestions, title: "Dictionary suggestions", hint: "›",
                    badge: model.suggestions.pending.count, highlight: highlight)
            MenuSeparator()
        }
        MenuSubmenuRow(submenu: .library, icon: "books.vertical", title: "Library", highlight: highlight)
        MenuSubmenuRow(submenu: .dictationOptions, icon: "mic", title: "Dictation options", highlight: highlight)
        MenuSeparator()
        MenuRow(id: .openApp, icon: "macwindow", title: "Open BugVoice",
                hint: "⌃⌥\(model.settings.shortcuts.letter(for: .openApp))", highlight: highlight)
        MenuRow(id: .settings, icon: "gearshape", title: "Settings…", hint: "⌘,", highlight: highlight)
        MenuSubmenuRow(submenu: .tools, title: "Tools", highlight: highlight)
        MenuRow(id: .quit, title: "Quit BugVoice", hint: "⌘Q", highlight: highlight)
    }

    // MARK: Status

    private var status: MenuStatus {
        let names: [(PermissionKind, String)] = [
            (.microphone, "Microphone"), (.accessibility, "Accessibility"), (.inputMonitoring, "Input Monitoring"),
        ]
        let missing = names.filter { model.permissionStatus[$0.0] == false }.map(\.1)
        let secureApp = SecureInputMonitor.isActive ? (SecureInputMonitor.owningAppName ?? "another app") : nil
        let meetings = model.meetings
        let meeting: MenuMeetingState =
            meetings?.isRecording == true ? .recording
            : meetings?.isPaused == true ? .paused
            : meetings?.isTranscribing == true ? .transcribing : .idle
        return MenuStatus.resolve(missingPermissions: missing, secureInputApp: secureApp,
                                  listening: model.isListening, speech: speech,
                                  hotkeyActive: model.hotkeyActive, meeting: meeting)
    }

    /// The speech model matters only while on-device transcription is selected.
    private var speech: MenuSpeechState {
        guard model.settings.speech.engine == .whisperKit else { return .ready }
        switch model.speechState {
        case .downloading(let fraction): return .downloading(fraction)
        case .loading: return .loading
        case .failed: return .failed
        case .notLoaded, .ready: return .ready
        }
    }

    private func runStatusAction(_ action: MenuStatusAction) {
        switch action {
        case .fixPermissions:
            close()
            model.openPermissionsWindow()
        case .retrySpeech:
            model.retrySpeech()
        case .fixHotkey:
            close()
            model.dictation?.retryHotkey()
            if !Permissions.isGranted(.inputMonitoring) { model.openPermissionsWindow() }
        }
    }
}
