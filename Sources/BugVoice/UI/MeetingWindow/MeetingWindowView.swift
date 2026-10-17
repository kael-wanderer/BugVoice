import AppKit
import SwiftUI
import VoiceCore

enum MeetingWindowTab: String, CaseIterable {
    case notes = "My notes"
    case transcript = "Transcript"
    case summary = "Summary"
}

/// The meeting window: top bar, header, meters, tabs and the dock.
struct MeetingWindowView: View {
    @Bindable var model: AppModel
    @Bindable var controller: MeetingController
    let onToggleCollapse: () -> Void
    let onClose: () -> Void
    @State private var tab: MeetingWindowTab = .notes
    @State private var titleDraft = ""
    @State private var question = ""
    @State private var answerHeight: CGFloat = 0
    /// The title is a label until clicked, so the window never opens with the keyboard in it.
    @State private var editingTitle = false
    @FocusState private var titleFocused: Bool

    private var collapsed: Bool { model.settings.meetings.windowCollapsed }
    private var recording: Bool { controller.isRecording || controller.isPaused }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if !collapsed {
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    header
                    if recording { meters }
                    Picker("Meeting tabs", selection: $tab) {
                        ForEach(MeetingWindowTab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                Divider()
                tabContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if let answer = controller.answer { answerCard(answer) }
                Divider()
                dock
            }
        }
        .frame(minWidth: MeetingWindowController.minWidth, maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.regularMaterial)
        // The window has no visible title bar; the top bar takes its place.
        .ignoresSafeArea()
        .onAppear { titleDraft = controller.title }
        .onChange(of: controller.title) { _, title in if !titleFocused { titleDraft = title } }
        .onChange(of: titleFocused) { _, focused in
            guard !focused, editingTitle else { return }
            editingTitle = false
            Task { await controller.rename(titleDraft) }
        }
        .onChange(of: tab) { _, _ in Task { await controller.flushNotes() } }
    }

    // MARK: Top bar

    private var stateColor: Color {
        if controller.isTranscribing { return .blue }
        if controller.isPaused { return .orange }
        if controller.isRecording { return .red }
        return .green
    }

    private var stateLabel: String {
        if controller.isTranscribing { return "Transcribing \(Int(controller.transcriptProgress * 100))%" }
        if controller.isPaused { return "Paused" }
        if controller.isRecording { return "Recording" }
        return "Finished"
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            Circle().fill(stateColor).frame(width: 9, height: 9)
            Text(stateLabel).fontWeight(.semibold)
            if collapsed {
                Text(controller.title).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                Text(MeetingTimeText.text(controller.elapsed)).monospacedDigit()
            }
            Button(action: onToggleCollapse) {
                Image(systemName: collapsed ? "chevron.down" : "chevron.up")
            }
            .buttonStyle(.borderless)
            .help(collapsed ? "Expand" : "Collapse")
            if controller.isFinished {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help("Close")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: MeetingWindowController.topBarHeight)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            if editingTitle {
                TextField("Meeting title", text: $titleDraft)
                    .textFieldStyle(.plain)
                    .font(.title3.weight(.semibold))
                    .focused($titleFocused)
                    .onAppear { titleFocused = true }
                    .onSubmit { titleFocused = false }
            } else {
                Text(controller.title.isEmpty ? "Meeting" : controller.title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        titleDraft = controller.title
                        editingTitle = true
                    }
                    .help("Click to rename")
            }
            HStack(spacing: 8) {
                if let started = controller.meetingStartedAt {
                    chip(Label(started.formatted(date: .omitted, time: .shortened), systemImage: "clock"))
                }
                FolderPicker(model: model, folderID: controller.folderID) { folderID in
                    Task { await controller.setFolder(folderID) }
                }
                .controlSize(.small)
                if recording { languageMenu }
                Spacer(minLength: 0)
            }
        }
    }

    private func chip(_ content: some View) -> some View {
        content
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.secondary.opacity(0.12), in: Capsule())
    }

    private var languageMenu: some View {
        Menu {
            ForEach(MeetingLanguages.choices, id: \.self) { language in
                Toggle(language.displayName, isOn: Binding(
                    get: { controller.languages.contains(language) },
                    set: { _ in controller.toggleLanguage(language) }
                ))
                .disabled(controller.languages == [language])
            }
        } label: {
            Text(controller.languages.map { $0.rawValue.uppercased() }.joined(separator: " · "))
                .font(.caption.weight(.medium))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Languages spoken in this meeting")
    }

    // MARK: Meters

    private var meters: some View {
        HStack(spacing: 14) {
            meter("You", level: controller.youLevel)
            meter("Others", level: controller.othersLevel)
            Spacer(minLength: 0)
            if let feedback = controller.markFeedback {
                Text(feedback).font(.caption.weight(.semibold)).foregroundStyle(.orange)
            }
            Button("Mark") { Task { await controller.mark() } }
                .controlSize(.small)
            if controller.isPaused {
                Button("Resume") { Task { await controller.resume() } }.controlSize(.small)
            } else {
                Button("Pause") { Task { await controller.pause() } }.controlSize(.small)
            }
        }
    }

    private func meter(_ title: String, level: Float) -> some View {
        HStack(spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            LevelBars(level: level).foregroundStyle(level > 0.02 ? .green : .secondary)
        }
    }

    // MARK: Tabs

    @ViewBuilder private var tabContent: some View {
        switch tab {
        case .notes:
            ZStack(alignment: .topLeading) {
                MeetingNotesEditor(text: $controller.notes)
                if controller.notes.isEmpty {
                    Text("Write your notes. The summary follows your headings.")
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 12)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if controller.notesSaveFailed {
                    Text("Could not save notes").font(.caption).foregroundStyle(.orange).padding(10)
                }
            }
        case .transcript:
            MeetingTranscriptView(
                segments: controller.segments,
                marks: controller.marks,
                elapsed: controller.elapsed,
                isListening: controller.isRecording,
                offersEnglish: controller.offersEnglish,
                showEnglish: controller.showEnglish,
                englishNeedsModel: controller.translationNeedsModel,
                onShowEnglish: { show in Task { await controller.setShowEnglish(show) } }
            )
        case .summary:
            summary
        }
    }

    @ViewBuilder private var summary: some View {
        if let final = controller.finalSummary, !final.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                summaryCaption("Final summary")
                MarkdownDocView(text: final, onToggleTask: { _ in })
            }
        } else if controller.summaryState == .finalizing {
            ProgressView("Writing the summary")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if controller.summaryState == .noModel {
            needsModel
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let live = controller.liveSummary, !live.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    summaryCaption(liveCaption(now: context.date))
                }
                MarkdownDocView(text: live, onToggleTask: { _ in })
            }
        } else if controller.summaryState == .failed {
            Text("Not updated: model unavailable").foregroundStyle(.orange)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if controller.summaryState == .refreshing {
            ProgressView("Writing the summary")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Text("The first summary comes after 3 minutes of talk.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func summaryCaption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 24)
            .padding(.top, 12)
    }

    private func liveCaption(now: Date) -> String {
        var parts = ["So far"]
        if let updated = controller.liveSummaryUpdatedAt {
            parts.append("updated \(max(0, Int(now.timeIntervalSince(updated) / 60))) min ago")
        }
        if controller.summaryState == .failed {
            parts.append("Not updated: model unavailable")
        } else if controller.summaryState == .refreshing {
            parts.append("updating")
        } else if controller.isRecording, let last = controller.lastRefreshActiveTime {
            let next = max(0, LiveSummaryPlanner.interval - (controller.elapsed - last))
            parts.append("next in \(Int((next / 60).rounded(.up))) min")
        }
        return parts.joined(separator: " · ")
    }

    private var needsModel: some View {
        VStack(spacing: 8) {
            Text("Summary needs a Meeting notes model.").foregroundStyle(.secondary)
            Button("Open Settings") {
                model.settingsTab = .models
                model.openMainWindow(.settings)
            }
        }
    }

    // MARK: Answer

    private func answerCard(_ answer: MeetingAnswer) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(answer.question).font(.caption).foregroundStyle(.secondary)
            switch answer.state {
            case .loading:
                ProgressView().controlSize(.small)
            case .noModel:
                needsModel
            case .failed(let message):
                Text(message).foregroundStyle(.orange)
            case .done:
                // Short answers take their own height; long ones scroll.
                ScrollView {
                    Text(LocalizedStringKey(answer.text))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { answerHeight = $0 }
                }
                .frame(height: min(220, max(18, answerHeight)))
            }
            HStack {
                if answer.state == .done {
                    Button("Add to notes") { controller.addAnswerToNotes() }
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(answer.text, forType: .string)
                    }
                }
                Spacer()
                Button("Close") { controller.closeAnswer() }
                    .keyboardShortcut(.cancelAction)
            }
            .controlSize(.small)
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    // MARK: Dock

    private var dock: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let status = controller.statusMessage {
                Text(status).font(.caption).foregroundStyle(.orange)
            }
            if controller.isFinished {
                HStack {
                    Button("Open in Meetings") {
                        if let id = controller.shownMeetingID { model.selectedMeetingID = id }
                        model.openMainWindow(.meetings)
                    }
                    .buttonStyle(.borderedProminent)
                    Spacer()
                    Button("Close", action: onClose)
                }
            } else {
                Text("Recording stays on this Mac. Tell people you are recording.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Button {
                        Task { await controller.stop() }
                    } label: {
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 2).fill(.red).frame(width: 9, height: 9)
                            Text("Stop")
                        }
                    }
                    .disabled(!recording)
                    HStack(spacing: 6) {
                        TextField("Ask anything about this meeting", text: $question)
                            .textFieldStyle(.plain)
                            .onSubmit {
                                controller.ask(question)
                                question = ""
                            }
                        Button("What did I miss?") { controller.ask(nil) }
                            .buttonStyle(.borderless)
                            .font(.caption)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(14)
    }
}
