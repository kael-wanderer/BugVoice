import Foundation

/// Keeps every reply well under the 4 MB socket line, whatever a note or list holds.
extension MCPFormat {
    /// Most UTF-8 bytes of reply text sent to an agent.
    public static let maxReplyBytes = 3_500_000
    public static let noteTooLong = "More: this note is longer than an agent reply can hold. Open it in BugVoice."
    public static let replyTooLong = "More: this reply is longer than an agent reply can hold. Open it in BugVoice."

    /// `text` when it fits; otherwise cut at the last line break that leaves room
    /// for a newline and `notice`, which ends the reply.
    public static func capped(_ text: String, notice: String, limit: Int = maxReplyBytes) -> String {
        guard text.utf8.count > limit else { return text }
        let budget = max(0, limit - notice.utf8.count - 1)
        var bytes = Array(text.utf8.prefix(budget))
        if let lastBreak = bytes.lastIndex(of: 0x0A) {
            bytes.removeSubrange(lastBreak...)
        } else {
            // No line break: drop a character cut in half.
            while let last = bytes.last, last & 0xC0 == 0x80 { bytes.removeLast() }
            if let last = bytes.last, last >= 0xC0 { bytes.removeLast() }
        }
        return String(decoding: bytes, as: UTF8.self) + "\n" + notice
    }

    /// Pretty JSON of as many leading rows as fit in `limit` bytes.
    public static func jsonRows(_ rows: [JSONValue], limit: Int = maxReplyBytes) -> String {
        let all = json(.array(rows))
        guard all.utf8.count > limit else { return all }
        var low = 0, high = rows.count
        while low < high {
            let mid = (low + high + 1) / 2
            if json(.array(Array(rows.prefix(mid)))).utf8.count <= limit { low = mid } else { high = mid - 1 }
        }
        return json(.array(Array(rows.prefix(low))))
    }

    /// Any tool's reply, kept under `limit`: lists lose rows from the end, a note
    /// is cut at a line, anything else is cut with a general notice.
    public static func fitted(_ text: String, for call: MCPCall, limit: Int = maxReplyBytes) -> String {
        guard text.utf8.count > limit else { return text }
        switch call {
        case .listFolders, .listNotes, .listMeetings:
            if let rows = (try? JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)))?.arrayValue {
                return jsonRows(rows, limit: limit)
            }
            return capped(text, notice: replyTooLong, limit: limit)
        case .getNote:
            return capped(text, notice: noteTooLong, limit: limit)
        default:
            return capped(text, notice: replyTooLong, limit: limit)
        }
    }
}
