import Testing
@testable import VoiceCore

struct ProjectWordExtractorTests {
    @Test func codeShaped() {
        for token in ["AppModel", "replaceLast", "max_tokens", "API_KEY", "uncleanedText"] {
            #expect(ProjectWordExtractor.isCodeShaped(token))
        }
        for token in ["model", "Model", "API", "test", "deadbeef12", "a1b2c3d4e5", "x123456"] {
            #expect(!ProjectWordExtractor.isCodeShaped(token))
        }
    }

    @Test func fileNames() {
        #expect(ProjectWordExtractor.fileNameWords(path: "Sources/BugVoice/AppModel+Models.swift") == ["AppModel"])
        #expect(ProjectWordExtractor.fileNameWords(path: "Sources/BugVoice/AppModel+ProjectWords.swift") == ["AppModel", "ProjectWords"])
        #expect(ProjectWordExtractor.fileNameWords(path: "Scripts/build-app.sh") == ["build-app.sh"])
        #expect(ProjectWordExtractor.fileNameWords(path: "README.md").isEmpty)
        #expect(ProjectWordExtractor.fileNameWords(path: "docs/HANDOFF.md").isEmpty)
    }

    @Test func identifiersFromSwift() {
        let contents = "final class DictationController {\n func replaceLast(_ x: Int) { let model = AppModel() } }"
        #expect(Set(ProjectWordExtractor.identifiers(in: contents)) == ["DictationController", "replaceLast", "AppModel"])
    }

    @Test func declaredNames() {
        let swift = "final class DictationController {\n func replaceLast(_ x: Int) { let model = AppModel() } }"
        #expect(ProjectWordExtractor.declared(in: swift) == ["DictationController", "replaceLast"])
        #expect(ProjectWordExtractor.declared(in: "def load_settings():\nclass HistoryLog:") == ["load_settings", "HistoryLog"])
    }

    @Test func secretFilesSkipped() {
        for path in [".env", "config/.env.local", "certs/server.pem", "keys/id.key", "aws_credentials.py", "my_secret_store.ts", "notes.md"] {
            #expect(!ProjectWordExtractor.shouldRead(path: path))
        }
        #expect(ProjectWordExtractor.shouldRead(path: "Sources/App.swift"))
    }

    @Test func rankCountsFilesAndBoostsDeclared() {
        let baseFiles = [
            ProjectSourceFile(path: "A.swift", contents: "class AppModel { let item = HistoryEntry(); let again = AppModel() }"),
            ProjectSourceFile(path: "B.swift", contents: "let model = AppModel()"),
            ProjectSourceFile(path: "HistoryEntry.swift", contents: ""),
        ]
        let ranked = ProjectWordExtractor.extract(files: baseFiles, hidden: [])
        let ranks = Dictionary(uniqueKeysWithValues: ranked.map { ($0.word, $0.rank) })
        #expect(ranks["AppModel"] == 7)
        #expect(ranks["HistoryEntry"] == 7)
        #expect(ranked.firstIndex(where: { $0.word == "AppModel" })! < ranked.firstIndex(where: { $0.word == "HistoryEntry" })!)
        let withD = ProjectWordExtractor.extract(files: baseFiles + [ProjectSourceFile(path: "D.swift", contents: "let one = HistoryEntry(); let two = HistoryEntry(); let three = HistoryEntry()")], hidden: [])
        #expect(withD.first(where: { $0.word == "HistoryEntry" })?.rank == 8)
    }

    @Test func tiesAlphabetical() {
        let words = ProjectWordExtractor.extract(files: [
            ProjectSourceFile(path: "A.swift", contents: "let first = BetaWord(); let second = AlphaWord()")
        ], hidden: [])
        #expect(words.map(\.word) == ["AlphaWord", "BetaWord"])
    }

    @Test func hiddenDropped() {
        let words = ProjectWordExtractor.extract(files: [ProjectSourceFile(path: "A.swift", contents: "class AppModel {}")], hidden: ["AppModel"])
        #expect(!words.contains(where: { $0.word == "AppModel" }))
    }

    @Test func capsAtMaxWords() {
        let names = (0..<1_200).map { "Type\($0)Model" }
        let contents = names.map { "let item = \($0)()" }.joined(separator: "\n")
        let words = ProjectWordExtractor.extract(files: [ProjectSourceFile(path: "A.swift", contents: contents)], hidden: [])
        #expect(words.count == ProjectWordExtractor.maxWords)
    }
    @Test func projectNamesBeforeLibraryNames() {
        var files = [ProjectSourceFile(path: "A.swift", contents: "final class AppModel {}")]
        for n in 0..<10 { files.append(ProjectSourceFile(path: "U\(n).swift", contents: "if items.isEmpty {}")) }
        let words = ProjectWordExtractor.extract(files: files, hidden: [])
        #expect(words.map(\.word) == ["AppModel", "isEmpty"])
        #expect(words.first?.rank == 6)
        #expect(words.last?.rank == 10)
    }
}
