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
            let suggesting = settings.meetings.suggestKnownVoices
            // An unreadable voices.json skips suggestions; it never fails the split.
            let saved = suggesting ? ((try? await voiceStore.load().voices) ?? []) : []
            let change = try await updateMeetingSpeakers(id: id) { meeting in
                let split = MeetingSpeakers.applySplit(result, to: meeting, tracks: tracks)
                return suggesting ? KnownVoices.suggest(in: split, voices: saved) : split
            }
            await recordKnownVoices(.split, before: change.before, after: change.after)
        } catch {
            do {
                let message = error.localizedDescription
                try await updateMeetingSpeakers(id: id) { var m = $0; m.speakerSplit = .failed(message); return m }
            } catch { saveError = "Could not save speakers: \(error.localizedDescription)" }
        }
        await reloadMeetings()
    }

    func editMeetingSpeakers(id: MeetingID, edit: MeetingSpeakers.Edit) async -> MeetingSpeakers.EditError? {
        // A suggestion for a voice deleted in Settings is stale: Yes must not bring the voice back.
        if case let .accept(speakerID) = edit {
            let name = meetingManifests.first { $0.id == id }?.speakers.first { $0.id == speakerID }?.suggestion?.name
            let saved = (try? await voiceStore.load().voices) ?? []
            guard let name, saved.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else { return nil }
        }
        do {
            let change = try await updateMeetingSpeakers(id: id) { try MeetingSpeakers.apply(edit, to: $0) }
            switch edit {
            case let .rename(speakerID, _), let .accept(speakerID):
                await recordKnownVoices(.edit(speakerID: speakerID), before: change.before, after: change.after)
            case .assign, .newPerson, .decline: break
            }
            await reloadMeetings()
        } catch let error as MeetingSpeakers.EditError { return error }
        catch { saveError = "Could not save speakers: \(error.localizedDescription)" }
        return nil
    }

    /// Applies `change` through whichever session owns the meeting, and returns the meeting before and after.
    @discardableResult
    func updateMeetingSpeakers(
        id: MeetingID, change: @escaping @Sendable (MeetingManifest) throws -> MeetingManifest
    ) async throws -> (before: MeetingManifest, after: MeetingManifest) {
        let captured = CapturedChange()
        let recording: @Sendable (MeetingManifest) throws -> MeetingManifest = { before in
            let after = try change(before)
            captured.set(before, after)
            return after
        }
        if let meetings, try await meetings.updateSpeakersInSession(id: id, change: recording) { return try captured.value() }
        if let uploads, try await uploads.updateSpeakersInSession(id: id, change: recording) { return try captured.value() }
        _ = try await meetingStore.update(id: id, change: recording)
        return try captured.value()
    }

    /// Saves contributions only while "Suggest names from known voices" is on.
    private func recordKnownVoices(_ change: KnownVoices.Change, before: MeetingManifest, after: MeetingManifest) async {
        guard settings.meetings.suggestKnownVoices else { return }
        do {
            knownVoices = try await voiceStore.update {
                KnownVoices.record(change, before: before, after: after, in: $0, now: Date())
            }.voices
        } catch { saveError = "Could not save known voices: \(error.localizedDescription)" }
    }

    func deleteKnownVoice(name: String) async {
        do { knownVoices = try await voiceStore.update { KnownVoices.delete(name: name, from: $0) }.voices }
        catch { saveError = "Could not delete the voice: \(error.localizedDescription)" }
    }

    /// Runs on every meeting list load, so a broken voices.json is reported once, not every reload.
    func pruneKnownVoices(keeping meetings: Set<MeetingID>) async {
        do {
            knownVoices = try await voiceStore.update { KnownVoices.prune($0, keeping: meetings) }.voices
            voiceStoreErrorShown = false
        } catch {
            guard !voiceStoreErrorShown else { return }
            voiceStoreErrorShown = true
            saveError = "Could not load known voices: \(error.localizedDescription)"
        }
    }
}

/// The meeting before and after a speaker change, captured inside the session's update.
private final class CapturedChange: @unchecked Sendable {
    private let lock = NSLock()
    private var pair: (MeetingManifest, MeetingManifest)?

    func set(_ before: MeetingManifest, _ after: MeetingManifest) { lock.withLock { pair = (before, after) } }

    func value() throws -> (before: MeetingManifest, after: MeetingManifest) {
        guard let pair = lock.withLock({ pair }) else { throw CocoaError(.fileReadUnknown) }
        return (pair.0, pair.1)
    }
}
