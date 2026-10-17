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
        VStack(alignment: .leading, spacing: 10) {
            switch meeting.speakerSplit {
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
                        .disabled(regenerating || meeting.speakerSplit == .running)
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
        let count = MeetingSpeakers.people(in: meeting)
        let range = MeetingSpeakers.peopleRange(in: meeting)
        return HStack(spacing: 6) {
            Text("People in this meeting").foregroundStyle(.secondary).fixedSize()
            Button("−") { pendingPeople = max(range.lowerBound, count - 1) }
                .disabled(count <= range.lowerBound)
            Text("\(count)").monospacedDigit().fontWeight(.semibold)
            Button("+") { pendingPeople = max(range.lowerBound, count + 1) }
                .disabled(count >= range.upperBound)
        }
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
                    } else {
                        Button(display(speaker)) {
                            if editingID != nil { saveName() }
                            editingID = speaker.id; draft = display(speaker); editError = nil; nameFocused = true
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 9).padding(.vertical, 3)
                .background(Color(nsColor: .quaternaryLabelColor).opacity(0.20), in: Capsule())
                .overlay(Capsule().stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
            }
        }
    }

    private func display(_ speaker: MeetingSpeaker) -> String { speaker.name ?? MeetingSpeakers.defaultName(for: speaker.id) }
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
                    } icon: { Image(systemName: "circle.fill").foregroundStyle(SpeakerColors.color(speaker.colorIndex)) }
                }
            }
            Divider()
            Button("New person…") { draft = ""; error = nil; newPerson = true }
        } label: {
            Text(segment.speaker)
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
