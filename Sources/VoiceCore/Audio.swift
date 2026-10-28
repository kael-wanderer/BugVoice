import Foundation

/// Mono Float32 audio at 16 kHz, the format every speech engine here expects.
public struct AudioClip: Sendable, Equatable {
    public static let sampleRate: Double = 16_000

    public var samples: [Float]

    public init(samples: [Float]) {
        self.samples = samples
    }

    public var duration: TimeInterval {
        Double(samples.count) / Self.sampleRate
    }

    /// Root mean square, 0 for an empty clip. Used to skip silent clips
    /// before Whisper has a chance to hallucinate on them.
    public var rms: Float {
        guard !samples.isEmpty else { return 0 }
        let sum = samples.reduce(Float(0)) { $0 + $1 * $1 }
        return (sum / Float(samples.count)).squareRoot()
    }
}

public enum WAVError: Error, Equatable {
    case notWAV
    case unsupportedFormat(String)
}

/// 16-bit PCM, mono, 16 kHz.
public enum WAVEncoder {
    public static func encode(_ clip: AudioClip) -> Data {
        let sampleRate = UInt32(AudioClip.sampleRate)
        let dataSize = UInt32(clip.samples.count * 2)
        var data = Data(capacity: 44 + Int(dataSize))

        func append(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func append(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }

        data.append(contentsOf: Array("RIFF".utf8))
        append(36 + dataSize)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        append(UInt32(16))          // fmt chunk size
        append(UInt16(1))           // PCM
        append(UInt16(1))           // mono
        append(sampleRate)
        append(sampleRate * 2)      // byte rate
        append(UInt16(2))           // block align
        append(UInt16(16))          // bits per sample
        data.append(contentsOf: Array("data".utf8))
        append(dataSize)

        for sample in clip.samples {
            let clamped = max(-1, min(1, sample))
            let value = Int16(clamped < 0 ? clamped * 32768 : clamped * 32767)
            append(UInt16(bitPattern: value))
        }
        return data
    }
}

/// Reads back what `WAVEncoder` writes. Used for *Retry last*.
public enum WAVDecoder {
    public static func decode(_ data: Data) throws -> AudioClip {
        guard data.count >= 44,
              String(decoding: data[0..<4], as: UTF8.self) == "RIFF",
              String(decoding: data[8..<12], as: UTF8.self) == "WAVE"
        else { throw WAVError.notWAV }

        func u16(_ o: Int) -> UInt16 { UInt16(data[o]) | UInt16(data[o + 1]) << 8 }
        func u32(_ o: Int) -> UInt32 { (0..<4).reduce(UInt32(0)) { $0 | UInt32(data[o + $1]) << (8 * $1) } }

        var offset = 12
        var format: (channels: UInt16, rate: UInt32, bits: UInt16)?
        while offset + 8 <= data.count {
            let id = String(decoding: data[offset..<offset + 4], as: UTF8.self)
            let size = Int(u32(offset + 4))
            let body = offset + 8
            guard size <= data.count - body else { throw WAVError.notWAV }
            if id == "fmt " {
                guard size >= 16 else { throw WAVError.notWAV }
                format = (u16(body + 2), u32(body + 4), u16(body + 14))
            } else if id == "data" {
                guard let format else { throw WAVError.unsupportedFormat("data before fmt") }
                guard format.channels == 1, format.rate == 16_000, format.bits == 16 else {
                    throw WAVError.unsupportedFormat("\(format.channels) ch, \(format.rate) Hz, \(format.bits) bit")
                }
                let end = min(body + size, data.count)
                var samples: [Float] = []
                samples.reserveCapacity((end - body) / 2)
                var i = body
                while i + 1 < end {
                    let value = Int16(bitPattern: u16(i))
                    samples.append(value < 0 ? Float(value) / 32768 : Float(value) / 32767)
                    i += 2
                }
                return AudioClip(samples: samples)
            }
            offset = body + size + (size % 2)
        }
        throw WAVError.notWAV
    }
}
