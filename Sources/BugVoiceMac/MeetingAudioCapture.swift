import AVFoundation
import CoreAudio
import Darwin
import Foundation
import VoiceCore

public protocol MeetingAudioSource: Sendable {
    var track: MeetingTrack { get }
    func start(onBuffer: @escaping @Sendable (AudioClip, TimeInterval, Float) -> Void) async throws
    func pause() async throws
    func resume() async throws
    func stop() async throws
}

public enum MeetingAudioCaptureError: Error, Equatable {
    case sourceUnavailable(MeetingTrack)
    case coreAudio(operation: String, status: OSStatus)
}

public actor MeetingAudioCaptureCoordinator: MeetingAudioSourceControl {
    private let sources: [MeetingTrack: any MeetingAudioSource]
    private let writer: MeetingPCMJournalWriter
    private var started: Set<MeetingTrack> = []
    private var lastCheckpoint: MeetingCheckpoint?
    private let levelMeter = MeetingCaptureLevelMeter()

    public func level(for track: MeetingTrack) -> Float { levelMeter.value(for: track) }

    public init(sources: [MeetingTrack: any MeetingAudioSource], writer: MeetingPCMJournalWriter) {
        self.sources = sources
        self.writer = writer
    }

    public func start(track: MeetingTrack) async throws {
        guard let source = sources[track] else { throw MeetingAudioCaptureError.sourceUnavailable(track) }
        if started.isEmpty { lastCheckpoint = nil }
        try writer.start(track: track)
        do {
            let meter = levelMeter
            try await source.start { [writer] clip, offset, level in
                writer.append(clip.samples, track: track, offset: offset)
                meter.set(level, for: track)
            }
            started.insert(track)
        } catch {
            await rollbackSources()
            throw error
        }
    }

    public func pause() async throws {
        for track in MeetingTrack.allCases where started.contains(track) {
            try await sources[track]?.pause()
        }
        lastCheckpoint = try writer.checkpoint()
    }

    public func resume() async throws {
        for track in MeetingTrack.allCases where started.contains(track) {
            try await sources[track]?.resume()
        }
    }

    public func checkpoint() async throws -> MeetingCheckpoint {
        if started.isEmpty, let lastCheckpoint { return lastCheckpoint }
        let checkpoint = try writer.checkpoint()
        lastCheckpoint = checkpoint
        return checkpoint
    }

    public func stop() async throws {
        var firstError: Error?
        for track in MeetingTrack.allCases where started.contains(track) {
            do { try await sources[track]?.stop() } catch { if firstError == nil { firstError = error } }
        }
        started.removeAll()
        do { lastCheckpoint = try writer.checkpoint() } catch { if firstError == nil { firstError = error } }
        writer.close()
        if let firstError { throw firstError }
    }

    public func recover(id: MeetingID, manifest: MeetingManifest) async throws -> MeetingCheckpoint {
        try writer.recover()
    }

    private func rollbackSources() async {
        for source in sources.values { try? await source.stop() }
        started.removeAll()
        lastCheckpoint = try? writer.checkpoint()
        writer.close()
    }
}

/// Serializes callback buffers away from Core Audio's real-time thread and
/// advances durable per-track checkpoints only after journal bytes are synced.
public final class MeetingPCMJournalWriter: @unchecked Sendable {
    private struct TrackState {
        var handle: FileHandle
        var bytes = 0
        var samples = 0
        var startOffset: TimeInterval = .greatestFiniteMagnitude
        var endOffset: TimeInterval = 0
    }

    private let directory: URL
    private let queue = DispatchQueue(label: "com.bugvoice.meeting-pcm-journal")
    private let sampleCountsLock = NSLock()
    private var latestSampleCounts: [MeetingTrack: Int] = [:]
    private var tracks: [MeetingTrack: TrackState] = [:]
    private var appendFailure: Error?
    private var checkpointTimer: DispatchSourceTimer?

    public init(directory: URL) { self.directory = directory }

    public func start(track: MeetingTrack) throws {
        try queue.sync {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = journalURL(track)
            if !FileManager.default.fileExists(atPath: url.path) {
                guard FileManager.default.createFile(atPath: url.path, contents: Data()) else {
                    throw CocoaError(.fileWriteUnknown)
                }
            }
            let handle = try FileHandle(forWritingTo: url)
            try handle.seekToEnd()
            let existingBytes = Int(try handle.offset())
            tracks[track] = TrackState(handle: handle, bytes: existingBytes, samples: existingBytes / 2)
            setLatestSampleCount(existingBytes / 2, for: track)
            appendFailure = nil
            if checkpointTimer == nil {
                let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "com.bugvoice.meeting-checkpoint-timer"))
                timer.schedule(deadline: .now() + 1, repeating: 1)
                timer.setEventHandler { [weak self] in self?.checkpointOnTimer() }
                checkpointTimer = timer
                timer.resume()
            }
        }
    }

    public func append(_ samples: [Float], track: MeetingTrack, offset: TimeInterval) {
        guard !samples.isEmpty else { return }
        queue.async {
            guard var state = self.tracks[track] else { return }
            let clip = AudioClip(samples: samples)
            let bytes = MeetingPCMJournal.encode(clip)
            do {
                try state.handle.write(contentsOf: bytes)
                state.bytes += bytes.count
                state.samples += samples.count
                state.startOffset = min(state.startOffset, offset)
                state.endOffset = max(state.endOffset, offset + clip.duration)
                self.tracks[track] = state
                self.setLatestSampleCount(state.samples, for: track)
            } catch {
                self.appendFailure = error
            }
        }
    }

    public func checkpoint() throws -> MeetingCheckpoint {
        try queue.sync {
            if let appendFailure { throw appendFailure }
            guard !tracks.isEmpty else { return MeetingCheckpoint() }
            for track in Array(tracks.keys) {
                guard let state = tracks[track] else { continue }
                try state.handle.synchronize()
            }
            let checkpoint = MeetingCheckpoint(tracks: tracks.keys.sorted { $0.rawValue < $1.rawValue }.compactMap { track in
                guard let state = tracks[track] else { return nil }
                return MeetingTrackCheckpoint(
                    track: track,
                    committedByteCount: state.bytes,
                    sampleCount: state.samples,
                    startOffset: state.startOffset == .greatestFiniteMagnitude ? 0 : state.startOffset,
                    endOffset: state.endOffset
                )
            })
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try DurableMeetingFile.replace(encoder.encode(checkpoint), at: directory.appendingPathComponent("checkpoint.json"))
            return checkpoint
        }
    }

    @discardableResult
    public func recover() throws -> MeetingCheckpoint {
        try queue.sync {
            let url = directory.appendingPathComponent("checkpoint.json")
            guard FileManager.default.fileExists(atPath: url.path) else { return MeetingCheckpoint() }
            let checkpoint = try JSONDecoder().decode(MeetingCheckpoint.self, from: Data(contentsOf: url))
            var safeTracks: [MeetingTrackCheckpoint] = []
            for item in checkpoint.tracks {
                let journal = journalURL(item.track)
                guard FileManager.default.fileExists(atPath: journal.path) else { continue }
                let actualBytes = (try FileManager.default.attributesOfItem(atPath: journal.path)[.size] as? NSNumber)?.intValue ?? 0
                let committedBytes = min(actualBytes, max(0, item.committedByteCount)) / 2 * 2
                let handle = try FileHandle(forWritingTo: journal)
                try handle.truncate(atOffset: UInt64(committedBytes))
                try handle.synchronize()
                try handle.close()
                let samples = min(item.sampleCount, committedBytes / 2)
                let maximumEnd = item.startOffset + Double(samples) / Double(MeetingPCMJournal.sampleRate)
                safeTracks.append(MeetingTrackCheckpoint(
                    track: item.track, committedByteCount: committedBytes, sampleCount: samples,
                    startOffset: item.startOffset, endOffset: min(item.endOffset, maximumEnd)
                ))
            }
            let safeCheckpoint = MeetingCheckpoint(tracks: safeTracks)
            for track in MeetingTrack.allCases {
                setLatestSampleCount(safeCheckpoint.track(track)?.sampleCount ?? 0, for: track)
            }
            if safeCheckpoint != checkpoint {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys]
                try DurableMeetingFile.replace(encoder.encode(safeCheckpoint), at: url)
            }
            return safeCheckpoint
        }
    }

    public func close() {
        queue.sync {
            checkpointTimer?.setEventHandler {}
            checkpointTimer?.cancel()
            checkpointTimer = nil
            for state in tracks.values { try? state.handle.close() }
            tracks.removeAll()
        }
    }

    public func storedCheckpoint() throws -> MeetingCheckpoint {
        let url = directory.appendingPathComponent("checkpoint.json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(MeetingCheckpoint.self, from: data)
    }

    public func makeReader(for track: MeetingTrack) throws -> MeetingPCMJournalReader {
        let checkpoint = try storedCheckpoint()
        let sampleCount = checkpoint.track(track)?.sampleCount ?? 0
        return try MeetingPCMJournalReader(url: journalURL(track), sampleCount: sampleCount)
    }

    /// A lock-only snapshot for UI scheduling. It never waits for journal I/O.
    public func sampleCount(for track: MeetingTrack) -> Int {
        sampleCountsLock.lock()
        defer { sampleCountsLock.unlock() }
        return latestSampleCounts[track, default: 0]
    }

    public func committedSamples(for track: MeetingTrack, range: Range<Int>) throws -> [Float] {
        try queue.sync {
            try committedSamplesOnQueue(for: track, range: range)
        }
    }

    /// Reads away from the caller's actor so live monitoring never performs
    /// journal file I/O on MainActor.
    public func committedSamplesAsync(for track: MeetingTrack, range: Range<Int>) async throws -> [Float] {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do { continuation.resume(returning: try self.committedSamplesOnQueue(for: track, range: range)) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }

    private func committedSamplesOnQueue(for track: MeetingTrack, range: Range<Int>) throws -> [Float] {
        if let appendFailure { throw appendFailure }
        let count: Int
        if let activeTrack = tracks[track] {
            count = activeTrack.samples
        } else {
            count = try storedCheckpoint().track(track)?.sampleCount ?? 0
        }
        let lower = min(count, max(0, range.lowerBound))
        let upper = min(count, max(lower, range.upperBound))
        guard upper > lower else { return [] }
        let handle = try FileHandle(forReadingFrom: journalURL(track))
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(lower * 2))
        let data = try handle.read(upToCount: (upper - lower) * 2) ?? Data()
        guard data.count.isMultiple(of: 2) else { throw CocoaError(.fileReadCorruptFile) }
        return data.withUnsafeBytes { bytes in
            bytes.bindMemory(to: Int16.self).map { Float(Int16(littleEndian: $0)) / 32_768 }
        }
    }

    private func setLatestSampleCount(_ count: Int, for track: MeetingTrack) {
        sampleCountsLock.lock()
        latestSampleCounts[track] = count
        sampleCountsLock.unlock()
    }

    public func committedData(for track: MeetingTrack) throws -> Data {
        let checkpoint = try queue.sync { try Data(contentsOf: directory.appendingPathComponent("checkpoint.json")) }
        let model = try JSONDecoder().decode(MeetingCheckpoint.self, from: checkpoint)
        let committed = model.track(track)?.committedByteCount ?? 0
        let data = try Data(contentsOf: journalURL(track))
        return MeetingPCMJournal.recover(data, committedByteCount: committed).committedData
    }

    private func checkpointOnTimer() {
        do { _ = try checkpoint() }
        catch { queue.async { self.appendFailure = error } }
    }

    private func journalURL(_ track: MeetingTrack) -> URL {
        directory.appendingPathComponent("\(track.rawValue).pcm")
    }
}

/// Sequential reader bounded by the durable sample count in the checkpoint.
public final class MeetingPCMJournalReader: @unchecked Sendable {
    public let totalSampleCount: Int
    public private(set) var remainingSampleCount: Int
    private var handle: FileHandle?

    fileprivate init(url: URL, sampleCount: Int) throws {
        totalSampleCount = max(0, sampleCount)
        remainingSampleCount = max(0, sampleCount)
        if sampleCount > 0 {
            handle = try FileHandle(forReadingFrom: url)
        }
    }

    public func readSamples(maxCount: Int) throws -> [Float] {
        guard maxCount > 0, remainingSampleCount > 0, let handle else { return [] }
        let count = min(maxCount, remainingSampleCount)
        let data = try handle.read(upToCount: count * 2) ?? Data()
        guard data.count == count * 2 else { throw CocoaError(.fileReadCorruptFile) }
        remainingSampleCount -= count
        return data.withUnsafeBytes { bytes in
            bytes.bindMemory(to: Int16.self).map { Float(Int16(littleEndian: $0)) / 32_768 }
        }
    }

    deinit { try? handle?.close() }
}

private enum DurableMeetingFile {
    static func replace(_ data: Data, at destination: URL) throws {
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".\(destination.lastPathComponent).\(UUID().uuidString).tmp")
        let descriptor = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw posixError() }
        do {
            try data.withUnsafeBytes { rawBuffer in
                guard let base = rawBuffer.baseAddress else { return }
                var written = 0
                while written < rawBuffer.count {
                    let result = write(descriptor, base.advanced(by: written), rawBuffer.count - written)
                    if result <= 0 { throw posixError() }
                    written += result
                }
            }
            guard fsync(descriptor) == 0 else { throw posixError() }
            guard close(descriptor) == 0 else { throw posixError() }
            guard rename(temporary.path, destination.path) == 0 else { throw posixError() }
            let directoryDescriptor = open(destination.deletingLastPathComponent().path, O_RDONLY)
            if directoryDescriptor >= 0 {
                let syncResult = fsync(directoryDescriptor)
                let syncError = syncResult == 0 ? nil : posixError()
                _ = close(directoryDescriptor)
                if let syncError { throw syncError }
            }
        } catch {
            _ = close(descriptor)
            _ = unlink(temporary.path)
            throw error
        }
    }

    private static func posixError() -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
}

public final class MeetingAudioEngineSource: MeetingAudioSource, @unchecked Sendable {
    public let track: MeetingTrack
    private let deviceID: AudioDeviceID?
    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var converter: AVAudioConverter?
    private var bufferHandler: (@Sendable (AudioClip, TimeInterval, Float) -> Void)?
    private let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
    private var activeStart: TimeInterval = 0
    private var activeDuration: TimeInterval = 0
    private var running = false
    private var tapInstalled = false

    public init(track: MeetingTrack, deviceID: AudioDeviceID? = nil) {
        self.track = track
        self.deviceID = deviceID
    }

    public func start(onBuffer: @escaping @Sendable (AudioClip, TimeInterval, Float) -> Void) async throws {
        lock.withLock { bufferHandler = onBuffer; activeStart = ProcessInfo.processInfo.systemUptime }
        let input = engine.inputNode
        if var deviceID {
            guard let unit = input.audioUnit else { throw RecorderError.noInputDevice }
            let status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &deviceID, UInt32(MemoryLayout<AudioDeviceID>.size))
            guard status == noErr else { throw MeetingAudioCaptureError.coreAudio(operation: "select audio input", status: status) }
        }
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw RecorderError.noInputDevice }
        converter = AVAudioConverter(from: format, to: target)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in self?.consume(buffer) }
        tapInstalled = true
        engine.prepare()
        try engine.start()
        running = true
    }

    public func pause() async throws {
        lock.withLock { activeDuration += max(0, ProcessInfo.processInfo.systemUptime - activeStart) }
        engine.pause()
        running = false
    }

    public func resume() async throws {
        lock.withLock { activeStart = ProcessInfo.processInfo.systemUptime }
        try engine.start()
        running = true
    }

    public func stop() async throws {
        if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
        engine.stop()
        running = false
        lock.withLock { bufferHandler = nil }
    }

    private func consume(_ buffer: AVAudioPCMBuffer) {
        guard let converter, let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: AVAudioFrameCount(Double(buffer.frameLength) * target.sampleRate / buffer.format.sampleRate) + 64) else { return }
        var supplied = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            guard !supplied else { status.pointee = .noDataNow; return nil }
            supplied = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, let samples = output.floatChannelData?[0], output.frameLength > 0 else { return }
        let array = Array(UnsafeBufferPointer(start: samples, count: Int(output.frameLength)))
        let clip = AudioClip(samples: array)
        let uptime = ProcessInfo.processInfo.systemUptime
        let (offset, handler) = lock.withLock {
            (activeDuration + max(0, uptime - activeStart), bufferHandler)
        }
        handler?(clip, offset, min(1, clip.rms * 8))
    }
}

public final class CoreAudioProcessTapSource: MeetingAudioSource, @unchecked Sendable {
    public let track: MeetingTrack = .system
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)

    public init() {}

    public func start(onBuffer: @escaping @Sendable (AudioClip, TimeInterval, Float) -> Void) async throws {
        let processObject = try Self.processObjectID(for: getpid())
        let description = CATapDescription(monoGlobalTapButExcludeProcesses: [processObject])
        description.name = "BugVoice Meeting System Audio"
        description.isPrivate = true
        description.isMixdown = true
        description.isMono = true
        var newTap = AudioObjectID(kAudioObjectUnknown)
        let tapStatus = AudioHardwareCreateProcessTap(description, &newTap)
        guard tapStatus == noErr else { throw MeetingAudioCaptureError.coreAudio(operation: "create system audio tap", status: tapStatus) }
        tapID = newTap

        var address = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyUID, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var uid: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let readStatus = withUnsafeMutablePointer(to: &uid) { AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, $0) }
        guard readStatus == noErr, let tapUID = uid?.takeRetainedValue() else {
            cleanup()
            throw MeetingAudioCaptureError.coreAudio(operation: "read system audio tap UID", status: readStatus)
        }
        let dictionary: [String: Any] = [
            kAudioAggregateDeviceNameKey: "BugVoice Meeting System Audio",
            kAudioAggregateDeviceUIDKey: "com.bugvoice.meeting.\(UUID().uuidString)",
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: tapUID as String, kAudioSubTapDriftCompensationKey: true]],
            kAudioAggregateDeviceTapAutoStartKey: true
        ]
        var newAggregate = AudioObjectID(kAudioObjectUnknown)
        let aggregateStatus = AudioHardwareCreateAggregateDevice(dictionary as CFDictionary, &newAggregate)
        guard aggregateStatus == noErr else {
            cleanup()
            throw MeetingAudioCaptureError.coreAudio(operation: "create system audio aggregate device", status: aggregateStatus)
        }
        aggregateID = newAggregate
        let deviceSource = MeetingAudioEngineSource(track: .system, deviceID: aggregateID)
        activeDeviceSource = deviceSource
        try await deviceSource.start(onBuffer: onBuffer)
    }

    private var activeDeviceSource: MeetingAudioEngineSource?
    public func pause() async throws { try await activeDeviceSource?.pause() }
    public func resume() async throws { try await activeDeviceSource?.resume() }
    public func stop() async throws {
        try await activeDeviceSource?.stop()
        activeDeviceSource = nil
        cleanup()
    }

    private func cleanup() {
        if aggregateID != AudioObjectID(kAudioObjectUnknown) { AudioHardwareDestroyAggregateDevice(aggregateID); aggregateID = AudioObjectID(kAudioObjectUnknown) }
        if tapID != AudioObjectID(kAudioObjectUnknown) { AudioHardwareDestroyProcessTap(tapID); tapID = AudioObjectID(kAudioObjectUnknown) }
    }

    private static func processObjectID(for pid: pid_t) throws -> AudioObjectID {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        var status = AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size)
        guard status == noErr else { throw MeetingAudioCaptureError.coreAudio(operation: "list audio processes", status: status) }
        var objects = [AudioObjectID](repeating: AudioObjectID(kAudioObjectUnknown), count: Int(size) / MemoryLayout<AudioObjectID>.size)
        status = AudioObjectGetPropertyData(system, &address, 0, nil, &size, &objects)
        guard status == noErr else { throw MeetingAudioCaptureError.coreAudio(operation: "read audio processes", status: status) }
        for object in objects {
            var pidAddress = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyPID, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var objectPID: pid_t = 0
            var pidSize = UInt32(MemoryLayout<pid_t>.size)
            if AudioObjectGetPropertyData(object, &pidAddress, 0, nil, &pidSize, &objectPID) == noErr, objectPID == pid { return object }
        }
        throw MeetingAudioCaptureError.coreAudio(operation: "find BugVoice process object", status: -1)
    }
}


private final class MeetingCaptureLevelMeter: @unchecked Sendable {
    private let lock = NSLock()
    private var levels: [MeetingTrack: Float] = [:]
    func set(_ level: Float, for track: MeetingTrack) { lock.withLock { levels[track] = level } }
    func value(for track: MeetingTrack) -> Float { lock.withLock { levels[track] ?? 0 } }
}
