import AppKit
import BugVoiceMac
import SwiftUI
import UniformTypeIdentifiers
import VoiceCore

struct UploadRing: View {
    @Environment(AppearanceStore.self) private var store
    let progress: Double?

    var body: some View {
        Group {
            if let progress {
                ZStack {
                    Circle().stroke(store.theme.secondaryText.opacity(0.2), lineWidth: 2)
                    Circle().trim(from: 0, to: min(1, max(0, progress)))
                        .stroke(store.theme.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
            } else {
                ProgressView().controlSize(.mini)
            }
        }
        .frame(width: 16, height: 16)
        .accessibilityLabel("Upload progress")
    }
}

struct UploadPage: View {
    @Environment(AppearanceStore.self) private var store
    @Bindable var model: AppModel
    @State private var targeted = false
    @State private var page = 0

    private static let pageSize = 5

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LayoutTokens.spacing[4]) {
                Text("Upload").bvFont(.title2)
                if let controller = model.uploads {
                    VStack(spacing: LayoutTokens.spacing[3]) {
                        if controller.active == nil {
                            Text("Upload a recording").bvFont(.title2)
                            Button(speechLabel) { model.openSpeechSettings() }
                                .buttonStyle(.link)
                        }
                        if controller.probing {
                            ProgressView()
                        }
                        if let error = controller.draftError {
                            errorCard(
                                error, name: controller.errorFileName ?? "", meetingID: nil, controller: controller)
                        }
                        if !controller.drafts.isEmpty {
                            ForEach(controller.drafts) { draft in
                                VStack(spacing: LayoutTokens.spacing[1]) {
                                    metadataCard(
                                        name: draft.metadata.fileName, kind: draft.metadata.kind,
                                        duration: draft.metadata.duration, bytes: draft.metadata.byteSize)
                                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 8) {
                                        GridRow {
                                            Text("Save to").bvFont(.footnote).foregroundStyle(.bvSecondary)
                                            HStack(spacing: LayoutTokens.spacing[1]) {
                                                FolderPicker(model: model, folderID: draft.labels.folderID) { id in
                                                    controller.setDraftLabels(draft.id, ItemLabels(folderID: id, tags: draft.labels.tags))
                                                }
                                                if draft.labels.folderID != nil, draft.labels.folderID == model.library.lastUploadFolderID {
                                                    Text("Last used").bvFont(.footnote).foregroundStyle(.bvSecondary)
                                                }
                                            }
                                        }
                                        GridRow {
                                            Text("Tags").bvFont(.footnote).foregroundStyle(.bvSecondary)
                                            TagField(tags: draft.labels.tags, catalog: model.allTagCatalog, noun: "meeting") { tags in
                                                controller.setDraftLabels(draft.id, ItemLabels(folderID: draft.labels.folderID, tags: tags))
                                            }
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, LayoutTokens.spacing[3])
                                    if controller.drafts.count > 1, draft.id == controller.drafts.first?.id {
                                        Button("Apply to all") { controller.applyFirstLabelsToAll() }
                                    }
                                }
                            }
                            HStack {
                                Button("Cancel") { controller.clearDraft() }
                                Button("Transcribe") { controller.submit() }
                                    .buttonStyle(.borderedProminent)
                            }
                            Text(
                                "Only the audio is kept, as a small audio.m4a in the meeting folder. The video stays where it is."
                            )
                            .bvFont(.footnote).foregroundStyle(.bvSecondary).multilineTextAlignment(.center)
                        }
                        if let active = controller.active {
                            progressCard(active, controller: controller)
                        }
                        dropZone(compact: !controller.queue.jobs.isEmpty)
                        if controller.queue.jobs.isEmpty && controller.drafts.isEmpty {
                            Text(
                                "You can drop several files; they are transcribed one at a time. Uploads appear in Meetings when they are ready."
                            )
                            .bvFont(.footnote).foregroundStyle(.bvSecondary).multilineTextAlignment(.center)
                        }
                        if !controller.queue.jobs.isEmpty {
                            // Newest first, so older files sit on later pages.
                            let jobs = Array(controller.queue.jobs.reversed())
                            let paging = ListPaging(count: jobs.count, pageSize: Self.pageSize)
                            let current = paging.clamp(page)
                            HStack {
                                Text(jobs.count == 1 ? "1 file" : "\(jobs.count) files")
                                Spacer()
                                Button("Clear history") {
                                    controller.clearFinished()
                                    page = 0
                                }
                                .help("Removes finished files from this list. Their meetings stay in Meetings.")
                            }
                            .bvFont(.footnote).foregroundStyle(.bvSecondary)
                            ForEach(jobs[paging.range(page: current)]) { job in
                                queueRow(job, controller: controller)
                            }
                            if paging.pageCount > 1 {
                                HStack {
                                    Button("Newer") { page = current - 1 }
                                        .disabled(current == 0)
                                    Text("Page \(current + 1) of \(paging.pageCount)")
                                        .bvFont(.footnote).foregroundStyle(.bvSecondary)
                                    Button("Older") { page = current + 1 }
                                        .disabled(current == paging.pageCount - 1)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: store.scaled(560))
                    .frame(maxWidth: .infinity)
                } else {
                    ProgressView()
                }
            }
            .padding(LayoutTokens.spacing[4])
            .frame(maxWidth: .infinity, minHeight: 500, alignment: .topLeading)
        }
        .background(targeted ? store.theme.accent.opacity(0.06) : store.theme.background)
        .contentShape(Rectangle())
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $targeted) { providers in
            Task {
                var urls: [URL] = []
                for provider in providers {
                    if let url = await loadURL(provider) { urls.append(url) }
                }
                await model.uploads?.choose(urls)
            }
            return true
        }
    }

    private var speechLabel: String {
        let speech = model.settings.speech
        if speech.engine == .whisperKit {
            return "Transcribed on this Mac with \(speech.whisperModel)"
        }
        return
            "Transcribed by \(URL(string: speech.serverBaseURL)?.host ?? speech.serverBaseURL) with \(speech.serverModel)"
    }

    private func browse() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = MediaAudioDecoder.extensions.compactMap {
            UTType(filenameExtension: $0)
        }
        panel.allowsOtherFileTypes = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        Task { await model.uploads?.choose(panel.urls) }
    }

    private func loadURL(_ provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let value = item as? URL {
                    url = value
                } else {
                    url = nil
                }
                continuation.resume(returning: url)
            }
        }
    }

    private func dropZone(compact: Bool) -> some View {
        Button(action: browse) {
            VStack(spacing: LayoutTokens.spacing[2]) {
                if !compact { Image(systemName: "square.and.arrow.up").bvFont(.stat) }
                Text(
                    compact
                        ? "Drop more files, or click to browse"
                        : "Drop an audio or video file, or click to browse"
                )
                .fontWeight(.medium)
                Text("MP3, WAV, M4A, AIFF, CAF, MP4, MOV, M4V")
                    .bvFont(.footnote).foregroundStyle(.bvSecondary)
            }
            .padding(compact ? LayoutTokens.spacing[3] : LayoutTokens.spacing[5])
            .frame(maxWidth: .infinity)
            .background(store.theme.card, in: RoundedRectangle(cornerRadius: LayoutTokens.largeCardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: LayoutTokens.largeCardRadius).strokeBorder(
                    store.theme.secondaryText.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [5])))
        }
        .buttonStyle(.plain)
        .disabled(model.uploads?.accepting != true)
    }

    private func metadataCard(name: String, kind: UploadMediaKind, duration: Double, bytes: Int64, addedBy: String? = nil)
        -> some View
    {
        HStack(spacing: LayoutTokens.spacing[2]) {
            Image(systemName: kind == .video ? "film" : "waveform")
                .bvFont(.title2).foregroundStyle(.bvAccent)
            VStack(alignment: .leading, spacing: LayoutTokens.spacing[0]) {
                Text(name).fontWeight(.medium).lineLimit(2)
                if let addedBy { Text("Added by \(addedBy)").bvFont(.footnote).foregroundStyle(.bvSecondary) }
                Text(
                    "\(kind.rawValue) · \(clock(duration)) · \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))"
                )
                .bvFont(.footnote).foregroundStyle(.bvSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(LayoutTokens.spacing[3])
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(store.theme.card, in: RoundedRectangle(cornerRadius: LayoutTokens.largeCardRadius))
    }

    private func progressCard(_ job: UploadJob, controller: UploadController) -> some View {
        VStack(spacing: LayoutTokens.spacing[2]) {
            if let value = job.progress {
                ProgressView(value: value)
            } else {
                ProgressView()
            }
            Text(
                job.state == .reading
                    ? "Reading file…"
                    : (model.settings.speech.engine == .whisperKit
                        ? "Transcribing locally…" : "Transcribing…")
            )
            .bvFont(.bodyStrong)
            Text(job.fileName + (job.progress.map { " · \(Int($0 * 100))%" } ?? ""))
                .bvFont(.footnote).foregroundStyle(.bvSecondary)
            if let addedBy = job.addedBy {
                Text("Added by \(addedBy)").bvFont(.footnote).foregroundStyle(.bvSecondary)
            }
            HStack(spacing: LayoutTokens.spacing[3]) {
                Text("1 Reading file").foregroundStyle(job.state == .reading ? store.theme.text : store.theme.secondaryText)
                Text("2 Transcribing locally").foregroundStyle(
                    job.state == .transcribing ? store.theme.text : store.theme.secondaryText)
            }
            .bvFont(.footnote)
            if controller.waitingForMeeting {
                Text("Waiting for meeting to finish").bvFont(.footnote)
            }
            Button("Cancel") { Task { await controller.cancel(job.id) } }
            Text(
                "You can leave this page; the Upload item in the sidebar shows progress. If a meeting starts, the upload pauses and continues when the meeting stops. If BugVoice quits while transcribing, it continues on next launch."
            )
            .bvFont(.footnote).foregroundStyle(.bvSecondary).multilineTextAlignment(.center)
        }
        .padding(LayoutTokens.spacing[4])
        .frame(maxWidth: .infinity)
        .background(store.theme.card, in: RoundedRectangle(cornerRadius: LayoutTokens.largeCardRadius))
    }

    @ViewBuilder
    private func queueRow(_ job: UploadJob, controller: UploadController) -> some View {
        if job.state == .failed {
            errorCard(
                job.errorMessage ?? UploadFailure.unreadable.localizedDescription, name: job.fileName,
                meetingID: job.meetingID, controller: controller)
        } else {
            VStack(alignment: .leading, spacing: LayoutTokens.spacing[1]) {
                metadataCard(
                    name: job.fileName, kind: job.kind, duration: job.duration, bytes: job.byteSize,
                    addedBy: job.addedBy)
                HStack {
                    switch job.state {
                    case .queued:
                        Text("Waiting")
                        Spacer()
                        Button("Cancel") { Task { await controller.cancel(job.id) } }
                    case .reading:
                        Text("Reading file…")
                    case .transcribing:
                        Text("Transcribing \(Int((job.progress ?? 0) * 100))%")
                    case .ready:
                        Text("Ready")
                        if let id = job.meetingID {
                            if let meeting = model.meetingManifests.first(where: { $0.id == id }) {
                                Text(
                                    "\(meeting.title) · \(clock(meeting.duration)) · \(meeting.segments.count) lines")
                            }
                            Spacer()
                            Button("Open in Meetings") { controller.open(id) }
                        }
                        Button("Upload another", action: browse)
                    case .cancelled:
                        Text("Cancelled")
                    case .failed:
                        EmptyView()
                    }
                }
                .bvFont(.footnote)
            }
        }
    }

    private func errorCard(
        _ error: String, name: String, meetingID: MeetingID?, controller: UploadController
    ) -> some View {
        VStack(spacing: LayoutTokens.spacing[2]) {
            Text(error).bvFont(.bodyStrong).multilineTextAlignment(.center)
            Text(name).bvFont(.footnote).foregroundStyle(.bvSecondary)
            HStack {
                Button("Choose another file", action: browse)
                if let meetingID {
                    Button("Open in Meetings") { controller.open(meetingID) }
                }
            }
        }
        .padding(LayoutTokens.spacing[4])
        .frame(maxWidth: .infinity)
        .background(store.theme.card, in: RoundedRectangle(cornerRadius: LayoutTokens.largeCardRadius))
    }

    private func clock(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
