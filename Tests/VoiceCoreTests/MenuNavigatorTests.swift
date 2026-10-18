import Testing
@testable import VoiceCore

@Suite struct MenuNavigatorTests {
    let ids = ["a", "b", "c"]
    @Test func startsWithNothingHighlighted() { #expect(MenuNavigator<String>().highlighted == nil) }
    @Test func downStartsAtFirstAndWraps() {
        var nav = MenuNavigator<String>()
        nav.next(in: ids); #expect(nav.highlighted == "a")
        nav.next(in: ids); nav.next(in: ids); #expect(nav.highlighted == "c")
        nav.next(in: ids); #expect(nav.highlighted == "a")
    }
    @Test func upStartsAtLastAndWraps() {
        var nav = MenuNavigator<String>()
        nav.previous(in: ids); #expect(nav.highlighted == "c")
        nav.previous(in: ids); nav.previous(in: ids); #expect(nav.highlighted == "a")
        nav.previous(in: ids); #expect(nav.highlighted == "c")
    }
    @Test func hoverMovesTheHighlight() {
        var nav = MenuNavigator<String>()
        nav.hover("b"); nav.next(in: ids); #expect(nav.highlighted == "c")
        nav.clear(); #expect(nav.highlighted == nil)
    }
    @Test func highlightLostWhenItemDisappears() {
        var nav = MenuNavigator(highlighted: "b")
        nav.next(in: ["a", "c"]); #expect(nav.highlighted == "a")
        nav = MenuNavigator(highlighted: "b")
        nav.previous(in: ["a", "c"]); #expect(nav.highlighted == "c")
    }
    @Test func emptyListHighlightsNothing() {
        var nav = MenuNavigator(highlighted: "a")
        nav.next(in: []); #expect(nav.highlighted == nil)
    }
}
