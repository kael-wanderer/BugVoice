import Testing
@testable import VoiceCore

struct HoldGestureDetectorTests {
    @Test func holdStartsAfterThresholdAndStopsOnRelease() {
        var d = HoldGestureDetector()
        #expect(d.handle(.hotkeyDown(0)) == [])
        #expect(d.tick(now: 0.10) == [])
        #expect(d.tick(now: 0.16) == [.startHold])
        #expect(d.isRecording)
        #expect(d.handle(.hotkeyUp(2)) == [.stop])
        #expect(!d.isRecording)
    }

    @Test func otherKeyBeforeThresholdMeansModifierUseNoRecording() {
        var d = HoldGestureDetector()
        _ = d.handle(.hotkeyDown(0))
        #expect(d.handle(.otherKeyDown(0.05)) == [])
        #expect(d.tick(now: 0.5) == [])
        #expect(d.handle(.hotkeyUp(0.6)) == [])
        #expect(!d.isRecording)
    }

    @Test func otherKeyDuringHoldCancels() {
        var d = HoldGestureDetector()
        _ = d.handle(.hotkeyDown(0))
        _ = d.tick(now: 0.2)
        #expect(d.handle(.otherKeyDown(0.4)) == [.cancel])
        #expect(d.handle(.hotkeyUp(0.5)) == [])
    }

    @Test func doubleTapStartsHandsFreeAndNextTapStops() {
        var d = HoldGestureDetector()
        _ = d.handle(.hotkeyDown(0)); #expect(d.handle(.hotkeyUp(0.05)) == [])
        _ = d.handle(.hotkeyDown(0.20)); #expect(d.handle(.hotkeyUp(0.25)) == [.startHandsFree])
        #expect(d.isRecording)
        #expect(d.handle(.otherKeyDown(3)) == [])   // typing does not end hands-free
        _ = d.handle(.hotkeyDown(10))
        #expect(d.tick(now: 10.5) == [])            // a long press in hands-free is still a stop
        #expect(d.handle(.hotkeyUp(10.6)) == [.stop])
    }

    @Test func slowSecondTapIsNotDoubleTap() {
        var d = HoldGestureDetector()
        _ = d.handle(.hotkeyDown(0)); _ = d.handle(.hotkeyUp(0.05))
        _ = d.handle(.hotkeyDown(0.6)); #expect(d.handle(.hotkeyUp(0.65)) == [])
        #expect(!d.isRecording)
    }

    @Test func handsFreeDisabledIgnoresDoubleTap() {
        var d = HoldGestureDetector()
        d.handsFreeEnabled = false
        _ = d.handle(.hotkeyDown(0)); _ = d.handle(.hotkeyUp(0.05))
        _ = d.handle(.hotkeyDown(0.2)); #expect(d.handle(.hotkeyUp(0.25)) == [])
    }

    @Test func lateReleaseWithoutTickIsNeitherHoldNorTap() {
        var d = HoldGestureDetector()
        _ = d.handle(.hotkeyDown(0))
        #expect(d.handle(.hotkeyUp(0.4)) == [])
        _ = d.handle(.hotkeyDown(0.5)); #expect(d.handle(.hotkeyUp(0.55)) == [])
    }

    @Test func resetReturnsToIdle() {
        var d = HoldGestureDetector()
        _ = d.handle(.hotkeyDown(0)); _ = d.tick(now: 0.2)
        d.reset()
        #expect(!d.isRecording)
        #expect(d.handle(.hotkeyUp(0.3)) == [])
    }

    // Option used as a normal modifier (⌥E, ⌥⇧K, ⌃⌥V): Task 14 reports any other
    // key or modifier press as `.otherKeyDown`.

    @Test func otherKeyBeforeThresholdNeverStartsRecordingEvenIfHeldLong() {
        var d = HoldGestureDetector()
        _ = d.handle(.hotkeyDown(0))
        _ = d.handle(.otherKeyDown(0.05))
        for t in stride(from: 0.1, through: 30.0, by: 0.1) {
            #expect(d.tick(now: t) == [])
        }
        #expect(!d.isRecording)
        #expect(d.handle(.hotkeyUp(30)) == [])
        #expect(!d.isRecording)
    }

    @Test func multipleOtherKeysBeforeThresholdStillNoRecording() {
        var d = HoldGestureDetector()
        _ = d.handle(.hotkeyDown(0))
        _ = d.handle(.otherKeyDown(0.02))
        _ = d.handle(.otherKeyDown(0.04))
        #expect(d.tick(now: 0.3) == [])
        #expect(d.handle(.hotkeyUp(0.4)) == [])
    }

    @Test func taintedPressDoesNotCountTowardDoubleTap() {
        var d = HoldGestureDetector()
        _ = d.handle(.hotkeyDown(0)); _ = d.handle(.otherKeyDown(0.02))
        #expect(d.handle(.hotkeyUp(0.05)) == [])
        _ = d.handle(.hotkeyDown(0.1)); #expect(d.handle(.hotkeyUp(0.15)) == [])
        #expect(!d.isRecording)
    }

    @Test func cancelDuringHoldStopsRecordingAndNeverRestarts() {
        var d = HoldGestureDetector()
        _ = d.handle(.hotkeyDown(0))
        #expect(d.tick(now: 0.2) == [.startHold])
        #expect(d.handle(.otherKeyDown(0.4)) == [.cancel])
        #expect(!d.isRecording)
        #expect(d.tick(now: 5) == [])
        #expect(d.handle(.hotkeyUp(6)) == [])
        #expect(!d.isRecording)
    }

    @Test func nextPressWorksNormallyAfterCancel() {
        var d = HoldGestureDetector()
        _ = d.handle(.hotkeyDown(0)); _ = d.tick(now: 0.2)
        _ = d.handle(.otherKeyDown(0.4)); _ = d.handle(.hotkeyUp(0.5))
        _ = d.handle(.hotkeyDown(1)); #expect(d.tick(now: 1.2) == [.startHold])
        #expect(d.handle(.hotkeyUp(2)) == [.stop])
    }
}
