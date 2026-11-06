import Foundation
import Testing
@testable import VoiceCore

@Suite struct BuiltInChoicesTests {
    private let small = BuiltInCatalog.models[0]
    private let medium = BuiltInCatalog.models[1]
    private let large = BuiltInCatalog.models[2]

    // MARK: Picker entries

    @Test func pickerLabelNamesTheModel() {
        #expect(BuiltInChoices.pickerLabel(medium) == "Built-in · Medium")
    }

    @Test func dictationListsInstalledModelsInCatalogOrder() {
        let models = BuiltInChoices.dictationChoices(installed: [large.id, small.id])
        #expect(models == [small, large])
        #expect(BuiltInChoices.dictationChoices(installed: []).isEmpty)
    }

    @Test func dictationIgnoresUnknownIDs() {
        #expect(BuiltInChoices.dictationChoices(installed: ["gone-model"]).isEmpty)
    }

    @Test func notesListsOnlyDictationsBuiltInModel() {
        let installed: Set = [small.id, medium.id, large.id]
        #expect(BuiltInChoices.notesChoices(dictation: .builtIn(medium.id), installed: installed) == [medium])
    }

    @Test func notesListsNoBuiltInWhenDictationUsesAnotherEngine() {
        let installed: Set = [small.id, medium.id]
        #expect(BuiltInChoices.notesChoices(dictation: .appleIntelligence, installed: installed).isEmpty)
        #expect(BuiltInChoices.notesChoices(dictation: .none, installed: installed).isEmpty)
    }

    @Test func notesListsNothingWhenDictationsModelIsNotInstalled() {
        #expect(BuiltInChoices.notesChoices(dictation: .builtIn(medium.id), installed: [small.id]).isEmpty)
    }

    // MARK: State and readiness

    @Test func stateIsReadyWhenInstalled() {
        let state = BuiltInChoices.state(of: medium.id, installed: [medium.id], downloads: [medium.id: 0.4], failures: [:])
        #expect(state == .ready)
    }

    @Test func stateIsDownloadingWithTheFraction() {
        let state = BuiltInChoices.state(of: medium.id, installed: [], downloads: [medium.id: 0.41], failures: [medium.id: "x"])
        #expect(state == .downloading(0.41))
    }

    @Test func stateIsFailedWithTheMessage() {
        let state = BuiltInChoices.state(of: medium.id, installed: [], downloads: [:], failures: [medium.id: "The download was damaged. Try again."])
        #expect(state == .failed("The download was damaged. Try again."))
    }

    @Test func installedWithALoadFailureIsFailed() {
        let state = BuiltInChoices.state(of: medium.id, installed: [medium.id], downloads: [:], failures: [:],
                                         loadFailures: [medium.id: "The built-in model did not start."])
        #expect(state == .failed("The built-in model did not start."))
    }

    @Test func aLoadFailureOfAnotherModelDoesNotCount() {
        let state = BuiltInChoices.state(of: medium.id, installed: [medium.id], downloads: [:], failures: [:],
                                         loadFailures: [small.id: "x"])
        #expect(state == .ready)
    }

    @Test func readinessShowsTheLoadFailureWithOpenModels() {
        let check = BuiltInChoices.readinessCheck(
            dictation: .builtIn(medium.id), installed: [medium.id], downloads: [:], failures: [:],
            loadFailures: [medium.id: "The built-in model did not start."])
        #expect(check == .builtIn(name: "Medium", state: .failed("The built-in model did not start.")))
        let row = Readiness.cleanupRow(check!)
        #expect(row.tone == .problem)
        #expect(row.action == .openModels)
    }

    @Test func loadFailureMessageKeepsPlainReasons() {
        #expect(BuiltInChoices.loadFailureMessage(ProviderError.unavailable("Small is not downloaded. Download it in Settings → Models."))
            == "Small is not downloaded. Download it in Settings → Models.")
    }

    @Test func loadFailureMessageHidesOtherDetail() {
        struct Odd: Error {}
        #expect(BuiltInChoices.loadFailureMessage(Odd()) == "The built-in model did not start.")
        #expect(BuiltInChoices.loadFailureMessage(ProviderError.http(status: 500, body: "/Users/x/model.gguf")) == "The built-in model did not start.")
    }

    @Test func loadFailureMessageIgnoresCancellation() {
        #expect(BuiltInChoices.loadFailureMessage(CancellationError()) == nil)
    }

    @Test func checkingTheFileAtFullProgress() {
        #expect(BuiltInChoices.isChecking(1))
        #expect(!BuiltInChoices.isChecking(0.999))
    }

    @Test func stateIsNotDownloadedOtherwise() {
        #expect(BuiltInChoices.state(of: medium.id, installed: [small.id], downloads: [small.id: 0.2], failures: [:]) == .notDownloaded)
    }

    @Test func readinessUsesTheModelNameAndState() {
        let check = BuiltInChoices.readinessCheck(
            dictation: .builtIn(medium.id), installed: [], downloads: [medium.id: 0.5], failures: [:])
        #expect(check == .builtIn(name: "Medium", state: .downloading(0.5)))
        let row = Readiness.cleanupRow(BuiltInChoices.readinessCheck(
            dictation: .builtIn(medium.id), installed: [medium.id], downloads: [:], failures: [:])!)
        #expect(row.detail == "Medium, built in")
        #expect(row.tone == .ok)
    }

    @Test func readinessOffersDownloadWhenNotDownloaded() {
        let check = BuiltInChoices.readinessCheck(dictation: .builtIn(small.id), installed: [], downloads: [:], failures: [:])
        #expect(check == .builtIn(name: "Small", state: .notDownloaded))
        #expect(Readiness.cleanupRow(check!).action == .downloadBuiltIn)
    }

    @Test func readinessIsNilForOtherEnginesAndUnknownModels() {
        #expect(BuiltInChoices.readinessCheck(dictation: .appleIntelligence, installed: [], downloads: [:], failures: [:]) == nil)
        #expect(BuiltInChoices.readinessCheck(dictation: .builtIn("gone-model"), installed: [], downloads: [:], failures: [:]) == nil)
    }

    // MARK: Choosing and deleting

    @Test func choosingForDictationClearsANotesBuiltInThatNoLongerMatches() {
        var models = ModelSettings()
        models.dictation = ModelUse(engine: .builtIn(small.id), disableThinking: true)
        models.notes = ModelUse(engine: .builtIn(small.id), disableThinking: true)
        BuiltInChoices.chooseForDictation(.builtIn(medium.id), in: &models)
        #expect(models.dictation.engine == .builtIn(medium.id))
        #expect(models.notes == nil)
    }

    @Test func choosingForDictationKeepsOtherNotesEngines() {
        var models = ModelSettings()
        models.notes = ModelUse(engine: .appleIntelligence)
        BuiltInChoices.chooseForDictation(.builtIn(medium.id), in: &models)
        #expect(models.notes?.engine == .appleIntelligence)
        BuiltInChoices.chooseForDictation(.none, in: &models)
        #expect(models.dictation.engine == ModelEngine.none)
    }

    @Test func choosingANonBuiltInClearsANotesBuiltIn() {
        var models = ModelSettings()
        models.dictation = ModelUse(engine: .builtIn(small.id), disableThinking: true)
        models.notes = ModelUse(engine: .builtIn(small.id), disableThinking: true)
        BuiltInChoices.chooseForDictation(.appleIntelligence, in: &models)
        #expect(models.notes == nil)
    }

    @Test func choosingABuiltInTurnsThinkingOff() {
        var models = ModelSettings()
        models.dictation = ModelUse(engine: .appleIntelligence, disableThinking: false)
        BuiltInChoices.chooseForDictation(.builtIn(small.id), in: &models)
        #expect(models.dictation.disableThinking)
    }

    @Test func inUseMeansDictationOrNotes() {
        var models = ModelSettings()
        #expect(!BuiltInChoices.isInUse(small.id, models: models))
        models.dictation = ModelUse(engine: .builtIn(small.id))
        #expect(BuiltInChoices.isInUse(small.id, models: models))
        #expect(!BuiltInChoices.isInUse(medium.id, models: models))
    }

    @Test func forgettingTheDictationModelTurnsCleanupOff() {
        var models = ModelSettings()
        models.dictation = ModelUse(engine: .builtIn(small.id), disableThinking: true)
        models.notes = ModelUse(engine: .builtIn(small.id), disableThinking: true)
        BuiltInChoices.forget(small.id, in: &models)
        #expect(models.dictation.engine == ModelEngine.none)
        #expect(models.notes == nil)
    }

    @Test func forgettingAnotherModelChangesNothing() {
        var models = ModelSettings()
        models.dictation = ModelUse(engine: .builtIn(small.id), disableThinking: true)
        let before = models
        BuiltInChoices.forget(medium.id, in: &models)
        #expect(models == before)
    }

    @Test func deleteConfirmationText() {
        #expect(BuiltInChoices.deleteQuestion(medium) == "Delete Medium? Dictation cleanup turns off until you choose another model.")
    }

    // MARK: Text

    @Test func sizesUseOneDecimalGB() {
        #expect(BuiltInChoices.gigabytes(2_497_280_256) == "2.5 GB")
        #expect(BuiltInChoices.gigabytes(5_027_783_488) == "5.0 GB")
        #expect(BuiltInChoices.gigabytes(1_107_409_952) == "1.1 GB")
    }

    @Test func downloadButtonTitle() {
        #expect(BuiltInChoices.downloadTitle(medium) == "Download 2.5 GB")
    }

    @Test func progressText() {
        #expect(BuiltInChoices.progress(0.64, of: medium) == "1.6 of 2.5 GB")
    }

    @Test func timeLeftInSecondsThenMinutes() {
        // 10% done in 4 s from zero: 36 s left.
        #expect(BuiltInChoices.timeLeft(fraction: 0.1, startFraction: 0, elapsed: 4) == "About 36 seconds left.")
        // 10% done in 20 s: 180 s left.
        #expect(BuiltInChoices.timeLeft(fraction: 0.1, startFraction: 0, elapsed: 20) == "About 3 minutes left.")
        #expect(BuiltInChoices.timeLeft(fraction: 0.5, startFraction: 0, elapsed: 61) == "About 1 minute left.")
    }

    @Test func timeLeftIsNilBeforeAnyProgressOrTooEarly() {
        #expect(BuiltInChoices.timeLeft(fraction: 0.3, startFraction: 0.3, elapsed: 10) == nil)
        #expect(BuiltInChoices.timeLeft(fraction: 0.01, startFraction: 0, elapsed: 0.5) == nil)
    }

    @Test func timeLeftCountsOnlyThisSessionsProgress() {
        // Resumed at 50%, now 60% after 10 s: 40 s left.
        #expect(BuiltInChoices.timeLeft(fraction: 0.6, startFraction: 0.5, elapsed: 10) == "About 40 seconds left.")
    }

    @Test func memoryLine() {
        #expect(BuiltInChoices.memoryLine(physicalMemory: 17_179_869_184) == "Bigger models clean better and take longer. This Mac has 16 GB of memory.")
    }

    @Test func selfTestSentenceIsFixed() {
        #expect(BuiltInChoices.testSentence == "um so tomorrow mình họp lúc ba giờ nha, uh, with the design team")
    }
}
