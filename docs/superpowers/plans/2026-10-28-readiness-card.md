# Readiness card — plan for Codex Luna (2026-10-28)

Spec: `docs/superpowers/specs/2026-10-28-readiness-card-design.md`
Mockup: `docs/design/proposal-readiness.html`

Every decision is made below and every code block was compiled and tested by
Claude in a draft worktree (full suite passed: 1,351 VoiceCore, 30 MCPKit,
114 BugVoiceMac). Copy the code exactly. Do not redesign, rename or widen scope.
If something here does not match the code, stop and report instead of improvising.

## Ground rules

- Read `AGENTS.md` first. Swift Testing (`@Test`, `#expect`), not XCTest.
- Work on a new branch: `git switch -c feat/readiness-card` from `main`.
- For each task: write the test, run it and see it fail (or fail to compile), then
  add the code, run `swift test` (whole suite must pass), then commit. One commit
  per task, message as given, ending with a blank line and
  `Co-Authored-By: Codex <noreply@openai.com>`.
- The pre-commit hook bumps the build number in `App/Info.plist`; let it.
- Do not launch the app, do not send synthetic input, do not push or merge.
- Touch only the files named below.

## Task 1 — readiness rows in VoiceCore

Create `Tests/VoiceCoreTests/ReadinessTests.swift`:

```swift
import Testing
@testable import VoiceCore

@Suite struct ReadinessTests {
    func rows(missing: [String] = [], hotkey: Bool = true, speech: MenuSpeechState = .ready,
              onDevice: String? = "large-v3 turbo", server: String? = nil,
              cleanup: CleanupCheck = .reachable(name: "Qwen")) -> [ReadinessRow] {
        Readiness.rows(missingPermissions: missing, hotkeyActive: hotkey, hotkey: "Right Control",
                       speech: speech, onDeviceModel: onDevice, serverURL: server, cleanup: cleanup)
    }

    @Test func allGoodIsReady() {
        let r = rows()
        #expect(r.map(\.kind) == [.permissions, .hotkey, .speech, .cleanup])
        #expect(r.map(\.tone) == [.ok, .ok, .ok, .ok])
        #expect(r.map(\.detail) == [
            "Microphone, Accessibility and Input Monitoring are on",
            "Hold Right Control to speak",
            "large-v3 turbo on this Mac",
            "Qwen, server reachable",
        ])
        #expect(Readiness.isReady(r))
        #expect(Readiness.summary(r) == "Ready to dictate")
        #expect(r.allSatisfy { $0.action == nil })
    }

    @Test func missingPermissionsNameEach() {
        #expect(rows(missing: ["Accessibility"])[0].detail == "Accessibility is off")
        let two = rows(missing: ["Microphone", "Accessibility", "Input Monitoring"])[0]
        #expect(two.detail == "Microphone, Accessibility and Input Monitoring are off")
        #expect(two.tone == .problem)
        #expect(two.action == .openPermissions)
        #expect(two.actionTitle == "Open permissions")
    }

    @Test func inactiveHotkeyOffersRetry() {
        let row = rows(hotkey: false)[1]
        #expect(row.detail == "Right Control is not being watched")
        #expect(row.tone == .problem)
        #expect(row.action == .retryHotkey)
    }

    @Test func speechStates() {
        #expect(rows(speech: .downloading(0.404))[2].detail == "Downloading large-v3 turbo, 40%")
        #expect(rows(speech: .downloading(0.404))[2].tone == .waiting)
        #expect(rows(speech: .loading)[2].tone == .waiting)
        let failed = rows(speech: .failed)[2]
        #expect(failed.detail == "large-v3 turbo failed to load")
        #expect(failed.action == .retrySpeech)
        let server = rows(speech: .failed, onDevice: nil, server: "http://localhost:9000")[2]
        #expect(server.detail == "Speech server at http://localhost:9000")
        #expect(server.tone == .ok)
    }

    @Test func cleanupStates() {
        let off = rows(cleanup: .off)
        #expect(off[3].tone == .off)
        #expect(off[3].action == .openModels)
        #expect(Readiness.isReady(off))
        let unchecked = rows(cleanup: .unchecked(name: "Qwen"))[3]
        #expect(unchecked.detail == "Qwen, not checked yet")
        #expect(unchecked.action == .checkCleanup)
        let failed = rows(cleanup: .failed(name: "Qwen", message: "The key was refused."))[3]
        #expect(failed.detail == "Qwen: The key was refused.")
        #expect(failed.actionTitle == "Check again")
        #expect(rows(cleanup: .local(name: "Apple Intelligence"))[3].tone == .ok)
        #expect(rows(cleanup: .unavailable("Codex was not found on this Mac."))[3].action == .openModels)
    }

    @Test func summaryCountsProblemsAndWaiting() {
        #expect(Readiness.summary(rows(speech: .loading, cleanup: .unchecked(name: "Qwen"))) == "Getting ready")
        #expect(Readiness.summary(rows(hotkey: false)) == "1 item needs attention")
        #expect(Readiness.summary(rows(missing: ["Microphone"], hotkey: false)) == "2 items need attention")
        #expect(!Readiness.isReady(rows(speech: .loading)))
    }
}
```

Run `swift test --filter ReadinessTests`; it must fail to compile.

Create `Sources/VoiceCore/Readiness.swift`:

```swift
import Foundation

/// How a readiness row reads: fine, still getting ready, needs a fix, or
/// turned off on purpose.
public enum ReadinessTone: Equatable, Sendable { case ok, waiting, problem, off }

/// What a readiness row's button does.
public enum ReadinessAction: Equatable, Sendable { case openPermissions, retryHotkey, retrySpeech, checkCleanup, openModels }

/// The dictation cleanup model as the readiness card sees it.
public enum CleanupCheck: Equatable, Sendable {
    /// Cleanup is set to None: raw text is pasted.
    case off
    /// The connection has not been checked this session.
    case unchecked(name: String)
    case reachable(name: String)
    case failed(name: String, message: String)
    /// Apple Intelligence or a coding CLI: nothing to reach over the network.
    case local(name: String)
    /// The chosen model cannot be used, with the reason.
    case unavailable(String)
}

public struct ReadinessRow: Equatable, Sendable, Identifiable {
    public enum Kind: String, Sendable { case permissions, hotkey, speech, cleanup }
    public var kind: Kind
    public var title: String
    public var detail: String
    public var tone: ReadinessTone
    public var action: ReadinessAction?
    public var actionTitle: String?
    public var id: String { kind.rawValue }
}

/// The four things dictation needs, in the order they are checked.
public enum Readiness {
    public static func rows(missingPermissions: [String], hotkeyActive: Bool, hotkey: String,
                            speech: MenuSpeechState, onDeviceModel: String?, serverURL: String?,
                            cleanup: CleanupCheck) -> [ReadinessRow] {
        [permissions(missingPermissions), hotkeyRow(active: hotkeyActive, hotkey: hotkey),
         speechRow(speech, onDeviceModel: onDeviceModel, serverURL: serverURL), cleanupRow(cleanup)]
    }

    /// Ready when nothing needs a fix or is still loading. Cleanup off counts as ready.
    public static func isReady(_ rows: [ReadinessRow]) -> Bool {
        rows.allSatisfy { $0.tone == .ok || $0.tone == .off }
    }

    public static func summary(_ rows: [ReadinessRow]) -> String {
        if isReady(rows) { return "Ready to dictate" }
        let problems = rows.filter { $0.tone == .problem }.count
        if problems == 0 { return "Getting ready" }
        return problems == 1 ? "1 item needs attention" : "\(problems) items need attention"
    }

    static func permissions(_ missing: [String]) -> ReadinessRow {
        guard !missing.isEmpty else {
            return ReadinessRow(kind: .permissions, title: "Permissions",
                                detail: "Microphone, Accessibility and Input Monitoring are on", tone: .ok)
        }
        let names = missing.count == 1
            ? missing[0]
            : missing.dropLast().joined(separator: ", ") + " and " + missing[missing.count - 1]
        return ReadinessRow(kind: .permissions, title: "Permissions",
                            detail: "\(names) \(missing.count == 1 ? "is" : "are") off", tone: .problem,
                            action: .openPermissions, actionTitle: "Open permissions")
    }

    static func hotkeyRow(active: Bool, hotkey: String) -> ReadinessRow {
        active
            ? ReadinessRow(kind: .hotkey, title: "Hotkey", detail: "Hold \(hotkey) to speak", tone: .ok)
            : ReadinessRow(kind: .hotkey, title: "Hotkey", detail: "\(hotkey) is not being watched", tone: .problem,
                           action: .retryHotkey, actionTitle: "Try again")
    }

    static func speechRow(_ speech: MenuSpeechState, onDeviceModel: String?, serverURL: String?) -> ReadinessRow {
        guard let onDeviceModel else {
            return ReadinessRow(kind: .speech, title: "Speech model",
                                detail: "Speech server at \(serverURL ?? "no address")", tone: .ok)
        }
        switch speech {
        case .ready:
            return ReadinessRow(kind: .speech, title: "Speech model", detail: "\(onDeviceModel) on this Mac", tone: .ok)
        case .downloading(let fraction):
            return ReadinessRow(kind: .speech, title: "Speech model",
                                detail: "Downloading \(onDeviceModel), \(Int(fraction * 100))%", tone: .waiting)
        case .loading:
            return ReadinessRow(kind: .speech, title: "Speech model", detail: "Loading \(onDeviceModel)", tone: .waiting)
        case .failed:
            return ReadinessRow(kind: .speech, title: "Speech model", detail: "\(onDeviceModel) failed to load",
                                tone: .problem, action: .retrySpeech, actionTitle: "Retry")
        }
    }

    static func cleanupRow(_ cleanup: CleanupCheck) -> ReadinessRow {
        switch cleanup {
        case .off:
            return ReadinessRow(kind: .cleanup, title: "Cleanup model", detail: "Off, raw text is pasted", tone: .off,
                                action: .openModels, actionTitle: "Choose a model")
        case .unchecked(let name):
            return ReadinessRow(kind: .cleanup, title: "Cleanup model", detail: "\(name), not checked yet", tone: .waiting,
                                action: .checkCleanup, actionTitle: "Check")
        case .reachable(let name):
            return ReadinessRow(kind: .cleanup, title: "Cleanup model", detail: "\(name), server reachable", tone: .ok)
        case .failed(let name, let message):
            return ReadinessRow(kind: .cleanup, title: "Cleanup model", detail: "\(name): \(message)", tone: .problem,
                                action: .checkCleanup, actionTitle: "Check again")
        case .local(let name):
            return ReadinessRow(kind: .cleanup, title: "Cleanup model", detail: name, tone: .ok)
        case .unavailable(let reason):
            return ReadinessRow(kind: .cleanup, title: "Cleanup model", detail: reason, tone: .problem,
                                action: .openModels, actionTitle: "Open Models")
        }
    }
}
```

Run `swift test` (whole suite).

Commit: `feat(core): readiness rows for permissions, hotkey, speech and cleanup`

## Task 2 — settings search finds the card

In `Tests/VoiceCoreTests/GlobalSearchTests.swift`:

1. In `settingsListIsExact`, change `#expect(GlobalSearch.settingsEntries.count == 44)`
   to `#expect(GlobalSearch.settingsEntries.count == 45)`, and change the `.last`
   expectation to:

   ```swift
        #expect(GlobalSearch.settingsEntries.last == SettingsSearchEntry(label: "Ready to dictate", section: "general", keywords: ["setup", "status", "permissions", "readiness"]))
   ```

2. In the `settingsKeywordsFindTheSection` arguments, after
   `("retry", "Failed recordings", "storage"),` add:

   ```swift
        ("setup", "Ready to dictate", "general"),
   ```

Run `swift test --filter GlobalSearchTests`; it must fail.

In `Sources/VoiceCore/GlobalSearch.swift`, after the line
`.init(label: "Known voices", section: "meetings", keywords: ["speaker", "voice"]),`
add:

```swift
        .init(label: "Ready to dictate", section: "general", keywords: ["setup", "status", "permissions", "readiness"]),
```

Run `swift test`.

Commit: `feat(core): settings search finds the readiness card`

## Task 3 — the card in Settings › General

App code; no unit test (the logic is covered by Task 1).

Create `Sources/BugVoice/AppModel+Readiness.swift`:

```swift
import BugVoiceMac
import Foundation
import VoiceCore

/// The Settings › General readiness card: what dictation needs, and how to fix it.
extension AppModel {
    var readinessRows: [ReadinessRow] {
        let names: [(PermissionKind, String)] = [
            (.microphone, "Microphone"), (.accessibility, "Accessibility"), (.inputMonitoring, "Input Monitoring"),
        ]
        let onDevice = settings.speech.engine == .whisperKit
        return Readiness.rows(
            missingPermissions: names.filter { permissionStatus[$0.0] == false }.map(\.1),
            hotkeyActive: hotkeyActive,
            hotkey: settings.hotkey.spokenName,
            speech: readinessSpeech,
            onDeviceModel: onDevice ? speechModelName : nil,
            serverURL: onDevice ? nil : settings.speech.serverBaseURL,
            cleanup: cleanupCheck
        )
    }

    /// The connection dictation cleanup uses, if it uses one.
    var dictationConnection: ModelConnection? {
        if case .connection(let connection, _, _, _, _) = plan(for: .dictation) { return connection }
        return nil
    }

    func runReadinessAction(_ action: ReadinessAction) {
        switch action {
        case .openPermissions: openPermissionsWindow()
        case .retryHotkey: dictation?.retryHotkey()
        case .retrySpeech: retrySpeech()
        case .checkCleanup:
            guard let connection = dictationConnection else { return }
            Task { await testConnection(connection) }
        case .openModels: settingsTab = .models
        }
    }

    private var readinessSpeech: MenuSpeechState {
        switch speechState {
        case .downloading(let fraction): .downloading(fraction)
        case .loading, .notLoaded: .loading
        case .failed: .failed
        case .ready: .ready
        }
    }

    private var speechModelName: String {
        let id = settings.speech.whisperModel
        let label = SpeechTab.whisperModels.first { $0.0 == id }?.1
        return label?.components(separatedBy: " · ").first ?? id
    }

    private var cleanupCheck: CleanupCheck {
        let plan = plan(for: .dictation)
        switch plan {
        case .none:
            return .off
        case .unavailable(let reason):
            return .unavailable(reason)
        case .connection(let connection, _, _, _, _):
            let name = plan.shortName ?? connection.name
            switch connectionStatus[connection.id] {
            case nil: return .unchecked(name: name)
            case .reachable: return .reachable(name: name)
            case .failed(let message): return .failed(name: name, message: message)
            }
        case .appleIntelligence, .cli:
            return .local(name: plan.shortName ?? "")
        }
    }
}
```

Create `Sources/BugVoice/UI/Settings/ReadinessCard.swift`:

```swift
import SwiftUI
import VoiceCore

/// Top of Settings › General: each thing dictation needs, with a fix button.
struct ReadinessCard: View {
    @Environment(AppearanceStore.self) private var store
    @Bindable var model: AppModel

    var body: some View {
        let rows = model.readinessRows
        SettingsCard(title: Readiness.summary(rows)) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 { Divider() }
                HStack(alignment: .firstTextBaseline, spacing: LayoutTokens.spacing[2]) {
                    Circle().fill(color(row.tone)).frame(width: 9, height: 9)
                        .accessibilityLabel(label(row.tone))
                    VStack(alignment: .leading, spacing: 0) {
                        Text(row.title)
                        Text(row.detail).bvFont(.footnote).foregroundStyle(.bvSecondary).textSelection(.enabled)
                    }
                    Spacer(minLength: LayoutTokens.spacing[2])
                    if let action = row.action, let title = row.actionTitle {
                        Button(title) { model.runReadinessAction(action) }
                    }
                }
            }
        }
        // Check the cleanup connection once when the card first shows.
        .task {
            if let connection = model.dictationConnection, model.connectionStatus[connection.id] == nil {
                await model.testConnection(connection)
            }
        }
    }

    private func color(_ tone: ReadinessTone) -> Color {
        switch tone {
        case .ok: store.theme.success
        case .waiting: store.theme.secondaryText.opacity(0.5)
        case .problem: store.theme.warning
        case .off: store.theme.secondaryText.opacity(0.35)
        }
    }

    /// The dot's meaning for VoiceOver, since color alone carries it.
    private func label(_ tone: ReadinessTone) -> String {
        switch tone {
        case .ok: "Ready"
        case .waiting: "Not ready yet"
        case .problem: "Needs attention"
        case .off: "Off"
        }
    }
}
```

In `Sources/BugVoice/UI/Settings/GeneralTab.swift`, change:

```swift
        SettingsScroll {
            SettingsCard {
                SettingsRow(title: "Hotkey") {
```

to:

```swift
        SettingsScroll {
            ReadinessCard(model: model)
            SettingsCard {
                SettingsRow(title: "Hotkey") {
```

Run `swift build` (no errors, no warnings) and `swift test`.

Commit: `feat(app): readiness card at the top of Settings › General`

## Task 4 — docs

In `AGENTS.md`, under "Key documents", after the line starting
`- Failed dictations spec:` add:

```
- Readiness card spec: `docs/superpowers/specs/2026-10-28-readiness-card-design.md` (mockup: `docs/design/proposal-readiness.html`)
- Readiness card plan: `docs/superpowers/plans/2026-10-28-readiness-card.md`
```

Commit (include the spec, mockup and this plan if they are untracked):
`docs: readiness card spec, mockup and plan`

## Finish

1. `swift test` — whole suite passes.
2. `Scripts/build-app.sh` — builds and signs. Do not run the app.
3. Do not merge or push. Report: branch name, the four commit hashes with
   messages, test totals from the last `swift test`, and any place where the code
   did not match this plan.
