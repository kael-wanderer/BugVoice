import AppKit
import SwiftUI
import UniformTypeIdentifiers
import VoiceCore

private enum MeetingDetailTab: String, CaseIterable {
    case transcript = "Transcript"
    case summary = "Summary"
    case actionItems = "Action items"
}

private enum MeetingExportKind {
    case markdown, srt, audio
}

struct MeetingsPage: View {
    @Bindable var model: AppModel
    @State private var player = MeetingPlayerModel()
    @State private var pendingDelete: MeetingManifest?
    @State private var pendingRename: MeetingManifest?
    @State private var renameTitle = ""
    @State private var managingFolders = false
    @State private var tagEditMeetingID: MeetingID?

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
                .frame(minWidth: 250, idealWidth: 285, maxWidth: 340)
            Divider()
            if let meeting = model.selectedMeeting {
                MeetingDetails(model: model, meeting: meeting, player: player)
            } else {
                ContentUnavailableView("No meeting selected", systemImage: "waveform.path", description: Text("Choose a meeting or start a recording."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            await model.reloadMeetings()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                await model.reloadMeetings()
            }
        }
    }

    private var library: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Meetings").font(.title2.weight(.semibold))
                Spacer()
                if model.meetings?.isRecording == true || model.meetings?.isPaused == true {
                    Button("Stop") { Task { await model.meetings?.stop(); await model.reloadMeetings() } }
                } else if model.meetings?.isTranscribing == true {
                    Label("Transcribing…", systemImage: "hourglass")
                } else {
                    Button { Task { await model.meetings?.start() } } label: { Image(systemName: "record.circle") }
                        .buttonStyle(.borderedProminent)
                        .help("Start meeting recording")
                }
            }
            HStack(spacing: 6) {
                FolderFilterMenu(
                    model: model,
                    filter: Binding(get: { model.meetingsFolderFilter }, set: { model.meetingsFolderFilter = $0 }),
                    counts: LibraryProjection.counts(model.meetingManifests, known: model.library.knownIDs),
                    allTitle: "All meetings",
                    onManage: { managingFolders = true }
                )
                TagFilterBar(catalog: model.meetingTagCatalog, selected: $model.meetingTagFilter)
                Spacer(minLength: 0)
            }
            TextField("Search meetings", text: $model.meetingSearchQuery)
                .textFieldStyle(.roundedBorder)
            if model.meetingManifests.isEmpty {
                ContentUnavailableView("No meetings yet", systemImage: "waveform.path", description: Text("Record a meeting to see its transcript here."))
            } else if groups.isEmpty {
                ContentUnavailableView("No matching meetings", systemImage: "magnifyingglass", description: Text("Try a different title or transcript search."))
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(groups) { group in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(group.label.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
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
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(14)
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
        .sheet(isPresented: $managingFolders) { ManageFoldersSheet(model: model) }
        .sheet(item: $pendingRename) { meeting in
            MeetingRenameSheet(model: model, id: meeting.id, title: $renameTitle) { pendingRename = nil }
        }
    }
}

private struct MeetingRenameSheet: View {
    let model: AppModel
    let id: MeetingID
    @Binding var title: String
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rename meeting").font(.headline)
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
        .padding(20).frame(width: 360)
    }
}

private struct MeetingListRow: View {
    let meeting: MeetingManifest
    let folderName: String?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(meeting.title).font(.body.weight(.medium)).lineLimit(1)
                    if meeting.source == .upload {
                        Text("Uploaded")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                    }
                    Spacer(minLength: 3)
                    Text(status).font(.caption).foregroundStyle(meeting.state == .failed ? .orange : .secondary)
                }
                Text(meeting.startedAt.formatted(date: .omitted, time: .shortened) + " · " + clock(meeting.duration))
                    .font(.caption).foregroundStyle(.secondary)
                if folderName != nil || !meeting.tags.isEmpty {
                    HStack(spacing: 4) {
                        if let folderName {
                            Label(folderName, systemImage: "folder").font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(meeting.tags.prefix(3), id: \.self) { TagChip(name: $0) }
                        if meeting.tags.count > 3 {
                            Text("+\(meeting.tags.count - 3)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if let line = meeting.segments.last?.text, !line.isEmpty {
                    Text(line).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Color.accentColor.opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
            // Make the whole card clickable, not only the drawn text.
            .contentShape(RoundedRectangle(cornerRadius: 8))
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
    @Bindable var model: AppModel
    let meeting: MeetingManifest
    @Bindable var player: MeetingPlayerModel
    @State private var tab: MeetingDetailTab = .transcript
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
        VStack(alignment: .leading, spacing: 12) {
            header
            Text(
                meeting.startedAt.formatted(date: .long, time: .shortened)
                    + " · " + clock(meeting.duration)
                    + (meeting.sourceFileName.map { " · from \($0)" } ?? "")
            )
            .font(.callout)
            .foregroundStyle(.secondary)
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
                MeetingPlayer(audioURL: audioURL, model: player)
                    .padding(.vertical, 4)
            } else {
                Label(meeting.state == .recording || meeting.state == .paused ? "Audio is recording" : "Audio is unavailable", systemImage: "waveform")
                    .foregroundStyle(.secondary)
            }
            Picker("Meeting details", selection: $tab) {
                ForEach(MeetingDetailTab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            Group {
                switch tab {
                case .transcript: transcript
                case .summary: generatedText(meeting.summary, kind: .summary, emptyMessage: "Generate a summary from this transcript.")
                case .actionItems: generatedText(meeting.actionItems, kind: .actionItems, emptyMessage: "Find the action items discussed in this meeting.")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(20)
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
            Text(meeting.title).font(.title2.weight(.semibold)).lineLimit(2)
            if meeting.source == .upload {
                Text("Uploaded")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
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
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 3) {
                if let error = meeting.transcriptionError {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).padding(8)
                }
                ForEach(meeting.segments.sorted { $0.start < $1.start }) { segment in
                    let active = activeSegmentID == segment.id
                    Button { player.seek(to: MeetingTimeline.seekTime(for: segment)) } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(clock(segment.start)) – \(clock(segment.end))")
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 108, alignment: .leading)
                            Text(segment.speaker).font(.caption.weight(.semibold)).frame(width: 60, alignment: .leading)
                            Text(segment.text).font(.body).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 9).padding(.vertical, 7)
                        .background(active ? Color.accentColor.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
                if meeting.segments.isEmpty {
                    ContentUnavailableView("No transcript yet", systemImage: "text.bubble", description: Text("Transcript lines appear as speech is processed."))
                }
            }
        }
    }

    private func generatedText(_ value: String?, kind: MeetingTextKind, emptyMessage: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let value, !value.isEmpty {
                ScrollView { Text(value).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }
            } else {
                ContentUnavailableView(kind == .summary ? "No summary" : "No action items", systemImage: kind == .summary ? "text.alignleft" : "checklist", description: Text(emptyMessage))
            }
            if let generationProgress {
                ProgressView(value: generationProgress.fraction) {
                    Text(generationProgress.phase == .parts ? "Summarizing part \(generationProgress.completedParts) of \(generationProgress.totalParts)" : "Combining results")
                }
            }
            if let generationError { Text(generationError).font(.callout).foregroundStyle(.orange) }
            HStack {
                if generationTask != nil {
                    Button("Cancel") { generationTask?.cancel() }
                } else {
                    Button(value == nil || value?.isEmpty == true ? (kind == .summary ? "Generate summary" : "Generate action items") : "Regenerate") {
                        generate(kind)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(meeting.segments.isEmpty)
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
