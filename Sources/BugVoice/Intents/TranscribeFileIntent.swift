import AppIntents
import Foundation
import UniformTypeIdentifiers
import VoiceCore

enum ShortcutsLanguageEntity: String, AppEnum {
    case auto, english, vietnamese, spanish
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Language")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .auto: "Auto", .english: "English", .vietnamese: "Vietnamese", .spanish: "Spanish"
    ]
    var languages: [SpeechLanguage]? { ShortcutsLanguage(rawValue: rawValue)?.languages }
}

struct TranscribeFileIntent: AppIntent, ProgressReportingIntent {
    static let title: LocalizedStringResource = "Transcribe audio file"
    static let description = IntentDescription("Transcribes an audio file on this Mac and returns the transcript. The recording is kept in Meetings.")
    static let openAppWhenRun = false
    @Parameter(title: "File", supportedContentTypes: [.audio, .movie]) var file: IntentFile
    @Parameter(title: "Language", default: .auto) var language: ShortcutsLanguageEntity
    @Parameter(title: "Wait for transcript", default: true) var wait: Bool
    static var parameterSummary: some ParameterSummary {
        Summary("Transcribe \(\.$file)") { \.$language; \.$wait }
    }
    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let model = try await ShortcutsBridge.ready()
        guard let uploads = model.uploads else { throw ShortcutsError.notReady }
        let name = (file.filename as NSString).lastPathComponent
        let ext = (name as NSString).pathExtension.lowercased()
        guard MCPTools.uploadExtensions.contains(ext) else { throw ShortcutsError.other(MCPTools.unsupportedType(ext)) }
        let url: URL
        var copiedDirectory: URL?
        if let original = file.fileURL, FileManager.default.isReadableFile(atPath: original.path) {
            url = original
        } else {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("BugVoice-Shortcuts-\(UUID().uuidString)", isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                url = directory.appendingPathComponent(name)
                try file.data.write(to: url, options: .atomic)
                copiedDirectory = directory
            } catch {
                try? FileManager.default.removeItem(at: directory)
                throw ShortcutsError.other(UploadFailure.unreadable.localizedDescription)
            }
        }
        let id: UUID
        do {
            id = try await uploads.submitForAgent(url: url, title: nil, labels: ItemLabels(), client: "Shortcuts", languages: language.languages)
        } catch {
            if let copiedDirectory { try? FileManager.default.removeItem(at: copiedDirectory) }
            throw ShortcutsError.other(error.localizedDescription)
        }
        if let copiedDirectory { Self.removeWhenDone(copiedDirectory, job: id, uploads: uploads) }
        guard wait else { return .result(value: (name as NSString).deletingPathExtension) }
        progress.totalUnitCount = 100
        let deadline = ContinuousClock.now.advanced(by: .seconds(ShortcutsActions.transcriptWait))
        repeat {
            try Task.checkCancellation()
            if let job = uploads.jobStatus(id: id) {
                if let value = job.progress { progress.completedUnitCount = Int64(min(1, max(0, value)) * 100) }
                switch job.state {
                case .ready:
                    if let meetingID = job.meetingID {
                        // The queue marks ready before the controller finishes reloading the library.
                        if !model.meetingManifests.contains(where: { $0.id == meetingID }) { await model.reloadMeetings() }
                        if let meeting = model.meetingManifests.first(where: { $0.id == meetingID }) {
                            progress.completedUnitCount = 100
                            return .result(value: MeetingExporter.transcriptText(meeting))
                        }
                    }
                case .failed: throw ShortcutsError.other(job.errorMessage ?? UploadFailure.unreadable.localizedDescription)
                case .cancelled: throw ShortcutsError.other("The transcription was cancelled.")
                default: break
                }
            }
            try await Task.sleep(for: .seconds(1))
        } while ContinuousClock.now < deadline
        throw ShortcutsError.transcriptTimeout
    }

    /// The copy of a file Shortcuts handed over as data is the owner's audio:
    /// it stays only while the upload may still read it (a relaunch resumes
    /// from the same path) and is removed once the job ends.
    @MainActor private static func removeWhenDone(_ directory: URL, job id: UUID, uploads: UploadController) {
        Task { @MainActor [weak uploads] in
            while let uploads, let job = uploads.jobStatus(id: id), !job.state.isTerminal {
                try? await Task.sleep(for: .seconds(5))
            }
            try? FileManager.default.removeItem(at: directory)
        }
    }
}
