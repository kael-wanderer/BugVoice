import AVFoundation
import AudioToolbox
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
public final class AudioRecorder: @unchecked Sendable {
    private var engine = AVAudioEngine()
    private let samples = Mutex<[Float]>([])
    private let levelValue = Mutex<Float>(0)
    private var converter: AVAudioConverter?
    private let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: AudioClip.sampleRate, channels: 1, interleaved: false)!
    public private(set) var isRunning = false

    public init() {}

    /// 0…1, smoothed enough for a meter.
    public var level: Float { levelValue.withLock { $0 } }

    public func start(deviceUID: String? = nil) throws {
        guard !isRunning else { throw RecorderError.alreadyRunning }
        // A fresh engine each time picks up device changes since the last run.
        engine = AVAudioEngine()
        samples.withLock { $0.removeAll(keepingCapacity: true) }
        levelValue.withLock { $0 = 0 }

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
        converter = AVAudioConverter(from: format, to: target)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.consume(buffer)
        }
        engine.prepare()
        try engine.start()
        isRunning = true
    }

    public func stop() -> AudioClip {
        if isRunning {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        isRunning = false
        return AudioClip(samples: samples.withLock { $0 })
    }

    private func consume(_ buffer: AVAudioPCMBuffer) {
        guard let converter else { return }
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
    }
}
