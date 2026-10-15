import Foundation
import Testing
@testable import VoiceCore

struct UploadChunkPlanTests {
    @Test func reuseRequiresStableIDFileTrackRangeAndSuccessfulState() {
        let range = 464_000..<944_000
        let id = UploadChunkPlan.id(for: range)
        var record = MeetingChunkRecord(id: id, track: .file, offset: 29, duration: 30, requestedLanguage: .auto, state: .complete)
        #expect(UploadChunkPlan.reusable([record], range: range) == record)
        record.state = .empty
        #expect(UploadChunkPlan.reusable([record], range: range) == record)
        record.state = .failed
        #expect(UploadChunkPlan.reusable([record], range: range) == nil)
        record.state = .complete
        record.track = .mic
        #expect(UploadChunkPlan.reusable([record], range: range) == nil)
        record.track = .file
        record.duration = 29
        #expect(UploadChunkPlan.reusable([record], range: range) == nil)
        record.duration = 30
        record.id = "different"
        #expect(UploadChunkPlan.reusable([record], range: range) == nil)
    }

    @Test func linksReadingAndReportsWaitingCleanupFailure() {
        var queue = UploadQueue()
        let job = UploadJob(fileName: "retry.mov", kind: .video, duration: 60, byteSize: 20)
        queue.append([job])
        queue.attach(id: job.id, meetingID: MeetingID(rawValue: "retained"))
        #expect(queue.jobs[0].meetingID == MeetingID(rawValue: "retained"))
        queue.apply(id: job.id, event: .cleanupFailed)
        #expect(queue.jobs[0].state == .failed)
        #expect(queue.jobs[0].errorMessage == "Could not remove the cancelled upload.")
        queue.apply(id: job.id, event: .progress(1))
        #expect(queue.jobs[0].state == .failed)
    }

    @Test func diskFullIncludesWrappedPOSIXAndCocoaErrors() {
        #expect(UploadFailure.isDiskFull(NSError(domain: NSPOSIXErrorDomain, code: 28)))
        #expect(UploadFailure.isDiskFull(CocoaError(.fileWriteOutOfSpace)))
        let wrapped = NSError(domain: "Writer", code: 1, userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: 28)])
        #expect(UploadFailure.isDiskFull(wrapped))
        #expect(!UploadFailure.isDiskFull(CocoaError(.fileReadNoSuchFile)))
    }
}
