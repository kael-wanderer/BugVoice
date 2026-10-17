import AppKit
import SwiftUI
import VoiceCore

/// The six speaker colours from proposal-meeting-speakers.html, adapting to appearance.
enum SpeakerColors {
    static func color(_ index: Int) -> Color {
        let light = [0x3a6ff0, 0x8a57d6, 0xd0731c, 0x1f9a5a, 0xc2407a, 0x2a8fa8]
        let dark = [0x6e93ff, 0xb48cf0, 0xf0a050, 0x4cc98a, 0xf07aae, 0x5cc4dc]
        let slot = ((index % light.count) + light.count) % light.count
        return Color(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark[slot] : light[slot]
            return NSColor(srgbRed: Double((hex >> 16) & 255) / 255,
                           green: Double((hex >> 8) & 255) / 255,
                           blue: Double(hex & 255) / 255, alpha: 1)
        })
    }
}

extension SpeakerColors {
    /// A filled dot as an image, so menus keep its colour.
    static func dot(_ index: Int) -> Image {
        let color = NSColor(color(index))
        let image = NSImage(size: NSSize(width: 10, height: 10), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
        return Image(nsImage: image)
    }
}

extension MeetingSpeaker {
    /// The saved voice waiting for Yes or No, while suggestions are on and the voice is still saved.
    func pendingSuggestion(enabled: Bool, known: [KnownVoice]) -> String? {
        guard enabled, name == nil, let suggested = suggestion?.name,
              known.contains(where: { $0.name.caseInsensitiveCompare(suggested) == .orderedSame }) else { return nil }
        return suggested
    }
}

struct MeetingSpeakersRow: View {
    let meeting: MeetingManifest
    @Environment(AppModel.self) private var model
    @State private var pendingPeople: Int?
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
        VStack(alignment: .leading, spacing: 10) {
            switch splitState {
            case .running:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.mini)
                    Text("Finding speakers…").foregroundStyle(.secondary)
                }
            case .failed:
                HStack {
                    Text("Speakers could not be found.").foregroundStyle(.secondary)
                    Button("Try again") { find(nil) }
                }
            case .none:
                if !meeting.segments.isEmpty {
                    HStack {
                        Text("This meeting was recorded before speakers were split.")
                        Spacer(minLength: 0)
                        Button("Find speakers") { find(nil) }.buttonStyle(.borderedProminent)
                    }
                    .padding(10)
                    .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                }
            case .done:
                speakerRow
                if let pendingPeople {
                    HStack(spacing: 10) {
                        Text("Split again for \(pendingPeople) people? Your changes to single lines are cleared. Names stay on the voices that keep them.")
                        Spacer(minLength: 0)
                        Button("Split again") { find(pendingPeople); self.pendingPeople = nil }
                            .buttonStyle(.borderedProminent)
                        Button("Cancel") { self.pendingPeople = nil }
                    }
                    .padding(10)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.orange, lineWidth: 1))
                }
            }
            if let editError { Text(editError).foregroundStyle(.orange) }
            if MeetingSpeakers.namesChangedSinceSummary(meeting), dismissedChanges != changeStamp {
                HStack(spacing: 10) {
                    Text("Names changed. The summary still uses the old names.")
                    Spacer(minLength: 0)
                    Button("Regenerate summary") { regenerate() }
                        .buttonStyle(.borderedProminent)
                        .disabled(regenerating || splitState == .running)
                    Button("Not now") { dismissedChanges = changeStamp }
                }
                .padding(10)
                .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
            }
            if let generationError { Text(generationError).foregroundStyle(.orange) }
        }
        .font(.system(size: 12))
        .controlSize(.small)
        .padding(.vertical, 8)
        .onChange(of: nameFocused) { _, focused in if !focused { saveName() } }
        .onChange(of: meeting.id) { _, _ in
            editingID = nil; pendingPeople = nil; editError = nil; dismissedChanges = nil
        }
    }

    private var changeStamp: [String] {
        meeting.speakers.map { "\($0.id):\($0.name ?? MeetingSpeakers.defaultName(for: $0.id))" }
            + meeting.segments.map { "\($0.id):\($0.speakerID ?? "")" }
    }

    private var speakerRow: some View {
        FlowLayout(spacing: 8) {
            peopleControl
            Divider().frame(width: 1, height: 18)
            chips
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
        .disabled(saving)
    }

    private var peopleControl: some View {
        // Steps from the number waiting for Split again, so 4 to 2 is two clicks and one confirm.
        let count = pendingPeople ?? MeetingSpeakers.people(in: meeting)
        let range = MeetingSpeakers.peopleRange(in: meeting)
        return HStack(spacing: 6) {
            Text("People in this meeting").foregroundStyle(.secondary).fixedSize()
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
            Text("Speakers").foregroundStyle(.secondary)
            ForEach(orderedSpeakers) { speaker in
                HStack(spacing: 6) {
                    Circle().fill(SpeakerColors.color(speaker.colorIndex)).frame(width: 8, height: 8)
                    if editingID == speaker.id {
                        TextField("", text: $draft)
                            .textFieldStyle(.roundedBorder).frame(width: 90)
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
                .padding(.horizontal, 9).padding(.vertical, 3)
                .background(Color(nsColor: .quaternaryLabelColor).opacity(0.20), in: Capsule())
                .overlay {
                    if speaker.pendingSuggestion(enabled: suggesting, known: model.knownVoices) != nil {
                        Capsule().stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    } else {
                        Capsule().stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
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
    private func find(_ people: Int?) { Task { await model.findSpeakers(id: meeting.id, people: people) } }
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
                .font(.system(size: 12, weight: .semibold))
                .underline(true, pattern: .dot)
                .foregroundStyle(color)
                .frame(width: 78, alignment: .leading)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .disabled(meeting.speakerSplit != .done)
        .onChange(of: meeting.speakerSplit) { _, state in if state == .running { newPerson = false } }
        .popover(isPresented: $newPerson) {
            VStack(alignment: .leading, spacing: 8) {
                TextField("New person…", text: $draft).textFieldStyle(.roundedBorder)
                    .focused($focused).onSubmit { createPerson() }
                    .onExitCommand { newPerson = false }
                if let error { Text(error).font(.caption).foregroundStyle(.orange) }
            }
            .padding(12).frame(width: 210)
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
        return segment.track == .mic ? .accentColor : .secondary
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
