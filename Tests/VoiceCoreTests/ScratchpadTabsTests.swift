import Testing
@testable import VoiceCore

struct ScratchpadTabsTests {
    let a = NoteID(rawValue: "a"), b = NoteID(rawValue: "b"), c = NoteID(rawValue: "c")

    @Test func openAppendsOnceAndActivates() {
        var tabs = ScratchpadTabs()
        tabs.open(a)
        tabs.open(b)
        tabs.open(a)
        #expect(tabs.ids == [a, b])
        #expect(tabs.active == a)
    }

    @Test func closingActivePicksRightThenLeft() {
        var tabs = ScratchpadTabs(ids: [a, b, c], active: b)
        tabs.close(b)
        #expect(tabs.active == c)
        tabs.close(c)
        #expect(tabs.active == a)
        tabs.close(a)
        #expect(tabs.active == nil)
        #expect(tabs.ids.isEmpty)
    }

    @Test func closingInactiveKeepsActive() {
        var tabs = ScratchpadTabs(ids: [a, b, c], active: a)
        tabs.close(c)
        #expect(tabs.active == a)
        #expect(tabs.ids == [a, b])
    }

    @Test func pruneDropsMissingNotes() {
        var tabs = ScratchpadTabs(ids: [a, b, c], active: b)
        tabs.prune(existing: [a, c])
        #expect(tabs.ids == [a, c])
        #expect(tabs.active == c)
    }

    @Test func restoreAndSaveBySlug() {
        let slugs = [a: "alpha", b: "beta"]
        let tabs = ScratchpadTabs.restore(openTabs: ["beta", "gone", "alpha", "beta"], activeTab: "alpha", slugs: slugs)
        #expect(tabs.ids == [b, a])
        #expect(tabs.active == a)
        let saved = tabs.saved(slugs: slugs)
        #expect(saved.openTabs == ["beta", "alpha"])
        #expect(saved.activeTab == "alpha")
    }

    @Test func restoreWithMissingActiveUsesFirst() {
        let tabs = ScratchpadTabs.restore(openTabs: ["alpha"], activeTab: "gone", slugs: [a: "alpha"])
        #expect(tabs.active == a)
    }
}
