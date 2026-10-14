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
    private let meetingDirectory: URL

    public init(meetingDirectory: URL) {
        self.meetingDirectory = meetingDirectory
    }

    public func finalize(_ manifest: MeetingManifest) async throws -> MeetingManifest {
        let journal = MeetingPCMJournalWriter(directory: meetingDirectory.appendingPathComponent(".capture", isDirectory: true))
        let micData = try journal.committedData(for: .mic)
        let systemData = try journal.committedData(for: .system)
        let mic = try samples(from: micData, track: .mic)
        let system = try samples(from: systemData, track: .system)
        let mixed = mix(mic, system)

        try writeAAC(mic, to: meetingDirectory.appendingPathComponent("mic.m4a"))
        try writeAAC(system, to: meetingDirectory.appendingPathComponent("system.m4a"))
        try writeAAC(mixed, to: meetingDirectory.appendingPathComponent("audio.m4a"))

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

    private func samples(from data: Data, track: MeetingTrack) throws -> [Float] {
        guard data.count.isMultiple(of: 2) else { throw MeetingAudioFinalizationError.invalidPCMData(track) }
        return data.withUnsafeBytes { bytes in
            let values = bytes.bindMemory(to: Int16.self)
            return values.map { Float(Int16(littleEndian: $0)) / 32_768 }
        }
    }

    private func mix(_ first: [Float], _ second: [Float]) -> [Float] {
        let count = max(first.count, second.count)
        return (0..<max(1, count)).map { index in
            let a = index < first.count ? first[index] : 0
            let b = index < second.count ? second[index] : 0
            return max(-1, min(1, (a + b) * 0.5))
        }
    }

    private func writeAAC(_ samples: [Float], to destination: URL) throws {
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
            let count = max(1, samples.count)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: AVAudioFrameCount(count)),
                  let channel = buffer.floatChannelData?[0] else {
                throw MeetingAudioFinalizationError.audioFile("Could not allocate AAC input buffer")
            }
            buffer.frameLength = AVAudioFrameCount(count)
            if samples.isEmpty {
                channel[0] = 0
            } else {
                samples.withUnsafeBufferPointer { source in channel.update(from: source.baseAddress!, count: samples.count) }
            }
            try file.write(from: buffer)
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
