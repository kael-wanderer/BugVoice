import AVFoundation
import SwiftUI
import VoiceCore

@MainActor
@Observable
final class MeetingPlayerModel {
    let player = AVPlayer()
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var waveform: [Float] = []
    private(set) var isPlaying = false
    var speed: Float = 1
    @ObservationIgnored private var observer: Any?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var loadedURL: URL?
    @ObservationIgnored private var waveformTask: Task<[Float], Never>?

    init() {
        observer = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.currentTime = max(0, time.seconds) }
        }
    }

    func load(_ url: URL) async {
        guard loadedURL != url else { return }
        loadedURL = url
        player.pause()
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.isPlaying = false }
        }
        currentTime = 0
        isPlaying = false
        do {
            let asset = AVURLAsset(url: url)
            duration = try await asset.load(.duration).seconds
        } catch {
            duration = 0
        }
        waveformTask?.cancel()
        let task = Task.detached(priority: .utility) { Self.readWaveform(url) }
        waveformTask = task
        let bars = await task.value
        if loadedURL == url, !Task.isCancelled { waveform = bars }
    }

    func togglePlayback() {
        if isPlaying { player.pause(); isPlaying = false }
        else { player.playImmediately(atRate: speed); isPlaying = true }
    }

    func seek(to seconds: TimeInterval) {
        let bounded = min(max(0, seconds), max(0, duration))
        player.seek(to: CMTime(seconds: bounded, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = bounded
    }

    func skip(_ seconds: TimeInterval) { seek(to: currentTime + seconds) }

    func setSpeed(_ value: Float) {
        speed = value
        if isPlaying { player.rate = value }
    }

    func stopAndDetach() {
        player.pause()
        isPlaying = false
        waveformTask?.cancel()
        waveformTask = nil
    }

    private nonisolated static func readWaveform(_ url: URL) -> [Float] {
        guard let file = try? AVAudioFile(forReading: url) else { return [] }
        let frames = Int(file.length)
        guard frames > 0 else { return [] }
        let bucketCount = 180
        var bars: [Float] = []
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 16_000) else { return [] }
        for bucket in 0..<bucketCount {
            let start = bucket * frames / bucketCount
            let end = (bucket + 1) * frames / bucketCount
            file.framePosition = AVAudioFramePosition(start)
            var remaining = end - start
            var peak: Float = 0
            while remaining > 0 {
                if Task.isCancelled { return [] }
                let count = min(16_000, remaining)
                do {
                    try file.read(into: buffer, frameCount: AVAudioFrameCount(count))
                } catch {
                    return []
                }
                let samples = Int(buffer.frameLength)
                guard samples > 0 else { return [] }
                if let channel = buffer.floatChannelData?[0] {
                    for index in 0..<samples { peak = max(peak, abs(channel[index])) }
                } else if let channel = buffer.int16ChannelData?[0] {
                    for index in 0..<samples { peak = max(peak, abs(Float(channel[index]) / 32_768)) }
                }
                remaining -= samples
            }
            bars.append(min(1, peak))
        }
        return bars
    }
}

struct MeetingPlayer: View {
    let audioURL: URL
    @Bindable var model: MeetingPlayerModel

    private let speeds: [Float] = [0.75, 1, 1.25, 1.5, 2]

    var body: some View {
        VStack(spacing: 10) {
            waveform
                .frame(height: 54)
                .accessibilityLabel("Scrub meeting waveform")
            HStack(spacing: 12) {
                Button { model.skip(-15) } label: { Image(systemName: "gobackward.15") }.help("Back 15 seconds")
                Button { model.togglePlayback() } label: { Image(systemName: model.isPlaying ? "pause.fill" : "play.fill") }
                    .buttonStyle(.borderedProminent)
                Button { model.skip(15) } label: { Image(systemName: "goforward.15") }.help("Forward 15 seconds")
                Text("\(clock(model.currentTime)) / \(clock(model.duration))")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Spacer()
                Picker("Playback speed", selection: Binding(get: { model.speed }, set: model.setSpeed)) {
                    ForEach(speeds, id: \.self) { speed in Text("\(speed, format: .number.precision(.fractionLength(2)))×").tag(speed) }
                }
                .labelsHidden().frame(width: 86)
            }
        }
        .task(id: audioURL) { await model.load(audioURL) }
        .onDisappear { model.stopAndDetach() }
    }

    private var waveform: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                guard !model.waveform.isEmpty else { return }
                let mid = size.height / 2
                let width = size.width / CGFloat(model.waveform.count)
                for (index, peak) in model.waveform.enumerated() {
                    let x = CGFloat(index) * width
                    let height = max(2, CGFloat(peak) * size.height * 0.9)
                    let rect = CGRect(x: x, y: mid - height / 2, width: max(1, width * 0.62), height: height)
                    context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(x / size.width <= progress ? .accentColor : .secondary.opacity(0.38)))
                }
                var line = Path()
                let x = CGFloat(progress) * size.width
                line.move(to: CGPoint(x: x, y: 0)); line.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(line, with: .color(.accentColor), lineWidth: 1)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                let fraction = min(1, max(0, value.location.x / max(1, geometry.size.width)))
                model.seek(to: model.duration * fraction)
            })
        }
    }

    private var progress: Double { model.duration > 0 ? min(1, model.currentTime / model.duration) : 0 }

    private func clock(_ value: TimeInterval) -> String {
        let seconds = max(0, Int(value))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
