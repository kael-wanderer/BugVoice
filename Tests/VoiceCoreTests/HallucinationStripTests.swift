import Testing
@testable import VoiceCore

struct HallucinationStripTests {
    @Test func stripsAChannelLineInsideSpeech() {
        let text = "Mai mình họp lúc chín giờ. Hãy subscribe cho kênh Ghiền Mì Gõ để không bỏ lỡ những video hấp dẫn."
        #expect(HallucinationFilter.strip(text) == "Mai mình họp lúc chín giờ.")
    }

    @Test func stripsInTheMiddleAndKeepsBothSides() {
        let text = "We ship Monday. Subtitles by the Amara.org community. Then we review."
        #expect(HallucinationFilter.strip(text) == "We ship Monday. Then we review.")
    }

    @Test func keepsShortPhrasesThatCanBeRealSpeech() {
        let text = "Thank you, that helps. Please subscribe me to the list."
        #expect(HallucinationFilter.strip(text) == text)
    }

    @Test func caseAndPunctuationDoNotMatter() {
        #expect(HallucinationFilter.strip("OK. HẸN GẶP LẠI CÁC BẠN, trong những video tiếp theo!") == "OK.")
    }

    @Test func dictationDropsTheStrippedLine() async throws {
        #expect(HallucinationFilter.strip("Hãy subscribe cho kênh Ghiền Mì Gõ để không bỏ lỡ những video hấp dẫn") == "")
    }

    @Test func stripsTheSpanishAmaraCredit() {
        let text = "Mañana enviamos el informe. Subtítulos realizados por la comunidad de Amara.org"
        #expect(HallucinationFilter.strip(text) == "Mañana enviamos el informe.")
    }

    @Test func spanishCreditsAloneAreSilence() {
        #expect(HallucinationFilter.isHallucination("Subtítulos realizados por la comunidad de Amara.org"))
        #expect(HallucinationFilter.isHallucination("¡Gracias por ver!"))
        #expect(HallucinationFilter.isHallucination("Gracias por ver el video."))
        #expect(!HallucinationFilter.isHallucination("Gracias por ver el informe conmigo."))
    }
}
