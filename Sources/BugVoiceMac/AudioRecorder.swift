import AVFoundation
import AudioToolbox
import OSLog
import Synchronization
import VoiceCore

public enum RecorderError: Error {
    case noInputDevice
    case deviceNotFound
    case deviceSelectionFailed(OSStatus)
    case alreadyRunning
}

/// Microphone → 16 kHz mono Float32, with a level meter for the HUD.
/// Echo cancellation, noise suppression and AGC are not applied (raw input),
/// matching what Whisper expects.
///
/// Opening a Bluetooth headset's mic switches it to its call profile, which
/// changes the input format and stops the engine. The recorder then rebuilds
/// its tap and restarts, keeping the samples captured so far.
public final class AudioRecorder: @unchecked Sendable {
    private var engine = AVAudioEngine()
    private let samples = Mutex<[Float]>([])
    private let levelValue = Mutex<Float>(0)
    private var deviceUID: String?
    private var configObserver: NSObjectProtocol?
    private let buffersSinceAttach = Mutex<Int>(0)
    private var restarts = 0
    private static let maxRestarts = 8
    private static let silentEngineTimeout: TimeInterval = 0.5
    private let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: AudioClip.sampleRate, channels: 1, interleaved: false)!
    public private(set) var isRunning = false
    /// How long to keep recording after the key is released so audio still
    /// in flight arrives: Bluetooth inputs lag, wired and built-in ones do not.
    public private(set) var releaseTail: TimeInterval = 0

    public init() {}

    /// 0…1, smoothed enough for a meter.
    public var level: Float { levelValue.withLock { $0 } }

    /// Sample-based time, independent of timer scheduling.
    public var recordedDuration: TimeInterval {
        samples.withLock { Double($0.count) / AudioClip.sampleRate }
    }

    /// Copies only the requested tail while the audio callback holds the same mutex.
    public func recentSamples(seconds: TimeInterval) -> AudioClip {
        samples.withLock { values in
            let duration = max(0, min(seconds.isFinite ? seconds : 0, Double(values.count) / AudioClip.sampleRate))
            return AudioClip(samples: Array(values.suffix(Int(duration * AudioClip.sampleRate))))
        }
    }

    public func start(deviceUID: String? = nil) throws {
        guard !isRunning else { throw RecorderError.alreadyRunning }
        self.deviceUID = deviceUID
        samples.withLock { $0.removeAll(keepingCapacity: true) }
        levelValue.withLock { $0 = 0 }
        restarts = 0
        releaseTail = AudioDevices.isBluetoothInput(uid: deviceUID) ? 0.4 : 0
        try attach()
        isRunning = true
        scheduleWatchdog()
    }

    public func stop() -> AudioClip {
        if isRunning { detach() }
        isRunning = false
        return AudioClip(samples: samples.withLock { $0 })
    }

    /// A fresh engine each time picks up device changes since the last run.
    private func attach() throws {
        engine = AVAudioEngine()
        buffersSinceAttach.withLock { $0 = 0 }
        let current = engine
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: current, queue: .main
        ) { [weak self] _ in
            guard let self, self.isRunning, self.engine === current else { return }
            self.restart(reason: "audio configuration change")
        }
        do {
            try connect()
        } catch {
            detach()
            throw error
        }
    }

    private func detach() {
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        configObserver = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }

    /// Selects the device, installs the tap for the input's current format and starts the engine.
    private func connect() throws {
        let input = engine.inputNode
        if let deviceUID {
            guard var deviceID = AudioDevices.deviceID(forUID: deviceUID) else { throw RecorderError.deviceNotFound }
            guard let unit = input.audioUnit else { throw RecorderError.noInputDevice }
            let status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &deviceID, UInt32(MemoryLayout<AudioDeviceID>.size))
            // Never fall back to the default mic when the chosen one fails.
            guard status == noErr else { throw RecorderError.deviceSelectionFailed(status) }
        }
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw RecorderError.noInputDevice }
        guard let converter = AVAudioConverter(from: format, to: target) else { throw RecorderError.noInputDevice }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.consume(buffer, converter: converter)
        }
        engine.prepare()
        try engine.start()
    }

    /// Replaces the engine mid-recording, keeping the samples captured so far.
    /// A failed restart is retried by the watchdog until the device settles.
    private func restart(reason: String) {
        guard restarts < Self.maxRestarts else { return }
        restarts += 1
        detach()
        do {
            try attach()
            Log.dictation.info("recorder restarted after \(reason, privacy: .public)")
        } catch {
            Log.dictation.error("recorder restart failed: \(String(describing: error), privacy: .public)")
        }
        scheduleWatchdog()
    }

    /// An engine that started but delivers no buffers (a headset still
    /// switching profiles, with no change notice) is replaced.
    private func scheduleWatchdog() {
        let current = engine
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.silentEngineTimeout) { [weak self] in
            guard let self, self.isRunning, self.engine === current,
                  self.buffersSinceAttach.withLock({ $0 }) == 0 else { return }
            self.restart(reason: "no audio from the input")
        }
    }

    private func consume(_ buffer: AVAudioPCMBuffer, converter: AVAudioConverter) {
        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
        var supplied = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if supplied {
                status.pointee = .noDataNow
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, let channel = output.floatChannelData?[0] else { return }
        let count = Int(output.frameLength)
        let chunk = Array(UnsafeBufferPointer(start: channel, count: count))
        let rms = AudioClip(samples: chunk).rms
        levelValue.withLock { $0 = $0 * 0.6 + min(1, rms * 8) * 0.4 }
        samples.withLock { $0.append(contentsOf: chunk) }
        buffersSinceAttach.withLock { $0 += 1 }
    }
}
