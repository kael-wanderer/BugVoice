import Foundation

/// One process that Core Audio lists, with what BugVoice needs to decide
/// whether it is in a meeting.
public struct AudioInputProcess: Equatable, Sendable {
    public var pid: Int32
    public var bundleID: String
    public var isRunningInput: Bool
    /// Window titles of the app; filled only for browsers.
    public var windowTitles: [String]

    public init(pid: Int32, bundleID: String, isRunningInput: Bool, windowTitles: [String] = []) {
        self.pid = pid
        self.bundleID = bundleID
        self.isRunningInput = isRunningInput
        self.windowTitles = windowTitles
    }
}

public struct MeetingCandidate: Equatable, Sendable {
    /// The app's bundle ID (a helper process maps to its app).
    public var bundleID: String
    public var appName: String
    /// Meeting title from the window title, or the app name.
    public var title: String

    public init(bundleID: String, appName: String, title: String) {
        self.bundleID = bundleID
        self.appName = appName
        self.title = title
    }
}

public enum MeetingDetectionEvent: Equatable, Sendable {
    case detected(MeetingCandidate)
    case ended(bundleID: String)
}

/// Decides from microphone use when to offer to record a meeting and when
/// to offer to stop. It never starts or stops anything itself.
public struct MeetingDetector: Sendable {
    public static let meetingApps: [String: String] = [
        "us.zoom.xos": "Zoom",
        "com.microsoft.teams2": "Microsoft Teams",
        "com.microsoft.teams": "Microsoft Teams",
        "com.tinyspeck.slackmacgap": "Slack",
        "com.apple.FaceTime": "FaceTime",
        "Cisco-Systems.Spark": "Webex",
        "com.hnc.Discord": "Discord",
    ]
    public static let browsers: [String: String] = [
        "com.google.Chrome": "Google Chrome",
        "com.apple.Safari": "Safari",
        "company.thebrowser.Browser": "Arc",
        "com.microsoft.edgemac": "Microsoft Edge",
        "org.mozilla.firefox": "Firefox",
        "com.brave.Browser": "Brave",
    ]
    /// Seconds the recorded app must stay off the microphone before "Meeting ended".
    public static let endDelay: TimeInterval = 10

    private let ownPID: Int32
    /// Apps already offered while they kept using the microphone.
    private var offered: Set<String> = []
    private var quietSince: Date?
    private var endedSent = false

    public init(ownPID: Int32) {
        self.ownPID = ownPID
    }

    /// The app a bundle ID belongs to: itself, or the app whose ID it extends
    /// (`com.google.Chrome.helper` belongs to `com.google.Chrome`;
    /// `com.apple.WebKit.GPU` to Safari). Nil when unknown.
    public static func appBundleID(for bundleID: String) -> String? {
        // Safari records the microphone in WebKit's GPU process.
        if bundleID == "com.apple.WebKit.GPU" { return "com.apple.Safari" }
        for known in Array(meetingApps.keys) + Array(browsers.keys)
        where bundleID == known || bundleID.hasPrefix(known + ".") {
            return known
        }
        return nil
    }

    /// Feed the current process list. Call on every change and at least every
    /// 2 seconds while recording so "Meeting ended" can fire.
    public mutating func update(
        processes: [AudioInputProcess],
        now: Date,
        isRecording: Bool,
        recordingApp: String?,
        muted: Set<String>
    ) -> [MeetingDetectionEvent] {
        var active: [String: MeetingCandidate] = [:]
        var order: [String] = []
        for process in processes where process.pid != ownPID && process.isRunningInput {
            guard let app = Self.appBundleID(for: process.bundleID), active[app] == nil,
                  let candidate = Self.candidate(app: app, windowTitles: process.windowTitles) else { continue }
            active[app] = candidate
            order.append(app)
        }
        offered.formIntersection(active.keys)

        var events: [MeetingDetectionEvent] = []
        if isRecording {
            offered.formUnion(active.keys)
            if let recordingApp {
                if active[recordingApp] != nil {
                    quietSince = nil
                    endedSent = false
                } else {
                    let since = quietSince ?? now
                    quietSince = since
                    if !endedSent, now.timeIntervalSince(since) >= Self.endDelay {
                        endedSent = true
                        events.append(.ended(bundleID: recordingApp))
                    }
                }
            }
        } else {
            quietSince = nil
            endedSent = false
            if let app = order.first(where: { !offered.contains($0) && !muted.contains($0) }), let candidate = active[app] {
                offered.insert(app)
                events.append(.detected(candidate))
            }
        }
        return events
    }

    static func candidate(app: String, windowTitles: [String]) -> MeetingCandidate? {
        if let name = meetingApps[app] {
            return MeetingCandidate(bundleID: app, appName: name, title: name)
        }
        for title in windowTitles {
            guard let service = webMeetingService(windowTitle: title) else { continue }
            return MeetingCandidate(bundleID: app, appName: service, title: meetingTitle(fromWindowTitle: title) ?? service)
        }
        return nil
    }

    /// "Google Meet", "Microsoft Teams" or "Zoom" when a browser window title is a web meeting.
    public static func webMeetingService(windowTitle: String) -> String? {
        let title = windowTitle.lowercased()
        if title.hasPrefix("meet:") || title.hasPrefix("meet - ") || title.hasPrefix("meet – ")
            || title.contains(" meet - ") || title.contains(" meet – ") {
            return "Google Meet"
        }
        if title.contains("microsoft teams") { return "Microsoft Teams" }
        if title.contains("zoom"), title.contains("meeting") { return "Zoom" }
        return nil
    }

    private static let titleNoise: Set<String> = [
        "meet", "google meet", "microsoft teams", "zoom", "google chrome", "safari", "arc",
        "microsoft edge", "microsoft​ edge", "firefox", "mozilla firefox", "brave",
        "camera or microphone recording", "microphone recording", "audio playing",
    ]

    /// "Meet - Helpdesk bot sync - Google Chrome" gives "Helpdesk bot sync". Nil when only app names are left.
    public static func meetingTitle(fromWindowTitle windowTitle: String) -> String? {
        var text = windowTitle
        if text.lowercased().hasPrefix("meet:") { text = String(text.dropFirst(5)) }
        let parts = text.split(separator: /\s[-–—|]\s/)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !titleNoise.contains($0.lowercased()) }
        let joined = parts.joined(separator: " - ")
        return joined.isEmpty ? nil : joined
    }
}
