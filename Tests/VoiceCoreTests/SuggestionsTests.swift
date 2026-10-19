import Foundation
import Testing
@testable import VoiceCore

struct SuggestionsTests {
    func record(_ file: inout SuggestionFile, _ written: String = "Kael", _ heard: String = "Kale", at: Date = Date(), dictionary: DictionaryFile = DictionaryFile(), real: (String) -> Bool = { _ in false }) {
        file.record(.init(heard: heard, written: written), app: "Slack", at: at, dictionary: dictionary, isRealWord: real)
    }
    @Test func recordAddsNewestFirst() { var f = SuggestionFile(); record(&f); record(&f, "Tuấn", "Tuan"); #expect(f.pending.map(\.written) == ["Tuấn", "Kael"]) }
    @Test func recordCountsSamePair() { var f = SuggestionFile(); record(&f); record(&f, "Tuấn", "Tuan"); let now = Date(); record(&f, "Kael", "kale", at: now); #expect(f.pending.count == 2); #expect(f.pending[0].count == 2); #expect(f.pending[0].lastSeen == now) }
    @Test func dismissedNeverReturns() { var f = SuggestionFile(); record(&f); f.dismiss(id: f.pending[0].id); record(&f, "Kael", "kale"); #expect(f.pending.isEmpty) }
    @Test func knownPairIgnored() { var f = SuggestionFile(); record(&f, dictionary: .init(words: [.init(word: "Kael", heardAs: ["kale"])])); #expect(f.pending.isEmpty); record(&f, dictionary: .init(words: [.init(word: "Kael")])); #expect(f.pending.count == 1) }
    @Test func bothRealWordsStartWithoutReplace() { var f = SuggestionFile(); record(&f, "sell", "cell", real: { _ in true }); #expect(!f.pending[0].replace); record(&f, real: { $0 == "Kale" }); #expect(f.pending[0].replace) }
    @Test func capsPendingAndDismissed() { var f = SuggestionFile(); for i in 0..<51 { record(&f, "w\(i)") }; #expect(f.pending.count == 50); #expect(!f.pending.contains { $0.written == "w0" }); for i in 0..<501 { record(&f, "d\(i)"); f.dismiss(id: f.pending[0].id) }; #expect(f.dismissed.count == 500) }
    @Test func acceptAddsWordAndHeardAs() { var f = SuggestionFile(); record(&f); var d = DictionaryFile(); d.accept(f.pending[0]); #expect(d.words[0].word == "Kael"); #expect(d.words[0].heardAs == ["Kale"]) }
    @Test func acceptWithoutReplaceAddsWordOnly() { var f = SuggestionFile(); record(&f); f.setReplace(id: f.pending[0].id, false); var d = DictionaryFile(); d.accept(f.pending[0]); #expect(d.words[0].heardAs.isEmpty) }
    @Test func acceptExistingWordAddsHeardAs() { var f = SuggestionFile(); record(&f); var d = DictionaryFile(words: [.init(word: "kael")]); d.accept(f.pending[0]); #expect(d.words.count == 1); #expect(d.words[0].heardAs == ["Kale"]) }
    @Test func roundTripAndTolerantDecode() throws { let f = try JSONDecoder().decode(SuggestionFile.self, from: Data(#"{"pending":[{"written":"Kael","heard":"Kale"}]}"#.utf8)); #expect(f.pending[0].count == 1); #expect(f.pending[0].replace); #expect(try JSONDecoder().decode(SuggestionFile.self, from: JSONEncoder().encode(f)) == f) }
    @Test func storeSurvivesCorruptFile() async throws { let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: root) }; try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); let url = root.appendingPathComponent("suggestions.json"); try Data("bad".utf8).write(to: url); #expect(await SuggestionStore(url: url).load().pending.isEmpty); #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix("suggestions.corrupt-") }) }
    @Test func olderRevisionIsIgnored() async throws { let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: root) }; let store = SuggestionStore(url: root.appendingPathComponent("suggestions.json")); var f = SuggestionFile(); record(&f); try await store.save(f, revision: 2); try await store.save(SuggestionFile(), revision: 1); #expect(await store.load() == f) }
}
