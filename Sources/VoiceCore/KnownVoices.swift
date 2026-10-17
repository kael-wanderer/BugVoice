import Foundation

/// A voice the owner named in earlier meetings: one centroid per meeting.
public struct KnownVoice: Codable, Equatable, Sendable, Identifiable {
    public struct Contribution: Codable, Equatable, Sendable {
        public var meetingID: MeetingID
        public var centroid: [Float]
        public init(meetingID: MeetingID, centroid: [Float]) {
            self.meetingID = meetingID
            self.centroid = centroid
        }
    }

    public var name: String
    public var contributions: [Contribution]
    public var updatedAt: Date
    public var id: String { name }

    public init(name: String, contributions: [Contribution], updatedAt: Date) {
        self.name = name
        self.contributions = contributions
        self.updatedAt = updatedAt
    }

    /// Element-wise mean of the contributions of the most common length.
    public var voiceprint: [Float] {
        guard let length = contributions.first?.centroid.count else { return [] }
        let usable = contributions.map(\.centroid).filter { $0.count == length }
        var sum = [Float](repeating: 0, count: length)
        for centroid in usable { for i in 0..<length { sum[i] += centroid[i] } }
        return sum.map { $0 / Float(usable.count) }
    }
}

/// The contents of `voices.json`.
public struct KnownVoiceFile: Codable, Equatable, Sendable {
    public var voices: [KnownVoice]
    public init(voices: [KnownVoice] = []) { self.voices = voices }
}

/// Matching split speakers to saved voices, and keeping saved voices in step with the owner's names.
public enum KnownVoices {
    /// Measured 2026-10-17 on call audio: same person 0.09–0.10, different people 0.28–0.35.
    public static let threshold = 0.2
    /// The closest saved voice must beat the next one by this much.
    public static let margin = 0.1

    public enum Change: Equatable, Sendable {
        /// The owner renamed, confirmed or cleared one speaker.
        case edit(speakerID: String)
        /// A split replaced the speakers; carried names update their contribution, nothing new is added.
        case split
    }

    public static func suggest(in meeting: MeetingManifest, voices: [KnownVoice]) -> MeetingManifest {
        var updated = meeting
        for index in updated.speakers.indices where updated.speakers[index].name != nil {
            // A suggestion stays on a named speaker only as the record of a Yes.
            if updated.speakers[index].suggestion?.name != updated.speakers[index].name { updated.speakers[index].suggestion = nil }
        }
        let taken = Set(MeetingSpeakers.names(in: meeting).values.map { $0.lowercased() })
            .union(meeting.declinedVoices.map { $0.lowercased() })
        let prints = voices.filter { !taken.contains($0.name.lowercased()) }.map { ($0.name, $0.voiceprint) }
        var pairs: [(distance: Double, speaker: Int, name: String)] = []
        for (index, speaker) in meeting.speakers.enumerated() {
            guard speaker.id.hasPrefix("s"), speaker.name == nil, let centroid = speaker.centroid else { continue }
            let distances = prints.compactMap { name, print in cosineDistance(centroid, print).map { ($0, name) } }
                .sorted { $0.0 != $1.0 ? $0.0 < $1.0 : $0.1 < $1.1 }
            guard let best = distances.first, best.0 <= threshold + 1e-6 else { continue }
            if distances.count > 1, distances[1].0 - best.0 < margin - 1e-6 { continue }
            pairs.append((best.0, index, best.1))
        }
        var usedNames: Set<String> = []
        for pair in pairs.sorted(by: { $0.distance != $1.distance ? $0.distance < $1.distance : $0.speaker < $1.speaker })
        where !usedNames.contains(pair.name) {
            usedNames.insert(pair.name)
            updated.speakers[pair.speaker].suggestion = SpeakerSuggestion(name: pair.name, distance: pair.distance)
        }
        return updated
    }

    public static func record(_ change: Change, before: MeetingManifest, after: MeetingManifest,
                              in file: KnownVoiceFile, now: Date) -> KnownVoiceFile {
        let id = after.id
        var updated = file
        switch change {
        case let .edit(speakerID):
            let old = confirmed(before)[speakerID]
            let new = confirmed(after)[speakerID]
            guard old?.name != new?.name || old?.centroid != new?.centroid else { return file }
            if let old { remove(name: old.name, meeting: id, from: &updated, now: now) }
            if let new {
                let contribution = KnownVoice.Contribution(meetingID: id, centroid: new.centroid)
                if let index = index(of: new.name, in: updated) {
                    updated.voices[index].contributions.removeAll { $0.meetingID == id }
                    updated.voices[index].contributions.append(contribution)
                    updated.voices[index].updatedAt = now
                } else {
                    updated.voices.append(KnownVoice(name: new.name, contributions: [contribution], updatedAt: now))
                }
            }
        case .split:
            let names = confirmed(after).values
            for voice in file.voices where voice.contributions.contains(where: { $0.meetingID == id }) {
                if let carried = names.first(where: { $0.name.caseInsensitiveCompare(voice.name) == .orderedSame }),
                   let index = index(of: voice.name, in: updated) {
                    for c in updated.voices[index].contributions.indices where updated.voices[index].contributions[c].meetingID == id {
                        updated.voices[index].contributions[c].centroid = carried.centroid
                    }
                    updated.voices[index].updatedAt = now
                } else {
                    remove(name: voice.name, meeting: id, from: &updated, now: now)
                }
            }
        }
        return updated
    }

    public static func prune(_ file: KnownVoiceFile, keeping meetings: Set<MeetingID>) -> KnownVoiceFile {
        var updated = file
        for index in updated.voices.indices { updated.voices[index].contributions.removeAll { !meetings.contains($0.meetingID) } }
        updated.voices.removeAll { $0.contributions.isEmpty }
        return updated
    }

    public static func delete(name: String, from file: KnownVoiceFile) -> KnownVoiceFile {
        var updated = file
        updated.voices.removeAll { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        return updated
    }

    /// Split speakers the owner named, with their centroid.
    private static func confirmed(_ meeting: MeetingManifest) -> [String: (name: String, centroid: [Float])] {
        var result: [String: (name: String, centroid: [Float])] = [:]
        for speaker in meeting.speakers where speaker.id.hasPrefix("s") {
            if let name = speaker.name, let centroid = speaker.centroid { result[speaker.id] = (name, centroid) }
        }
        return result
    }

    private static func index(of name: String, in file: KnownVoiceFile) -> Int? {
        file.voices.firstIndex { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    private static func remove(name: String, meeting: MeetingID, from file: inout KnownVoiceFile, now: Date) {
        guard let index = index(of: name, in: file) else { return }
        file.voices[index].contributions.removeAll { $0.meetingID == meeting }
        file.voices[index].updatedAt = now
        if file.voices[index].contributions.isEmpty { file.voices.remove(at: index) }
    }

    static func cosineDistance(_ a: [Float], _ b: [Float]) -> Double? {
        guard a.count == b.count, !a.isEmpty else { return nil }
        var dot = 0.0, aa = 0.0, bb = 0.0
        for i in a.indices { dot += Double(a[i]) * Double(b[i]); aa += Double(a[i]) * Double(a[i]); bb += Double(b[i]) * Double(b[i]) }
        guard aa > 0, bb > 0 else { return nil }
        let value = 1 - dot / (aa * bb).squareRoot()
        return value.isFinite ? value : nil
    }
}
