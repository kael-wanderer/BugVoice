import Foundation

public enum MeetingExporter {
    public static func srt(_ meeting: MeetingManifest) -> String {
        ordered(meeting.segments).enumerated().map { index, segment in
            "\(index + 1)\n\(srtTime(segment.start)) --> \(srtTime(segment.end))\n\(segment.speaker): \(flattenNewlines(segment.text))"
        }.joined(separator: "\n\n")
    }

    public static func markdown(_ meeting: MeetingManifest) -> String {
        var lines = ["# \(meeting.title)", "", dateLine(meeting.startedAt), ""]
        if let summary = meeting.summary, !summary.isEmpty {
            lines += ["## Summary", summary, ""]
        }
        let notes = meeting.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !notes.isEmpty {
            lines += ["## My notes", notes, ""]
        }
        if let actionItems = meeting.actionItems, !actionItems.isEmpty {
            lines += ["## Action items", actionItems, ""]
        }
        lines.append("## Transcript")
        for segment in ordered(meeting.segments) {
            lines.append("\(displayTime(segment.start)) | \(segment.speaker) | \(flattenNewlines(segment.text))")
            if let english = segment.translation, !english.isEmpty {
                lines.append("  English: \(flattenNewlines(english))")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// One line per segment, `m:ss Speaker: text`, for Send to Scratchpad.
    public static func transcriptText(_ meeting: MeetingManifest) -> String {
        ordered(meeting.segments).map {
            "\(displayTime($0.start)) \($0.speaker): \(flattenNewlines($0.text))"
        }.joined(separator: "\n")
    }

    private static func ordered(_ segments: [MeetingSegment]) -> [MeetingSegment] {
        segments.sorted {
            if $0.start != $1.start { return $0.start < $1.start }
            if $0.track != $1.track { return $0.track.order < $1.track.order }
            if $0.end != $1.end { return $0.end < $1.end }
            return $0.id < $1.id
        }
    }

    private static func flattenNewlines(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).joined(separator: " ")
    }

    private static func srtTime(_ seconds: TimeInterval) -> String {
        let totalMilliseconds = max(0, Int64((seconds * 1_000).rounded()))
        let hours = totalMilliseconds / 3_600_000
        let minutes = (totalMilliseconds / 60_000) % 60
        let wholeSeconds = (totalMilliseconds / 1_000) % 60
        let milliseconds = totalMilliseconds % 1_000
        return String(format: "%02lld:%02lld:%02lld,%03lld", hours, minutes, wholeSeconds, milliseconds)
    }

    private static func displayTime(_ seconds: TimeInterval) -> String {
        let whole = max(0, Int(seconds))
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }

    private static func dateLine(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm 'UTC'"
        return formatter.string(from: date)
    }
}
