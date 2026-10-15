import Foundation

public enum NotesListProjection {
    public static func filter(_ items: [NotesListItem], query: String) -> [NotesListItem] {
        let normalizedQuery = normalize(query.trimmingCharacters(in: .whitespacesAndNewlines))
        let sorted = items.sorted { lhs, rhs in
            if lhs.modifiedAt != rhs.modifiedAt { return lhs.modifiedAt > rhs.modifiedAt }
            let leftTitle = normalize(lhs.title)
            let rightTitle = normalize(rhs.title)
            if leftTitle != rightTitle { return leftTitle < rightTitle }
            return lhs.id.rawValue < rhs.id.rawValue
        }
        guard !normalizedQuery.isEmpty else { return sorted }
        return sorted.filter { item in
            normalize(item.title).contains(normalizedQuery)
                || normalize(item.body).contains(normalizedQuery)
                || LibraryTagSearch.matches(item.tags, query: query)
        }
    }

    private static func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
}

/// Search text `acme` or `#acme` matches an item tagged `acme`.
public enum LibraryTagSearch {
    public static func matches(_ tags: [String], query: String) -> Bool {
        guard let needle = TagName.normalize(query) else { return false }
        return tags.contains { $0.contains(needle) }
    }
}
