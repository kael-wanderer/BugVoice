import Foundation
import Testing

@testable import VoiceCore

struct UploadRecoveryPlanTests {
  @Test func sourceSplitsStagingCommittedAndReadyInStableOrder() {
    let date = Date(timeIntervalSince1970: 1)
    let staging = MeetingManifest(
      id: MeetingID(rawValue: "stage"), startedAt: date, state: .interrupted, source: .upload)
    let b = MeetingManifest(
      id: MeetingID(rawValue: "b"), startedAt: date, state: .transcribing, source: .upload)
    let a = MeetingManifest(
      id: MeetingID(rawValue: "a"), startedAt: date, state: .transcribing, source: .upload)
    let ready = MeetingManifest(
      id: MeetingID(rawValue: "ready"), startedAt: date, state: .ready, source: .upload)
    let recording = MeetingManifest(
      id: MeetingID(rawValue: "recording"), startedAt: date, state: .interrupted)
    let plan = UploadRecoveryPlan([b, recording, ready, staging, a])
    #expect(plan.discard == [staging.id])
    #expect(plan.resume.map(\.id) == [a.id, b.id])
    #expect(plan.ready.map(\.id) == [ready.id])
    #expect(MeetingRecoveryPolicy.action(for: recording) == .recoverCapture)
    #expect(MeetingRecoveryPolicy.action(for: staging) == nil)
    #expect(MeetingRecoveryPolicy.action(for: a) == .retryTranscription)
  }

  @Test func uploadSearchAndGroupingUseMediaTime() {
    let date = Date(timeIntervalSince1970: 1_704_067_200)
    var meeting = MeetingManifest(
      title: "Original review", startedAt: date, state: .ready, source: .upload, importedAt: Date())
    meeting.segments = [MeetingSegment(start: 0, end: 1, text: "Searchable words", track: .file)]
    #expect(MeetingListProjection.matches(meeting, query: "original"))
    #expect(MeetingListProjection.matches(meeting, query: "searchable"))
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let groups = MeetingListProjection.groups(meetings: [meeting], now: Date(), calendar: calendar)
    #expect(groups.first?.day == calendar.startOfDay(for: date))
  }
}
