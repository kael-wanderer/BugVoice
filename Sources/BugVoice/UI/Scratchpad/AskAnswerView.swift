import AppKit
import SwiftUI
import VoiceCore

struct AskAnswerView: View {
    @Bindable var assistant: ScratchpadAssistant
    let model: AppModel
    @State private var selection: AskCitationSelection?

    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.width < 700
            HStack(spacing: 0) {
                ZStack {
                    answer.opacity(compact && selection != nil ? 0 : 1)
                        .allowsHitTesting(!(compact && selection != nil))
                        .accessibilityHidden(compact && selection != nil)
                    if compact, let selection {
                        CitationPanel(model: model, selection: selection, compact: true) { self.selection = nil }
                            .id(selection.id)
                    }
                }.frame(maxWidth: .infinity)
                if !compact, let selection {
                    Divider()
                    CitationPanel(model: model, selection: selection, compact: false) { self.selection = nil }
                        .id(selection.id).frame(maxWidth: .infinity)
                }
            }
        }
        .onChange(of: assistant.askStep) { _, step in if step != nil { selection = nil } }
    }

    private var answer: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let step = assistant.askStep { progress(step) }
                else {
                    Button {
                        assistant.backToNote()
                    } label: {
                        Label("Back to note", systemImage: "chevron.left")
                    }
                    .buttonStyle(.link)
                    if let error = assistant.askError { Text(error).foregroundStyle(.orange) }
                    if let saved = assistant.askResult {
                        Text(saved.question).font(.callout).foregroundStyle(.secondary)
                        switch saved.outcome {
                        case .answered(let result, let reason):
                            if let reason { wordOnly(reason) }
                            Text(result.answer).textSelection(.enabled)
                            Text("Searched: \(model.askScopeTitle(saved.scope)) · \(matched(result))")
                                .font(.caption).foregroundStyle(.secondary)
                            ForEach(result.cards) { card in cardView(card) }
                            HStack {
                                Button("Copy") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(AskMarkdown.render(question: saved.question, result: result, calendar: .current), forType: .string)
                                }
                                Button("New note") { Task { await model.newNoteFromAsk(question: saved.question, result: result) } }
                            }
                        case .nothingFound(let reason):
                            if let reason { wordOnly(reason) }
                            Text("Nothing about this in your notes or meetings.")
                            Text("Searched: \(model.askScopeTitle(saved.scope)) · \(saved.counts.meetings) meetings, \(saved.counts.notes) notes, \(saved.counts.dictations) dictations")
                                .font(.caption).foregroundStyle(.secondary)
                        case .failed(let failure): Text(Self.failureText(failure)).foregroundStyle(.orange)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }

    private func progress(_ step: AskStep) -> some View {
        let index: Int = switch step { case .understanding: 0; case .searching: 1; case .reading: 2 }
        let labels = [index == 0 ? "Understanding the question…" : "Understanding the question", searchText(step), readingText(step)]
        return VStack(alignment: .leading, spacing: 14) {
            ForEach(0..<3) { row in
                HStack(spacing: 10) {
                    if row < index { Image(systemName: "checkmark").foregroundStyle(.green) }
                    else if row == index { ProgressView().controlSize(.small) }
                    else { Image(systemName: "circle").foregroundStyle(.tertiary) }
                    Text(labels[row]).foregroundStyle(row > index ? .secondary : .primary)
                }
            }
        }
    }

    private func searchText(_ step: AskStep) -> String {
        if case .searching(let m, let n, let d) = step { return "Searching \(m) meetings, \(n) notes, \(d) dictations…" }
        if case .reading = step {
            let counts = assistant.searchedCounts
            return "Searching \(counts.meetings) meetings, \(counts.notes) notes, \(counts.dictations) dictations"
        }
        return "Searching"
    }
    private func readingText(_ step: AskStep) -> String {
        if case .reading(let count) = step { return "Reading \(count) passages…" }
        return "Reading passages"
    }

    private func wordOnly(_ reason: WordOnlyReason) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(reason == .noModel
                 ? "Word search only: no embedding model is set up. Results may miss other languages."
                 : "Word search only: the embedding model is not answering.")
            if reason == .noModel {
                Button("Set up in Settings") { model.settingsTab = .models; model.openMainWindow(.settings) }
            }
        }.font(.callout).padding(10).background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    private func cardView(_ card: AskCard) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(card.info.title).fontWeight(.semibold)
                Text(badge(card.info.kind)).font(.caption2).padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.1), in: Capsule())
            }
            Text(metadata(card.info)).font(.caption).foregroundStyle(.secondary)
            ForEach(card.citations) { citation in
                VStack(alignment: .leading, spacing: 5) {
                    if let start = citation.start, let end = citation.end {
                        Button("▶ \(Self.clock(start))–\(Self.clock(end))") {
                            selection = AskCitationSelection(card: card, citation: citation)
                        }
                    } else if case .note(let id) = card.source {
                        Button("Open note") { Task { await model.openNoteInWindow(id) } }
                    } else if case .meeting = card.source {
                        Text(partTitle(citation.part)).font(.caption).foregroundStyle(.secondary)
                    }
                    Text(citation.lines.first.map { line in (line.speaker.map { "\($0): " } ?? "") + "\"\(line.text)\"" } ?? "")
                        .lineLimit(2).textSelection(.enabled)
                }
            }
            if case .meeting(let id) = card.source, let citation = card.citations.first {
                Button("Open in Meetings") {
                    selection = nil
                    model.openAskMeeting(id: id, citation: citation)
                }
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(selection?.card.id == card.id ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: selection?.card.id == card.id ? 2 : 1))
    }

    private func badge(_ kind: AskItemInfo.Kind) -> String {
        switch kind { case .meeting: "Meeting"; case .uploaded: "Uploaded"; case .note: "Note"; case .dictation: "Dictation" }
    }
    private func metadata(_ info: AskItemInfo) -> String {
        var parts = [info.date.formatted(date: .abbreviated, time: info.kind == .dictation ? .shortened : .omitted)]
        if !info.people.isEmpty { parts.append(info.people.joined(separator: ", ")) }
        if let folder = info.folderName { parts.append(folder) }
        return parts.joined(separator: " · ")
    }
    private func matched(_ result: AskResult) -> String {
        let recordings = result.cards.filter { $0.info.kind == .meeting || $0.info.kind == .uploaded }.count
        let notes = result.cards.filter { $0.info.kind == .note }.count
        let dictations = result.cards.filter { $0.info.kind == .dictation }.count
        var parts = ["\(recordings) \(recordings == 1 ? "recording" : "recordings")", "\(notes) \(notes == 1 ? "note" : "notes")"]
        if dictations > 0 { parts.append("\(dictations) \(dictations == 1 ? "dictation" : "dictations")") }
        return parts.joined(separator: ", ") + " matched"
    }
    private func partTitle(_ part: AskPart) -> String {
        switch part { case .summary: "Summary"; case .actionItems: "Action items"; case .myNotes: "My notes"; default: "" }
    }
    static func clock(_ time: Double) -> String { String(format: "%02d:%02d", max(0, Int(time)) / 60, max(0, Int(time)) % 60) }
    static func failureText(_ failure: AskFailure) -> String {
        switch failure {
        case .model: "Ask could not reach the model. Try again."
        case .unreadable: "Ask could not read the model's answer. Try again."
        case .tooSlow: "Ask took too long. Try a smaller scope."
        }
    }
}

struct AskMeetingPicker: View {
    let meetings: [MeetingManifest]
    let select: (MeetingID) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("A meeting…").font(.headline)
            TextField("Search meetings", text: $query).textFieldStyle(.roundedBorder)
            List {
                ForEach(meetings.filter { meeting in
                    meeting.state == .ready && (query.isEmpty || AskText.fold(meeting.title + " " + meeting.startedAt.formatted(date: .abbreviated, time: .omitted)).contains(AskText.fold(query)))
                }.sorted { $0.startedAt > $1.startedAt }) { meeting in
                    Button { select(meeting.id) } label: {
                        VStack(alignment: .leading) {
                            Text(meeting.title)
                            Text(meeting.startedAt.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary)
                        }
                    }.buttonStyle(.plain)
                }
            }
            HStack { Spacer(); Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction) }
        }.padding(20).frame(width: 380, height: 420)
    }
}
