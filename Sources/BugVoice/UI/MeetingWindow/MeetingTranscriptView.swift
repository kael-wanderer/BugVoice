import AppKit
import SwiftUI
import VoiceCore

/// Live transcript lines and marks, newest at the bottom.
struct MeetingTranscriptView: View {
    let segments: [MeetingSegment]
    let marks: [MeetingMark]
    let elapsed: TimeInterval
    let isListening: Bool
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
            .filter { needle.isEmpty || $0.text.localizedCaseInsensitiveContains(needle) }
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
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
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
                    .foregroundStyle(segment.track == .mic ? Color.accentColor : .secondary)
                    .frame(width: 46, alignment: .leading)
                Text(segment.text).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
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

    private func copy() {
        let text = segments.sorted { $0.start < $1.start }.map(MeetingPromptLines.line).joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
