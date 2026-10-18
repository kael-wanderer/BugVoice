import SwiftUI
import VoiceCore

/// Status dot, bold title, secondary line and an optional Fix… / Retry button.
struct MenuStatusLine: View {
    @Environment(AppearanceStore.self) private var store
    let status: MenuStatus
    let hotkey: String
    let unavailableShortcuts: [String]
    let highlight: MenuHighlight
    let runAction: (MenuStatusAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutTokens.spacing[1]) {
            HStack(spacing: LayoutTokens.spacing[1]) {
                Circle().fill(dotStyle).frame(width: store.scaled(10), height: store.scaled(10))
                VStack(alignment: .leading, spacing: 0) {
                    Text(status.title).bvFont(.bodyStrong)
                    if let detail = status.detail(hotkey: hotkey) {
                        Text(detail).bvFont(.footnote).foregroundStyle(.bvSecondary)
                    }
                }
                Spacer(minLength: LayoutTokens.spacing[1])
                if let action = status.action, let title = status.actionTitle {
                    MenuButton(small: true, primary: true, highlighted: highlight.isOn(.statusAction),
                               onHover: highlight.hover(.statusAction), action: { runAction(action) }) {
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
    let close: () -> Void

    var body: some View {
        HStack(spacing: LayoutTokens.spacing[1]) {
            if meetings.isTranscribing {
                Text("Transcribing meeting…").bvFont(.footnote).foregroundStyle(.bvSecondary)
                Spacer(minLength: 0)
            } else {
                Text(MeetingTimeText.text(meetings.elapsed)).bvFont(.bodyStrong).monospacedDigit()
                Spacer(minLength: LayoutTokens.spacing[1])
                if meetings.isPaused {
                    MenuButton(small: true, highlighted: highlight.isOn(.meetingPause),
                               onHover: highlight.hover(.meetingPause),
                               action: { Task { await meetings.resume() } }) { Text("Resume") }
                } else {
                    MenuButton(small: true, highlighted: highlight.isOn(.meetingPause),
                               onHover: highlight.hover(.meetingPause),
                               action: { Task { await meetings.pause() } }) { Text("Pause") }
                }
                MenuButton(small: true, highlighted: highlight.isOn(.meetingMark),
                           onHover: highlight.hover(.meetingMark),
                           action: { Task { await meetings.mark() } }) { Text("Mark moment") }
                MenuButton(small: true, highlighted: highlight.isOn(.meetingStop),
                           onHover: highlight.hover(.meetingStop),
                           action: { close(); Task { await meetings.stop() } }) {
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
    let close: () -> Void

    var body: some View {
        let meetings = model.meetings
        let meetingRunning = meetings?.isRecording == true || meetings?.isPaused == true
        Grid(horizontalSpacing: LayoutTokens.spacing[1], verticalSpacing: LayoutTokens.spacing[1]) {
            GridRow {
                tile(.newNote, "New note", "square.and.pencil") {
                    close()
                    Task { await model.openScratchpadWindow(newNote: true) }
                }
                if meetingRunning {
                    tile(.meeting, "Stop meeting", "stop.fill", recording: true) {
                        close()
                        Task { await model.meetings?.stop() }
                    }
                } else {
                    tile(.meeting, "Record meeting", "record.circle", iconRecording: true) {
                        close()
                        Task { await model.meetings?.start() }
                    }
                    .disabled(meetings?.isTranscribing == true)
                }
            }
            GridRow {
                tile(.upload, "Upload", "square.and.arrow.up") {
                    close()
                    model.openMainWindow(.upload)
                }
                tile(.pasteLast, "Paste last", "doc.on.clipboard") {
                    close()
                    Task {
                        try? await Task.sleep(for: .milliseconds(60))
                        model.dictation?.pasteLast()
                    }
                }
                .disabled(model.lastResult?.finalText.isEmpty ?? true)
            }
        }
        .padding(.horizontal, LayoutTokens.spacing[0])
        .padding(.bottom, LayoutTokens.spacing[0])
    }

    private func tile(_ id: MenuControl, _ title: String, _ symbol: String, recording: Bool = false,
                      iconRecording: Bool = false, action: @escaping () -> Void) -> some View {
        MenuButton(fillsWidth: true, highlighted: highlight.isOn(id), onHover: highlight.hover(id), action: action) {
            HStack(spacing: LayoutTokens.spacing[1]) {
                Image(systemName: symbol)
                    .foregroundStyle(recording || iconRecording ? AnyShapeStyle(.bvRecording) : AnyShapeStyle(.bvSecondary))
                Text(title).foregroundStyle(recording ? AnyShapeStyle(.bvRecording) : AnyShapeStyle(.bvText))
            }
        }
    }
}

/// App, time, up to three lines of the last dictation, Copy and Retry.
struct MenuLastDictation: View {
    let result: DictationResult
    let model: AppModel
    let highlight: MenuHighlight
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutTokens.spacing[0]) {
            VStack(alignment: .leading, spacing: LayoutTokens.spacing[0]) {
                Text("Last dictation · \(result.appName ?? "Unknown") · \(result.startedAt.formatted(date: .omitted, time: .shortened))")
                    .bvFont(.footnote).foregroundStyle(.bvSecondary)
                Text(result.finalText).bvFont(.reading).lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: LayoutTokens.spacing[1]) {
                MenuButton(small: true, highlighted: highlight.isOn(.copyLast), onHover: highlight.hover(.copyLast),
                           action: { close(); model.dictation?.copy(result.finalText) }) { Text("Copy") }
                MenuButton(small: true, highlighted: highlight.isOn(.retryLast), onHover: highlight.hover(.retryLast),
                           action: { close(); model.dictation?.retryLast() }) { Text("Retry") }
            }
            .padding(.top, LayoutTokens.spacing[0])
        }
        .padding(.horizontal, LayoutTokens.spacing[1])
        .padding(.vertical, LayoutTokens.spacing[0])
    }
}
