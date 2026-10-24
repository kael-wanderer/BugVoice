import AppKit
import SwiftUI
import UniformTypeIdentifiers
import VoiceCore

enum MeetingDetailTab: String, CaseIterable {
    case transcript = "Transcript"
    case summary = "Summary"
    case actionItems = "Action items"
    case notes = "My notes"
}

private enum MeetingExportKind {
    case markdown, srt, audio
}

struct MeetingsPage: View {
    @Environment(AppearanceStore.self) private var store
    @Bindable var model: AppModel
    @State private var player = MeetingPlayerModel()
    @State private var citedLineIDs: Set<String> = []
    @State private var citationScrollRequest: UInt64 = 0
    @State private var pendingDelete: MeetingManifest?
    @State private var pendingRename: MeetingManifest?
    @State private var renameTitle = ""
    @State private var librarySheet: LibrarySheetTab?

    private var visibleMeetings: [MeetingManifest] {
        LibraryProjection.filter(
            model.meetingManifests,
            folder: model.meetingsFolderFilter,
            tags: model.meetingTagFilter,
            known: model.library.knownIDs
        )
    }

    private var groups: [MeetingDayGroup] {
        MeetingListProjection.groups(meetings: visibleMeetings, query: model.meetingSearchQuery)
    }

    var body: some View {
        HStack(spacing: 0) {
            library
                .frame(width: model.listPaneWidth)
                .background(.bvSidebar)
            ResizeHandle(width: model.listPaneWidth, range: ShellLayout.listPaneRange) { model.listPaneDraggedWidth = $0 }
            if let meeting = model.selectedMeeting {
                MeetingDetails(model: model, meeting: meeting, player: player, citedLineIDs: $citedLineIDs, citationScrollRequest: citationScrollRequest)
                    .environment(model)
            } else {
                EmptyState("No meeting selected", systemImage: "waveform.path", message: "Choose a meeting or start a recording.")
            }
        }
        .simultaneousGesture(TapGesture().onEnded { citedLineIDs = [] })
        .onChange(of: model.meetingSelectionRequest) { _, _ in citedLineIDs = [] }
        .task(id: model.pendingMeetingJump) { await consumeMeetingJump() }
        .task {
            await model.reloadMeetings()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                await model.reloadMeetings()
            }
        }
    }

    private func consumeMeetingJump() async {
        guard let jump = model.pendingMeetingJump else { return }
        let directory = model.paths.meetings.appendingPathComponent(jump.id.rawValue)
        let manifest = directory.appendingPathComponent("meeting.json")
        guard model.meetingManifests.contains(where: { $0.id == jump.id }),
              model.selectedMeetingID == jump.id,
              FileManager.default.fileExists(atPath: manifest.path) else {
            if model.pendingMeetingJump == jump { model.pendingMeetingJump = nil }
            return
        }
        citedLineIDs = jump.lineIDs
        if !jump.lineIDs.isEmpty { model.meetingDetailTab = .transcript }
        citationScrollRequest &+= 1
        let audio = directory.appendingPathComponent("audio.m4a")
        let hasAudio = FileManager.default.fileExists(atPath: audio.path)
        if hasAudio && jump.play { await player.load(audio) }
        guard !Task.isCancelled, model.pendingMeetingJump == jump else { return }
        guard model.selectedMeetingID == jump.id, FileManager.default.fileExists(atPath: manifest.path) else {
            model.pendingMeetingJump = nil
            return
        }
        if hasAudio && jump.play {
            player.seek(to: jump.start)
            if !player.isPlaying { player.togglePlayback() }
        }
        model.pendingMeetingJump = nil
    }

    private var library: some View {
        ScrollView {
        VStack(spacing: LayoutTokens.spacing[1]) {
            FilterRow {
                FolderFilterMenu(
                    model: model,
                    filter: Binding(get: { model.meetingsFolderFilter }, set: { model.meetingsFolderFilter = $0 }),
                    counts: LibraryProjection.counts(model.meetingManifests, known: model.library.knownIDs),
                    allTitle: "All meetings",
                    onManage: { librarySheet = .folders }
                )
                TagFilterBar(catalog: model.meetingTagCatalog, selected: $model.meetingTagFilter, onManage: { librarySheet = .tags })
            }
            if model.meetingManifests.isEmpty {
                EmptyState("No meetings yet", systemImage: "waveform.path", message: "Record a meeting to see its transcript here.")
            } else if groups.isEmpty {
                EmptyState("No matching meetings", systemImage: "magnifyingglass", message: "Try a different title or transcript search.")
            } else {
                    LazyVStack(alignment: .leading, spacing: LayoutTokens.spacing[2]) {
                        ForEach(groups) { group in
                            VStack(alignment: .leading, spacing: LayoutTokens.spacing[0]) {
                                Text(group.label.uppercased()).bvFont(.footnote).foregroundStyle(.bvSecondary)
                                ForEach(group.meetings) { meeting in
                                    MeetingListRow(
                                        meeting: meeting,
                                        folderName: model.meetingsFolderFilter == .all ? model.folderName(meeting.folderID) : nil,
                                        selected: meeting.id == model.selectedMeetingID
                                    ) {
                                        model.selectedMeetingID = meeting.id
                                    }
                                    .contextMenu {
                                        Button("Rename…") {
                                            renameTitle = meeting.title
                                            pendingRename = meeting
                                        }
                                        Menu("Move to folder") {
                                            Button("Unfiled") {
                                                Task { await model.setMeetingLabels(id: meeting.id, folderID: nil, tags: meeting.tags) }
                                            }
                                            Divider()
                                            ForEach(model.sortedFolders) { folder in
                                                Button {
                                                    Task { await model.setMeetingLabels(id: meeting.id, folderID: folder.id, tags: meeting.tags) }
                                                } label: {
                                                    if folder.id == meeting.folderID { Label(folder.name, systemImage: "checkmark") } else { Text(folder.name) }
                                                }
                                            }
                                        }
                                        Button("Tags…") { model.selectedMeetingID = meeting.id }
                                        if meeting.state != .recording, meeting.state != .paused {
                                            Divider()
                                            Button("Delete…", role: .destructive) { pendingDelete = meeting }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.vertical, LayoutTokens.spacing[0])
            }
        }
        .padding(LayoutTokens.spacing[2])
        }
        .confirmationDialog(
            "Delete this meeting?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { meeting in
            Button("Delete meeting", role: .destructive) { Task { await model.deleteMeeting(id: meeting.id) } }
        } message: { _ in
            Text("The transcript and audio files will be deleted.")
        }
        .sheet(item: $librarySheet) { ManageLibrarySheet(model: model, tab: $0) }
        .sheet(item: $pendingRename) { meeting in
            MeetingRenameSheet(model: model, id: meeting.id, title: $renameTitle) { pendingRename = nil }
        }
    }
}

private struct MeetingRenameSheet: View {
    @Environment(AppearanceStore.self) private var store
    let model: AppModel
    let id: MeetingID
    @Binding var title: String
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutTokens.spacing[3]) {
            Text("Rename meeting").bvFont(.bodyStrong)
            TextField("Meeting title", text: $title)
            HStack {
                Spacer()
                Button("Cancel", action: dismiss)
                Button("Save") {
                    Task { await model.renameMeeting(id: id, title: title); dismiss() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(LayoutTokens.spacing[3]).frame(width: store.scaled(360))
    }
}

private struct MeetingListRow: View {
    @Environment(AppearanceStore.self) private var store
    let meeting: MeetingManifest
    let folderName: String?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: LayoutTokens.spacing[0]) {
                HStack {
                    Text(meeting.title).bvFont(.reading).lineLimit(1)
                    if meeting.source == .upload {
                        Text("Uploaded")
                            .bvFont(.caption)
                            .padding(.horizontal, LayoutTokens.spacing[0])
                            .padding(.vertical, LayoutTokens.spacing[0])
                            .background(store.theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: LayoutTokens.controlRadius))
                    }
                    Spacer(minLength: 3)
                    Text(status).bvFont(.footnote).foregroundStyle(meeting.state == .failed ? store.theme.warning : store.theme.secondaryText)
                }
                Text(meeting.startedAt.formatted(date: .omitted, time: .shortened) + " · " + clock(meeting.duration))
                    .bvFont(.footnote).foregroundStyle(.bvSecondary)
                if folderName != nil || !meeting.tags.isEmpty {
                    FlowLayout(spacing: LayoutTokens.spacing[0]) {
                        if let folderName {
                            Label(folderName, systemImage: "folder").bvFont(.footnote).foregroundStyle(.bvSecondary)
                        }
                        ForEach(meeting.tags.prefix(3), id: \.self) { TagChip(name: $0) }
                        if meeting.tags.count > 3 {
                            Text("+\(meeting.tags.count - 3)").bvFont(.footnote).foregroundStyle(.bvSecondary)
                        }
                    }
                }
                if let line = meeting.segments.last?.text, !line.isEmpty {
                    Text(line).bvFont(.footnote).foregroundStyle(.bvSecondary).lineLimit(2)
                }
            }
            .padding(LayoutTokens.spacing[1])
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? store.theme.accent.opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: LayoutTokens.controlRadius))
            // Make the whole card clickable, not only the drawn text.
            .contentShape(RoundedRectangle(cornerRadius: LayoutTokens.controlRadius))
        }
        .buttonStyle(.plain)
    }

    private var status: String {
        switch meeting.state {
        case .recording: "Recording"
        case .paused: "Paused"
        case .interrupted: "Interrupted"
        case .transcribing: "Transcribing \(Int((meeting.transcriptProgress ?? 0) * 100))%"
        case .ready: "Ready"
        case .failed: "Transcript failed"
        }
    }

    private func clock(_ seconds: TimeInterval) -> String {
        let whole = max(0, Int(seconds))
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }
}

private struct MeetingDetails: View {
    @Environment(AppearanceStore.self) private var store
    @Bindable var model: AppModel
    let meeting: MeetingManifest
    @Bindable var player: MeetingPlayerModel
    @Binding var citedLineIDs: Set<String>
    let citationScrollRequest: UInt64
    @State private var showDelete = false
    @State private var showRename = false
    @State private var renameTitle = ""
    @State private var generationTask: Task<Void, Never>?
    @State private var generationProgress: MeetingTextProgress?
    @State private var generationError: String?

    private var meetingDirectory: URL { model.paths.meetings.appendingPathComponent(meeting.id.rawValue, isDirectory: true) }
    private var audioURL: URL? {
        let url = meetingDirectory.appendingPathComponent("audio.m4a")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    var body: some View {
        ScrollViewReader { reader in
        ScrollView {
        VStack(alignment: .leading, spacing: LayoutTokens.spacing[2]) {
            header
            Text(
                meeting.startedAt.formatted(date: .long, time: .shortened)
                    + " · " + clock(meeting.duration)
                    + (meeting.sourceFileName.map { " · from \($0)" } ?? "")
            )
            .bvFont(.body)
            .foregroundStyle(.bvSecondary)
            LabelsBox(
                model: model,
                labels: ItemLabels(folderID: meeting.folderID, tags: meeting.tags),
                catalog: model.allTagCatalog,
                noun: "meeting",
                suggested: meeting.suggestedTags,
                suggestionSource: model.plan(for: .meetings).shortName ?? "Meetings model",
                onChange: { labels in
                    Task { await model.setMeetingLabels(id: meeting.id, folderID: labels.folderID, tags: labels.tags) }
                },
                onAcceptSuggestion: { tag in
                    var labels = ItemLabels(folderID: meeting.folderID, tags: meeting.tags)
                    labels.addTag(tag)
                    Task {
                        await model.setMeetingLabels(
                            id: meeting.id, folderID: labels.folderID, tags: labels.tags,
                            suggestedTags: meeting.suggestedTags.filter { $0 != tag })
                    }
                },
                onDismissSuggestions: {
                    Task { await model.setMeetingLabels(id: meeting.id, folderID: meeting.folderID, tags: meeting.tags, suggestedTags: []) }
                }
            )
            if let audioURL {
                MeetingPlayer(audioURL: audioURL, model: player, marks: meeting.marks.map(\.offset))
                    .padding(.vertical, LayoutTokens.spacing[0])
            } else {
                Label(meeting.state == .recording || meeting.state == .paused ? "Audio is recording" : "Audio is unavailable", systemImage: "waveform")
                    .foregroundStyle(.bvSecondary)
            }
            RoundPills("Meeting view", items: MeetingDetailTab.allCases.map { ($0, $0.rawValue) }, selection: $model.meetingDetailTab)
            Group {
                switch model.meetingDetailTab {
                case .transcript: transcript
                case .summary: generatedText(meeting.summary, kind: .summary, emptyMessage: "Generate a summary from this transcript.")
                case .actionItems: generatedText(meeting.actionItems, kind: .actionItems, emptyMessage: "Find the action items discussed in this meeting.")
                case .notes: MeetingDetailNotes(model: model, meeting: meeting).id(meeting.id)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .bvPageColumn(.reading)
        }
        .task(id: citationScrollRequest) {
            if let first = meeting.segments.sorted(by: { $0.start < $1.start }).first(where: { citedLineIDs.contains($0.id) }) {
                reader.scrollTo(first.id, anchor: .center)
            }
        }
        }
        .confirmationDialog("Delete this meeting?", isPresented: $showDelete, titleVisibility: .visible) {
            Button("Delete meeting", role: .destructive) { Task { await model.deleteMeeting(id: meeting.id) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The transcript and audio files will be deleted.")
        }
        .sheet(isPresented: $showRename) {
            MeetingRenameSheet(model: model, id: meeting.id, title: $renameTitle) { showRename = false }
        }
        .onChange(of: meeting.id) { _, _ in
            generationTask?.cancel()
            player.stopAndDetach()
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(meeting.title).bvFont(.title2).lineLimit(2)
            if meeting.source == .upload {
                Text("Uploaded")
                    .bvFont(.caption)
                    .padding(.horizontal, LayoutTokens.spacing[0])
                    .padding(.vertical, LayoutTokens.spacing[0])
                    .background(store.theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: LayoutTokens.controlRadius))
            }
            Spacer()
            if recoveryAction == .recoverCapture, meeting.state == .interrupted {
                Button("Recover recording") { Task { await model.meetings?.recover(id: meeting.id) } }
                    .buttonStyle(.borderedProminent)
            } else if recoveryAction == .retryTranscription {
                if meeting.source == .upload {
                    if let job = model.uploads?.queue.jobs.first(where: { $0.meetingID == meeting.id && !$0.state.isTerminal }) {
                        Button("Cancel") { Task { await model.uploads?.cancel(job.id) } }
                    } else {
                        Button("Retry transcript") { model.retryMeeting(meeting) }
                            .buttonStyle(.borderedProminent)
                    }
                } else if model.meetings?.isTranscribing == true {
                    Button("Cancel") { Task { await model.meetings?.cancel() } }
                } else {
                    Button("Retry transcript") { model.retryMeeting(meeting) }
                        .buttonStyle(.borderedProminent)
                }
            }
            Menu("More") {
                Button("Rename…") { renameTitle = meeting.title; showRename = true }
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([meetingDirectory]) }
                Menu("Export") {
                    Button("Markdown…") { export(.markdown) }
                    Button("SubRip captions…") { export(.srt) }
                    Button("Audio…") { export(.audio) }
                }
                Menu("Send to Scratchpad") {
                    ForEach(ScratchpadSendKind.allCases, id: \.self) { kind in
                        Button(kind.title) { Task { await model.sendToScratchpad(kind, meeting: meeting) } }
                            .disabled(kind.text(of: meeting) == nil)
                    }
                }
                Divider()
                Button("Delete…", role: .destructive) { showDelete = true }
            }
            .fixedSize()
        }
    }

    private var recoveryAction: MeetingRecoveryAction? {
        MeetingRecoveryPolicy.action(for: meeting)
    }

    private var transcript: some View {
        let activeSegmentID = MeetingTimeline.activeSegment(at: player.currentTime, segments: meeting.segments, isPlaying: player.isPlaying)?.id
        return Group {
            // The speaker row sits outside the lazy stack, so its open edits survive scrolling.
            VStack(alignment: .leading, spacing: LayoutTokens.spacing[0]) {
                if let error = meeting.transcriptionError {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.bvWarning).padding(LayoutTokens.spacing[1])
                }
                if meeting.segments.contains(where: { !($0.translation ?? "").isEmpty }) {
                    HStack {
                        Spacer()
                        Toggle("Show English", isOn: Binding(
                            get: { meeting.showEnglish },
                            set: { show in Task { await model.setMeetingShowEnglish(id: meeting.id, show: show) } }
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .bvFont(.footnote)
                    }
                    .padding(.horizontal, LayoutTokens.spacing[1])
                }
                MeetingSpeakersRow(meeting: meeting)
                LazyVStack(alignment: .leading, spacing: LayoutTokens.spacing[0]) {
                let segments = meeting.segments.sorted { $0.start < $1.start }
                ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                    let active = activeSegmentID == segment.id
                    ForEach(marks(from: index == 0 ? -.infinity : segments[index - 1].start, to: segment.start)) { mark in
                        markRow(mark)
                    }
                    HStack(alignment: .top, spacing: LayoutTokens.spacing[2]) {
                        Button { player.seek(to: MeetingTimeline.seekTime(for: segment)) } label: {
                            Text(clock(segment.start))
                                .bvCode(.footnote).monospacedDigit().foregroundStyle(.bvSecondary)
                                .frame(width: store.scaled(50), alignment: .leading)
                        }
                        MeetingSpeakerLineMenu(meeting: meeting, segment: segment)
                        Button { player.seek(to: MeetingTimeline.seekTime(for: segment)) } label: {
                            VStack(alignment: .leading, spacing: LayoutTokens.spacing[0]) {
                                Text(segment.text).bvFont(.reading).frame(maxWidth: store.readingWidth, alignment: .leading)
                                if meeting.showEnglish, let english = segment.translation, !english.isEmpty {
                                    Text(english).bvFont(.body).foregroundStyle(.bvSecondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, LayoutTokens.spacing[1]).padding(.vertical, LayoutTokens.spacing[0])
                    .background(citedLineIDs.contains(segment.id) ? store.theme.accent.opacity(0.24) : active ? store.theme.accent.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: LayoutTokens.controlRadius))
                    .id(segment.id)
                }
                ForEach(marks(from: segments.last?.start ?? -.infinity, to: .infinity)) { mark in
                    markRow(mark)
                }
                if meeting.segments.isEmpty {
                    EmptyState("No transcript yet", systemImage: "text.bubble", message: "Transcript lines appear as speech is processed.")
                }
                }
            }
        }
    }

    /// Marks at or after `start` and before `end`, in time order.
    private func marks(from start: TimeInterval, to end: TimeInterval) -> [MeetingMark] {
        meeting.marks.filter { $0.offset >= start && $0.offset < end }.sorted { $0.offset < $1.offset }
    }

    private func markRow(_ mark: MeetingMark) -> some View {
        Button { play(from: mark.offset) } label: {
            Label("Mark · \(clock(mark.offset))", systemImage: "bookmark.fill")
                .bvFont(.footnote)
                .foregroundStyle(.bvWarning)
                .padding(.horizontal, LayoutTokens.spacing[1]).padding(.vertical, LayoutTokens.spacing[0])
        }
        .buttonStyle(.plain)
    }

    private func play(from offset: TimeInterval) {
        player.seek(to: offset)
        if !player.isPlaying { player.togglePlayback() }
    }

    private func generatedText(_ value: String?, kind: MeetingTextKind, emptyMessage: String) -> some View {
        VStack(alignment: .leading, spacing: LayoutTokens.spacing[2]) {
            if let value, !value.isEmpty {
                if kind == .actionItems {
                    let parsed = ActionItemParser.parse(value, meetingID: meeting.id)
                    VStack(spacing: 0) {
                        ForEach(parsed.items) { item in
                            ActionItemRowView(row: ActionItemRow(item: item, doneAt: model.actionItemsDone.doneAt(item))) {
                                model.setActionItemDone(item, $0)
                            }
                        }
                    }
                    ForEach(Array(parsed.otherLines.enumerated()), id: \.offset) { _, line in
                        Text(line).bvFont(.reading).textSelection(.enabled)
                    }
                } else {
                    MarkdownDocView(text: value, onToggleTask: { _ in }, scrolls: false, pagePadding: false).bvFont(.reading)
                }
            } else {
                EmptyState(kind == .summary ? "No summary" : "No action items", systemImage: kind == .summary ? "text.alignleft" : "checklist", message: emptyMessage)
            }
            if kind == .actionItems {
                Text("Checkmarks are shared with the Action items page and kept after Regenerate when an item's text is the same.")
                    .bvFont(.footnote).foregroundStyle(.bvSecondary)
            }
            if let generationProgress {
                ProgressView(value: generationProgress.fraction) {
                    Text(generationProgress.phase == .parts ? "Summarizing part \(generationProgress.completedParts) of \(generationProgress.totalParts)" : "Combining results")
                }
            }
            if let generationError { Text(generationError).bvFont(.body).foregroundStyle(.bvWarning) }
            HStack {
                if generationTask != nil {
                    Button("Cancel") { generationTask?.cancel() }
                } else {
                    Button(value == nil || value?.isEmpty == true ? (kind == .summary ? "Generate summary" : "Generate action items") : "Regenerate") {
                        generate(kind)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(meeting.segments.isEmpty)
                    if let value, !value.isEmpty {
                        Button("Send to Scratchpad") {
                            Task { await model.sendToScratchpad(kind == .summary ? .summary : .actionItems, meeting: meeting) }
                        }
                    }
                }
            }
        }
    }

    private func generate(_ kind: MeetingTextKind) {
        generationError = nil
        generationProgress = nil
        generationTask = Task {
            defer { generationTask = nil }
            do {
                _ = try await model.generateMeetingText(id: meeting.id, kind: kind) { progress in
                    Task { @MainActor in generationProgress = progress }
                }
            } catch is CancellationError {
                generationError = nil
            } catch {
                generationError = "Could not generate text: \(error.localizedDescription)"
            }
        }
    }

    private func export(_ kind: MeetingExportKind) {
        guard kind == .audio || meeting.state == .ready else { return }
        let panel = NSSavePanel()
        switch kind {
        case .markdown:
            panel.nameFieldStringValue = "\(safeFilename(meeting.title)).md"
            panel.allowedContentTypes = [.plainText]
        case .srt:
            panel.nameFieldStringValue = "\(safeFilename(meeting.title)).srt"
            panel.allowedContentTypes = [.plainText]
        case .audio:
            panel.nameFieldStringValue = "\(safeFilename(meeting.title)).m4a"
            panel.allowedContentTypes = [.mpeg4Audio]
        }
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            switch kind {
            case .markdown: try MeetingExporter.markdown(meeting).write(to: destination, atomically: true, encoding: .utf8)
            case .srt: try MeetingExporter.srt(meeting).write(to: destination, atomically: true, encoding: .utf8)
            case .audio:
                guard let audioURL else { return }
                if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
                try FileManager.default.copyItem(at: audioURL, to: destination)
            }
        } catch {
            model.saveError = "Could not export meeting: \(error.localizedDescription)"
        }
    }

    private func safeFilename(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:")
        let cleaned = value.components(separatedBy: invalid).filter { !$0.isEmpty }.joined(separator: "-")
        return cleaned.isEmpty ? "Meeting" : cleaned
    }

    private func clock(_ value: TimeInterval) -> String {
        let whole = max(0, Int(value))
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }
}


/// The meeting's own notes on the detail page; saved 1 second after typing stops.
private struct MeetingDetailNotes: View {
    @Environment(AppearanceStore.self) private var store
    let model: AppModel
    let meeting: MeetingManifest
    @State private var draft = ""
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        ZStack(alignment: .topLeading) {
            MeetingNotesEditor(text: $draft).frame(minHeight: store.scaled(220))
            if draft.isEmpty {
                Text("No notes for this meeting.")
                    .foregroundStyle(.bvSecondary)
                    .padding(.horizontal, LayoutTokens.spacing[3])
                    .padding(.vertical, LayoutTokens.spacing[2])
                    .allowsHitTesting(false)
            }
        }
        .background(store.theme.secondaryText.opacity(0.06), in: RoundedRectangle(cornerRadius: LayoutTokens.controlRadius))
        .onAppear { draft = meeting.notes }
        .onChange(of: meeting.notes) { _, notes in
            if saveTask == nil { draft = notes }
        }
        .onChange(of: draft) { _, notes in
            guard notes != meeting.notes else { return }
            saveTask?.cancel()
            saveTask = Task {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                saveTask = nil
                await model.setMeetingNotes(id: meeting.id, notes: notes)
            }
        }
        .onDisappear {
            guard saveTask != nil else { return }
            saveTask?.cancel()
            saveTask = nil
            let id = meeting.id
            let notes = draft
            Task { await model.setMeetingNotes(id: id, notes: notes) }
        }
    }
}
