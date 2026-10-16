import Foundation
import VoiceCore

/// English under non-English transcript lines, through the Meetings model.
extension MeetingController {
    /// The Transcript tab offers Show English for this meeting.
    var offersEnglish: Bool {
        MeetingTranslation.isOffered(languages) || segments.contains { !($0.translation ?? "").isEmpty }
    }

    /// Ticks once a second from Start until a new meeting starts, so lines
    /// still without English after Stop are translated too.
    func startTranslationLoop() {
        translationLoop?.cancel()
        translationRetryAt = nil
        translationNeedsModel = false
        translationLoop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.translateIfDue()
            }
        }
    }

    /// Sends the next batch of lines that need English, one request at a time.
    func translateIfDue() {
        guard translationTask == nil, !translationHeld, let session else { return }
        // Dictation, the live summary and the final summary go first on the same model.
        guard model.dictation?.isBusy != true, !model.isListening else { return }
        guard summaryTask == nil, summaryState != .finalizing else { return }
        if let retry = translationRetryAt, Date() < retry { return }
        translationTask = Task { [weak self] in
            guard let self else { return }
            defer { self.translationTask = nil }
            guard let meeting = await session.snapshot(),
                  [.recording, .paused, .ready].contains(meeting.state) else { return }
            let lines = MeetingTranslation.pending(in: meeting)
            guard !lines.isEmpty else { return }
            guard let textModel = await self.model.meetingTextModel() else {
                self.translationNeedsModel = true
                self.translationRetryAt = Date().addingTimeInterval(MeetingTranslation.retryDelay)
                return
            }
            self.translationNeedsModel = false
            let request = MeetingTranslation.request(lines: lines, budget: MeetingTextBudget(settings: self.model.settings.meetings))
            do {
                let english = MeetingTranslation.parse(try await textModel.clean(request), lines: lines)
                guard !english.isEmpty else {
                    self.translationRetryAt = Date().addingTimeInterval(MeetingTranslation.retryDelay)
                    return
                }
                try await session.setTranslations(english)
                self.translationRetryAt = nil
                if let saved = await session.snapshot() { self.showTranslations(from: saved) }
                if !self.isActive { await self.model.reloadMeetings() }
            } catch {
                self.translationRetryAt = Date().addingTimeInterval(MeetingTranslation.retryDelay)
            }
        }
    }

    /// Show English in the meeting window; saved on the meeting.
    func setShowEnglish(_ show: Bool) async {
        // A failed save leaves the switch as it was.
        guard let session, (try? await session.setShowEnglish(show)) != nil else { return }
        showEnglish = show
        translationRetryAt = nil
        if !isActive { await model.reloadMeetings() }
    }

    /// Show English from the detail page; false when the window's session does not own the meeting.
    func setShowEnglishInSession(id: MeetingID, show: Bool) async throws -> Bool {
        guard session != nil, await session?.snapshot()?.id == id else { return false }
        try await session?.setShowEnglish(show)
        if shownMeetingID == id { showEnglish = show }
        translationRetryAt = nil
        return true
    }
}
