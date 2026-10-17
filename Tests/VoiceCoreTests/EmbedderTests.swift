import Foundation
import Testing
@testable import VoiceCore

// Nested in ProviderTests so the shared StubURLProtocol handler is never used by two suites at once.
extension ProviderTests {
@Suite struct EmbedderTests {
    func json(_ data: Data) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    func embedder(key: String? = nil) -> OpenAICompatibleEmbedder {
        OpenAICompatibleEmbedder(baseURL: URL(string: "http://localhost:8000")!, model: "emb", apiKey: key, session: StubURLProtocol.session())
    }

    func reply(_ vectors: [[Double]], indexes: [Int]? = nil) -> Data {
        let rows = vectors.enumerated().map { i, v in
            #"{"index":\#(indexes?[i] ?? i),"embedding":\#(v)}"#
        }
        return Data(#"{"data":[\#(rows.joined(separator: ","))]}"#.utf8)
    }

    @Test func requestBody() async throws {
        StubURLProtocol.handler = { req, body in
            #expect(req.url?.path == "/v1/embeddings")
            #expect(req.httpMethod == "POST")
            let j = self.json(body)
            #expect(j["model"] as? String == "emb")
            #expect(j["input"] as? [String] == ["a", "b"])
            return (200, self.reply([[1, 0], [0, 1]]))
        }
        let e = embedder()
        #expect(e.modelID == "emb")
        _ = try await e.embed(["a", "b"])
    }

    @Test func batchesOf32() async throws {
        var sizes: [Int] = []
        StubURLProtocol.handler = { _, body in
            let n = (self.json(body)["input"] as? [String])?.count ?? 0
            sizes.append(n)
            return (200, self.reply(Array(repeating: [1, 0], count: n)))
        }
        let out = try await embedder().embed((0..<70).map { "t\($0)" })
        #expect(sizes == [32, 32, 6])
        #expect(out.count == 70)
    }

    @Test func ordersByIndex() async throws {
        StubURLProtocol.handler = { _, _ in (200, self.reply([[0, 1], [1, 0]], indexes: [1, 0])) }
        let out = try await embedder().embed(["a", "b"])
        #expect(out == [[1, 0], [0, 1]])
    }

    @Test func normalises() async throws {
        StubURLProtocol.handler = { _, _ in (200, self.reply([[3, 4], [0, 0]])) }
        let out = try await embedder().embed(["a", "b"])
        #expect(abs(out[0][0] - 0.6) < 1e-6 && abs(out[0][1] - 0.8) < 1e-6)
        #expect(out[1] == [0, 0])
    }

    @Test func emptyInputSendsNothing() async throws {
        StubURLProtocol.handler = { _, _ in Issue.record("request sent"); return (500, Data()) }
        #expect(try await embedder().embed([]) == [])
    }

    @Test func httpErrorThrows() async {
        StubURLProtocol.handler = { _, _ in (500, Data("secret echo".utf8)) }
        do {
            _ = try await embedder().embed(["a"])
            Issue.record("expected throw")
        } catch ProviderError.http(let status, let body) {
            #expect(status == 500)
            #expect(body.isEmpty)
        } catch { Issue.record("wrong error \(error)") }
    }

    @Test func countMismatchThrows() async {
        StubURLProtocol.handler = { _, _ in (200, self.reply([[1, 0]])) }
        do {
            _ = try await embedder().embed(["a", "b"])
            Issue.record("expected throw")
        } catch ProviderError.malformedResponse {
        } catch { Issue.record("wrong error \(error)") }
    }

    @Test func badIndexThrows() async {
        StubURLProtocol.handler = { _, _ in (200, self.reply([[1, 0], [0, 1]], indexes: [0, 0])) }
        do {
            _ = try await embedder().embed(["a", "b"])
            Issue.record("expected throw")
        } catch ProviderError.malformedResponse {
        } catch { Issue.record("wrong error \(error)") }
    }

    @Test func keySentAsBearer() async throws {
        var auth: [String?] = []
        StubURLProtocol.handler = { req, _ in
            auth.append(req.value(forHTTPHeaderField: "Authorization"))
            return (200, self.reply([[1, 0]]))
        }
        _ = try await embedder(key: "KEY").embed(["a"])
        _ = try await embedder(key: nil).embed(["a"])
        #expect(auth == ["Bearer KEY", nil])
    }
}
}
