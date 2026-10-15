import AVFoundation
import AudioToolbox
import Foundation
import CoreVideo
import Testing

// Test-only ownership is serial: each invocation creates its own writer.
enum UploadAssetFactory {
    static func make(
        at url: URL,
        rate: Double = 16_000,
        channels: Int = 1,
        seconds: Int = 3,
        audio: Bool = true,
        video: Bool = false,
        creationDate: String? = nil
    ) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: video ? .mov : .m4a)
        if let creationDate {
            let metadata = AVMutableMetadataItem()
            metadata.identifier = .commonIdentifierCreationDate
            metadata.value = creationDate as NSString
            writer.metadata = [metadata]
        }
        var layout = AudioChannelLayout()
        layout.mChannelLayoutTag = channels == 6 ? kAudioChannelLayoutTag_MPEG_5_1_A : (channels == 2 ? kAudioChannelLayoutTag_Stereo : kAudioChannelLayoutTag_Mono)
        var asbd = AudioStreamBasicDescription(
            mSampleRate: rate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(channels * 4),
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(channels * 4),
            mChannelsPerFrame: UInt32(channels),
            mBitsPerChannel: 32,
            mReserved: 0
        )
        var description: CMAudioFormatDescription?
        let status = CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &asbd,
            layoutSize: MemoryLayout<AudioChannelLayout>.size,
            layout: &layout,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &description
        )
        guard status == noErr, let description else { throw CocoaError(.fileWriteUnknown) }
        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: rate,
            AVNumberOfChannelsKey: channels,
            AVEncoderBitRateKey: channels == 6 ? 384_000 : (rate < 22_050 ? 32_000 : 128_000)
        ], sourceFormatHint: description)
        if audio {
            guard writer.canAdd(audioInput) else { throw CocoaError(.featureUnsupported) }
            writer.add(audioInput)
        }
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            // Motion JPEG has no frame reordering, so the writer never holds audio back waiting for video.
            AVVideoCodecKey: AVVideoCodecType.jpeg,
            AVVideoWidthKey: 16,
            AVVideoHeightKey: 16
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: 16,
            kCVPixelBufferHeightKey as String: 16
        ])
        // Test fixtures are written as fast as possible; real-time mode stops the writer
        // from blocking one input while it waits to interleave the other.
        audioInput.expectsMediaDataInRealTime = true
        videoInput.expectsMediaDataInRealTime = true
        if video {
            guard writer.canAdd(videoInput) else { throw CocoaError(.featureUnsupported) }
            writer.add(videoInput)
        }
        guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        writer.startSession(atSourceTime: .zero)
        let frames = Int(rate) / 10
        for block in 0..<(seconds * 10) {
            if audio {
                while !audioInput.isReadyForMoreMediaData {
                    try Task.checkCancellation()
                    try await Task.sleep(for: .milliseconds(1))
                    if writer.status == .failed { throw writer.error ?? CocoaError(.fileWriteUnknown) }
                }
                var samples = [Float](repeating: 0, count: frames * channels)
                for frame in 0..<frames {
                    let value = Float(sin(2 * Double.pi * 440 * Double(block * frames + frame) / rate) * 0.4)
                    for channel in 0..<channels {
                        // 5.1 (L R C LFE Ls Rs): dialogue sits in the center channel, as in real films.
                        samples[frame * channels + channel] = channels == 6 ? (channel == 2 ? value : 0) : value
                    }
                }
                var buffer: CMBlockBuffer?
                let bytes = samples.count * 4
                guard CMBlockBufferCreateWithMemoryBlock(
                    allocator: kCFAllocatorDefault,
                    memoryBlock: nil,
                    blockLength: bytes,
                    blockAllocator: kCFAllocatorDefault,
                    customBlockSource: nil,
                    offsetToData: 0,
                    dataLength: bytes,
                    flags: 0,
                    blockBufferOut: &buffer
                ) == kCMBlockBufferNoErr, let buffer else { throw CocoaError(.fileWriteUnknown) }
                try samples.withUnsafeBytes { raw in
                    guard CMBlockBufferReplaceDataBytes(with: raw.baseAddress!, blockBuffer: buffer, offsetIntoDestination: 0, dataLength: bytes) == noErr else {
                        throw CocoaError(.fileWriteUnknown)
                    }
                }
                var timing = CMSampleTimingInfo(
                    duration: CMTime(value: 1, timescale: Int32(rate)),
                    presentationTimeStamp: CMTime(value: Int64(block * frames), timescale: Int32(rate)),
                    decodeTimeStamp: .invalid
                )
                var size = channels * 4
                var sampleBuffer: CMSampleBuffer?
                guard CMSampleBufferCreateReady(
                    allocator: kCFAllocatorDefault,
                    dataBuffer: buffer,
                    formatDescription: description,
                    sampleCount: frames,
                    sampleTimingEntryCount: 1,
                    sampleTimingArray: &timing,
                    sampleSizeEntryCount: 1,
                    sampleSizeArray: &size,
                    sampleBufferOut: &sampleBuffer
                ) == noErr, let sampleBuffer, audioInput.append(sampleBuffer) else {
                    throw writer.error ?? CocoaError(.fileWriteUnknown)
                }
            }
            if video {
                while !videoInput.isReadyForMoreMediaData {
                    try Task.checkCancellation()
                    try await Task.sleep(for: .milliseconds(1))
                    if writer.status == .failed { throw writer.error ?? CocoaError(.fileWriteUnknown) }
                }
                var pixel: CVPixelBuffer?
                guard CVPixelBufferCreate(kCFAllocatorDefault, 16, 16, kCVPixelFormatType_32ARGB, nil, &pixel) == kCVReturnSuccess,
                      let pixel else { throw CocoaError(.fileWriteUnknown) }
                CVPixelBufferLockBaseAddress(pixel, [])
                if let base = CVPixelBufferGetBaseAddress(pixel) {
                    base.initializeMemory(as: UInt8.self, repeating: 0, count: CVPixelBufferGetDataSize(pixel))
                }
                CVPixelBufferUnlockBaseAddress(pixel, [])
                guard adaptor.append(pixel, withPresentationTime: CMTime(value: Int64(block), timescale: 10)) else {
                    throw writer.error ?? CocoaError(.fileWriteUnknown)
                }
            }
        }
        if audio { audioInput.markAsFinished() }
        if video { videoInput.markAsFinished() }
        writer.endSession(atSourceTime: CMTime(value: Int64(seconds), timescale: 1))
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
    }
}
