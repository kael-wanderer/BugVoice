import Foundation

public enum NotesTitleCommitReason: Sendable {
    case bodyDebounce
    case returnKey
    case focusOut
}

public enum NotesRefreshTrigger: CaseIterable, Sendable {
    case selection
    case appActivation
    case beforeSave
}

public enum NotesAutosavePolicy {
    public static let bodyDebounceInterval: TimeInterval = 0.5

    public static func deadline(afterBodyEditAt date: Date) -> Date {
        date.addingTimeInterval(bodyDebounceInterval)
    }

    public static func bodySaveIsDue(now: Date, lastBodyEditAt: Date) -> Bool {
        now >= deadline(afterBodyEditAt: lastBodyEditAt)
    }

    public static func titleForBodySave(committedTitle: String, draftTitle: String, titleEditing: Bool) -> String {
        titleEditing ? committedTitle : draftTitle
    }

    public static func committedTitle(previous: String, draft: String, reason: NotesTitleCommitReason) -> String {
        switch reason {
        case .bodyDebounce: previous
        case .returnKey, .focusOut: draft
        }
    }

    /// Equal revisions represent idempotent saves of the same buffer state.
    public static func mayWrite(requestedRevision: UInt64, storedRevision: UInt64) -> Bool {
        requestedRevision >= storedRevision
    }

    public static func fileVersionChanged(from previous: NoteFileVersion, to current: NoteFileVersion) -> Bool {
        previous != current
    }
}

extension NoteFileVersion {
    public static func fingerprint(data: Data, modifiedAt: Date) -> NoteFileVersion {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return NoteFileVersion(modifiedAt: modifiedAt, byteCount: Int64(data.count), contentHash: hash)
    }
}
