import Testing
@testable import VoiceCore

struct DevScreenTests {
    let main = DevScreen.Display(x: 0, y: 0)
    let right = DevScreen.Display(x: 2560, y: 0)
    let above = DevScreen.Display(x: 0, y: -1440)

    @Test func secondDisplayIsChosenWhenAsked() {
        #expect(DevScreen.choose([main, right], primary: main, setting: "second") == 1)
        // The order macOS lists them in does not decide it; the primary does.
        #expect(DevScreen.choose([right, main], primary: main, setting: "second") == 0)
        #expect(DevScreen.choose([main, above, right], primary: main, setting: "second") == 1)
    }

    @Test func oneDisplayLeavesTheWindowAlone() {
        #expect(DevScreen.choose([main], primary: main, setting: "second") == nil)
        #expect(DevScreen.choose([], primary: nil, setting: "second") == nil)
    }

    @Test func normalLaunchAndPrimaryOverrideLeaveTheWindowAlone() {
        #expect(DevScreen.choose([main, right], primary: main, setting: nil) == nil)
        #expect(DevScreen.choose([main, right], primary: main, setting: "") == nil)
        #expect(DevScreen.choose([main, right], primary: main, setting: "primary") == nil)
        #expect(DevScreen.choose([main, right], primary: main, setting: "PRIMARY") == nil)
    }

    @Test func missingPrimaryTreatsFirstDisplayAsPrimary() {
        #expect(DevScreen.choose([main, right], primary: nil, setting: "second") == 1)
    }
}
