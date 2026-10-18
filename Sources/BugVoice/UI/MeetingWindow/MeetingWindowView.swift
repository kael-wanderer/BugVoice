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
    @Environment(AppearanceStore.self) private var store
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
                VStack(alignment: .leading, spacing: LayoutTokens.spacing[1]) {
                    header
                    if recording { meters }
                    Picker("Meeting tabs", selection: $tab) {
                        ForEach(MeetingWindowTab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                .padding(.horizontal, LayoutTokens.spacing[2])
                .padding(.vertical, LayoutTokens.spacing[1])
                Divider()
                tabContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if let answer = controller.answer { answerCard(answer) }
                Divider()
                dock
            }
        }
        .frame(minWidth: MeetingWindowController.minWidth, maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.bvCard)
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
        if controller.isTranscribing { return store.theme.accent }
        if controller.isPaused { return store.theme.warning }
        if controller.isRecording { return store.theme.recording }
        return store.theme.success
    }

    private var stateLabel: String {
        if controller.isTranscribing { return "Transcribing \(Int(controller.transcriptProgress * 100))%" }
        if controller.isPaused { return "Paused" }
        if controller.isRecording { return "Recording" }
        return "Finished"
    }

    private var topBar: some View {
        HStack(spacing: LayoutTokens.spacing[1]) {
            Circle().fill(stateColor).frame(width: 9, height: 9)
            Text(stateLabel).fontWeight(.semibold)
            if collapsed {
                Text(controller.title).foregroundStyle(.bvSecondary).lineLimit(1)
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
        .padding(.horizontal, LayoutTokens.spacing[2])
        .frame(height: MeetingWindowController.topBarHeight)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: LayoutTokens.spacing[1]) {
            if editingTitle {
                TextField("Meeting title", text: $titleDraft)
                    .textFieldStyle(.plain)
                    .bvFont(.title3)
                    .focused($titleFocused)
                    .onAppear { titleFocused = true }
                    .onSubmit { titleFocused = false }
            } else {
                Text(controller.title.isEmpty ? "Meeting" : controller.title)
                    .bvFont(.title3)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        titleDraft = controller.title
                        editingTitle = true
                    }
                    .help("Click to rename")
            }
            HStack(spacing: LayoutTokens.spacing[1]) {
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
            .bvFont(.footnote)
            .foregroundStyle(.bvSecondary)
            .padding(.horizontal, LayoutTokens.spacing[1])
            .padding(.vertical, LayoutTokens.spacing[0])
            .background(store.theme.secondaryText.opacity(0.12), in: Capsule())
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
                .bvFont(.footnote)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Languages spoken in this meeting")
    }

    // MARK: Meters

    private var meters: some View {
        HStack(spacing: LayoutTokens.spacing[2]) {
            meter("You", level: controller.youLevel)
            meter("Others", level: controller.othersLevel)
            Spacer(minLength: 0)
            if let feedback = controller.markFeedback {
                Text(feedback).bvFont(.footnote).foregroundStyle(.bvWarning)
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
        HStack(spacing: LayoutTokens.spacing[0]) {
            Text(title).bvFont(.footnote).foregroundStyle(.bvSecondary)
            LevelBars(level: level).foregroundStyle(level > 0.02 ? store.theme.success : store.theme.secondaryText)
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
                        .foregroundStyle(.bvSecondary)
                        .padding(.horizontal, LayoutTokens.spacing[3])
                        .padding(.vertical, LayoutTokens.spacing[2])
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if controller.notesSaveFailed {
                    Text("Could not save notes").bvFont(.footnote).foregroundStyle(.bvWarning).padding(LayoutTokens.spacing[1])
                }
            }
        case .transcript:
            MeetingTranscriptView(
                segments: controller.segments,
                speakers: controller.speakers,
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
            Text("Not updated: model unavailable").foregroundStyle(.bvWarning)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if controller.summaryState == .refreshing {
            ProgressView("Writing the summary")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Text("The first summary comes after \(LiveSummaryPlanner.intervalLabel(model.settings.meetings.liveSummaryInterval)) of talk.")
                .foregroundStyle(.bvSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func summaryCaption(_ text: String) -> some View {
        Text(text)
            .bvFont(.footnote)
            .foregroundStyle(.bvSecondary)
            .padding(.horizontal, LayoutTokens.spacing[4])
            .padding(.top, LayoutTokens.spacing[2])
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
            let next = max(0, TimeInterval(model.settings.meetings.liveSummaryInterval) - (controller.elapsed - last))
            parts.append("next in \(Int((next / 60).rounded(.up))) min")
        }
        return parts.joined(separator: " · ")
    }

    private var needsModel: some View {
        VStack(spacing: LayoutTokens.spacing[1]) {
            Text("Summary needs a Meeting notes model.").foregroundStyle(.bvSecondary)
            Button("Open Settings") {
                model.settingsTab = .models
                model.openMainWindow(.settings)
            }
        }
    }

    // MARK: Answer

    private func answerCard(_ answer: MeetingAnswer) -> some View {
        VStack(alignment: .leading, spacing: LayoutTokens.spacing[1]) {
            Text(answer.question).bvFont(.footnote).foregroundStyle(.bvSecondary)
            switch answer.state {
            case .loading:
                ProgressView().controlSize(.small)
            case .noModel:
                needsModel
            case .failed(let message):
                Text(message).foregroundStyle(.bvWarning)
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
        .padding(LayoutTokens.spacing[2])
        .background(store.theme.secondaryText.opacity(0.08), in: RoundedRectangle(cornerRadius: LayoutTokens.cardRadius))
        .padding(.horizontal, LayoutTokens.spacing[2])
        .padding(.bottom, LayoutTokens.spacing[1])
    }

    // MARK: Dock

    private var dock: some View {
        VStack(alignment: .leading, spacing: LayoutTokens.spacing[1]) {
            if let status = controller.statusMessage {
                Text(status).bvFont(.footnote).foregroundStyle(.bvWarning)
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
                    .bvFont(.footnote).foregroundStyle(.bvSecondary)
                HStack(spacing: LayoutTokens.spacing[1]) {
                    Button {
                        Task { await controller.stop() }
                    } label: {
                        HStack(spacing: LayoutTokens.spacing[0]) {
                            RoundedRectangle(cornerRadius: LayoutTokens.controlRadius).fill(.bvRecording).frame(width: 9, height: 9)
                            Text("Stop")
                        }
                    }
                    .disabled(!recording)
                    HStack(spacing: LayoutTokens.spacing[0]) {
                        TextField("Ask anything about this meeting", text: $question)
                            .textFieldStyle(.plain)
                            .onSubmit {
                                controller.ask(question)
                                question = ""
                            }
                        Button("What did I miss?") { controller.ask(nil) }
                            .buttonStyle(.borderless)
                            .bvFont(.footnote)
                    }
                    .padding(.horizontal, LayoutTokens.spacing[1])
                    .padding(.vertical, LayoutTokens.spacing[0])
                    .background(store.theme.secondaryText.opacity(0.1), in: RoundedRectangle(cornerRadius: LayoutTokens.controlRadius))
                }
            }
        }
        .padding(LayoutTokens.spacing[2])
    }
}
