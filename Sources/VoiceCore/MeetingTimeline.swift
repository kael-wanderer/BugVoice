import Foundation

public enum MeetingTimeline {
    public static func seekTime(for segment: MeetingSegment) -> TimeInterval {
        max(0, segment.start)
    }

    public static func activeSegment(
        at time: TimeInterval,
        segments: [MeetingSegment],
        isPlaying: Bool
    ) -> MeetingSegment? {
        guard isPlaying, time >= 0 else { return nil }
        return segments.first { time >= $0.start && time < $0.end }
    }
}
