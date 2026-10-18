import AppKit
import SwiftUI
import VoiceCore

extension MeetingSpeaker {
    /// The saved voice waiting for Yes or No, while suggestions are on and the voice is still saved.
    func pendingSuggestion(enabled: Bool, known: [KnownVoice]) -> String? {
        guard enabled, name == nil, let suggested = suggestion?.name,
              known.contains(where: { $0.name.caseInsensitiveCompare(suggested) == .orderedSame }) else { return nil }
        return suggested
    }
}

struct MeetingSpeakersRow: View {
    @Environment(AppearanceStore.self) private var store
    let meeting: MeetingManifest
    @Environment(AppModel.self) private var model
    @State private var pendingPeople: Int?
    /// The number of people asked for last, so Try again repeats it.
    @State private var requestedPeople: Int?
    @State private var editingID: String?
    @State private var draft = ""
    @State private var editError: String?
    @State private var saving = false
    @State private var dismissedChanges: [String]?
    @State private var regenerating = false
    @State private var generationError: String?
    @FocusState private var nameFocused: Bool

    var body: some View {
        // Speakers are split once the transcript is final; while recording lines stay You and Others.
        if meeting.state == .ready { content }
    }

    /// A split that was running when BugVoice quit has no task left; it shows as failed.
    private var splitState: SpeakerSplitState {
        meeting.speakerSplit == .running && model.speakerTasks[meeting.id] == nil ? .failed("") : meeting.speakerSplit
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: LayoutTokens.spacing[1]) {
            switch splitState {
            case .running:
                HStack(spacing: LayoutTokens.spacing[1]) {
                    ProgressView().controlSize(.mini)
                    Text("Finding speakers…").foregroundStyle(.bvSecondary)
                }
            case .failed:
                HStack {
                    Text("Speakers could not be found.").foregroundStyle(.bvSecondary)
                    Button("Try again") { find(requestedPeople) }
                }
            case .none:
                if !meeting.segments.isEmpty {
                    HStack {
                        Text("This meeting was recorded before speakers were split.")
                        Spacer(minLength: 0)
                        Button("Find speakers") { find(nil) }.buttonStyle(.borderedProminent)
                    }
                    .padding(LayoutTokens.spacing[1])
                    .background(store.theme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: LayoutTokens.controlRadius))
                }
            case .done:
                speakerRow
                if let pendingPeople {
                    HStack(spacing: LayoutTokens.spacing[1]) {
                        Text("Split again for \(pendingPeople) people? Your changes to single lines are cleared. Names stay on the voices that keep them.")
                        Spacer(minLength: 0)
                        Button("Split again") { find(pendingPeople); self.pendingPeople = nil }
                            .buttonStyle(.borderedProminent)
                        Button("Cancel") { self.pendingPeople = nil }
                    }
                    .padding(LayoutTokens.spacing[1])
                    .overlay(RoundedRectangle(cornerRadius: LayoutTokens.controlRadius).stroke(store.theme.warning, lineWidth: 1))
                }
            }
            if let editError { Text(editError).foregroundStyle(.bvWarning) }
            if MeetingSpeakers.namesChangedSinceSummary(meeting), dismissedChanges != changeStamp {
                HStack(spacing: LayoutTokens.spacing[1]) {
                    Text("Names changed. The summary still uses the old names.")
                    Spacer(minLength: 0)
                    Button("Regenerate summary") { regenerate() }
                        .buttonStyle(.borderedProminent)
                        .disabled(regenerating || splitState == .running)
                    Button("Not now") { dismissedChanges = changeStamp }
                }
                .padding(LayoutTokens.spacing[1])
                .background(store.theme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: LayoutTokens.controlRadius))
            }
            if let generationError { Text(generationError).foregroundStyle(.bvWarning) }
        }
        .bvFont(.footnote)
        .controlSize(.small)
        .padding(.vertical, LayoutTokens.spacing[1])
        .onChange(of: nameFocused) { _, focused in if !focused { saveName() } }
        .onChange(of: meeting.id) { _, _ in
            editingID = nil; pendingPeople = nil; requestedPeople = nil; editError = nil; dismissedChanges = nil
        }
    }

    private var changeStamp: [String] {
        meeting.speakers.map { "\($0.id):\($0.name ?? MeetingSpeakers.defaultName(for: $0.id))" }
            + meeting.segments.map { "\($0.id):\($0.speakerID ?? "")" }
    }

    private var speakerRow: some View {
        FlowLayout(spacing: LayoutTokens.spacing[1]) {
            peopleControl
            Divider().frame(width: 1, height: 18)
            chips
        }
        .padding(.horizontal, LayoutTokens.spacing[1]).padding(.vertical, LayoutTokens.spacing[1])
        .background(store.theme.card, in: RoundedRectangle(cornerRadius: LayoutTokens.controlRadius))
        .overlay(RoundedRectangle(cornerRadius: LayoutTokens.controlRadius).stroke(store.theme.separator, lineWidth: 0.5))
        .disabled(saving)
    }

    private var peopleControl: some View {
        // Steps from the number waiting for Split again, so 4 to 2 is two clicks and one confirm.
        let count = pendingPeople ?? MeetingSpeakers.people(in: meeting)
        let range = MeetingSpeakers.peopleRange(in: meeting)
        return HStack(spacing: LayoutTokens.spacing[0]) {
            Text("People in this meeting").foregroundStyle(.bvSecondary).fixedSize()
            Button("−") { step(to: count - 1, in: range) }
                .disabled(count <= range.lowerBound)
                .accessibilityLabel("Fewer people")
            Text("\(count)").monospacedDigit().fontWeight(.semibold)
            Button("+") { step(to: count + 1, in: range) }
                .disabled(count >= range.upperBound)
                .accessibilityLabel("More people")
        }
    }

    /// Back at the current number there is nothing to split again.
    private func step(to people: Int, in range: ClosedRange<Int>) {
        let people = min(range.upperBound, max(range.lowerBound, people))
        pendingPeople = people == MeetingSpeakers.people(in: meeting) ? nil : people
    }

    private var orderedSpeakers: [MeetingSpeaker] {
        meeting.speakers.sorted { a, b in
            if a.id == MeetingSpeakers.youID { return b.id != MeetingSpeakers.youID }
            if b.id == MeetingSpeakers.youID { return false }
            let firstA = meeting.segments.filter { $0.speakerID == a.id }.map(\.start).min() ?? .infinity
            let firstB = meeting.segments.filter { $0.speakerID == b.id }.map(\.start).min() ?? .infinity
            return firstA == firstB ? a.id < b.id : firstA < firstB
        }
    }

    private var chips: some View {
        Group {
            Text("Speakers").foregroundStyle(.bvSecondary)
            ForEach(orderedSpeakers) { speaker in
                HStack(spacing: LayoutTokens.spacing[0]) {
                    Circle().fill(SpeakerColors.color(speaker.colorIndex)).frame(width: 8, height: 8)
                    if editingID == speaker.id {
                        TextField("", text: $draft)
                            .textFieldStyle(.roundedBorder).frame(width: store.scaled(90))
                            .focused($nameFocused)
                            .accessibilityLabel("Name for \(display(speaker))")
                            .onSubmit { saveName() }
                            .onExitCommand { editingID = nil; nameFocused = false; editError = nil }
                    } else if let suggested = speaker.pendingSuggestion(enabled: suggesting, known: model.knownVoices) {
                        Text("\(suggested)?")
                        Button("Yes") { decide(.accept(speakerID: speaker.id)) }
                            .buttonStyle(.borderedProminent).controlSize(.mini)
                            .accessibilityLabel("Yes, this is \(suggested)")
                        Button("No") { decide(.decline(speakerID: speaker.id)) }
                            .controlSize(.mini)
                            .accessibilityLabel("No, this is not \(suggested)")
                    } else {
                        Button(display(speaker)) {
                            if editingID != nil { saveName() }
                            editingID = speaker.id; draft = display(speaker); editError = nil; nameFocused = true
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Rename this speaker on every line")
                    }
                }
                .fixedSize()
                .padding(.horizontal, LayoutTokens.spacing[1]).padding(.vertical, LayoutTokens.spacing[0])
                .background(store.theme.hover.opacity(0.20), in: Capsule())
                .overlay {
                    if speaker.pendingSuggestion(enabled: suggesting, known: model.knownVoices) != nil {
                        Capsule().stroke(store.theme.accent, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    } else {
                        Capsule().stroke(store.theme.separator, lineWidth: 0.5)
                    }
                }
            }
        }
    }

    private func display(_ speaker: MeetingSpeaker) -> String { speaker.name ?? MeetingSpeakers.defaultName(for: speaker.id) }
    private var suggesting: Bool { model.settings.meetings.suggestKnownVoices }
    private func decide(_ edit: MeetingSpeakers.Edit) {
        guard meeting.speakerSplit == .done, !saving else { return }
        saving = true
        Task {
            if case let .duplicateName(name) = await model.editMeetingSpeakers(id: meeting.id, edit: edit) {
                editError = "\(name) is already a speaker."
            }
            saving = false
        }
    }
    private func find(_ people: Int?) {
        requestedPeople = people
        Task { await model.findSpeakers(id: meeting.id, people: people) }
    }
    private func saveName() {
        guard meeting.speakerSplit != .running else { editingID = nil; return }
        guard let id = editingID, !saving else { return }
        let name = draft
        editingID = nil; nameFocused = false; saving = true
        Task {
            let error = await model.editMeetingSpeakers(id: meeting.id, edit: .rename(speakerID: id, name: name))
            if case let .duplicateName(name) = error { editError = "\(name) is already a speaker." }
            saving = false
        }
    }
    private func regenerate() {
        regenerating = true; generationError = nil
        Task {
            defer { regenerating = false }
            do {
                _ = try await model.generateMeetingText(id: meeting.id, kind: .summary) { _ in }
                _ = try await model.generateMeetingText(id: meeting.id, kind: .actionItems) { _ in }
            } catch { generationError = "Could not generate text: \(error.localizedDescription)" }
        }
    }
}

/// Only the speaker label opens a menu; the enclosing page owns seeking on time and text.
struct MeetingSpeakerLineMenu: View {
    @Environment(AppearanceStore.self) private var store
    let meeting: MeetingManifest
    let segment: MeetingSegment
    @Environment(AppModel.self) private var model
    @State private var newPerson = false
    @State private var draft = ""
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        Menu {
            ForEach(meeting.speakers) { speaker in
                Button { edit(.assign(segmentID: segment.id, speakerID: speaker.id)) } label: {
                    Label {
                        Text(speaker.name ?? MeetingSpeakers.defaultName(for: speaker.id))
                    } icon: { SpeakerColors.dot(speaker.colorIndex) }
                }
            }
            Divider()
            Button("New person…") { draft = ""; error = nil; newPerson = true }
        } label: {
            Text(label)
                .bvFont(.footnote)
                .underline(true, pattern: .dot)
                .foregroundStyle(color)
                .frame(width: store.scaled(78), alignment: .leading)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .disabled(meeting.speakerSplit != .done)
        .onChange(of: meeting.speakerSplit) { _, state in if state == .running { newPerson = false } }
        .popover(isPresented: $newPerson) {
            VStack(alignment: .leading, spacing: LayoutTokens.spacing[1]) {
                TextField("New person…", text: $draft).textFieldStyle(.roundedBorder)
                    .focused($focused).onSubmit { createPerson() }
                    .onExitCommand { newPerson = false }
                if let error { Text(error).bvFont(.footnote).foregroundStyle(.bvWarning) }
            }
            .padding(LayoutTokens.spacing[2]).frame(width: store.scaled(210))
            .onAppear { focused = true }
        }
    }
    /// "Dani?" while the line's speaker waits for Yes or No; export and prompts keep Other N.
    private var label: String {
        let speaker = meeting.speakers.first { $0.id == segment.speakerID }
        if let suggested = speaker?.pendingSuggestion(enabled: model.settings.meetings.suggestKnownVoices, known: model.knownVoices) { return "\(suggested)?" }
        return segment.speaker
    }
    private var color: Color {
        if let speaker = meeting.speakers.first(where: { $0.id == segment.speakerID }) { return SpeakerColors.color(speaker.colorIndex) }
        return segment.track == .mic ? store.theme.accent : store.theme.secondaryText
    }
    private func createPerson() {
        guard !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        edit(.newPerson(segmentID: segment.id, name: draft))
    }
    private func edit(_ change: MeetingSpeakers.Edit) {
        guard meeting.speakerSplit == .done else { return }
        Task {
            if case let .duplicateName(name) = await model.editMeetingSpeakers(id: meeting.id, edit: change) {
                error = "\(name) is already a speaker."
            } else { newPerson = false }
        }
    }
}
