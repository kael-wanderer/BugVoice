import BugVoiceMac
import SwiftUI
import VoiceCore

/// The body of one onboarding step.
struct OnboardingStepBody: View {
    @Bindable var model: AppModel
    let step: OnboardingStep
    let advance: () -> Void
    let finish: () -> Void
    let startTour: () -> Void

    var body: some View {
        switch step {
        case .welcome: WelcomeStep()
        case .hotkey: HotkeyStep(model: model)
        case .permissions: PermissionsStep(model: model)
        case .speech: SpeechStep(model: model)
        case .cleanup: PlaceholderStep(title: "Cleanup model", advance: advance) // Task 5 fills this in.
        case .tryIt: PlaceholderStep(title: "Try it", advance: advance) // Task 5 fills this in.
        case .finish: FinishStep(model: model, finish: finish, startTour: startTour)
        }
    }
}

private struct StepHeading: View {
    let title: String
    let lead: String
    var body: some View {
        VStack(alignment: .leading, spacing: LayoutTokens.spacing[1]) {
            Text(title).bvFont(.title1)
            Text(lead).bvFont(.reading).foregroundStyle(.bvSecondary)
        }
    }
}

private struct WelcomeStep: View {
    var body: some View {
        VStack(spacing: LayoutTokens.spacing[2]) {
            Spacer()
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 84, height: 84)
            Text("Talk instead of type").bvFont(.title1)
            Text("Hold a key, speak English, Vietnamese or both, let go. Clean text appears where your cursor is. Everything runs on this Mac.")
                .bvFont(.reading).foregroundStyle(.bvSecondary)
                .multilineTextAlignment(.center).frame(maxWidth: 400)
            Text("Setup takes about 3 minutes.").bvFont(.footnote).foregroundStyle(.bvSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

private struct HotkeyStep: View {
    @Bindable var model: AppModel
    @State private var seenTick = 0
    @State private var keySeen = false

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutTokens.spacing[2]) {
            StepHeading(title: "Pick your talk key",
                        lead: "Hold it while you speak. Let go to paste. Pressing another key while holding cancels.")
            SettingsCard {
                SettingsRow(title: "Talk key") {
                    Picker("Talk key", selection: $model.settings.hotkey) {
                        ForEach(HotkeyKey.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .labelsHidden().fixedSize()
                }
            }
            VStack(spacing: LayoutTokens.spacing[1]) {
                Text("Press \(model.settings.hotkey.spokenName) now")
                    .bvFont(.bodyStrong)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.bvHover, in: RoundedRectangle(cornerRadius: LayoutTokens.cardRadius))
                Text(keySeen ? "Key seen. It works." : " ")
                    .foregroundStyle(.bvSuccess)
            }
            .frame(maxWidth: .infinity)
            if model.permissionStatus[.inputMonitoring] == false {
                Text("BugVoice cannot see keys until Input Monitoring is on. The next step turns it on.")
                    .bvFont(.footnote).foregroundStyle(.bvWarning)
            }
            Text("Other choices: Right Option, Right Command, Fn, or a function key.")
                .bvFont(.footnote).foregroundStyle(.bvSecondary)
        }
        .onAppear { model.hotkeyProbe = { seenTick += 1 } }
        .onDisappear { model.hotkeyProbe = nil }
        .task(id: seenTick) {
            guard seenTick > 0 else { return }
            keySeen = true
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled { keySeen = false }
        }
    }
}

private struct PermissionsStep: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutTokens.spacing[1]) {
            StepHeading(title: "Let BugVoice hear and paste",
                        lead: "macOS asks once for each. You can change them later in System Settings.")
            PermissionsView(model: model)
        }
    }
}

private struct SpeechStep: View {
    @Bindable var model: AppModel

    private var modelLabel: String {
        SpeechTab.whisperModels.first { $0.0 == model.settings.speech.whisperModel }?.1
            ?? model.settings.speech.whisperModel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutTokens.spacing[2]) {
            StepHeading(title: "Download the speech model",
                        lead: "This turns your voice into text. It runs on this Mac, no internet needed after the download.")
            if model.settings.speech.engine != .whisperKit {
                Text("Speech goes to the server set in Settings › Speech. Nothing to download here.")
                    .bvFont(.body).foregroundStyle(.bvSecondary)
            } else {
                VStack(alignment: .leading, spacing: LayoutTokens.spacing[1]) {
                    Text(modelLabel).bvFont(.bodyStrong)
                    status
                }
                .padding(LayoutTokens.spacing[2])
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.bvHover, in: RoundedRectangle(cornerRadius: LayoutTokens.cardRadius))
            }
            Text("Older or 8 GB Macs: choose a smaller model in Settings › Speech later.")
                .bvFont(.footnote).foregroundStyle(.bvSecondary)
        }
    }

    @ViewBuilder private var status: some View {
        switch model.speechState {
        case .notLoaded, .loading:
            ProgressView().controlSize(.small)
            Text("Getting ready. You can continue.").bvFont(.footnote).foregroundStyle(.bvSecondary)
        case .downloading(let fraction):
            ProgressView(value: fraction)
            Text("Downloading, \(Int(fraction * 100))%. You can continue.").bvFont(.footnote).foregroundStyle(.bvSecondary)
        case .ready:
            Text("Ready.").foregroundStyle(.bvSuccess)
        case .failed(let message):
            Text("The download failed: \(message)").bvFont(.footnote).foregroundStyle(.bvWarning)
            Button("Retry") { model.retrySpeech() }
        }
    }
}

private struct PlaceholderStep: View {
    let title: String
    let advance: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: LayoutTokens.spacing[2]) {
            Text(title).bvFont(.title1)
            Text("Press Continue.").bvFont(.reading).foregroundStyle(.bvSecondary)
        }
    }
}

private struct FinishStep: View {
    @Bindable var model: AppModel
    let finish: () -> Void
    let startTour: () -> Void

    var body: some View {
        VStack(spacing: LayoutTokens.spacing[2]) {
            Spacer()
            Image(systemName: "checkmark.circle.fill").bvFont(.stat).foregroundStyle(.bvSuccess)
            Text("You are ready").bvFont(.title1)
            Text("Hold \(model.settings.hotkey.spokenName) in any app to speak. Want a quick look at the rest: Meetings, Scratchpad, Dictionary and Style?")
                .bvFont(.reading).foregroundStyle(.bvSecondary)
                .multilineTextAlignment(.center).frame(maxWidth: 400)
            HStack {
                Button("Skip, start using BugVoice") { finish() }
                Button("Take a 1-minute tour") { startTour() }.buttonStyle(.borderedProminent)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
