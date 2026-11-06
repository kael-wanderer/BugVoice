import SwiftUI
import VoiceCore

/// The onboarding frame: step body, then a footer with "Step N of 7", the
/// step dots, Back, Skip and the primary button.
struct OnboardingView: View {
    @Environment(AppearanceStore.self) private var store
    @Bindable var model: AppModel
    @State private var step: OnboardingStep
    @State private var cleanupDraft = OnboardingCleanupDraft()
    let close: () -> Void

    init(model: AppModel, start: OnboardingStep, close: @escaping () -> Void) {
        self.model = model
        self._step = State(initialValue: start)
        self.close = close
    }

    var body: some View {
        VStack(spacing: 0) {
            OnboardingStepBody(model: model, step: step, cleanupDraft: cleanupDraft, finish: finish, startTour: tour)
                .id(step)
                .padding(LayoutTokens.spacing[4])
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Divider()
            footer
        }
        .frame(width: store.scaled(620), height: store.scaled(460))
    }

    private var footer: some View {
        HStack(spacing: LayoutTokens.spacing[2]) {
            if step != .welcome {
                Text("Step \(step.number) of \(OnboardingStep.allCases.count)")
                    .bvFont(.footnote).foregroundStyle(.bvSecondary)
            }
            Spacer()
            HStack(spacing: 6) {
                ForEach(OnboardingStep.allCases, id: \.self) { item in
                    Group {
                        if item == step { Circle().fill(.bvAccent) } else { Circle().fill(.bvHover) }
                    }
                    .frame(width: 7, height: 7)
                }
            }
            .accessibilityHidden(true)
            Spacer()
            if step.previous != nil {
                Button("Back") { if let previous = step.previous { step = previous } }
            }
            if step == .welcome {
                Button("Skip setup") { finish() }
            } else if step.showsSkip {
                Button("Skip") { advance() }
            }
            if step == .welcome {
                Button("Get started") { advance() }.buttonStyle(.borderedProminent)
            } else if step == .cleanup, cleanupDraft.needsDownload(model), let item = cleanupDraft.builtInModel {
                Button(BuiltInChoices.downloadTitle(item)) { cleanupDraft.startDownload(on: model) }
                    .buttonStyle(.borderedProminent)
            } else if step == .cleanup {
                Button("Continue") { if cleanupDraft.commit(to: model) { advance() } }
                    .buttonStyle(.borderedProminent).disabled(!cleanupDraft.canContinue)
            } else if step.next != nil {
                Button("Continue") { advance() }.buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, LayoutTokens.spacing[4])
        .padding(.vertical, LayoutTokens.spacing[2])
    }

    private func advance() {
        if let next = step.next { step = next }
    }

    private func finish() {
        model.finishOnboarding()
        close()
    }

    private func tour() {
        model.finishOnboarding()
        close()
        model.startTour()
    }
}
