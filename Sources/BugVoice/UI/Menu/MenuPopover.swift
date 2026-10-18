import AppKit
import BugVoiceMac
import SwiftUI
import VoiceCore
import WhisperEngine

enum MenuSubmenu: Hashable { case library, dictationOptions, tools }

/// Every highlightable control in the popover.
enum MenuControl: Hashable, Sendable {
    case statusAction, meetingPause, meetingMark, meetingStop
    case newNote, meeting, upload, pasteLast, copyLast, retryLast
    case submenu(MenuSubmenu), openApp, settings, quit
    case back, item(String)
}

/// How a control asks whether it is highlighted and reports hover.
struct MenuHighlight {
    let isOn: (MenuControl) -> Bool
    let set: (MenuControl, Bool) -> Void

    func hover(_ id: MenuControl) -> (Bool) -> Void { { set(id, $0) } }
}

/// The menu bar popover (spec: docs/superpowers/specs/2026-10-18-menu-popover-design.md).
struct MenuPopover: View {
    @Environment(AppearanceStore.self) private var store
    let model: AppModel
    let maxHeight: CGFloat
    let close: () -> Void
    @State private var submenu: MenuSubmenu?
    @State private var nav = MenuNavigator<MenuControl>()
    @State private var contentHeight: CGFloat = 0

    init(model: AppModel, maxHeight: CGFloat, close: @escaping () -> Void) {
        self.model = model
        self.maxHeight = maxHeight
        self.close = close
    }

    var body: some View {
        let radius = min(store.scaled(LayoutTokens.largeCardRadius), 20)
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
                if let submenu {
                    submenuBody(submenu)
                } else {
                    mainList
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(LayoutTokens.spacing[1])
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { contentHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: min(store.scaled(330), 520), height: min(contentHeight, maxHeight))
        .background(.bvCard, in: RoundedRectangle(cornerRadius: radius))
        .overlay(RoundedRectangle(cornerRadius: radius).stroke(.bvSeparator, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: radius))
    }

    private var highlight: MenuHighlight {
        MenuHighlight(isOn: { nav.highlighted == $0 }) { id, inside in
            if inside { nav.hover(id) } else if nav.highlighted == id { nav.clear() }
        }
    }

    // MARK: Main list

    @ViewBuilder private var mainList: some View {
        MenuStatusLine(status: status, hotkey: model.settings.hotkey.displayName,
                       unavailableShortcuts: model.unavailableShortcuts, highlight: highlight,
                       runAction: runStatusAction)
        if let meetings = model.meetings, meetings.isRecording || meetings.isPaused || meetings.isTranscribing {
            MenuMeetingStrip(meetings: meetings, highlight: highlight, close: close)
        }
        MenuActionGrid(model: model, highlight: highlight, close: close)
        MenuSeparator()
        if let last = model.lastResult, !last.finalText.isEmpty {
            MenuLastDictation(result: last, model: model, highlight: highlight, close: close)
            MenuSeparator()
        }
        MenuSubmenuRow(icon: "books.vertical", title: "Library", highlighted: highlight.isOn(.submenu(.library)),
                       onHover: highlight.hover(.submenu(.library))) { submenu = .library }
        MenuSubmenuRow(icon: "mic", title: "Dictation options",
                       highlighted: highlight.isOn(.submenu(.dictationOptions)),
                       onHover: highlight.hover(.submenu(.dictationOptions))) { submenu = .dictationOptions }
        MenuSeparator()
        MenuRow(icon: "macwindow", title: "Open BugVoice",
                hint: "⌃⌥\(model.settings.shortcuts.letter(for: .openApp))",
                highlighted: highlight.isOn(.openApp), onHover: highlight.hover(.openApp)) {
            close()
            model.openMainWindow(.dictation)
        }
        MenuRow(icon: "gearshape", title: "Settings…", hint: "⌘,",
                highlighted: highlight.isOn(.settings), onHover: highlight.hover(.settings)) {
            close()
            model.openMainWindow(.settings)
        }
        MenuSubmenuRow(title: "Tools", highlighted: highlight.isOn(.submenu(.tools)),
                       onHover: highlight.hover(.submenu(.tools))) { submenu = .tools }
        MenuRow(title: "Quit BugVoice", hint: "⌘Q",
                highlighted: highlight.isOn(.quit), onHover: highlight.hover(.quit)) {
            NSApp.terminate(nil)
        }
    }

    // MARK: Submenus (content comes in Task 4)

    private func submenuBody(_ submenu: MenuSubmenu) -> some View {
        HStack(spacing: LayoutTokens.spacing[1]) {
            Button { self.submenu = nil } label: {
                Text("‹ Back").bvFont(.body).foregroundStyle(.bvAccent).fixedSize()
                    .padding(.horizontal, LayoutTokens.spacing[1]).padding(.vertical, LayoutTokens.spacing[0] / 2)
                    .background(highlight.isOn(.back) ? AnyShapeStyle(.bvHover) : AnyShapeStyle(.clear),
                                in: RoundedRectangle(cornerRadius: LayoutTokens.controlRadius))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover(perform: highlight.hover(.back))
            Text(title(submenu)).bvFont(.bodyStrong)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, LayoutTokens.spacing[0])
        .padding(.vertical, LayoutTokens.spacing[0])
    }

    private func title(_ submenu: MenuSubmenu) -> String {
        switch submenu {
        case .library: "Library"
        case .dictationOptions: "Dictation options"
        case .tools: "Tools"
        }
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
            model.dictation?.retryHotkey()
            if !Permissions.isGranted(.inputMonitoring) { model.openPermissionsWindow() }
            close()
        }
    }
}
