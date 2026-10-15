import Foundation

public enum UploadChunkPlan {
    public static func id(for range: Range<Int>) -> String {
        "file-final-\(range.lowerBound)-\(range.upperBound)"
    }

    public static func reusable(_ records: [MeetingChunkRecord], range: Range<Int>) -> MeetingChunkRecord? {
        records.first {
            $0.id == id(for: range) && $0.track == .file
                && Int(($0.offset * 16_000).rounded()) == range.lowerBound
                && Int(($0.duration * 16_000).rounded()) == range.count
                && ($0.state == .complete || $0.state == .empty)
        }
    }
}
