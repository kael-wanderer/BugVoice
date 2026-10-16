import Foundation

/// Open tabs on the Scratchpad page, in the order they were opened.
public struct ScratchpadTabs: Equatable, Sendable {
    public private(set) var ids: [NoteID]
    public private(set) var active: NoteID?

    public init(ids: [NoteID] = [], active: NoteID? = nil) {
        self.ids = ids
        self.active = active.flatMap { ids.contains($0) ? $0 : nil } ?? ids.first
    }

    public func isOpen(_ id: NoteID) -> Bool { ids.contains(id) }

    /// Appends the tab if needed and makes it active.
    public mutating func open(_ id: NoteID) {
        if !ids.contains(id) { ids.append(id) }
        active = id
    }

    /// Closes the tab. When it was active, the tab to its right becomes
    /// active, else the one to its left, else none.
    public mutating func close(_ id: NoteID) {
        guard let index = ids.firstIndex(of: id) else { return }
        ids.remove(at: index)
        guard active == id else { return }
        if ids.isEmpty {
            active = nil
        } else {
            active = ids[min(index, ids.count - 1)]
        }
    }

    /// Drops tabs whose notes no longer exist.
    public mutating func prune(existing: Set<NoteID>) {
        for id in ids where !existing.contains(id) { close(id) }
    }

    /// Rebuilds tabs from saved slugs. Unknown slugs are dropped.
    public static func restore(openTabs: [String], activeTab: String?, slugs: [NoteID: String]) -> ScratchpadTabs {
        var bySlug: [String: NoteID] = [:]
        for (id, slug) in slugs { bySlug[slug] = id }
        var ids: [NoteID] = []
        for slug in openTabs {
            if let id = bySlug[slug], !ids.contains(id) { ids.append(id) }
        }
        return ScratchpadTabs(ids: ids, active: activeTab.flatMap { bySlug[$0] })
    }

    /// The slugs to save. Tabs whose slug is unknown are left out.
    public func saved(slugs: [NoteID: String]) -> (openTabs: [String], activeTab: String?) {
        (ids.compactMap { slugs[$0] }, active.flatMap { slugs[$0] })
    }
}
