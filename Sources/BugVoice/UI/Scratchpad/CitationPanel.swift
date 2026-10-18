import SwiftUI
import VoiceCore

struct AskCitationSelection: Identifiable, Equatable {
    let card: AskCard
    let citation: AskCitation
    var id: String { card.id + citation.id }
    var meetingID: MeetingID? {
        if case .meeting(let id) = card.source { return id }
        return nil
    }
}

struct CitationPanel: View {
    @Environment(AppearanceStore.self) private var store
    let model: AppModel
    let selection: AskCitationSelection
    let compact: Bool
    let close: () -> Void
    @State private var pauseRequest: UInt64 = 0
    @State private var translating = true
    @State private var translationFailed = false

    private var meeting: MeetingManifest? { model.meetingManifests.first { $0.id == selection.meetingID } }
    private var citedIDs: Set<String> { Set(selection.citation.lines.map(\.id)) }
    private var context: [MeetingSegment] {
        guard let meeting else { return [] }
        let sorted = meeting.segments.sorted { $0.start < $1.start }
        let indices = sorted.indices.filter { citedIDs.contains(sorted[$0].id) }
        guard let first = indices.first, let last = indices.last else { return [] }
        return Array(sorted[max(0, first - 1)...min(sorted.count - 1, last + 1)])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutTokens.spacing[2]) {
            HStack {
                if compact { Button("‹ Answer", action: close) }
                Spacer()
                Button("Close", action: close).keyboardShortcut(.escape, modifiers: [])
            }
            if let meeting {
                Text("\(meeting.title) · \(AskAnswerView.clock(selection.citation.start ?? 0))–\(AskAnswerView.clock(selection.citation.end ?? 0))")
                    .bvFont(.bodyStrong)
                Text(meeting.startedAt.formatted(date: .abbreviated, time: .omitted) + " · " + people(meeting))
                    .bvFont(.footnote).foregroundStyle(.bvSecondary)
                if let url = audioURL(meeting.id), let start = selection.citation.start, let end = selection.citation.end {
                    CitationPlayer(url: url, start: start, end: end, pauseRequest: pauseRequest).id(selection.id)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: LayoutTokens.spacing[1]) {
                        ForEach(context) { line in
                            VStack(alignment: .leading, spacing: LayoutTokens.spacing[0]) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(AskAnswerView.clock(line.start)).bvCode(.footnote).monospacedDigit().foregroundStyle(.bvSecondary)
                                    Text(line.speaker).bvFont(.body)
                                }
                                Text(line.text).textSelection(.enabled)
                                if let english = line.translation {
                                    if !english.isEmpty { Text(english).bvFont(.body).foregroundStyle(.bvSecondary).textSelection(.enabled) }
                                } else if translating {
                                    Text("Translating…").bvFont(.body).foregroundStyle(.bvSecondary)
                                } else if translationFailed {
                                    Text("Translation unavailable").bvFont(.body).foregroundStyle(.bvSecondary)
                                }
                            }
                            .padding(LayoutTokens.spacing[1]).frame(maxWidth: .infinity, alignment: .leading)
                            .background(citedIDs.contains(line.id) ? store.theme.accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: LayoutTokens.controlRadius))
                        }
                    }
                }
                Button("Open in Meetings") {
                    pauseRequest &+= 1
                    model.openAskMeeting(id: meeting.id, citation: selection.citation)
                }
            } else {
                Text("This meeting was deleted.")
                Spacer()
            }
        }
        .padding(LayoutTokens.spacing[2]).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(store.theme.background)
        .task(id: selection.id) {
            translating = true
            translationFailed = false
            await model.reloadMeetings()
            guard !Task.isCancelled, let id = selection.meetingID, meeting != nil else { translating = false; return }
            let result = await model.translateCitation(meetingID: id, lineIDs: Set(context.map(\.id)))
            guard !Task.isCancelled else { return }
            translationFailed = result == nil || context.contains { $0.translation == nil }
            translating = false
        }
    }

    private func people(_ meeting: MeetingManifest) -> String {
        var labels: [String] = []
        for segment in meeting.segments where !labels.contains(segment.speaker) { labels.append(segment.speaker) }
        return labels.joined(separator: ", ")
    }
    private func audioURL(_ id: MeetingID) -> URL? {
        let url = model.paths.meetings.appendingPathComponent(id.rawValue).appendingPathComponent("audio.m4a")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}
