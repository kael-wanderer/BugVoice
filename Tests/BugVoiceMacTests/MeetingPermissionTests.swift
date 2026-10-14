import Testing
@testable import BugVoiceMac

struct MeetingPermissionTests {
    @Test func systemAudioPermissionHasNoPreflightAndDoesNotBlockDictation() {
        #expect(!Permissions.isGranted(.systemAudioRecording))
        #expect(!Permissions.requiredForDictation.contains(.systemAudioRecording))
        #expect(Permissions.requiredForDictation.count == 3)
    }
}
