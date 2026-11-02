import Testing
@testable import VoiceCore

@Suite("FocusFingerprint")
struct FocusFingerprintTests {
    let field = FocusFingerprint(pid: 42, role: "AXTextField", subrole: nil, x: 100, y: 200, width: 300, height: 24)

    @Test func identicalReferenceIsSame() {
        #expect(FocusFingerprint.isSameTarget(identical: true, start: nil, now: nil))
    }

    // A browser or text view can hand back a new accessibility object for the same field.
    @Test func newReferenceSameFieldIsSame() {
        #expect(FocusFingerprint.isSameTarget(identical: false, start: field, now: field))
    }

    @Test func subPointFrameNoiseIsSame() {
        var now = field
        now.x += 0.4
        now.height -= 0.3
        #expect(FocusFingerprint.isSameTarget(identical: false, start: field, now: now))
    }

    @Test func otherFieldInSameAppDiffers() {
        var other = field
        other.y = 260
        #expect(!FocusFingerprint.isSameTarget(identical: false, start: field, now: other))
    }

    @Test func otherAppDiffers() {
        var other = field
        other.pid = 43
        #expect(!FocusFingerprint.isSameTarget(identical: false, start: field, now: other))
    }

    @Test func otherRoleDiffers() {
        var other = field
        other.role = "AXTextArea"
        #expect(!FocusFingerprint.isSameTarget(identical: false, start: field, now: other))
        var sub = field
        sub.subrole = "AXSearchField"
        #expect(!FocusFingerprint.isSameTarget(identical: false, start: field, now: sub))
    }

    // Without a role or a real frame there is nothing to compare: fail closed.
    @Test func missingRoleOrEmptyFrameDiffers() {
        var noRole = field
        noRole.role = nil
        #expect(!FocusFingerprint.isSameTarget(identical: false, start: noRole, now: noRole))
        var empty = field
        empty.width = 0
        #expect(!FocusFingerprint.isSameTarget(identical: false, start: empty, now: empty))
        #expect(!FocusFingerprint.isSameTarget(identical: false, start: nil, now: field))
        #expect(!FocusFingerprint.isSameTarget(identical: false, start: field, now: nil))
    }
}
