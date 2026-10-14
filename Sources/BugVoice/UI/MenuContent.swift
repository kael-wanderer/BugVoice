import AppKit
import BugVoiceMac
import SwiftUI
import VoiceCore
import WhisperEngine

/// The menu-bar menu (spec section 9).
struct MenuContent: View {
    @Bindable var model: AppModel

    var body: some View {
        status
            .onAppear {
                model.refreshPermissions()
                Task { await model.refreshSpeechState() }
            }
        if let last = model.lastResult, !last.finalText.isEmpty {
            Text("Last · \(last.appName ?? "Unknown") · \(last.startedAt.formatted(date: .omitted, time: .shortened))")
            Text(String(last.finalText.prefix(80)) + (last.finalText.count > 80 ? "…" : ""))
        }
        Button("Paste last") { model.dictation?.pasteLast() }
            .keyboardShortcut("v", modifiers: [.control, .option])
            .disabled(model.lastResult?.finalText.isEmpty ?? true)
        Button("Retry last recording") { model.dictation?.retryLast() }
        Divider()
        meetingControls
        Divider()
        Button("New note") { model.createNoteAndShow() }
            .keyboardShortcut("n", modifiers: [.control, .option])
        Button("Open BugVoice…") { model.openMainWindow(.dictation) }
            .keyboardShortcut("b", modifiers: [.control, .option])
        ForEach(model.unavailableShortcuts, id: \.self) { shortcut in
            Text("\(shortcut): used by another app")
        }
        Divider()
        Toggle("Clean up with language model", isOn: $model.settings.cleanupEnabled)
        Toggle("Hands-free mode (double-tap)", isOn: $model.settings.handsFreeEnabled)
        Picker("Language", selection: $model.settings.speech.language) {
            Text("Auto").tag(SpeechLanguage.auto)
            Text("Vietnamese").tag(SpeechLanguage.vi)
            Text("English").tag(SpeechLanguage.en)
        }
        Picker("Text model", selection: $model.settings.textModel.provider) {
            Text("\(model.settings.textModel.model) (OpenAI-compatible)").tag(TextModelProvider.openAICompatible)
            Text("Anthropic-compatible").tag(TextModelProvider.anthropicCompatible)
            Text("Apple Intelligence").tag(TextModelProvider.appleIntelligence)
            Text("None").tag(TextModelProvider.none)
        }
        Divider()
        Button("Meetings…") { model.openMainWindow(.meetings) }
        Button("Notes…") { model.openMainWindow(.notes) }
        Button("Settings…") { model.openMainWindow(.settings) }.keyboardShortcut(",")
        Button("Permissions…") { model.openPermissionsWindow() }
        Button("Open data folder") { NSWorkspace.shared.open(model.paths.root) }
        Divider()
        Button("Quit BugVoice") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }


    @ViewBuilder private var meetingControls: some View {
        if model.meetings?.isTranscribing == true {
            Text("Transcribing meeting…")
        } else if model.meetings?.isRecording == true {
            Button("Pause meeting") { Task { await model.meetings?.pause() } }
            Button("Mark moment") { Task { await model.meetings?.mark() } }
            Button("Stop meeting") { Task { await model.meetings?.stop() } }
        } else if model.meetings?.isPaused == true {
            Button("Resume meeting") { Task { await model.meetings?.resume() } }
            Button("Mark moment") { Task { await model.meetings?.mark() } }
            Button("Stop meeting") { Task { await model.meetings?.stop() } }
        } else {
            Button("Start meeting recording") { Task { await model.meetings?.start() } }
        }
    }

    /// The speech model matters only while on-device transcription is selected.
    private var onDeviceSpeechState: WhisperKitTranscriber.LoadState? {
        model.settings.speech.engine == .whisperKit ? model.speechState : nil
    }

    @ViewBuilder var status: some View {
        if !model.permissionsGranted {
            Button("Needs permissions — fix…") { model.openPermissionsWindow() }
        } else if SecureInputMonitor.isActive {
            Text("Secure input on (\(SecureInputMonitor.owningAppName ?? "another app")) — hotkey paused")
        } else if model.isListening {
            Text("Listening…")
        } else if let speech = onDeviceSpeechState, case .downloading(let fraction) = speech {
            Text("Speech model downloading · \(Int(fraction * 100))%")
        } else if onDeviceSpeechState == .loading {
            Text("Model loading…")
        } else if let speech = onDeviceSpeechState, case .failed = speech {
            Button("Speech model failed to load — retry") { model.retrySpeech() }
        } else if !model.hotkeyActive {
            Button("Hotkey not active — fix…") {
                model.dictation?.retryHotkey()
                if !Permissions.isGranted(.inputMonitoring) { model.openPermissionsWindow() }
            }
        } else {
            Text("Ready · hold \(model.settings.hotkey.displayName) to talk")
        }
    }
}

/// The menu-bar icon. A badge dot means a permission is missing.
struct MenuBarIcon: View {
    var model: AppModel

    var body: some View {
        Image(nsImage: BrandImages.menuBar(badge: !model.permissionsGranted))
    }
}
