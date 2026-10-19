import Foundation

public enum BackupNaming {
    public static let fileExtension = "bugvoicebackup"
    public static let safetyCopyPrefix = "Restore safety copy "

    public static func fileName(at date: Date, timeZone: TimeZone, taken: Set<String>) -> String {
        let stem = "BugVoice Backup " + formatter(timeZone: timeZone).string(from: date)
        let original = "\(stem).\(fileExtension)"
        guard taken.contains(original) else { return original }
        var suffix = 2
        while taken.contains("\(stem) \(suffix).\(fileExtension)") { suffix += 1 }
        return "\(stem) \(suffix).\(fileExtension)"
    }

    public static func date(fromFileName name: String, timeZone: TimeZone) -> Date? {
        let pattern = #"\ABugVoice Backup ([0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{4})(?: (?:[2-9]|[1-9][0-9]+))?\.bugvoicebackup\z"#
        guard let range = name.range(of: pattern, options: .regularExpression),
              range == name.startIndex..<name.endIndex else { return nil }
        let timestamp = String(name.dropFirst("BugVoice Backup ".count).prefix(15))
        let formatter = formatter(timeZone: timeZone)
        guard let date = formatter.date(from: timestamp),
              formatter.string(from: date) == timestamp else { return nil }
        return date
    }

    public static func safetyCopyName(at date: Date, timeZone: TimeZone) -> String {
        safetyCopyPrefix + formatter(timeZone: timeZone).string(from: date)
    }

    private static func formatter(timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HHmm"
        formatter.isLenient = false
        return formatter
    }
}

public enum BackupSchedule {
    public static func isDue(_ frequency: BackupFrequency, newest: Date?, now: Date) -> Bool {
        guard frequency != .off else { return false }
        guard let newest else { return true }
        let interval: TimeInterval = frequency == .daily ? 86_400 : 604_800
        return now.timeIntervalSince(newest) >= interval
    }

    public static func filesToDelete(_ names: [String], keep: Int, timeZone: TimeZone) -> [String] {
        let dated = names.compactMap { name -> (name: String, date: Date)? in
            guard let date = BackupNaming.date(fromFileName: name, timeZone: timeZone) else { return nil }
            return (name, date)
        }.sorted {
            if $0.date == $1.date { return $0.name < $1.name }
            return $0.date < $1.date
        }
        return dated.prefix(max(0, dated.count - max(0, keep))).map(\.name)
    }

    public static func newest(_ names: [String], timeZone: TimeZone) -> Date? {
        names.compactMap { BackupNaming.date(fromFileName: $0, timeZone: timeZone) }.max()
    }
}
