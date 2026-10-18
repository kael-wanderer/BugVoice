import Testing
@testable import VoiceCore

struct TypeScaleTests {
    @Test func baseSizes() {
        for token in TextToken.allCases {
            #expect(TypeScale.size(token, scale: 100) == token.baseSize)
        }
    }

    @Test func scaledSizes() {
        #expect(TypeScale.size(.body, scale: 130) == 17)
        #expect(TypeScale.size(.footnote, scale: 130) == 15.5)
        #expect(TypeScale.size(.reading, scale: 130) == 19.5)
        #expect(TypeScale.size(.title2, scale: 115) == 20.5)
        #expect(TypeScale.size(.largeTitle, scale: 160) == 45)
        #expect(TypeScale.scaled(240, scale: 130) == 312)
    }

    @Test func largeControlsThreshold() {
        #expect(LayoutTokens.usesLargeControls(scale: 125) == false)
        #expect(LayoutTokens.usesLargeControls(scale: 130) == true)
    }

    @Test func weights() {
        #expect(TextToken.largeTitle.weight == .semibold)
        #expect(TextToken.title1.weight == .semibold)
        #expect(TextToken.title2.weight == .semibold)
        #expect(TextToken.title3.weight == .semibold)
        #expect(TextToken.bodyStrong.weight == .semibold)
        #expect(TextToken.stat.weight == .bold)
        #expect(TextToken.reading.weight == .regular)
        #expect(TextToken.body.weight == .regular)
        #expect(TextToken.footnote.weight == .regular)
        #expect(TextToken.caption.weight == .regular)
    }
}
