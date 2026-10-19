import AppIntents

struct BugVoiceShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartMeetingIntent(), phrases: ["Start a meeting in \(.applicationName)", "Start recording a meeting in \(.applicationName)"], shortTitle: "Start meeting", systemImageName: "record.circle")
        AppShortcut(intent: StopMeetingIntent(), phrases: ["Stop the meeting in \(.applicationName)"], shortTitle: "Stop meeting", systemImageName: "stop.circle")
        AppShortcut(intent: NewNoteIntent(), phrases: ["New \(.applicationName) note"], shortTitle: "New note", systemImageName: "note.text.badge.plus")
    }
}
