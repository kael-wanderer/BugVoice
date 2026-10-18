import Testing
@testable import VoiceCore

@Suite struct ShellLayoutTests {
    @Test func columnsScaleUntilCapped() {
        #expect(ShellLayout.sidebarWidth(scale: 100) == 200)
        #expect(ShellLayout.sidebarWidth(scale: 160) == 260)
        #expect(ShellLayout.listPaneWidth(scale: 100) == 250)
        #expect(ShellLayout.listPaneWidth(scale: 160) == 320)
        #expect(ShellLayout.sectionListWidth(scale: 100) == 180)
        #expect(ShellLayout.sectionListWidth(scale: 160) == 230)
    }
    @Test func minimumWindowWidthGrowsWithText() {
        #expect(ShellLayout.minimumWindowWidth(scale: 100, screenWidth: 3000) == 918) // 200+250+420+48
        #expect(ShellLayout.minimumWindowWidth(scale: 90, screenWidth: 3000) >= 820)
        #expect(ShellLayout.minimumWindowWidth(scale: 160, screenWidth: 3000) == 1048)
    }
    @Test func minimumWindowWidthNeverExceedsScreen() {
        #expect(ShellLayout.minimumWindowWidth(scale: 160, screenWidth: 1000) == 1000)
    }
    @Test func sidebarHidesOnlyWhenScreenTooSmall() {
        #expect(!ShellLayout.sidebarMustHide(scale: 160, screenWidth: 1440))
        #expect(ShellLayout.sidebarMustHide(scale: 160, screenWidth: 1000))
    }
    @Test func gutterShrinksToTwentyFour() {
        #expect(ShellLayout.gutter(available: 1000, block: 760) == 32)
        #expect(ShellLayout.gutter(available: 800, block: 760) == 24)
        #expect(ShellLayout.blockWidth(available: 800, block: 760) == 752)
        #expect(ShellLayout.blockWidth(available: 1400, block: 760) == 760)
        #expect(ShellLayout.blockWidth(available: 30, block: 760) == 0)
    }
}
