import Foundation
import Testing
@testable import VoiceCore

extension ProviderTests {
    @Test func transcriberSendsMultipartAndParsesVerboseJSON() async throws {
        StubURLProtocol.handler = { req, body in
            #expect(req.url?.path == "/v1/audio/transcriptions")
            let contentType = req.value(forHTTPHeaderField: "Content-Type") ?? ""
            #expect(contentType.hasPrefix("multipart/form-data; boundary="))
            let text = String(decoding: body, as: UTF8.self)
            #expect(text.contains(#"name="model""#))
            #expect(text.contains("whisper-1"))
            #expect(text.contains(#"name="language""#))
            #expect(text.contains(#"name="prompt""#))
            #expect(text.contains(#"filename="audio.wav""#))
            #expect(text.contains("verbose_json"))
            return (200, Data(#"{"text":" Xin chào ","language":"vietnamese","segments":[{"start":0.0,"end":1.2,"text":" Xin chào"}]}"#.utf8))
        }
        let t = OpenAICompatibleTranscriber(baseURL: URL(string: "http://h")!, model: "whisper-1", session: StubURLProtocol.session())
        let result = try await t.transcribe(AudioClip(samples: [0, 0.1]), options: TranscriptionOptions(language: .vi, prompt: "BugVoice"))
        #expect(result.text == "Xin chào")
        #expect(result.language == "vietnamese")
        #expect(result.segments == [TranscriptSegment(start: 0, end: 1.2, text: "Xin chào")])
    }

    @Test func transcriberOmitsLanguageForAuto() async throws {
        StubURLProtocol.handler = { _, body in
            #expect(!String(decoding: body, as: UTF8.self).contains(#"name="language""#))
            return (200, Data(#"{"text":"hi"}"#.utf8))
        }
        let t = OpenAICompatibleTranscriber(baseURL: URL(string: "http://h")!, model: "m", session: StubURLProtocol.session())
        #expect(try await t.transcribe(AudioClip(samples: [0]), options: TranscriptionOptions()).text == "hi")
    }
}
