import AVFoundation
import AudioToolbox
import Darwin
import Foundation
import VoiceCore

public enum MeetingAudioFinalizationError: Error, Equatable {
    case invalidPCMData(MeetingTrack)
    case audioFile(String)
}

public struct MeetingAudioFinalizer: MeetingAudioFinalizerProtocol {
    private static let blockFrames = 16_000
    private let meetingDirectory: URL

    public init(meetingDirectory: URL) {
        self.meetingDirectory = meetingDirectory
    }

    public func finalize(_ manifest: MeetingManifest) async throws -> MeetingManifest {
        let journal = MeetingPCMJournalWriter(directory: meetingDirectory.appendingPathComponent(".capture", isDirectory: true))
        let mic = try journal.makeReader(for: .mic)
        let system = try journal.makeReader(for: .system)
        try writeAAC(
            sampleCount: mic.totalSampleCount,
            readBlock: { _, count in try mic.readSamples(maxCount: count) },
            to: meetingDirectory.appendingPathComponent("mic.m4a")
        )
        try writeAAC(
            sampleCount: system.totalSampleCount,
            readBlock: { _, count in try system.readSamples(maxCount: count) },
            to: meetingDirectory.appendingPathComponent("system.m4a")
        )

        let micForMix = try journal.makeReader(for: .mic)
        let systemForMix = try journal.makeReader(for: .system)
        let mixCount = max(micForMix.totalSampleCount, systemForMix.totalSampleCount)
        try writeAAC(sampleCount: mixCount, readBlock: { _, count in
            let micSamples = try micForMix.readSamples(maxCount: count)
            let systemSamples = try systemForMix.readSamples(maxCount: count)
            return (0..<count).map { index in
                let a = index < micSamples.count ? micSamples[index] : 0
                let b = index < systemSamples.count ? systemSamples[index] : 0
                return max(-1, min(1, (a + b) * 0.5))
            }
        }, to: meetingDirectory.appendingPathComponent("audio.m4a"))

        var finalized = manifest
        finalized.audioFormat.finalEncoding = "aac"
        return finalized
    }

    public func cleanupCapture() async throws {
        let captureDirectory = meetingDirectory.appendingPathComponent(".capture", isDirectory: true)
        if FileManager.default.fileExists(atPath: captureDirectory.path) {
            try FileManager.default.removeItem(at: captureDirectory)
            try syncDirectory(meetingDirectory)
        }
    }

    private func writeAAC(
        sampleCount: Int,
        readBlock: (_ offset: Int, _ count: Int) throws -> [Float],
        to destination: URL
    ) throws {
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temporary = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(destination.deletingPathExtension().lastPathComponent).\(UUID().uuidString).tmp.m4a")
        do {
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 16_000,
                AVNumberOfChannelsKey: 1
            ]
            let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
            let file = try AVAudioFile(forWriting: temporary, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
            let finalFrameCount = max(1, sampleCount)
            var offset = 0
            while offset < finalFrameCount {
                let count = sampleCount == 0 ? 1 : min(Self.blockFrames, sampleCount - offset)
                let samples = sampleCount == 0 ? [] : try readBlock(offset, count)
                guard samples.count == (sampleCount == 0 ? 0 : count),
                      let buffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: AVAudioFrameCount(count)),
                      let channel = buffer.floatChannelData?[0] else {
                    throw MeetingAudioFinalizationError.audioFile("Could not read or allocate an AAC input block")
                }
                buffer.frameLength = AVAudioFrameCount(count)
                if samples.isEmpty { channel[0] = 0 }
                else { samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) } }
                try file.write(from: buffer)
                offset += count
            }
            file.close()
            let handle = try FileHandle(forWritingTo: temporary)
            try handle.synchronize()
            try handle.close()
            guard rename(temporary.path, destination.path) == 0 else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
            try syncDirectory(destination.deletingLastPathComponent())
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }

    private func syncDirectory(_ url: URL) throws {
        let descriptor = open(url.path, O_RDONLY)
        guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        let status = fsync(descriptor)
        let error = status == 0 ? nil : NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        _ = close(descriptor)
        if let error { throw error }
    }
}
