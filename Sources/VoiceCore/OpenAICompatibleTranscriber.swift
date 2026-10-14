import Foundation

/// `POST {base}/v1/audio/transcriptions` with a WAV file, for any local
/// transcription server that speaks the OpenAI API.
public struct OpenAICompatibleTranscriber: Transcriber {
    public var baseURL: URL
    public var model: String
    public var apiKey: String?
    public var session: URLSession

    public init(baseURL: URL, model: String, apiKey: String? = nil, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.model = model
        self.apiKey = apiKey
        self.session = session
    }

    struct Reply: Decodable {
        struct Segment: Decodable { let start: Double; let end: Double; let text: String }
        let text: String
        let language: String?
        let segments: [Segment]?
    }

    public func transcribe(_ clip: AudioClip, options: TranscriptionOptions) async throws -> Transcript {
        let boundary = "bugvoice-\(UUID().uuidString)"
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        field("model", model)
        field("response_format", "verbose_json")
        if options.language != .auto { field("language", options.language.rawValue) }
        if !options.prompt.isEmpty { field("prompt", options.prompt) }
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\nContent-Type: audio/wav\r\n\r\n".utf8))
        body.append(WAVEncoder.encode(clip))
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))

        var request = URLRequest(url: Endpoint.join(baseURL, "audio/transcriptions"), timeoutInterval: 120)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if let apiKey, !apiKey.isEmpty { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        request.httpBody = body

        let reply = try HTTP.decode(Reply.self, from: try await HTTP.send(request, session: session))
        let segments = (reply.segments ?? []).map {
            TranscriptSegment(start: $0.start, end: $0.end, text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return Transcript(
            text: reply.text.trimmingCharacters(in: .whitespacesAndNewlines),
            segments: segments,
            language: reply.language
        )
    }
}
