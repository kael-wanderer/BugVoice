import AppKit
import SwiftUI
import VoiceCore

/// Live transcript lines and marks, newest at the bottom.
struct MeetingTranscriptView: View {
    let segments: [MeetingSegment]
    let speakers: [MeetingSpeaker]
    let marks: [MeetingMark]
    let elapsed: TimeInterval
    let isListening: Bool
    /// Show English is offered for this meeting.
    let offersEnglish: Bool
    let showEnglish: Bool
    let englishNeedsModel: Bool
    let onShowEnglish: (Bool) -> Void
    @State private var query = ""
    @State private var followNewest = true

    private enum Row: Identifiable {
        case line(MeetingSegment)
        case mark(MeetingMark)

        var id: String {
            switch self {
            case .line(let segment): "s-\(segment.id)"
            case .mark(let mark): "m-\(mark.id)"
            }
        }

        var time: TimeInterval {
            switch self {
            case .line(let segment): segment.start
            case .mark(let mark): mark.offset
            }
        }
    }

    private var rows: [Row] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        let lines = segments
            .filter {
                needle.isEmpty || $0.speaker.localizedCaseInsensitiveContains(needle) || $0.text.localizedCaseInsensitiveContains(needle)
                    || (showEnglish && ($0.translation?.localizedCaseInsensitiveContains(needle) ?? false))
            }
            .map(Row.line)
        let markRows = needle.isEmpty ? marks.map(Row.mark) : []
        return (lines + markRows).sorted { $0.time < $1.time }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(MeetingTimeText.text(elapsed)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                TextField("Search", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                Button("Copy") { copy() }
                    .controlSize(.small)
                    .disabled(segments.isEmpty)
                if offersEnglish {
                    Toggle("Show English", isOn: Binding(get: { showEnglish }, set: { onShowEnglish($0) }))
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .font(.caption)
                        .fixedSize()
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            if offersEnglish && showEnglish && englishNeedsModel {
                Text("English needs a Meetings model.")
                    .font(.caption).foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
            }
            Divider()
            ZStack(alignment: .bottomTrailing) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(rows) { row in
                                rowView(row).id(row.id)
                            }
                            if isListening {
                                Text("Listening…").font(.callout).foregroundStyle(.secondary)
                            }
                            Color.clear.frame(height: 1).id("bottom")
                        }
                        .padding(12)
                    }
                    .onScrollGeometryChange(for: Bool.self) { geometry in
                        geometry.contentOffset.y + geometry.containerSize.height >= geometry.contentSize.height - 24
                    } action: { _, atBottom in
                        followNewest = atBottom
                    }
                    .onChange(of: segments.count) { _, _ in
                        if followNewest { proxy.scrollTo("bottom", anchor: .bottom) }
                    }
                    .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
                    .overlay(alignment: .bottomTrailing) {
                        if !followNewest {
                            Button("Newest") { proxy.scrollTo("bottom", anchor: .bottom) }
                                .controlSize(.small)
                                .padding(10)
                        }
                    }
                }
                if segments.isEmpty && !isListening {
                    Text("No transcript lines.").foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    @ViewBuilder private func rowView(_ row: Row) -> some View {
        switch row {
        case .line(let segment):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(MeetingTimeText.text(segment.start))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .leading)
                Text(segment.speaker).font(.caption.weight(.semibold))
                    .foregroundStyle(speakerColor(segment))
                    .frame(width: 62, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text(segment.text)
                    if let english = english(segment) {
                        Text(english).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            }
        case .mark(let mark):
            HStack(spacing: 6) {
                Image(systemName: "bookmark.fill")
                Text("Mark · \(MeetingTimeText.text(mark.offset))")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.orange)
        }
    }

    private func speakerColor(_ segment: MeetingSegment) -> Color {
        if let speaker = speakers.first(where: { $0.id == segment.speakerID }) {
            return SpeakerColors.color(speaker.colorIndex)
        }
        return segment.track == .mic ? .accentColor : .secondary
    }

    /// The English shown under a line, or nil.
    private func english(_ segment: MeetingSegment) -> String? {
        guard showEnglish, let english = segment.translation, !english.isEmpty else { return nil }
        return english
    }

    private func copy() {
        let text = segments.sorted { $0.start < $1.start }.map { segment in
            MeetingPromptLines.line(segment) + (english(segment).map { "\n  English: \($0)" } ?? "")
        }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
