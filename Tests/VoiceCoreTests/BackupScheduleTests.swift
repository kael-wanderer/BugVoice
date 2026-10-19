import Foundation
import Testing
@testable import VoiceCore

struct BackupScheduleTests {
    let utc = TimeZone(secondsFromGMT: 0)!
    var date: Date { ISO8601DateFormatter().date(from: "2026-10-19T09:12:30Z")! }
    let base = "BugVoice Backup 2026-10-19 0912.bugvoicebackup"

    @Test func fileNameUsesLocalMinute() {
        #expect(BackupNaming.fileExtension == "bugvoicebackup")
        #expect(BackupNaming.fileName(at: date, timeZone: utc, taken: []) == base)
        #expect(BackupNaming.fileName(at: date, timeZone: TimeZone(identifier: "Asia/Ho_Chi_Minh")!, taken: []) == "BugVoice Backup 2026-10-19 1612.bugvoicebackup")
    }

    @Test func fileNameAvoidsTakenNames() {
        let second = "BugVoice Backup 2026-10-19 0912 2.bugvoicebackup"
        #expect(BackupNaming.fileName(at: date, timeZone: utc, taken: [base]) == second)
        #expect(BackupNaming.fileName(at: date, timeZone: utc, taken: [base, second]) == "BugVoice Backup 2026-10-19 0912 3.bugvoicebackup")
    }

    @Test func dateParsesBothFormsAndRejectsOthers() {
        let minute = date.addingTimeInterval(-30)
        #expect(BackupNaming.date(fromFileName: base, timeZone: utc) == minute)
        #expect(BackupNaming.date(fromFileName: "BugVoice Backup 2026-10-19 0912 2.bugvoicebackup", timeZone: utc) == minute)
        for name in ["notes.zip", "BugVoice Backup 2026-13-40 9999.bugvoicebackup", "BugVoice Backup 2026-02-30 0912.bugvoicebackup", "BugVoice Backup 2026-10-19 2460.bugvoicebackup", "BugVoice Backup 2026-10-19 0912.zip", "BugVoice Backup 2026-10-19 0912 1.bugvoicebackup", "BugVoice Backup 2026-10-19 0912 02.bugvoicebackup", "BugVoice Backup 2026-10-19 0912.bugvoicebackup\n"] {
            #expect(BackupNaming.date(fromFileName: name, timeZone: utc) == nil)
        }
    }

    @Test func dueRules() {
        #expect(!BackupSchedule.isDue(.off, newest: nil, now: date))
        #expect(BackupSchedule.isDue(.daily, newest: nil, now: date))
        #expect(!BackupSchedule.isDue(.daily, newest: date.addingTimeInterval(-86340), now: date))
        #expect(BackupSchedule.isDue(.daily, newest: date.addingTimeInterval(-86400), now: date))
        #expect(!BackupSchedule.isDue(.weekly, newest: date.addingTimeInterval(-6 * 86400), now: date))
        #expect(BackupSchedule.isDue(.weekly, newest: date.addingTimeInterval(-7 * 86400), now: date))
    }

    @Test func pruneKeepsNewestAndIgnoresOtherFiles() {
        let names = (1...7).map { "BugVoice Backup 2026-10-0\($0) 0912.bugvoicebackup" }
        let mixed = Array(names.reversed()) + ["My notes.bugvoicebackup", "BugVoice Backup.txt"]
        #expect(BackupSchedule.filesToDelete(mixed, keep: 5, timeZone: utc) == Array(names.prefix(2)))
        #expect(BackupSchedule.newest(mixed, timeZone: utc) == ISO8601DateFormatter().date(from: "2026-10-07T09:12:00Z"))
        #expect(BackupSchedule.newest(["notes.zip"], timeZone: utc) == nil)
        #expect(BackupSchedule.filesToDelete(mixed, keep: 0, timeZone: utc) == names)
    }

    @Test func safetyCopyName() {
        #expect(BackupNaming.safetyCopyPrefix == "Restore safety copy ")
        #expect(BackupNaming.safetyCopyName(at: date, timeZone: utc) == "Restore safety copy 2026-10-19 0912")
    }
}
