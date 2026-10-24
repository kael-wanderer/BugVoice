import SwiftUI
import VoiceCore

/// Status dot, bold title, secondary line and an optional Fix… / Retry button.
struct MenuStatusLine: View {
    @Environment(AppearanceStore.self) private var store
    let status: MenuStatus
    let hotkey: String
    /// How VoiceOver says the hotkey ("Right Option", not "Right ⌥").
    let spokenHotkey: String
    let unavailableShortcuts: [String]
    let highlight: MenuHighlight

    var body: some View {
        let detail = status.detail(hotkey: hotkey)
        VStack(alignment: .leading, spacing: LayoutTokens.spacing[1]) {
            HStack(spacing: LayoutTokens.spacing[1]) {
                HStack(spacing: LayoutTokens.spacing[1]) {
                    Circle().fill(dotStyle).frame(width: store.scaled(10), height: store.scaled(10))
                    VStack(alignment: .leading, spacing: 0) {
                        Text(status.title).bvFont(.bodyStrong)
                        if let detail {
                            Text(detail).bvFont(.footnote).foregroundStyle(.bvSecondary)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(spokenStatus(status.detail(hotkey: spokenHotkey)))
                .accessibilitySortPriority(1)
                Spacer(minLength: LayoutTokens.spacing[1])
                if let title = status.actionTitle {
                    MenuButton(id: .statusAction, small: true, primary: true, highlight: highlight) {
                        Text(title)
                    }
                }
            }
            ForEach(unavailableShortcuts, id: \.self) { shortcut in
                Text("\(shortcut) is used by another app").bvFont(.footnote).foregroundStyle(.bvWarning)
            }
        }
        .padding(.horizontal, LayoutTokens.spacing[1])
        .padding(.top, LayoutTokens.spacing[0])
        .padding(.bottom, LayoutTokens.spacing[1])
    }

    /// "Ready to dictate, hold Right Option to speak, release to paste".
    private func spokenStatus(_ detail: String?) -> String {
        guard let detail else { return status.title }
        let spoken = detail.replacingOccurrences(of: " · ", with: ", ").replacingOccurrences(of: "·", with: ",")
        return "\(status.title), \(spoken)"
    }

    private var dotStyle: BVColorStyle {
        switch status.tone {
        case .good: .bvSuccess
        case .warning: .bvWarning
        case .recording: .bvRecording
        }
    }
}

/// Elapsed time and Pause / Mark moment / Stop while a meeting runs.
struct MenuMeetingStrip: View {
    let meetings: MeetingController
    let highlight: MenuHighlight

    var body: some View {
        HStack(spacing: LayoutTokens.spacing[1]) {
            if meetings.isTranscribing {
                Text("Transcribing meeting…").bvFont(.footnote).foregroundStyle(.bvSecondary)
                Spacer(minLength: 0)
            } else {
                Text(MeetingTimeText.text(meetings.elapsed)).bvFont(.bodyStrong).monospacedDigit()
                Spacer(minLength: LayoutTokens.spacing[1])
                MenuButton(id: .meetingPause, small: true, highlight: highlight) {
                    Text(meetings.isPaused ? "Resume" : "Pause")
                }
                MenuButton(id: .meetingMark, small: true, highlight: highlight) { Text("Mark moment") }
                MenuButton(id: .meetingStop, small: true, highlight: highlight) {
                    Text("Stop").foregroundStyle(.bvRecording)
                }
            }
        }
        .padding(.horizontal, LayoutTokens.spacing[1])
        .padding(.bottom, LayoutTokens.spacing[1])
    }
}

/// The 2 × 2 grid: New note, Record / Stop meeting, Upload, Paste last.
struct MenuActionGrid: View {
    let model: AppModel
    let highlight: MenuHighlight

    var body: some View {
        let meetings = model.meetings
        let meetingRunning = meetings?.isRecording == true || meetings?.isPaused == true
        Grid(horizontalSpacing: LayoutTokens.spacing[1], verticalSpacing: LayoutTokens.spacing[1]) {
            GridRow {
                tile(.newNote, "New note", "square.and.pencil")
                if meetingRunning {
                    tile(.meeting, "Stop meeting", "stop.fill", recording: true)
                } else {
                    tile(.meeting, "Record meeting", "record.circle", iconRecording: true)
                        .disabled(meetings?.isTranscribing == true)
                }
            }
            GridRow {
                tile(.upload, "Upload", "square.and.arrow.up")
                tile(.pasteLast, "Paste last", "doc.on.clipboard")
                    .disabled(model.lastResult?.finalText.isEmpty ?? true)
            }
        }
        .padding(.horizontal, LayoutTokens.spacing[0])
        .padding(.bottom, LayoutTokens.spacing[0])
    }

    private func tile(_ id: MenuControl, _ title: String, _ symbol: String, recording: Bool = false,
                      iconRecording: Bool = false) -> some View {
        MenuButton(id: id, fillsWidth: true, highlight: highlight) {
            HStack(spacing: LayoutTokens.spacing[1]) {
                Image(systemName: symbol)
                    .foregroundStyle(recording || iconRecording ? AnyShapeStyle(.bvRecording) : AnyShapeStyle(.bvSecondary))
                    .accessibilityHidden(true)
                Text(title).foregroundStyle(recording ? AnyShapeStyle(.bvRecording) : AnyShapeStyle(.bvText))
            }
        }
    }
}

/// App, time, up to three lines of the last dictation, Copy and Retry.
struct MenuLastDictation: View {
    let result: DictationResult
    /// The language the next "Redo in another language" press uses.
    /// Nil hides the redo button.
    let redoLanguage: SpeechLanguage?
    let shortcuts: ShortcutSettings
    let highlight: MenuHighlight

    var body: some View {
        let app = result.appName ?? "Unknown"
        let time = result.startedAt.formatted(date: .omitted, time: .shortened)
        VStack(alignment: .leading, spacing: LayoutTokens.spacing[0]) {
            VStack(alignment: .leading, spacing: LayoutTokens.spacing[0]) {
                HStack(spacing: LayoutTokens.spacing[0]) {
                    Text("\(result.command == nil ? "Last dictation" : "Last command") · \(app) · \(time)")
                        .bvFont(.footnote).foregroundStyle(.bvSecondary)
                    if !result.fidelityIssues.isEmpty {
                        Text(result.isFidelityFallback ? "raw · detail" : "check")
                            .bvFont(.caption).foregroundStyle(.bvWarning)
                            .help((["Cleanup changed"] + FidelityCheck.describe(result.fidelityIssues)).joined(separator: "\n"))
                    }
                }
                if let command = result.command {
                    Text("“\(command)”").italic().bvFont(.body).foregroundStyle(.bvSecondary)
                }
                Text(result.finalText).bvFont(.reading).lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(result.command == nil ? "Last dictation" : "Last command"), \(app), \(time), \(result.command ?? ""), \(result.finalText)")
            HStack(spacing: LayoutTokens.spacing[1]) {
                MenuButton(id: .copyLast, small: true, highlight: highlight) { Text("Copy") }
                if result.command != nil {
                    MenuButton(id: .rawLast, small: true, highlight: highlight) { Text("Original") }
                } else {
                    MenuButton(id: .retryLast, small: true, highlight: highlight) { Text("Retry") }
                    MenuButton(id: .rawLast, small: true, highlight: highlight) { Text(result.isFidelityFallback ? "Cleaned" : "Raw") }
                        .help("Paste \(result.isFidelityFallback ? "cleaned" : "raw") (⌃⌥\(shortcuts.letter(for: .pasteRaw)))")
                    if let redoLanguage {
                        MenuButton(id: .redoLast, small: true, highlight: highlight) {
                            Text(redoLanguage.displayName)
                        }
                        .help("Redo in \(redoLanguage.displayName) (⌃⌥\(shortcuts.letter(for: .redoOtherLanguage)))")
                    }
                }
            }
            .padding(.top, LayoutTokens.spacing[0])
        }
        .padding(.horizontal, LayoutTokens.spacing[1])
        .padding(.vertical, LayoutTokens.spacing[0])
    }
}
