import SwiftUI
import VoiceCore

struct ConnectionSheet: View {
    let model: AppModel
    let isNew: Bool
    let original: ModelConnection
    @State private var connection: ModelConnection
    @State private var key = ""
    @State private var keyRemoved = false
    @State private var models: [String] = []
    @State private var testResult: String?
    @State private var testing = false
    @Environment(\.dismiss) private var dismiss

    init(model: AppModel, draft: ConnectionDraft) {
        self.model = model
        isNew = draft.isNew
        original = draft.connection
        _connection = State(initialValue: draft.connection)
    }

    private var fixed: Bool { ConnectionAddress.fixedURL(for: connection.kind) != nil }
    private var addressProblem: String? { fixed ? nil : ConnectionAddress.problem(connection.baseURL) }
    private var addressChanged: Bool {
        !isNew && connection.baseURL.trimmingCharacters(in: .whitespaces) != original.baseURL.trimmingCharacters(in: .whitespaces)
    }
    private var hadKey: Bool { !(model.credentials.read(original.credentialAccount) ?? "").isEmpty }
    private var showsKey: Bool {
        connection.kind.isCloud || !(ConnectionAddress.baseURL(for: connection).map(ConnectionAddress.isLocal) ?? true)
            || hadKey
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isNew ? "Add connection" : "Edit connection").font(.headline)
            Form {
                TextField("Name", text: $connection.name)
                LabeledContent("Kind", value: connection.kind.title)
                if fixed {
                    LabeledContent("Address", value: ConnectionAddress.fixedURL(for: connection.kind)?.absoluteString ?? "")
                } else {
                    TextField("Address", text: $connection.baseURL)
                    if let addressProblem {
                        Text(addressProblem).font(.caption).foregroundStyle(.orange)
                    } else if addressChanged && hadKey {
                        Text("Enter the key again for the new address.").font(.caption).foregroundStyle(.orange)
                    }
                }
                if showsKey {
                    HStack {
                        SecureField("API key", text: $key, prompt: Text(hadKey && !keyRemoved && !addressChanged ? "Key saved" : "Paste the key"))
                        Button("Remove") { key = ""; keyRemoved = true }.disabled(!hadKey || keyRemoved)
                    }
                }
                HStack {
                    TextField("Default model", text: $connection.model)
                    Menu("Choose…") { ForEach(models, id: \.self) { id in Button(id) { connection.model = id } } }
                        .disabled(models.isEmpty).fixedSize()
                }
                HStack {
                    Button(testing ? "Testing…" : "Test connection") { Task { await test() } }
                        .disabled(testing || addressProblem != nil)
                    if let testResult { Text(testResult).font(.caption).foregroundStyle(.secondary) }
                }
            }
            .formStyle(.grouped)
            HStack {
                if !isNew {
                    Button("Delete", role: .destructive) { delete() }
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save", action: save).keyboardShortcut(.defaultAction)
                    .disabled(addressProblem != nil || connection.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    /// Lists models with the key typed here (or the saved one); generates nothing.
    private func test() async {
        testing = true
        defer { testing = false }
        guard let url = ConnectionAddress.baseURL(for: connection) else { return }
        let typed = key.trimmingCharacters(in: .whitespaces)
        let apiKey = typed.isEmpty && !keyRemoved && !addressChanged ? model.credentials.read(original.credentialAccount) : typed
        do {
            models = try await ModelCatalog.list(baseURL: url, apiKey: apiKey, anthropic: connection.kind.usesAnthropicAPI)
            testResult = models.count == 1 ? "Reachable · 1 model" : "Reachable · \(models.count) models"
        } catch {
            testResult = error.localizedDescription
        }
    }

    private func save() {
        let typed = key.trimmingCharacters(in: .whitespaces)
        do {
            if !typed.isEmpty {
                try model.credentials.write(typed, account: connection.credentialAccount)
            } else if keyRemoved || (addressChanged && hadKey) {
                try model.credentials.write(nil, account: connection.credentialAccount)
            }
        } catch {
            model.saveError = "Could not save the API key: \(error.localizedDescription)"
            return
        }
        connection.name = connection.name.trimmingCharacters(in: .whitespaces)
        connection.baseURL = connection.baseURL.trimmingCharacters(in: .whitespaces)
        if let index = model.settings.models.connections.firstIndex(where: { $0.id == connection.id }) {
            model.settings.models.connections[index] = connection
        } else {
            model.settings.models.connections.append(connection)
        }
        let saved = connection
        Task { await model.testConnection(saved) }
        dismiss()
    }

    /// The key goes with the connection. Rows that used it show "Choose a model".
    private func delete() {
        try? model.credentials.write(nil, account: original.credentialAccount)
        model.settings.models.connections.removeAll { $0.id == original.id }
        model.connectionStatus[original.id] = nil
        dismiss()
    }
}
