import AVFoundation
import SwiftUI
import VoiceCore

@MainActor @Observable
final class CitationPlayerModel {
    let player: AVPlayer
    let start: Double
    let end: Double
    var time: Double
    var isPlaying = false
    @ObservationIgnored private var boundary: Any?
    @ObservationIgnored private var periodic: Any?
    @ObservationIgnored private(set) var active = true
    @ObservationIgnored private var playGeneration = 0
    @ObservationIgnored private var ended: NSObjectProtocol?

    init(url: URL, start: Double, end: Double) {
        self.start = max(0, start)
        self.end = max(start + 0.01, end)
        time = max(0, start)
        player = AVPlayer(url: url)
        ended = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.pause() }
        }
        boundary = player.addBoundaryTimeObserver(forTimes: [NSValue(time: CMTime(seconds: self.end, preferredTimescale: 600))], queue: .main) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.time = self.end
                self.pause()
            }
        }
        periodic = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, self.active else { return }
                self.time = min(self.end, max(self.start, time.seconds.isFinite ? time.seconds : self.start))
                if time.seconds >= self.end { self.pause() }
                if self.player.currentItem?.status == .failed { self.pause() }
            }
        }
    }

    func play() async {
        guard active else { return }
        playGeneration += 1
        let generation = playGeneration
        let target = time >= end ? start : max(start, time)
        let sought = await player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        guard sought, active, playGeneration == generation, !Task.isCancelled else { return }
        player.play()
        isPlaying = true
    }
    func pause() { playGeneration += 1; player.pause(); isPlaying = false }
    func seek(_ value: Double) {
        time = min(end, max(start, value))
        player.seek(to: CMTime(seconds: time, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        if time >= end { pause() }
    }
    func stop() {
        active = false
        pause()
        if let boundary { player.removeTimeObserver(boundary); self.boundary = nil }
        if let periodic { player.removeTimeObserver(periodic); self.periodic = nil }
        if let ended { NotificationCenter.default.removeObserver(ended); self.ended = nil }
        player.replaceCurrentItem(with: nil)
    }
}

/// The player and its observers are made once, when the view first appears: `State(initialValue:)`
/// would build a new player on every parent redraw and leak the observers of discarded ones.
struct CitationPlayer: View {
    let url: URL
    let start: Double
    let end: Double
    let pauseRequest: UInt64
    @State private var playback: CitationPlayerModel?

    init(url: URL, start: Double, end: Double, pauseRequest: UInt64 = 0) {
        self.url = url
        self.start = start
        self.end = end
        self.pauseRequest = pauseRequest
    }

    var body: some View {
        HStack(spacing: LayoutTokens.spacing[1]) {
            if let playback {
                Button {
                    if playback.isPlaying { playback.pause() }
                    else { Task { await playback.play() } }
                } label: { Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill") }
                .accessibilityLabel(playback.isPlaying ? "Pause" : "Play")
                Slider(value: Binding(get: { playback.time }, set: { playback.seek($0) }), in: playback.start...playback.end)
                    .accessibilityLabel("Citation audio")
                Text("\(AskAnswerView.clock(playback.time)) / \(AskAnswerView.clock(playback.end))")
                    .bvCode(.footnote).monospacedDigit()
            } else {
                Image(systemName: "play.fill").foregroundStyle(.bvSecondary)
                Slider(value: .constant(max(0, start)), in: max(0, start)...max(start + 0.01, end)).disabled(true)
                Text("\(AskAnswerView.clock(max(0, start))) / \(AskAnswerView.clock(max(start + 0.01, end)))")
                    .bvCode(.footnote).monospacedDigit()
            }
        }
        .task {
            let current: CitationPlayerModel
            if let playback, playback.active { current = playback }
            else {
                current = CitationPlayerModel(url: url, start: start, end: end)
                playback = current
            }
            await current.play()
        }
        .onChange(of: pauseRequest) { _, _ in playback?.pause() }
        .onDisappear { playback?.stop() }
    }
}
