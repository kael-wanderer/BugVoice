import Foundation
import VoiceCore
import WhisperKit
import SpeakerKit

/// On-device speaker turns. The model is downloaded once beside the Whisper models.
public actor SpeakerSplitter {
    enum Tuning {
        static let clusterDistanceThreshold: Float? = nil
        static let minClusterSize: Int? = nil
    }

    private let downloadBase: URL
    private var kit: SpeakerKit?
    private var loading: Task<SpeakerKit, Error>?

    public init(downloadBase: URL) { self.downloadBase = downloadBase }

    private func loadedKit() async throws -> SpeakerKit {
        if let kit { return kit }
        if let loading { return try await loading.value }
        let base = downloadBase
        let task = Task {
            try await SpeakerKit(PyannoteConfig(downloadBase: base.path, download: true, load: false, verbose: false))
        }
        loading = task
        do {
            let loaded = try await task.value
            kit = loaded
            loading = nil
            return loaded
        } catch {
            loading = nil
            throw error
        }
    }

    public func split(audio: URL, voices: Int?) async throws -> MeetingSpeakers.SplitResult {
        let kit = try await loadedKit()
        let samples = try AudioProcessor.loadAudioAsFloatArray(fromPath: audio.path)
        let result = try await kit.diarize(audioArray: samples, options: PyannoteDiarizationOptions(
            numberOfSpeakers: voices,
            clusterDistanceThreshold: Tuning.clusterDistanceThreshold,
            minClusterSize: Tuning.minClusterSize
        ))
        let turns = result.segments.compactMap { segment -> MeetingSpeakers.Turn? in
            guard let voice = segment.speaker.speakerId else { return nil }
            return .init(voice: voice, start: Double(segment.startTime), end: Double(segment.endTime))
        }
        return .init(turns: turns, centroids: result.speakerCentroidEmbeddings)
    }

    public func unload() async {
        var current = kit
        if current == nil, let loading { current = try? await loading.value }
        kit = nil
        loading = nil
        await current?.unloadModels()
    }
}
