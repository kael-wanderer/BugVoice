import Foundation
import OSLog
import VoiceCore

/// One unified-log subsystem for the app, one category per area. Read it in
/// Terminal with `log show --last 1h --predicate 'subsystem == "com.kael.bugvoice"'`,
/// or with Settings › General › Copy diagnostics.
///
/// Log outcomes, counts, timings and error descriptions. Never what the user
/// said, wrote or asked.
public enum Log {
    public static let subsystem = "com.kael.bugvoice"

    public static let app = Logger(subsystem: subsystem, category: "app")
    public static let dictation = Logger(subsystem: subsystem, category: "dictation")
    public static let meeting = Logger(subsystem: subsystem, category: "meeting")
    public static let upload = Logger(subsystem: subsystem, category: "upload")
    public static let notes = Logger(subsystem: subsystem, category: "notes")
    public static let ask = Logger(subsystem: subsystem, category: "ask")
    public static let mcp = Logger(subsystem: subsystem, category: "mcp")

    /// "1.4 (19)": marketing version and build from Info.plist.
    public static var appVersion: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return "\(info["CFBundleShortVersionString"] as? String ?? "dev") (\(info["CFBundleVersion"] as? String ?? "dev"))"
    }

    /// "macOS 27.0.1".
    public static var systemVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    /// "arm64".
    public static var hardware: String {
        var system = utsname()
        uname(&system)
        return withUnsafeBytes(of: &system.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }

    /// This launch's entries for the subsystem, oldest first. Empty when the
    /// store cannot be opened.
    public static func entriesThisLaunch(limit: Int = 500) -> [Diagnostics.Entry] {
        guard let store = try? OSLogStore(scope: .currentProcessIdentifier),
              let entries = try? store.getEntries(matching: NSPredicate(format: "subsystem == %@", subsystem))
        else { return [] }
        let all: [Diagnostics.Entry] = entries.compactMap { entry in
            guard let log = entry as? OSLogEntryLog else { return nil }
            return Diagnostics.Entry(date: log.date, level: level(log.level), category: log.category, message: log.composedMessage)
        }
        return Array(all.suffix(limit))
    }

    private static func level(_ level: OSLogEntryLog.Level) -> String {
        switch level {
        case .debug: "debug"
        case .info: "info"
        case .notice: "notice"
        case .error: "error"
        case .fault: "fault"
        default: "log"
        }
    }
}
