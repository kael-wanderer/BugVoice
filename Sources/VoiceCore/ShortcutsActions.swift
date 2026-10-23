import Foundation

public enum ShortcutsLanguage: String, CaseIterable, Sendable {
    case auto, english, vietnamese, spanish
    public var languages: [SpeechLanguage]? {
        switch self { case .auto: nil; case .english: [.en]; case .vietnamese: [.vi]; case .spanish: [.es] }
    }
}

public enum ShortcutsError: Error, Equatable, Sendable {
    case meetingAlreadyRecording, noMeetingRecording, transcriptTimeout, textTooLong, emptyText, emptyInstruction, notReady
    case noFolder(String), noMeeting(String), command(CommandFailure), other(String)
    public var message: String {
        switch self {
        case .meetingAlreadyRecording: "A meeting is already recording."
        case .noMeetingRecording: "No meeting is recording."
        case .transcriptTimeout: "Still transcribing after 30 minutes. The transcript will finish in BugVoice › Meetings."
        case .textTooLong: "Text too long — 8,000 characters at most"
        case .emptyText: "No text to rewrite."
        case .emptyInstruction: "No instruction given."
        case .notReady: "BugVoice is still starting. Try again in a moment."
        case .noFolder(let name): "No folder named “\(name)”."
        case .noMeeting(let name): "No meeting named “\(name)”."
        case .command(let failure): failure.title + (failure == .outputTooLong ? "" : failure.detail.map { " — " + $0 } ?? "")
        case .other(let message): message
        }
    }
}

public enum ShortcutsActions {
    public static let defaultLimit = 50
    public static let maxLimit = 200
    public static let transcriptWait: TimeInterval = 30 * 60
    public static let bootstrapWait: TimeInterval = 10
    public static func folder(_ name: String?, in folders: [LibraryFolder]) -> Result<FolderID?, ShortcutsError> {
        let name = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return .success(nil) }
        return MCPResolve.folder(name, in: folders).map { Optional($0) }.mapError { _ in .noFolder(name) }
    }
    public static func checkRewrite(text: String, instruction: String) -> ShortcutsError? {
        if text.count > CommandPrompt.maxSelection { return .textTooLong }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .emptyText }
        if instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .emptyInstruction }
        return nil
    }
    public static func clampLimit(_ limit: Int?) -> Int { min(maxLimit, max(1, limit ?? defaultLimit)) }
    public static func actionItemLine(_ row: ActionItemRow, meetingTitle: String) -> String {
        row.item.text + (row.item.owner.map { " (\($0))" } ?? "") + " — " + meetingTitle
    }
    public static func openActionItems(meetings: [MeetingManifest], done: ActionItemFile, meeting: String?, limit: Int?, now: Date) -> Result<[String], ShortcutsError> {
        let title = (meeting ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let selected = title.isEmpty ? meetings : meetings.filter { AskText.fold($0.title) == AskText.fold(title) }
        if !title.isEmpty && selected.isEmpty { return .failure(.noMeeting(title)) }
        let board = ActionItemBoard(meetings: selected, done: done, status: .open, owner: .anyone, range: .all, query: "", now: now)
        return .success(Array(board.groups.flatMap { group in group.rows.map { actionItemLine($0, meetingTitle: group.title) } }.prefix(clampLimit(limit))))
    }
}
