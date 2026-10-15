import Foundation
import Testing
@testable import VoiceCore

struct DictionaryFileTests {
    @Test func addWordsSplitsOnCommasTrimsAndPutsNewestFirst() {
        var f = DictionaryFile()
        f.addWords("Kael")
        let added = f.addWords(" OpenWhispr ,Supabase,, ")
        #expect(added == 2)
        #expect(f.words.map(\.word) == ["OpenWhispr", "Supabase", "Kael"])
    }

    @Test func addWordsSkipsCaseInsensitiveDuplicates() {
        var f = DictionaryFile()
        f.addWords("BugVoice")
        let added = f.addWords("bugvoice, BUGVOICE, WhisperKit, whisperkit")
        #expect(added == 1)
        #expect(f.words.map(\.word) == ["WhisperKit", "BugVoice"])
    }

    @Test func heardAsAddsTrimmedUniqueFormsAndDropsTheWordItself() {
        var f = DictionaryFile()
        f.addWords("OpenWhispr")
        let id = f.words[0].id
        f.addHeardAs("open whisper, Open Whisper, openwhispr, , open whispers ", to: id)
        #expect(f.words[0].heardAs == ["open whisper", "open whispers"])
    }

    @Test func removeHeardAsIsCaseInsensitive() {
        var f = DictionaryFile()
        f.addWords("OpenWhispr")
        let id = f.words[0].id
        f.addHeardAs("open whisper, open whispers", to: id)
        f.removeHeardAs("Open Whisper", from: id)
        #expect(f.words[0].heardAs == ["open whispers"])
    }

    @Test func renameKeepsIdDropsMatchingHeardAsAndRejectsEmptyOrDuplicate() {
        var f = DictionaryFile()
        f.addWords("Kael, Open Whisper")
        let id = f.words[1].id
        f.addHeardAs("openwhispr, open whisper app", to: id)
        let renamed = f.renameWord(id, to: " OpenWhispr ")
        #expect(renamed)
        #expect(f.words[1].id == id)
        #expect(f.words[1].word == "OpenWhispr")
        #expect(f.words[1].heardAs == ["open whisper app"])
        let emptyRename = f.renameWord(id, to: "  ")
        let duplicateRename = f.renameWord(id, to: "kael")
        #expect(!emptyRename)
        #expect(!duplicateRename)
        #expect(f.words[1].word == "OpenWhispr")
    }

    @Test func deleteWord() {
        var f = DictionaryFile()
        f.addWords("Kael, BugVoice")
        f.deleteWord(f.words[0].id)
        #expect(f.words.map(\.word) == ["BugVoice"])
    }

    @Test func addSnippetTrimsEndsKeepsInnerLineBreaksNewestFirst() throws {
        var f = DictionaryFile()
        try f.addSnippet(trigger: " sign off ", text: "\n Best,\nKael \n")
        try f.addSnippet(trigger: "my linkedin", text: "linkedin.com/in/kael")
        #expect(f.snippets.map(\.trigger) == ["my linkedin", "sign off"])
        #expect(f.snippets[1].text == "Best,\nKael")
    }

    @Test func duplicateTriggerIsRejected() throws {
        var f = DictionaryFile()
        try f.addSnippet(trigger: "my linkedin", text: "a")
        #expect(throws: DictionaryError.duplicateTrigger) {
            try f.addSnippet(trigger: "My LinkedIn", text: "b")
        }
        #expect(f.snippets.count == 1)
        #expect(DictionaryError.duplicateTrigger.localizedDescription == "A snippet with this trigger already exists.")
    }

    @Test func emptyTriggerOrTextIsRejected() {
        var f = DictionaryFile()
        #expect(throws: DictionaryError.emptyTrigger) { try f.addSnippet(trigger: " ", text: "a") }
        #expect(throws: DictionaryError.emptyText) { try f.addSnippet(trigger: "a", text: " \n ") }
        #expect(f.snippets.isEmpty)
    }

    @Test func updateSnippetChecksOtherTriggersOnly() throws {
        var f = DictionaryFile()
        let a = try f.addSnippet(trigger: "cal link", text: "cal.com/kael")
        try f.addSnippet(trigger: "my linkedin", text: "linkedin.com/in/kael")
        try f.updateSnippet(a.id, trigger: "Cal Link", text: "cal.com/kael/30")
        #expect(f.snippets[1].trigger == "Cal Link")
        #expect(f.snippets[1].text == "cal.com/kael/30")
        #expect(throws: DictionaryError.duplicateTrigger) {
            try f.updateSnippet(a.id, trigger: "my linkedin", text: "x")
        }
    }

    @Test func deleteSnippet() throws {
        var f = DictionaryFile()
        let a = try f.addSnippet(trigger: "cal link", text: "cal.com/kael")
        f.deleteSnippet(a.id)
        #expect(f.snippets.isEmpty)
    }

    @Test func decodingSkipsBadEntriesAndFillsDefaults() throws {
        let json = #"{"words":[{"word":"Kael"},{"heardAs":["x"]},{"id":"6F1C2E4A-0000-0000-0000-000000000001","word":"BugVoice","heardAs":["bug voice"]}],"snippets":[{"trigger":"cal","text":"cal.com/kael"},{"trigger":"x"}]}"#
        let f = try JSONDecoder().decode(DictionaryFile.self, from: Data(json.utf8))
        #expect(f.schemaVersion == 1)
        #expect(f.words.map(\.word) == ["Kael", "BugVoice"])
        #expect(f.words[1].heardAs == ["bug voice"])
        #expect(f.words[0].heardAs.isEmpty)
        #expect(f.snippets.map(\.trigger) == ["cal"])
    }

    @Test func migratingVocabularyKeepsLaterLinesNewest() {
        let v = Vocabulary.parse("BugVoice\nWhisperKit\nbugvoice\nmy linkedin => linkedin.com/in/kael\nsign off => Best,\\nKael\nempty =>\n")
        let f = DictionaryFile(migrating: v)
        #expect(f.words.map(\.word) == ["WhisperKit", "BugVoice"])
        #expect(f.snippets.map(\.trigger) == ["sign off", "my linkedin"])
        #expect(f.snippets[0].text == "Best,\nKael")
    }
}
