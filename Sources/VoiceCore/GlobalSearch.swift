import Foundation

public enum SearchKind: String, Sendable, CaseIterable {
    case meeting, note, dictation, settings
}

public struct SearchHit: Equatable, Sendable, Identifiable {
    public enum Target: Hashable, Sendable {
        case meeting(MeetingID, part: AskPart?, lineID: String?)
        case note(NoteID)
        case dictation(UUID)
        case settings(section: String)
    }

    public var target: Target
    public var kind: SearchKind
    public var title: String
    public var snippet: String
    public var date: Date?
    public var score: Double
    public var id: String
}

public struct SearchTitle: Sendable {
    public var source: AskSource
    public var title: String
    public var date: Date

    public init(source: AskSource, title: String, date: Date) {
        self.source = source
        self.title = title
        self.date = date
    }
}

public struct SettingsSearchEntry: Sendable, Equatable {
    public var label: String
    public var section: String
}

public enum GlobalSearch {
    public static let limit = 8

    public static let settingsEntries: [SettingsSearchEntry] = [
        .init(label: "General", section: "general"),
        .init(label: "Shortcuts", section: "shortcuts"),
        .init(label: "Editing", section: "editing"),
        .init(label: "Theme & icons", section: "theme"),
        .init(label: "Speech", section: "speech"),
        .init(label: "Models", section: "models"),
        .init(label: "Agents", section: "agents"),
        .init(label: "Meetings", section: "meetings"),
        .init(label: "Storage", section: "storage"),
        .init(label: "Text size", section: "editing"),
        .init(label: "Font", section: "editing"),
        .init(label: "Code font", section: "editing"),
        .init(label: "Line spacing", section: "editing"),
        .init(label: "Reading width", section: "editing"),
        .init(label: "Theme", section: "theme"),
        .init(label: "Light and dark", section: "theme"),
        .init(label: "App icon", section: "theme"),
        .init(label: "Menu bar icon", section: "theme"),
        .init(label: "Recording pill", section: "theme"),
        .init(label: "Hold to talk", section: "shortcuts"),
        .init(label: "Hotkey", section: "shortcuts"),
        .init(label: "Paste last dictation", section: "shortcuts"),
        .init(label: "MCP server", section: "agents"),
    ]

    private enum ItemKey: Hashable {
        case meeting(MeetingID)
        case note(NoteID)
        case dictation(UUID)
    }

    private struct PassageMatch {
        var passage: AskPassage
        var score: Double
    }

    private struct ItemMatch {
        var bestPassage: PassageMatch?
        var passages: [PassageMatch] = []
        var title: SearchTitle?
        var titleMatched = false
    }

    public static func search(
        _ query: String, passages: [AskPassage], titles: [SearchTitle],
        first: SearchKind?, limit: Int = limit
    ) -> [SearchHit] {
        let terms = AskText.tokens(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !terms.isEmpty, limit > 0 else { return [] }

        let passageScores = AskRanking.wordScores(passages, terms: terms, people: [])
        var items: [ItemKey: ItemMatch] = [:]

        for passage in passages {
            guard let score = passageScores[passage.id], let key = itemKey(for: passage) else { continue }
            let match = PassageMatch(passage: passage, score: score)
            var item = items[key, default: ItemMatch()]
            item.passages.append(match)
            if let best = item.bestPassage {
                if isBetter(match, than: best) { item.bestPassage = match }
            } else {
                item.bestPassage = match
            }
            items[key] = item
        }

        for title in titles where titleMatches(title.title, terms: terms) {
            let key: ItemKey
            switch title.source {
            case .meeting(let id): key = .meeting(id)
            case .note(let id): key = .note(id)
            case .dictations: continue
            }
            var item = items[key, default: ItemMatch()]
            item.title = title
            item.titleMatched = true
            items[key] = item
        }

        var hits: [SearchHit] = []
        for (key, item) in items {
            guard item.bestPassage != nil || item.titleMatched else { continue }
            let passageMatch = item.bestPassage
            let score = (passageMatch?.score ?? 0) + (item.titleMatched ? 5 : 0)
            let date = item.title?.date ?? passageMatch?.passage.date

            switch key {
            case .meeting(let id):
                let passage = passageMatch?.passage
                let part = passage?.part
                let lineID = part == .transcript ? passage?.lines.first?.id : nil
                let title = item.title?.title ?? passageTitle(item.passages) ?? "Meeting"
                let snippet = passage.map { snippet($0.searchText, query: query) } ?? ""
                hits.append(SearchHit(
                    target: .meeting(id, part: part, lineID: lineID), kind: .meeting,
                    title: title, snippet: snippet, date: date, score: score,
                    id: "meeting:\(id.rawValue)"))
            case .note(let id):
                let passage = passageMatch?.passage
                let title = item.title?.title ?? passageTitle(item.passages) ?? "Note"
                let snippetPassage: AskPassage?
                if passage?.part == .title {
                    let bodyPassages: [PassageMatch] = item.passages.filter { match in
                        match.passage.part != .title
                    }
                    let orderedBodyPassages = bodyPassages.sorted { lhs, rhs in
                        isBetter(lhs, than: rhs)
                    }
                    snippetPassage = orderedBodyPassages.first?.passage
                } else {
                    snippetPassage = passage
                }
                let snippet = snippetPassage.map { snippet($0.searchText, query: query) } ?? ""
                hits.append(SearchHit(
                    target: .note(id), kind: .note, title: title, snippet: snippet,
                    date: date, score: score, id: "note:\(id.rawValue)"))
            case .dictation(let id):
                guard let passage = passageMatch?.passage else { continue }
                let appName = passage.lines.first?.speaker.flatMap { $0.isEmpty ? nil : $0 } ?? "Dictation"
                hits.append(SearchHit(
                    target: .dictation(id), kind: .dictation, title: appName,
                    snippet: snippet(passage.searchText, query: query), date: passage.date,
                    score: score, id: "dictation:\(id.uuidString.lowercased())"))
            }
        }

        for entry in settingsEntries where titleMatches(entry.label, terms: terms) {
            hits.append(SearchHit(
                target: .settings(section: entry.section), kind: .settings, title: entry.label,
                snippet: "", date: nil, score: 1,
                id: "settings:\(entry.section):\(AskText.fold(entry.label))"))
        }

        hits.sort { lhs, rhs in
            let lhsFirst = lhs.kind == first
            let rhsFirst = rhs.kind == first
            if lhsFirst != rhsFirst { return lhsFirst }
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            let lhsDate = lhs.date ?? .distantPast
            let rhsDate = rhs.date ?? .distantPast
            if lhsDate != rhsDate { return lhsDate > rhsDate }
            return lhs.id < rhs.id
        }
        return Array(hits.prefix(limit))
    }

    public static func snippet(_ text: String, query: String, maxLength: Int = 90) -> String {
        let collapsed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard maxLength > 0, !collapsed.isEmpty else { return "" }
        let characters = Array(collapsed)
        guard characters.count > maxLength else { return collapsed }

        let terms = AskText.tokens(query)
        let folded = AskText.fold(collapsed)
        let matchOffset = terms.compactMap { term -> Int? in
            guard let range = folded.range(of: term) else { return nil }
            return folded.distance(from: folded.startIndex, to: range.lowerBound)
        }.min()

        guard let matchOffset else {
            return String(characters.prefix(maxLength)) + "…"
        }
        let desiredStart = max(0, matchOffset - maxLength / 2)
        let start = min(desiredStart, characters.count - maxLength)
        let end = start + maxLength
        let window = String(characters[start..<end])
        return (start > 0 ? "…" : "") + window + (end < characters.count ? "…" : "")
    }

    private static func itemKey(for passage: AskPassage) -> ItemKey? {
        switch passage.source {
        case .meeting(let id): return .meeting(id)
        case .note(let id): return .note(id)
        case .dictations:
            guard let lineID = passage.lines.first?.id, let id = UUID(uuidString: lineID) else { return nil }
            return .dictation(id)
        }
    }

    private static func titleMatches(_ title: String, terms: [String]) -> Bool {
        let titleTokens = AskText.tokens(title)
        return terms.allSatisfy { term in titleTokens.contains { $0.hasPrefix(term) } }
    }

    private static func isBetter(_ lhs: PassageMatch, than rhs: PassageMatch) -> Bool {
        lhs.score != rhs.score ? lhs.score > rhs.score : lhs.passage.index < rhs.passage.index
    }

    private static func passageTitle(_ passages: [PassageMatch]) -> String? {
        passages.first(where: { $0.passage.part == .title })?.passage.lines.first?.text
    }
}
