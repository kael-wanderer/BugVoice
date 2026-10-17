import Foundation
import Testing
@testable import VoiceCore

struct WindowPlacementTests {
    // The owner's second display: visible frame right of the primary one.
    let visible = WindowPlacement.Frame(x: 2560, y: 90, width: 2560, height: 1350)

    @Test func frameInsideTheDisplayStaysWhereItIs() {
        let frame = WindowPlacement.Frame(x: 4263, y: 102, width: 845, height: 1296)
        #expect(WindowPlacement.onScreen(frame, visible: visible) == frame)
    }

    @Test func frameOverTheRightEdgeMovesLeft() {
        // The collapsed meeting bar the owner could not close: its buttons were past x 5120.
        let frame = WindowPlacement.Frame(x: 4501, y: 1322, width: 845, height: 44)
        let placed = WindowPlacement.onScreen(frame, visible: visible)
        #expect(placed == WindowPlacement.Frame(x: 4275, y: 1322, width: 845, height: 44))
    }

    @Test func frameOverTheLeftAndBottomEdgesMovesIn() {
        let frame = WindowPlacement.Frame(x: 2500, y: 40, width: 400, height: 300)
        #expect(WindowPlacement.onScreen(frame, visible: visible) == WindowPlacement.Frame(x: 2560, y: 90, width: 400, height: 300))
    }

    @Test func frameOverTheTopEdgeMovesDown() {
        let frame = WindowPlacement.Frame(x: 3000, y: 1300, width: 400, height: 300)
        #expect(WindowPlacement.onScreen(frame, visible: visible) == WindowPlacement.Frame(x: 3000, y: 1140, width: 400, height: 300))
    }

    @Test func frameLargerThanTheDisplayShrinksToFit() {
        let frame = WindowPlacement.Frame(x: 2000, y: 0, width: 3000, height: 2000)
        #expect(WindowPlacement.onScreen(frame, visible: visible) == visible)
    }
}
