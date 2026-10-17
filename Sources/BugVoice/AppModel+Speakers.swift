import Foundation
import VoiceCore

extension AppModel {
    /// Join an existing split instead of starting a second writer for this meeting.
    func findSpeakers(id: MeetingID, people: Int?) async {
        if let task = speakerTasks[id] { await task.value; return }
        let task = Task { await self.performSpeakerSplit(id: id, people: people) }
        speakerTasks[id] = task
        await task.value
        speakerTasks[id] = nil
    }

    private func performSpeakerSplit(id: MeetingID, people: Int?) async {
        let store = MeetingStore(root: paths.meetings)
        let manifest: MeetingManifest
        do { manifest = try await store.load(id: id) } catch {
            // A deleted meeting gets no failure written, which would recreate its folder.
            await reloadMeetings()
            return
        }
        guard manifest.state == .ready, !manifest.segments.isEmpty else { return }
        do {
            let directory = paths.meetings.appendingPathComponent(id.rawValue)
            let call = directory.appendingPathComponent("system.m4a")
            let hasCallAudio = manifest.source == .recording && FileManager.default.fileExists(atPath: call.path)
            let audio = hasCallAudio ? call : directory.appendingPathComponent("audio.m4a")
            guard FileManager.default.fileExists(atPath: audio.path) else {
                try await updateMeetingSpeakers(id: id) { var m = $0; m.speakerSplit = .failed("No call audio"); return m }
                await reloadMeetings()
                return
            }
            try await updateMeetingSpeakers(id: id) { var m = $0; m.speakerSplit = .running; return m }
            await reloadMeetings()
            // A microphone-only recording has only the owner; it needs no model.
            let micOnly = manifest.source == .recording && manifest.segments.allSatisfy { $0.track == .mic }
            let tracks: Set<MeetingTrack> = micOnly ? [.system] : MeetingSpeakers.splitTracks(for: manifest, hasCallAudio: hasCallAudio)
            var counted = manifest
            // A first split has no speakers yet, but a recorded call still counts the owner.
            if tracks == [.system], !counted.speakers.contains(where: { $0.id == MeetingSpeakers.youID }),
               counted.segments.contains(where: { $0.track == .mic }) {
                counted.speakers.append(.init(id: MeetingSpeakers.youID, colorIndex: 0))
            }
            let voices = people.map { MeetingSpeakers.voices(forPeople: $0, in: counted) }
            let result: MeetingSpeakers.SplitResult
            if micOnly { result = .init(turns: [], centroids: [:]) }
            else { result = try await speakerSplitter.split(audio: audio, voices: voices) }
            try Task.checkCancellation()
            try await updateMeetingSpeakers(id: id) { MeetingSpeakers.applySplit(result, to: $0, tracks: tracks) }
        } catch {
            do {
                let message = error.localizedDescription
                try await updateMeetingSpeakers(id: id) { var m = $0; m.speakerSplit = .failed(message); return m }
            } catch { saveError = "Could not save speakers: \(error.localizedDescription)" }
        }
        await reloadMeetings()
    }

    func editMeetingSpeakers(id: MeetingID, edit: MeetingSpeakers.Edit) async -> MeetingSpeakers.EditError? {
        do {
            try await updateMeetingSpeakers(id: id) { try MeetingSpeakers.apply(edit, to: $0) }
            await reloadMeetings()
        } catch let error as MeetingSpeakers.EditError { return error }
        catch { saveError = "Could not save speakers: \(error.localizedDescription)" }
        return nil
    }

    private func updateMeetingSpeakers(id: MeetingID, change: @Sendable (MeetingManifest) throws -> MeetingManifest) async throws {
        if let meetings, try await meetings.updateSpeakersInSession(id: id, change: change) { return }
        if let uploads, try await uploads.updateSpeakersInSession(id: id, change: change) { return }
        let store = MeetingStore(root: paths.meetings)
        let current = try await store.load(id: id)
        try await store.save(change(current))
    }
}
