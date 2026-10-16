import Foundation
import Testing
@testable import VoiceCore

struct MeetingDetectorTests {
    private let t0 = Date(timeIntervalSince1970: 1_000)
    private func chrome(_ title: String, input: Bool = true, pid: Int32 = 20) -> AudioInputProcess {
        AudioInputProcess(pid: pid, bundleID: "com.google.Chrome.helper", isRunningInput: input, windowTitles: [title])
    }
    private func zoom(input: Bool = true) -> AudioInputProcess {
        AudioInputProcess(pid: 30, bundleID: "us.zoom.xos", isRunningInput: input)
    }

    @Test func meetingAppUsingTheMicrophoneIsDetected() {
        var detector = MeetingDetector(ownPID: 1)
        let events = detector.update(processes: [zoom()], now: t0, isRecording: false, recordingApp: nil, muted: [])
        #expect(events == [.detected(MeetingCandidate(bundleID: "us.zoom.xos", appName: "Zoom", title: "Zoom"))])
    }

    @Test func browserCountsOnlyWithAMeetingTitle() {
        var detector = MeetingDetector(ownPID: 1)
        #expect(detector.update(processes: [chrome("YouTube - Google Chrome")], now: t0, isRecording: false, recordingApp: nil, muted: []).isEmpty)
        let events = detector.update(
            processes: [chrome("Meet - Helpdesk bot sync - Google Chrome")], now: t0, isRecording: false, recordingApp: nil, muted: []
        )
        #expect(events == [.detected(MeetingCandidate(bundleID: "com.google.Chrome", appName: "Google Meet", title: "Helpdesk bot sync"))])
    }

    @Test func teamsAndZoomWebTitlesCount() {
        #expect(MeetingDetector.webMeetingService(windowTitle: "Chat | Microsoft Teams") == "Microsoft Teams")
        #expect(MeetingDetector.webMeetingService(windowTitle: "Zoom Meeting - Safari") == "Zoom")
        #expect(MeetingDetector.webMeetingService(windowTitle: "Meet: abc-defg-hij") == "Google Meet")
        #expect(MeetingDetector.webMeetingService(windowTitle: "Meeting notes - Google Docs") == nil)
    }

    @Test func helperBundleIDsMapToTheirApp() {
        #expect(MeetingDetector.appBundleID(for: "com.google.Chrome.helper") == "com.google.Chrome")
        #expect(MeetingDetector.appBundleID(for: "us.zoom.xos") == "us.zoom.xos")
        #expect(MeetingDetector.appBundleID(for: "com.google.Chromecast") == nil)
        #expect(MeetingDetector.appBundleID(for: "com.apple.Music") == nil)
        #expect(MeetingDetector.appBundleID(for: "com.apple.WebKit.GPU") == "com.apple.Safari")
    }

    @Test func ownProcessIsIgnored() {
        var detector = MeetingDetector(ownPID: 30)
        #expect(detector.update(processes: [zoom()], now: t0, isRecording: false, recordingApp: nil, muted: []).isEmpty)
    }

    @Test func mutedAppsAreIgnored() {
        var detector = MeetingDetector(ownPID: 1)
        #expect(detector.update(processes: [zoom()], now: t0, isRecording: false, recordingApp: nil, muted: ["us.zoom.xos"]).isEmpty)
    }

    @Test func noOfferWhileRecordingOrRightAfterStop() {
        var detector = MeetingDetector(ownPID: 1)
        #expect(detector.update(processes: [zoom()], now: t0, isRecording: true, recordingApp: nil, muted: []).isEmpty)
        #expect(detector.update(processes: [zoom()], now: t0.addingTimeInterval(5), isRecording: false, recordingApp: nil, muted: []).isEmpty)
    }

    @Test func oneOfferForTwoAppsAndNoRepeatUntilInputRestarts() {
        var detector = MeetingDetector(ownPID: 1)
        let first = detector.update(processes: [zoom(), chrome("Meet - Sync")], now: t0, isRecording: false, recordingApp: nil, muted: [])
        #expect(first.count == 1)
        #expect(detector.update(processes: [zoom()], now: t0.addingTimeInterval(1), isRecording: false, recordingApp: nil, muted: []).isEmpty)
        #expect(detector.update(processes: [zoom(input: false)], now: t0.addingTimeInterval(2), isRecording: false, recordingApp: nil, muted: []).isEmpty)
        let again = detector.update(processes: [zoom()], now: t0.addingTimeInterval(3), isRecording: false, recordingApp: nil, muted: [])
        #expect(again.count == 1)
    }

    @Test func endedFiresOnceAfterTenQuietSecondsForTheRecordedApp() {
        var detector = MeetingDetector(ownPID: 1)
        _ = detector.update(processes: [zoom()], now: t0, isRecording: true, recordingApp: "us.zoom.xos", muted: [])
        #expect(detector.update(processes: [zoom(input: false)], now: t0.addingTimeInterval(1), isRecording: true, recordingApp: "us.zoom.xos", muted: []).isEmpty)
        #expect(detector.update(processes: [], now: t0.addingTimeInterval(10.5), isRecording: true, recordingApp: "us.zoom.xos", muted: []).isEmpty)
        #expect(detector.update(processes: [], now: t0.addingTimeInterval(11), isRecording: true, recordingApp: "us.zoom.xos", muted: []) == [.ended(bundleID: "us.zoom.xos")])
        #expect(detector.update(processes: [], now: t0.addingTimeInterval(20), isRecording: true, recordingApp: "us.zoom.xos", muted: []).isEmpty)
    }

    @Test func endedWaitsWhenTheAppComesBack() {
        var detector = MeetingDetector(ownPID: 1)
        _ = detector.update(processes: [], now: t0, isRecording: true, recordingApp: "us.zoom.xos", muted: [])
        _ = detector.update(processes: [zoom()], now: t0.addingTimeInterval(8), isRecording: true, recordingApp: "us.zoom.xos", muted: [])
        #expect(detector.update(processes: [], now: t0.addingTimeInterval(12), isRecording: true, recordingApp: "us.zoom.xos", muted: []).isEmpty)
    }

    @Test func otherAppsNeverEndARecording() {
        var detector = MeetingDetector(ownPID: 1)
        #expect(detector.update(processes: [], now: t0.addingTimeInterval(60), isRecording: true, recordingApp: nil, muted: []).isEmpty)
    }

    @Test func windowTitleCleanup() {
        #expect(MeetingDetector.meetingTitle(fromWindowTitle: "Meet - Helpdesk bot sync - Google Chrome") == "Helpdesk bot sync")
        #expect(MeetingDetector.meetingTitle(fromWindowTitle: "Meet – abc-defg-hij - Camera or microphone recording - Google Chrome") == "abc-defg-hij")
        #expect(MeetingDetector.meetingTitle(fromWindowTitle: "Meet: Weekly sync") == "Weekly sync")
        #expect(MeetingDetector.meetingTitle(fromWindowTitle: "Microsoft Teams") == nil)
    }
}
