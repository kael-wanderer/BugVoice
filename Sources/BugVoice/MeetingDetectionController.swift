import AppKit
import BugVoiceMac
import SwiftUI
import VoiceCore

/// Watches which apps use the microphone and offers to start or stop a
/// meeting recording. It never starts or stops one by itself.
@MainActor
final class MeetingDetectionController {
    /// Seconds between looks at the Core Audio process list.
    static let pollInterval: TimeInterval = 2

    private unowned let model: AppModel
    private var detector = MeetingDetector(ownPID: ProcessInfo.processInfo.processIdentifier)
    private var timer: Timer?
    private let popup = MeetingDetectionPopup()

    init(model: AppModel) {
        self.model = model
    }

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func hidePopup() {
        popup.hide()
    }

    private func tick() {
        guard let meetings = model.meetings else { return }
        guard model.settings.meetings.detectMeetings else {
            popup.hide()
            return
        }
        let processes: [AudioInputProcess]
        do {
            processes = try AudioInputProcesses.current()
        } catch {
            // Detection stays off for this run; recording by hand still works.
            model.meetingDetectionUnavailable = true
            timer?.invalidate()
            timer = nil
            return
        }
        let recording = meetings.isRecording || meetings.isPaused
        if meetings.isActive, popup.kind == .detected { popup.hide() }
        let events = detector.update(
            processes: processes,
            now: Date(),
            isRecording: meetings.isActive,
            recordingApp: recording ? meetings.detected?.bundleID : nil,
            muted: Set(model.settings.meetings.mutedMeetingApps)
        )
        for event in events {
            switch event {
            case .detected(let candidate):
                popup.showDetected(
                    candidate,
                    onStart: { [weak self] in
                        self?.popup.hide()
                        Task { await self?.model.meetings?.start(detected: candidate) }
                    },
                    onMute: { [weak self] in
                        self?.popup.hide()
                        self?.mute(candidate.bundleID)
                    }
                )
            case .ended(let bundleID):
                guard recording, meetings.detected?.bundleID == bundleID else { continue }
                let name = meetings.detected?.appName ?? bundleID
                popup.showEnded(appName: name, elapsed: meetings.elapsed) { [weak self] in
                    self?.popup.hide()
                    Task { await self?.model.meetings?.stop() }
                }
            }
        }
    }

    private func mute(_ bundleID: String) {
        guard !model.settings.meetings.mutedMeetingApps.contains(bundleID) else { return }
        model.settings.meetings.mutedMeetingApps.append(bundleID)
    }

    /// The display that shows the frontmost app's front window, else the one with the pointer.
    static func frontmostWindowScreen() -> NSScreen? {
        if let screen = AppWindow.developmentScreen() { return screen }
        if let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
           let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
           let primaryHeight = NSScreen.screens.first?.frame.height {
            for info in list where (info[kCGWindowOwnerPID as String] as? Int32) == pid && (info[kCGWindowLayer as String] as? Int) == 0 {
                guard let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                      let rect = CGRect(dictionaryRepresentation: bounds) else { continue }
                // Window bounds count from the top left of the primary display.
                let center = NSPoint(x: rect.midX, y: primaryHeight - rect.midY)
                if let screen = NSScreen.screens.first(where: { $0.frame.contains(center) }) { return screen }
            }
        }
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
    }
}

/// The small "Meeting detected" / "Meeting ended" offer at the top right.
@MainActor
final class MeetingDetectionPopup {
    enum Kind { case detected, ended }

    static let detectedSeconds: TimeInterval = 15
    static let endedSeconds: TimeInterval = 30
    static let size = NSSize(width: 440, height: 64)

    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?
    private(set) var kind: Kind?

    func showDetected(_ candidate: MeetingCandidate, onStart: @escaping () -> Void, onMute: @escaping () -> Void) {
        let subtitle = candidate.title == candidate.appName ? candidate.appName : "\(candidate.appName) · \(candidate.title)"
        show(
            kind: .detected,
            view: MeetingPopupView(
                title: "Meeting detected", subtitle: subtitle, action: "Start recording", actionIsStop: false,
                onAction: onStart, onMute: onMute, onClose: { [weak self] in self?.hide() }
            ),
            seconds: Self.detectedSeconds
        )
    }

    func showEnded(appName: String, elapsed: TimeInterval, onStop: @escaping () -> Void) {
        show(
            kind: .ended,
            view: MeetingPopupView(
                title: "Meeting ended", subtitle: "\(appName) stopped using the mic · \(MeetingTimeText.text(elapsed))",
                action: "Stop recording", actionIsStop: true,
                onAction: onStop, onMute: nil, onClose: { [weak self] in self?.hide() }
            ),
            seconds: Self.endedSeconds
        )
    }

    func hide() {
        hideTask?.cancel()
        hideTask = nil
        kind = nil
        panel?.orderOut(nil)
    }

    private func show(kind: Kind, view: MeetingPopupView, seconds: TimeInterval) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        self.kind = kind
        panel.contentView = NonKeyPopupHostingView(rootView: view)
        if let screen = MeetingDetectionController.frontmostWindowScreen() {
            let visible = screen.visibleFrame
            panel.setFrame(
                NSRect(x: visible.maxX - Self.size.width - 16, y: visible.maxY - Self.size.height - 12,
                       width: Self.size.width, height: Self.size.height),
                display: true
            )
        }
        panel.orderFrontRegardless()
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.setAccessibilityLabel("Meeting offer")
        return panel
    }
}

private final class NonKeyPopupHostingView: NSHostingView<MeetingPopupView> {
    override var acceptsFirstResponder: Bool { false }
}

private struct MeetingPopupView: View {
    let title: String
    let subtitle: String
    let action: String
    let actionIsStop: Bool
    let onAction: () -> Void
    let onMute: (() -> Void)?
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onClose) {
                Image(systemName: "xmark").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Close")
            Image(systemName: "video.fill").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.semibold)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Button(action: onAction) {
                HStack(spacing: 6) {
                    Circle().fill(.red).frame(width: 8, height: 8)
                    Text(action)
                }
            }
            .buttonStyle(.bordered)
            if let onMute {
                Menu {
                    Button("Don't ask for this app", action: onMute)
                } label: {
                    Image(systemName: "chevron.down")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
        .padding(.horizontal, 14)
        .frame(width: MeetingDetectionPopup.size.width, height: MeetingDetectionPopup.size.height)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.15)))
    }
}

/// `m:ss`, or `h:mm:ss` from one hour.
enum MeetingTimeText {
    static func text(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        if total >= 3600 { return String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60) }
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
