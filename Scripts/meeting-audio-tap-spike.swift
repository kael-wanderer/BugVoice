import AppKit
import CoreAudio
import Foundation
import Darwin

private func check(_ status: OSStatus, _ operation: String) throws {
    guard status == noErr else { throw NSError(domain: "MeetingTapSpike", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "\(operation) failed with OSStatus \(status)"]) }
}

private func propertyAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
}

private func processObjectID(for pid: pid_t) throws -> AudioObjectID {
    var address = propertyAddress(kAudioHardwarePropertyProcessObjectList)
    var size: UInt32 = 0
    try check(AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size), "query process list size")
    let count = Int(size) / MemoryLayout<AudioObjectID>.size
    var ids = [AudioObjectID](repeating: AudioObjectID(kAudioObjectUnknown), count: count)
    try check(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids), "query process list")
    for id in ids {
        var pidAddress = propertyAddress(kAudioProcessPropertyPID)
        var processPID: pid_t = 0
        var pidSize = UInt32(MemoryLayout<pid_t>.size)
        if AudioObjectGetPropertyData(id, &pidAddress, 0, nil, &pidSize, &processPID) == noErr, processPID == pid {
            return id
        }
    }
    throw NSError(domain: "MeetingTapSpike", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not find this process in Core Audio's process list"])
}

private func run() throws {
    let selfProcess = try processObjectID(for: getpid())
    let description = CATapDescription(monoGlobalTapButExcludeProcesses: [selfProcess])
    description.name = "BugVoice Meeting Tap Spike"
    description.isPrivate = true
    description.isMixdown = true
    description.isMono = true

    var tapID = AudioObjectID(kAudioObjectUnknown)
    try check(AudioHardwareCreateProcessTap(description, &tapID), "create process tap")

    var tapUIDAddress = propertyAddress(kAudioTapPropertyUID)
    var tapUID: Unmanaged<CFString>?
    var tapUIDSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    let uidStatus = withUnsafeMutablePointer(to: &tapUID) {
        AudioObjectGetPropertyData(tapID, &tapUIDAddress, 0, nil, &tapUIDSize, $0)
    }
    try check(uidStatus, "read tap UID")
    guard let uid = tapUID?.takeRetainedValue() else { throw NSError(domain: "MeetingTapSpike", code: -2) }

    let aggregateUID = "com.bugvoice.meeting-tap-spike.\(UUID().uuidString)"
    let tapEntry: [String: Any] = [
        kAudioSubTapUIDKey: uid as String,
        kAudioSubTapDriftCompensationKey: true
    ]
    let aggregateDescription: [String: Any] = [
        kAudioAggregateDeviceNameKey: "BugVoice Meeting Tap Spike",
        kAudioAggregateDeviceUIDKey: aggregateUID,
        kAudioAggregateDeviceIsPrivateKey: true,
        kAudioAggregateDeviceTapListKey: [tapEntry],
        kAudioAggregateDeviceTapAutoStartKey: true
    ]
    var aggregateID = AudioObjectID(kAudioObjectUnknown)
    try check(AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &aggregateID), "create private aggregate device")

    var ioProcID: AudioDeviceIOProcID?
    let ioStatus = AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateID, DispatchQueue.global(qos: .utility)) { _, inputData, _, _, _ in
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData))
        guard let first = buffers.first, let data = first.mData, first.mDataByteSize >= UInt32(MemoryLayout<Float>.size) else { return }
        let samples = data.assumingMemoryBound(to: Float.self)
        let count = Int(first.mDataByteSize) / MemoryLayout<Float>.size
        var sum: Double = 0
        for index in 0..<count { let value = Double(samples[index]); sum += value * value }
        let rms = count == 0 ? 0 : sqrt(sum / Double(count))
        if rms > 0.0001 { print(String(format: "system tap RMS %.5f", rms)) }
    }
    try check(ioStatus, "create aggregate IOProc")
    try check(AudioDeviceStart(aggregateID, ioProcID), "start aggregate device (permission is requested here)")

    print("Tap is running. Playing BugVoice-owned Glass sound; then play other system audio. Press Return to stop.")
    NSSound(named: NSSound.Name("Glass"))?.play()
    _ = readLine()

    AudioDeviceStop(aggregateID, ioProcID)
    if let ioProcID { AudioDeviceDestroyIOProcID(aggregateID, ioProcID) }
    AudioHardwareDestroyAggregateDevice(aggregateID)
    AudioHardwareDestroyProcessTap(tapID)
}

do {
    try run()
} catch {
    fputs("Meeting tap spike error: \(error.localizedDescription)\n", stderr)
    exit(1)
}
