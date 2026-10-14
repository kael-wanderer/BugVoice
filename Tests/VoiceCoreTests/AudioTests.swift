import Foundation
import Testing
@testable import VoiceCore

struct AudioTests {
    @Test func durationUsesSixteenKilohertz() {
        let clip = AudioClip(samples: Array(repeating: 0, count: 8_000))
        #expect(clip.duration == 0.5)
    }

    @Test func rmsOfSilenceIsZeroAndOfFullScaleIsOne() {
        #expect(AudioClip(samples: [0, 0, 0]).rms == 0)
        #expect(AudioClip(samples: [1, -1, 1, -1]).rms == 1)
        #expect(AudioClip(samples: []).rms == 0)
    }

    @Test func wavHeaderIsCanonical() throws {
        let data = WAVEncoder.encode(AudioClip(samples: [0, 0.5]))
        #expect(data.count == 44 + 4)
        #expect(String(decoding: data[0..<4], as: UTF8.self) == "RIFF")
        #expect(String(decoding: data[8..<12], as: UTF8.self) == "WAVE")
        #expect(String(decoding: data[36..<40], as: UTF8.self) == "data")
        #expect(data.readUInt32(at: 4) == 36 + 4)        // RIFF chunk size
        #expect(data.readUInt32(at: 24) == 16_000)       // sample rate
        #expect(data.readUInt16(at: 22) == 1)            // channels
        #expect(data.readUInt16(at: 34) == 16)           // bits per sample
        #expect(data.readUInt32(at: 40) == 4)            // data size
    }

    @Test func samplesAreClampedAndScaled() {
        let data = WAVEncoder.encode(AudioClip(samples: [0, 1, -1, 0.5, 2, -3]))
        let values = (0..<6).map { Int16(bitPattern: data.readUInt16(at: 44 + $0 * 2)) }
        #expect(values == [0, 32767, -32768, 16383, 32767, -32768])
    }

    @Test func decodeRoundTripsWithinQuantisation() throws {
        let original = AudioClip(samples: [0, 0.25, -0.25, 0.999])
        let decoded = try WAVDecoder.decode(WAVEncoder.encode(original))
        #expect(decoded.samples.count == 4)
        for (a, b) in zip(original.samples, decoded.samples) {
            #expect(abs(a - b) < 0.0001)
        }
    }

    @Test func decodeRejectsNonWAV() {
        #expect(throws: WAVError.notWAV) { try WAVDecoder.decode(Data("hello".utf8)) }
    }
}

extension Data {
    func readUInt32(at offset: Int) -> UInt32 {
        self[offset..<offset + 4].enumerated().reduce(0) { $0 | UInt32($1.element) << (8 * $1.offset) }
    }
    func readUInt16(at offset: Int) -> UInt16 {
        UInt16(self[offset]) | UInt16(self[offset + 1]) << 8
    }
}
