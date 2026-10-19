import Testing
@testable import VoiceCore

struct ProjectMatcherTests {
    private func project(_ name: String, path: String = "/projects", enabled: Bool = true, missing: Bool = false, words: [String]) -> Project {
        Project(path: path + "/" + name, name: name, enabled: enabled, words: words.enumerated().map { ProjectWord(word: $0.element, rank: words.count - $0.offset) }, missing: missing)
    }

    @Test func nonCodingAppGetsNothing() {
        let focus = FocusSnapshot(bundleID: "com.google.Chrome", windowTitle: "BugVoice")
        let projects = [project("BugVoice", words: ["AppModel"])]
        #expect(ProjectMatcher.match(focus: focus, style: .personal, projects: projects, scope: .codingApps, excluding: []) == ProjectMatch(projectName: nil, words: []))
        #expect(!ProjectMatcher.match(focus: focus, style: .personal, projects: projects, scope: .allApps, excluding: []).words.isEmpty)
    }

    @Test func offGetsNothing() {
        let focus = FocusSnapshot(bundleID: "com.apple.Terminal", windowTitle: "BugVoice")
        #expect(ProjectMatcher.match(focus: focus, style: .terminal, projects: [project("BugVoice", words: ["AppModel"])], scope: .off, excluding: []).words.isEmpty)
    }

    @Test func disabledProjectsIgnored() {
        let focus = FocusSnapshot(bundleID: "com.apple.Terminal", windowTitle: "BugVoice")
        #expect(ProjectMatcher.match(focus: focus, style: .terminal, projects: [project("BugVoice", enabled: false, words: ["AppModel"])], scope: .allApps, excluding: []).words.isEmpty)
    }

    @Test func missingProjectsStillUsed() {
        let focus = FocusSnapshot(bundleID: "com.apple.Terminal", windowTitle: "BugVoice")
        let match = ProjectMatcher.match(focus: focus, style: .terminal, projects: [project("BugVoice", missing: true, words: ["AppModel"])], scope: .codingApps, excluding: [])
        #expect(match.projectName == "BugVoice")
        #expect(match.words == ["AppModel"])
    }

    @Test func titleMatchesWholeWord() {
        let project = self.project("BugVoice", words: ["AppModel"])
        let good = FocusSnapshot(bundleID: "com.apple.Terminal", windowTitle: "AppModel.swift — BugVoice")
        let bad = FocusSnapshot(bundleID: "com.apple.Terminal", windowTitle: "BugVoiceExtras")
        #expect(ProjectMatcher.match(focus: good, style: .terminal, projects: [project], scope: .codingApps, excluding: []).projectName == "BugVoice")
        #expect(ProjectMatcher.match(focus: bad, style: .terminal, projects: [project], scope: .codingApps, excluding: []).projectName == nil)
    }

    @Test func pathMatches() {
        let focus = FocusSnapshot(bundleID: "com.apple.Terminal", windowTitle: "~/Kael/19-AppBuild/BugVoice")
        let project = self.project("BugVoice", path: "/Users/me/Kael/19-AppBuild", words: ["AppModel"])
        #expect(ProjectMatcher.match(focus: focus, style: .terminal, projects: [project], scope: .codingApps, excluding: []).projectName == "BugVoice")
    }

    @Test func longestWholeWordWins() {
        let focus = FocusSnapshot(bundleID: "com.apple.Terminal", windowTitle: "BugVoice-old — main.swift")
        let projects = [project("BugVoice", words: ["BugWord"]), project("BugVoice-old", words: ["OldWord"])]
        #expect(ProjectMatcher.match(focus: focus, style: .terminal, projects: projects, scope: .codingApps, excluding: []).projectName == "BugVoice-old")
    }

    @Test func noMatchInterleaves() {
        let focus = FocusSnapshot(bundleID: "com.apple.Terminal", windowTitle: "unrelated")
        let projects = [project("A", words: ["a1", "a2", "a3"]), project("B", words: ["b1", "b2"])]
        let match = ProjectMatcher.match(focus: focus, style: .terminal, projects: projects, scope: .codingApps, excluding: [], limit: 4)
        #expect(match.projectName == nil)
        #expect(match.words == ["a1", "b1", "a2", "b2"])
    }

    @Test func dictionaryWordsNotRepeated() {
        let focus = FocusSnapshot(bundleID: "com.apple.Terminal", windowTitle: "BugVoice")
        let project = self.project("BugVoice", words: ["AppModel", "HistoryEntry", "FocusInspector"])
        let match = ProjectMatcher.match(focus: focus, style: .terminal, projects: [project], scope: .codingApps, excluding: ["AppModel"], limit: 2)
        #expect(match.words == ["HistoryEntry", "FocusInspector"])
    }

    @Test func limitApplied() {
        let focus = FocusSnapshot(bundleID: "com.apple.Terminal", windowTitle: "unrelated")
        let words = (0..<400).map { "W\($0)" }
        let match = ProjectMatcher.match(focus: focus, style: .terminal, projects: [project("BugVoice", words: words)], scope: .codingApps, excluding: [])
        #expect(match.words.count == 150)
    }
    @Test func prioritizedMovesHeardWordsFirst() {
        let words = ["AppModel", "HistoryEntry", "replaceLast", "DictationController", "build-app.sh"]
        #expect(ProjectMatcher.prioritized(words, heard: "Open app model and check Replace last.")
            == ["AppModel", "replaceLast", "HistoryEntry", "DictationController", "build-app.sh"])
        #expect(ProjectMatcher.prioritized(words, heard: "run build app sh").first == "build-app.sh")
        #expect(ProjectMatcher.prioritized(words, heard: "the dictationcontroller").first == "DictationController")
        #expect(ProjectMatcher.prioritized(words, heard: "app models", limit: 2) == ["AppModel", "HistoryEntry"])
    }

    @Test func spokenForm() {
        #expect(ProjectWordExtractor.spokenForm("DictationController") == "dictation controller")
        #expect(ProjectWordExtractor.spokenForm("max_tokens") == "max tokens")
        #expect(ProjectWordExtractor.spokenForm("build-app.sh") == "build app sh")
        #expect(ProjectWordExtractor.spokenForm("URLSession") == "url session")
    }
}
