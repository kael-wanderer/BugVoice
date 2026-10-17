import Foundation

/// Pure speaker placement and edits. No audio or model types cross this boundary.
public enum MeetingSpeakers {
    public struct Turn: Equatable, Sendable {
        public var voice: Int
        public var start: TimeInterval
        public var end: TimeInterval
        public init(voice: Int, start: TimeInterval, end: TimeInterval) {
            self.voice = voice; self.start = start; self.end = end
        }
    }
    public struct SplitResult: Equatable, Sendable {
        public var turns: [Turn]
        public var centroids: [Int: [Float]]
        public init(turns: [Turn], centroids: [Int: [Float]]) {
            self.turns = turns; self.centroids = centroids
        }
    }
    public enum Edit: Equatable, Sendable {
        case rename(speakerID: String, name: String)
        case assign(segmentID: String, speakerID: String)
        case newPerson(segmentID: String, name: String)
    }
    public enum EditError: Error, Equatable {
        case duplicateName(String), unknownSpeaker, unknownSegment
    }
    public static let youID = "you"
    public static let colorCount = 6

    public static func defaultName(for id: String) -> String {
        id == youID ? "You" : "Other \(id.dropFirst())"
    }
    public static func splitTracks(for meeting: MeetingManifest, hasCallAudio: Bool) -> Set<MeetingTrack> {
        meeting.source == .upload ? [.file] : (hasCallAudio ? [.system] : [.mic, .system])
    }
    public static func people(in meeting: MeetingManifest) -> Int { meeting.speakers.count }
    public static func peopleRange(in meeting: MeetingManifest) -> ClosedRange<Int> {
        (meeting.speakers.contains { $0.id == youID } && meeting.segments.contains { $0.track == .system } ? 2 : 1)...10
    }
    public static func voices(forPeople people: Int, in meeting: MeetingManifest) -> Int {
        people - (meeting.speakers.contains { $0.id == youID } ? 1 : 0)
    }
    public static func names(in meeting: MeetingManifest) -> [String: String] {
        Dictionary(uniqueKeysWithValues: meeting.speakers.map { ($0.id, $0.name ?? defaultName(for: $0.id)) })
    }
    public static func namesChangedSinceSummary(_ meeting: MeetingManifest) -> Bool {
        guard !(meeting.summary ?? "").isEmpty || !(meeting.actionItems ?? "").isEmpty else { return false }
        if meeting.speakerNamesAtSummary == nil { return !meeting.speakers.isEmpty }
        return meeting.speakerNamesAtSummary != names(in: meeting)
    }

    public static func place(_ segments: [MeetingSegment], turns: [Turn], tracks: Set<MeetingTrack>) -> [String: Int] {
        var placed: [String: Int] = [:]
        for line in segments where tracks.contains(line.track) {
            var overlap: [Int: Double] = [:]
            var first: [Int: Double] = [:]
            for turn in turns {
                let seconds = max(0, min(line.end, turn.end) - max(line.start, turn.start))
                if seconds > 0 {
                    overlap[turn.voice, default: 0] += seconds
                    first[turn.voice] = min(first[turn.voice] ?? .infinity, turn.start)
                }
            }
            if let best = overlap.keys.sorted(by: {
                if overlap[$0] != overlap[$1] { return overlap[$0]! > overlap[$1]! }
                if first[$0] != first[$1] { return first[$0]! < first[$1]! }
                return $0 < $1
            }).first { placed[line.id] = best; continue }
            let nearest = turns.min {
                let a = max(0, max($0.start - line.end, line.start - $0.end))
                let b = max(0, max($1.start - line.end, line.start - $1.end))
                if a != b { return a < b }
                if $0.start != $1.start { return $0.start < $1.start }
                return $0.voice < $1.voice
            }
            if let nearest, max(0, max(nearest.start - line.end, line.start - nearest.end)) <= 1 {
                placed[line.id] = nearest.voice
            }
        }
        return placed
    }

    public static func applySplit(_ result: SplitResult, to meeting: MeetingManifest, tracks: Set<MeetingTrack>) -> MeetingManifest {
        var updated = meeting
        let placed = place(meeting.segments, turns: result.turns, tracks: tracks)
        var voices: [Int] = []
        for line in meeting.segments.sorted(by: { $0.start < $1.start }) {
            if let voice = placed[line.id], !voices.contains(voice) { voices.append(voice) }
        }
        var speakers: [MeetingSpeaker] = []
        if tracks == [.system], meeting.segments.contains(where: { $0.track == .mic }) {
            speakers.append(.init(id: youID, name: meeting.speakers.first { $0.id == youID }?.name, colorIndex: 0))
        }
        for (index, voice) in voices.enumerated() {
            speakers.append(.init(id: "s\(index + 1)", colorIndex: (index + 1) % colorCount, centroid: result.centroids[voice]))
        }
        var pairs: [(Double, String, Int)] = []
        for old in meeting.speakers where old.id.hasPrefix("s") && old.name != nil {
            guard let a = old.centroid else { continue }
            for index in speakers.indices {
                guard let b = speakers[index].centroid, let distance = cosineDistance(a, b) else { continue }
                pairs.append((distance, old.id, index))
            }
        }
        pairs.sort {
            if $0.0 != $1.0 { return $0.0 < $1.0 }
            if $0.1 != $1.1 { return $0.1 < $1.1 }
            return $0.2 < $1.2
        }
        var oldUsed: Set<String> = []; var newUsed: Set<Int> = []
        for (_, oldID, index) in pairs where !oldUsed.contains(oldID) && !newUsed.contains(index) {
            speakers[index].name = meeting.speakers.first { $0.id == oldID }?.name
            oldUsed.insert(oldID); newUsed.insert(index)
        }
        updated.speakers = speakers
        for index in updated.segments.indices {
            let line = updated.segments[index]
            if tracks.contains(line.track) {
                updated.segments[index].speakerID = placed[line.id].flatMap { voices.firstIndex(of: $0) }.map { "s\($0 + 1)" }
            } else if tracks == [.system], line.track == .mic {
                updated.segments[index].speakerID = youID
            } else { updated.segments[index].speakerID = nil }
        }
        updateNames(&updated)
        updated.speakerSplit = .done
        return updated
    }

    public static func apply(_ edit: Edit, to meeting: MeetingManifest) throws -> MeetingManifest {
        var updated = meeting
        switch edit {
        case let .rename(id, raw):
            guard let index = updated.speakers.firstIndex(where: { $0.id == id }) else { throw EditError.unknownSpeaker }
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            try validate(name.isEmpty ? defaultName(for: id) : name, excluding: id, in: meeting)
            updated.speakers[index].name = name.isEmpty ? nil : name
        case let .assign(segmentID, speakerID):
            guard updated.speakers.contains(where: { $0.id == speakerID }) else { throw EditError.unknownSpeaker }
            guard let index = updated.segments.firstIndex(where: { $0.id == segmentID }) else { throw EditError.unknownSegment }
            updated.segments[index].speakerID = speakerID
        case let .newPerson(segmentID, raw):
            guard let index = updated.segments.firstIndex(where: { $0.id == segmentID }) else { throw EditError.unknownSegment }
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            // The public error interface has no empty-name case; the field keeps empty submissions open.
            guard !name.isEmpty else { throw EditError.duplicateName(name) }
            try validate(name, excluding: nil, in: meeting)
            let next = (meeting.speakers.compactMap { $0.id.hasPrefix("p") ? Int($0.id.dropFirst()) : nil }.max() ?? 0) + 1
            let color = ((meeting.speakers.map(\.colorIndex).max() ?? -1) + 1) % colorCount
            let id = "p\(next)"
            updated.speakers.append(.init(id: id, name: name, colorIndex: color))
            updated.segments[index].speakerID = id
        }
        let used = Set(updated.segments.compactMap(\.speakerID))
        updated.speakers.removeAll { !used.contains($0.id) }
        updateNames(&updated)
        return updated
    }
    private static func validate(_ name: String, excluding id: String?, in meeting: MeetingManifest) throws {
        if names(in: meeting).contains(where: { $0.key != id && $0.value.caseInsensitiveCompare(name) == .orderedSame }) {
            throw EditError.duplicateName(name)
        }
    }
    private static func updateNames(_ meeting: inout MeetingManifest) {
        let display = names(in: meeting)
        for index in meeting.segments.indices {
            meeting.segments[index].speakerName = meeting.segments[index].speakerID.flatMap { display[$0] }
        }
    }
    private static func cosineDistance(_ a: [Float], _ b: [Float]) -> Double? {
        guard a.count == b.count else { return nil }
        let aa = a.reduce(0.0) { $0 + Double($1) * Double($1) }
        let bb = b.reduce(0.0) { $0 + Double($1) * Double($1) }
        guard aa > 0, bb > 0 else { return nil }
        let dot = zip(a, b).reduce(0.0) { $0 + Double($1.0) * Double($1.1) }
        let value = 1 - dot / sqrt(aa * bb)
        return value.isFinite ? value : nil
    }
}
