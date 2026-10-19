import Foundation

public enum CodingApps {
    public static let bundleIDs: Set<String> = [
        "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.todesktop.230313mzl4w4u92",
        "com.apple.dt.Xcode", "dev.zed.Zed", "com.stablyai.orca"
    ]

    public static func contains(focus: FocusSnapshot, style: Style) -> Bool {
        style == .terminal || focus.bundleID.map(bundleIDs.contains) == true
    }
}

public struct ProjectMatch: Equatable, Sendable {
    public var projectName: String?
    public var words: [String]

    public init(projectName: String? = nil, words: [String] = []) {
        self.projectName = projectName
        self.words = words
    }
}

public enum ProjectMatcher {
    public static let promptLimit = 150

    public static func match(focus: FocusSnapshot, style: Style, projects: [Project], scope: ProjectWordsScope,
                             excluding dictionaryTerms: [String], limit: Int = promptLimit) -> ProjectMatch {
        guard scope != .off else { return ProjectMatch() }
        if scope == .codingApps, !CodingApps.contains(focus: focus, style: style) { return ProjectMatch() }

        let enabled = projects.filter(\.enabled)
        let title = focus.windowTitle ?? ""
        let matches = enabled.filter { project in
            wholeWord(project.name, in: title) || pathCandidates(project.path).contains { containsPath($0, in: title) }
        }
        let active = matches.sorted { lhs, rhs in
            if lhs.name.count != rhs.name.count { return lhs.name.count > rhs.name.count }
            return false
        }.first
        let source = active.map { [$0] } ?? enabled
        let excluded = Set(dictionaryTerms)
        let cappedLimit = max(0, min(limit, promptLimit))
        guard cappedLimit > 0 else { return ProjectMatch(projectName: active?.name, words: []) }

        var words: [String] = []
        var seen = Set<String>()
        if let active {
            for word in active.words.map(\.word) where !excluded.contains(word) && seen.insert(word).inserted {
                words.append(word)
                if words.count == cappedLimit { break }
            }
        } else {
            var depth = 0
            while words.count < cappedLimit {
                var foundAtDepth = false
                for project in source where depth < project.words.count {
                    foundAtDepth = true
                    let word = project.words[depth].word
                    if !excluded.contains(word), seen.insert(word).inserted { words.append(word) }
                    if words.count == cappedLimit { break }
                }
                if !foundAtDepth { break }
                depth += 1
            }
        }
        return ProjectMatch(projectName: active?.name, words: words)
    }

    private static func wholeWord(_ candidate: String, in text: String) -> Bool {
        guard !candidate.isEmpty else { return false }
        let pattern = "(?<![\\p{L}\\p{N}_])" + NSRegularExpression.escapedPattern(for: candidate) + "(?![\\p{L}\\p{N}_])"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return false }
        return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    private static func containsPath(_ candidate: String, in title: String) -> Bool {
        guard !candidate.isEmpty, let range = title.range(of: candidate, options: [.caseInsensitive]) else { return false }
        let before = range.lowerBound == title.startIndex ? nil : title[title.index(before: range.lowerBound)]
        let after = range.upperBound == title.endIndex ? nil : title[range.upperBound]
        let pathCharacter: (Character) -> Bool = { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "/" || $0 == "." || $0 == "-" }
        return !(before.map(pathCharacter) ?? false) && !(after.map(pathCharacter) ?? false)
    }

    private static func pathCandidates(_ path: String) -> [String] {
        var candidates = [path, URL(fileURLWithPath: path).standardizedFileURL.path]
        let home = NSHomeDirectory().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !home.isEmpty, path.hasPrefix("/" + home + "/") {
            candidates.append("~/" + String(path.dropFirst(home.count + 2)))
        }
        let components = URL(fileURLWithPath: path).standardizedFileURL.pathComponents
        if components.count > 3, components[1] == "Users" || components[1] == "home" {
            candidates.append("~/" + components.dropFirst(3).joined(separator: "/"))
        }
        return Array(Set(candidates))
    }
}
