import Foundation
import Testing
@testable import VoiceCore

struct UploadQueueTests {
    private func job() -> UploadJob {
        UploadJob(fileName: "a.mov", kind: .video, duration: 60, byteSize: 100)
    }

    @Test func fifoMeetingGateProgressAndStaleCallbacks() {
        let a = job()
        let b = job()
        var queue = UploadQueue()
        queue.append([a, b])
        #expect(queue.admit(meetingActive: true) == nil)
        #expect(queue.admit(meetingActive: false)?.id == a.id)
        #expect(queue.admit(meetingActive: false) == nil)
        queue.apply(id: a.id, event: .progress(2))
        #expect(queue.jobs[0].progress == 1)
        queue.apply(id: a.id, event: .committed(MeetingID(rawValue: "a")))
        #expect(queue.jobs[0].progress == 0)
        queue.apply(id: a.id, event: .progress(-1))
        #expect(queue.jobs[0].progress == 0)
        queue.apply(id: a.id, event: .failed("failure"))
        queue.apply(id: a.id, event: .ready)
        queue.apply(id: a.id, event: .progress(0.9))
        #expect(queue.jobs[0].state == .failed)
        #expect(queue.admit(meetingActive: true) == nil)
        #expect(queue.admit(meetingActive: false)?.id == b.id)
    }

    @Test func invalidTransitionsCancelEveryPhaseAndClearOnlyHistory() {
        for phase in [UploadJobState.queued, .reading, .transcribing] {
            var a = job()
            a.meetingID = MeetingID(rawValue: "kept")
            var queue = UploadQueue()
            queue.append([a])
            if phase != .queued {
                _ = queue.admit(meetingActive: false)
            }
            if phase == .transcribing {
                queue.apply(id: a.id, event: .committed(MeetingID(rawValue: "kept")))
            }
            queue.apply(id: a.id, event: .cancelled)
            queue.apply(id: a.id, event: .committed(MeetingID(rawValue: "late")))
            #expect(queue.jobs[0].state == .cancelled)
            queue.clearFinished()
            #expect(queue.jobs.isEmpty)
            #expect(a.meetingID == MeetingID(rawValue: "kept"))
        }
        var queue = UploadQueue()
        let waiting = job()
        queue.append([waiting])
        queue.apply(id: waiting.id, event: .ready)
        queue.apply(id: waiting.id, event: .progress(0.8))
        #expect(queue.jobs[0].state == .queued)
        #expect(queue.jobs[0].progress == nil)
        queue.clearFinished()
        #expect(queue.jobs.count == 1)
    }
}
