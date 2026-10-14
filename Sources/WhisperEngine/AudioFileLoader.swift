import Foundation
import VoiceCore
import WhisperKit

public enum AudioFileLoader {
    /// Any format AVFoundation reads; WhisperKit resamples to 16 kHz mono.
    public static func load(_ url: URL) throws -> AudioClip {
        AudioClip(samples: try AudioProcessor.loadAudioAsFloatArray(fromPath: url.path))
    }
}
