import Foundation

public enum MCPTool: String, CaseIterable, Sendable {
    case listFolders = "list_folders"
    case listNotes = "list_notes"
    case getNote = "get_note"
    case listActionItems = "list_action_items"
    case listMeetings = "list_meetings"
    case getMeeting = "get_meeting"
    case search
    case ask
    case createNote = "create_note"
    case editNote = "edit_note"
    case uploadAudio = "upload_audio"
    case getJob = "get_job"
    case summarizeMeeting = "summarize_meeting"
}

/// `scope` for `search` and `ask`, before folder names are resolved.
public enum MCPScopeArgument: Equatable, Sendable {
    case all, unfiled, folder(String), meeting(String), note(String)

    /// Nil or empty means `.all`; an unknown form or an empty id is nil.
    public static func parse(_ s: String?) -> MCPScopeArgument? {
        let text = (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty || text == "all" { return .all }
        if text == "unfiled" { return .unfiled }
        let forms: [(String, (String) -> MCPScopeArgument)] = [
            ("folder:", { .folder($0) }), ("meeting:", { .meeting($0) }), ("note:", { .note($0) }),
        ]
        for (prefix, make) in forms where text.hasPrefix(prefix) {
            let value = text.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
            return value.isEmpty ? nil : make(value)
        }
        return nil
    }
}

public enum MCPEditMode: String, Equatable, Sendable { case replace, append }

public enum MCPTextKind: String, Equatable, Sendable {
    case summary
    case actionItems = "action_items"
}

public enum MCPMeetingPart: String, CaseIterable, Hashable, Sendable {
    case summary
    case actionItems = "action_items"
    case myNotes = "my_notes"
    case transcript
}

/// A tool call whose arguments passed the schema check, with defaults filled in.
public enum MCPCall: Equatable, Sendable {
    case listFolders
    case listNotes(folder: String?, tag: String?, text: String?, limit: Int)
    case getNote(id: String)
    case listActionItems(status: ActionItemStatus, meeting: String?, limit: Int)
    case listMeetings(folder: String?, tag: String?, from: Date?, to: Date?, text: String?, limit: Int)
    case getMeeting(id: String, parts: Set<MCPMeetingPart>, fromLine: Int)
    case search(query: String, scope: MCPScopeArgument, limit: Int)
    case ask(question: String, scope: MCPScopeArgument)
    case createNote(title: String, body: String, folder: String?, tags: [String])
    case editNote(id: String, body: String, mode: MCPEditMode, title: String?, folder: String?, tags: [String]?)
    case uploadAudio(path: String, title: String?, folder: String?, tags: [String])
    case getJob(jobID: String)
    case summarizeMeeting(id: String, kind: MCPTextKind, replace: Bool)

    public var tool: MCPTool {
        switch self {
        case .listFolders: .listFolders
        case .listNotes: .listNotes
        case .getNote: .getNote
        case .listActionItems: .listActionItems
        case .listMeetings: .listMeetings
        case .getMeeting: .getMeeting
        case .search: .search
        case .ask: .ask
        case .createNote: .createNote
        case .editNote: .editNote
        case .uploadAudio: .uploadAudio
        case .getJob: .getJob
        case .summarizeMeeting: .summarizeMeeting
        }
    }
}

public struct MCPArgumentError: Error, Equatable, Sendable {
    public var message: String

    public init(message: String) {
        self.message = message
    }
}

public enum MCPTools {
    public static let listDefault = 50, listMax = 200
    public static let searchDefault = 20, searchMax = 40
    /// The Upload page's file types, lowercased.
    public static let uploadExtensions: Set<String> = ["mp3", "wav", "m4a", "aiff", "aif", "caf", "mp4", "mov", "m4v"]
    public static let supportedTypesText = "MP3, WAV, M4A, AIFF, CAF, MP4, MOV, M4V"

    public static func unsupportedType(_ ext: String) -> String {
        ext.isEmpty
            ? "File type not supported. Supported: \(supportedTypesText)."
            : "File type not supported: .\(ext). Supported: \(supportedTypesText)."
    }

    // MARK: Definitions

    /// The `tools/list` result.
    public static var definitions: JSONValue {
        .object(["tools": .array(MCPTool.allCases.map(definition))])
    }

    private static let scopeText = "Where to look: all (default), folder:<id or name>, unfiled, meeting:<id> or note:<id>."

    private static func definition(_ tool: MCPTool) -> JSONValue {
        let (description, properties, required): (String, [String: JSONValue], [String]) = switch tool {
        case .listFolders:
            ("List folders with how many notes and meetings each holds.", [:], [])
        case .listNotes:
            ("List notes, newest edited first.", [
                "folder": prop("string", "Folder id or name."),
                "tag": prop("string", "Only notes with this tag."),
                "text": prop("string", "Only notes whose title contains this text."),
                "limit": prop("integer", "Most notes to return, 1 to 200. Default 50."),
            ], [])
        case .getNote:
            ("Read one note as Markdown.", ["id": prop("string", "Note id.")], ["id"])
        case .listActionItems:
            ("List action items from meetings, newest meeting first.", [
                "status": prop("string", "open, done or all. Default open."),
                "meeting": prop("string", "Meeting id."),
                "limit": prop("integer", "Most items to return, 1 to 200. Default 50."),
            ], [])
        case .listMeetings:
            ("List meetings and uploaded recordings, newest first.", [
                "folder": prop("string", "Folder id or name."),
                "tag": prop("string", "Only meetings with this tag."),
                "from": prop("string", "Earliest start date, YYYY-MM-DD."),
                "to": prop("string", "Latest start date, YYYY-MM-DD."),
                "text": prop("string", "Only meetings whose title contains this text."),
                "limit": prop("integer", "Most meetings to return, 1 to 200. Default 50."),
            ], [])
        case .getMeeting:
            ("Read one meeting as Markdown: summary, action items, my notes and transcript.", [
                "id": prop("string", "Meeting id."),
                "parts": .object([
                    "type": .string("array"),
                    "description": .string("Parts to include. Default all."),
                    "items": .object([
                        "type": .string("string"),
                        "enum": .array(MCPMeetingPart.allCases.map { .string($0.rawValue) }),
                    ]),
                ]),
                "from_line": prop("integer", "First transcript line to return. Default 1."),
            ], ["id"])
        case .search:
            ("Find passages in notes, meetings and dictations, without a model call.", [
                "query": prop("string", "Words to look for."),
                "scope": prop("string", scopeText),
                "limit": prop("integer", "Most passages to return, 1 to 40. Default 20."),
            ], ["query"])
        case .ask:
            ("Answer a question from notes, meetings and dictations, with the lines it used.", [
                "question": prop("string", "The question."),
                "scope": prop("string", scopeText),
            ], ["question"])
        case .createNote:
            ("Create a note.", [
                "title": prop("string", "Note title."),
                "body": prop("string", "Note text, Markdown."),
                "folder": prop("string", "Folder id or name."),
                "tags": stringList("Tags."),
            ], ["title", "body"])
        case .editNote:
            ("Replace or append to a note's text.", [
                "id": prop("string", "Note id."),
                "body": prop("string", "New text, Markdown."),
                "mode": .object([
                    "type": .string("string"),
                    "enum": .array([.string("replace"), .string("append")]),
                    "description": .string("replace swaps the whole text; append adds it at the end."),
                ]),
                "title": prop("string", "New title."),
                "folder": prop("string", "Folder id or name."),
                "tags": stringList("Tags that replace the note's tags."),
            ], ["id", "body", "mode"])
        case .uploadAudio:
            ("Transcribe an audio or video file into a new meeting.", [
                "path": prop("string", "Absolute path of an MP3, WAV, M4A, AIFF, CAF, MP4, MOV or M4V file."),
                "title": prop("string", "Meeting title."),
                "folder": prop("string", "Folder id or name."),
                "tags": stringList("Tags."),
            ], ["path"])
        case .getJob:
            ("Check an upload started by upload_audio.", ["job_id": prop("string", "Job id from upload_audio.")], ["job_id"])
        case .summarizeMeeting:
            ("Write and save a meeting's summary or action items.", [
                "id": prop("string", "Meeting id."),
                "kind": .object([
                    "type": .string("string"),
                    "enum": .array([.string("summary"), .string("action_items")]),
                ]),
                "replace": prop("boolean", "Write new text even when the meeting has some. Default false."),
            ], ["id", "kind"])
        }
        var schema: [String: JSONValue] = ["type": .string("object"), "properties": .object(properties)]
        if !required.isEmpty { schema["required"] = .array(required.map { .string($0) }) }
        return .object([
            "name": .string(tool.rawValue),
            "description": .string(description),
            "inputSchema": .object(schema),
        ])
    }

    private static func prop(_ type: String, _ description: String) -> JSONValue {
        .object(["type": .string(type), "description": .string(description)])
    }

    private static func stringList(_ description: String) -> JSONValue {
        .object(["type": .string("array"), "items": .object(["type": .string("string")]), "description": .string(description)])
    }

    // MARK: Checking

    public static func check(_ name: String, _ arguments: JSONValue?) -> Result<MCPCall, MCPArgumentError> {
        guard let tool = MCPTool(rawValue: name) else {
            return .failure(MCPArgumentError(message: "Unknown tool: \(name)."))
        }
        let args: [String: JSONValue]
        switch arguments {
        case nil, .null?: args = [:]
        case .object(let o)?: args = o
        default: return .failure(MCPArgumentError(message: "arguments must be an object."))
        }
        do {
            return .success(try call(tool, Arguments(values: args)))
        } catch let error as MCPArgumentError {
            return .failure(error)
        } catch {
            return .failure(MCPArgumentError(message: "arguments must be an object."))
        }
    }

    private static func call(_ tool: MCPTool, _ a: Arguments) throws -> MCPCall {
        switch tool {
        case .listFolders:
            return .listFolders
        case .listNotes:
            return .listNotes(
                folder: try a.string("folder"), tag: try a.string("tag"), text: try a.string("text"),
                limit: try a.limit("limit", default: listDefault, max: listMax))
        case .getNote:
            return .getNote(id: try a.required("id"))
        case .listActionItems:
            guard let status = ActionItemStatus(rawValue: try a.string("status") ?? "open") else {
                throw MCPArgumentError(message: "status must be open, done or all.")
            }
            if let value = a.values["limit"], value != .null {
                guard let limit = value.intValue, (1...listMax).contains(limit) else {
                    throw MCPArgumentError(message: "limit must be a whole number from 1 to 200.")
                }
            }
            return .listActionItems(status: status, meeting: try a.string("meeting"), limit: try a.limit("limit", default: listDefault, max: listMax))
        case .listMeetings:
            return .listMeetings(
                folder: try a.string("folder"), tag: try a.string("tag"),
                from: try a.date("from", endOfDay: false), to: try a.date("to", endOfDay: true),
                text: try a.string("text"), limit: try a.limit("limit", default: listDefault, max: listMax))
        case .getMeeting:
            return .getMeeting(id: try a.required("id"), parts: try a.parts(), fromLine: try a.fromLine())
        case .search:
            return .search(
                query: try a.required("query"), scope: try a.scope(),
                limit: try a.limit("limit", default: searchDefault, max: searchMax))
        case .ask:
            return .ask(question: try a.required("question"), scope: try a.scope())
        case .createNote:
            return .createNote(
                title: try a.required("title"), body: try a.text("body"), folder: try a.string("folder"),
                tags: try a.tags() ?? [])
        case .editNote:
            guard let mode = MCPEditMode(rawValue: try a.string("mode") ?? "") else {
                throw MCPArgumentError(message: "mode must be replace or append.")
            }
            return .editNote(
                id: try a.required("id"), body: try a.text("body"), mode: mode, title: try a.string("title"),
                folder: try a.string("folder"), tags: try a.tags())
        case .uploadAudio:
            let path = try a.required("path")
            guard path.hasPrefix("/") else { throw MCPArgumentError(message: "path must be an absolute file path.") }
            let ext = (path as NSString).pathExtension.lowercased()
            guard uploadExtensions.contains(ext) else { throw MCPArgumentError(message: unsupportedType(ext)) }
            return .uploadAudio(path: path, title: try a.string("title"), folder: try a.string("folder"), tags: try a.tags() ?? [])
        case .getJob:
            return .getJob(jobID: try a.required("job_id"))
        case .summarizeMeeting:
            guard let kind = MCPTextKind(rawValue: try a.string("kind") ?? "") else {
                throw MCPArgumentError(message: "kind must be summary or action_items.")
            }
            return .summarizeMeeting(id: try a.required("id"), kind: kind, replace: try a.bool("replace") ?? false)
        }
    }

    private struct Arguments {
        let values: [String: JSONValue]

        private func present(_ name: String) -> JSONValue? {
            guard let v = values[name], v != .null else { return nil }
            return v
        }

        func string(_ name: String) throws -> String? {
            guard let v = present(name) else { return nil }
            guard let s = v.stringValue else { throw MCPArgumentError(message: "\(name) must be a string.") }
            return s
        }

        /// A string that may be empty, such as a note body.
        func text(_ name: String) throws -> String {
            guard let s = try? string(name) else { throw MCPArgumentError(message: "\(name) must be a string.") }
            return s
        }

        func required(_ name: String) throws -> String {
            let s = (try? string(name))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !s.isEmpty else { throw MCPArgumentError(message: "\(name) must be a non-empty string.") }
            return s
        }

        func bool(_ name: String) throws -> Bool? {
            guard let v = present(name) else { return nil }
            guard let b = v.boolValue else { throw MCPArgumentError(message: "\(name) must be true or false.") }
            return b
        }

        /// Clamped to `max`; below 1 is an error.
        func limit(_ name: String, default fallback: Int, max: Int) throws -> Int {
            guard let v = present(name) else { return fallback }
            guard let n = v.intValue, n >= 1 else {
                throw MCPArgumentError(message: "\(name) must be a whole number from 1 to \(max).")
            }
            return min(n, max)
        }

        func fromLine() throws -> Int {
            guard let v = present("from_line") else { return 1 }
            guard let n = v.intValue, n >= 1 else { throw MCPArgumentError(message: "from_line must be a whole number of 1 or more.") }
            return n
        }

        func tags() throws -> [String]? {
            guard let v = present("tags") else { return nil }
            guard let list = v.arrayValue, list.allSatisfy({ $0.stringValue != nil }) else {
                throw MCPArgumentError(message: "tags must be a list of strings.")
            }
            return list.compactMap(\.stringValue)
        }

        /// An empty list means all parts.
        func parts() throws -> Set<MCPMeetingPart> {
            guard let v = present("parts") else { return Set(MCPMeetingPart.allCases) }
            let names = v.arrayValue?.map(\.stringValue)
            let parts = names?.compactMap { $0.flatMap(MCPMeetingPart.init(rawValue:)) }
            guard let names, let parts, parts.count == names.count else {
                throw MCPArgumentError(message: "parts must be a list of summary, action_items, my_notes or transcript.")
            }
            return parts.isEmpty ? Set(MCPMeetingPart.allCases) : Set(parts)
        }

        func scope() throws -> MCPScopeArgument {
            let failure = MCPArgumentError(message: "scope must be all, unfiled, folder:<id or name>, meeting:<id> or note:<id>.")
            let text: String?
            do { text = try string("scope") } catch { throw failure }
            guard let scope = MCPScopeArgument.parse(text) else { throw failure }
            return scope
        }

        /// `YYYY-MM-DD` in the local time zone, or a full ISO 8601 date and time.
        func date(_ name: String, endOfDay: Bool) throws -> Date? {
            guard let s = try string(name)?.trimmingCharacters(in: .whitespaces) else { return nil }
            let day = DateFormatter()
            day.locale = Locale(identifier: "en_US_POSIX")
            day.calendar = Calendar.current
            day.timeZone = Calendar.current.timeZone
            day.dateFormat = "yyyy-MM-dd"
            day.isLenient = false
            if let start = day.date(from: s) {
                guard endOfDay else { return start }
                return Calendar.current.date(byAdding: .day, value: 1, to: start).map { $0.addingTimeInterval(-1) }
            }
            if let full = ISO8601DateFormatter().date(from: s) { return full }
            throw MCPArgumentError(message: "\(name) must be a date like 2026-10-17.")
        }
    }
}
