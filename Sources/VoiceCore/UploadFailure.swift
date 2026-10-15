import Foundation

public enum UploadFailure: Error, LocalizedError, Equatable, Sendable {
    case noAudio
    case unreadable
    case diskFull
    case transcript
    case audioSave
    case missingJournal
    case cleanup

    public var errorDescription: String? {
        switch self {
        case .noAudio: "This file has no audio."
        case .unreadable: "BugVoice can't read this file. Use MP3, WAV, M4A, AIFF, CAF, MP4, MOV or M4V."
        case .diskFull: "Not enough disk space to transcribe this file."
        case .transcript: "Transcript could not be completed. The audio is saved; use Retry transcript in Meetings."
        case .audioSave: "Could not save the audio. Retry transcript in Meetings."
        case .missingJournal: "The transcript cannot be retried. The audio is saved."
        case .cleanup: "Could not remove the cancelled upload."
        }
    }

    public static func isDiskFull(_ error: any Error) -> Bool {
        if let failure = error as? UploadFailure, failure == .diskFull { return true }
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain && ns.code == CocoaError.fileWriteOutOfSpace.rawValue { return true }
        if ns.domain == NSPOSIXErrorDomain && ns.code == 28 { return true }
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError {
            return isDiskFull(underlying)
        }
        return false
    }
}
