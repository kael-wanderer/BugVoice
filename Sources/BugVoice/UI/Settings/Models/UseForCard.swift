import SwiftUI
import VoiceCore

struct UseForCard: View {
    @Bindable var model:AppModel
    @State private var testOutput:String?
    @State private var testing=false
    static let sample="ờ thì mình cần, à không, mình muốn deploy cái API lên staging vào thứ sáu"
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            HStack(alignment:.firstTextBaseline){Text("Use for").font(.headline);Spacer();Text("Which model each feature uses.").font(.caption).foregroundStyle(.secondary)}
            Grid(alignment:.leading,horizontalSpacing:12,verticalSpacing:10) {
                row(.dictation,use:$model.settings.models.dictation)
                notesRow
                row(.meetings,use:$model.settings.models.meetings)
            }
            HStack { Button(testing ? "Sending…":"Send test sentence"){Task{await runTest()}}.disabled(testing);if let testOutput{Text(testOutput).font(.callout).foregroundStyle(.secondary).lineLimit(2)} }
            Text("Coding CLIs take several seconds per call, so they are offered for Meeting notes only. Text goes to a cloud service only when a feature uses a cloud connection.").font(.caption).foregroundStyle(.secondary)
        }.insightsCard()
    }
    private func subtitle(_ feature:ModelFeature)->String { switch feature {case .dictation:"Answer within \(Int(model.settings.models.dictationTimeoutSeconds)) s or raw text is pasted";case .notes:"Same time limit";case .meetings:"Summary and action items. No time limit."} }
    private func label(_ feature:ModelFeature)->some View { VStack(alignment:.leading,spacing:1){Text(feature.title).fontWeight(.semibold);Text(subtitle(feature)).font(.caption).foregroundStyle(.secondary)}.frame(width:190,alignment:.leading) }
    private func row(_ feature:ModelFeature,use:Binding<ModelUse>)->some View {
        GridRow {
            label(feature)
            enginePicker(use.engine,allowCLI:feature == .meetings)
            TextField(placeholder(use.wrappedValue),text:use.model).textFieldStyle(.roundedBorder)
            thinkingOrEffort(use)
            if feature == .dictation { Picker("",selection:$model.settings.models.dictationTimeoutSeconds){Text("3 s").tag(3.0);Text("5 s").tag(5.0);Text("8 s").tag(8.0)}.labelsHidden().frame(width:70) } else {Color.clear.frame(width:70,height:1)}
            StatusDot(status:status(use.wrappedValue.engine))
        }
    }
    private var notesRow:some View {
        GridRow {
            label(.notes)
            Picker("",selection:Binding<ModelEngine?>(get:{model.settings.models.notes?.engine},set:{engine in model.settings.models.notes=engine.map{ModelUse(engine:$0,disableThinking:true)}})) {
                Text("Same as Dictation").tag(ModelEngine?.none);Divider()
                ForEach(model.settings.models.connections){Text($0.name).tag(ModelEngine?.some(.connection($0.id)))}
                if model.appleIntelligenceAvailable{Text("Apple Intelligence").tag(ModelEngine?.some(.appleIntelligence))}
                Text("None (raw text)").tag(ModelEngine?.some(.none))
            }.labelsHidden()
            if model.settings.models.notes != nil { TextField("Connection default",text:Binding(get:{model.settings.models.notes?.model ?? ""},set:{model.settings.models.notes?.model=$0})).textFieldStyle(.roundedBorder) } else {Text("—").foregroundStyle(.secondary)}
            Color.clear.frame(width:1,height:1);Color.clear.frame(width:70,height:1)
            StatusDot(status:status((model.settings.models.notes ?? model.settings.models.dictation).engine))
        }
    }
    private func enginePicker(_ engine:Binding<ModelEngine>,allowCLI:Bool)->some View {
        Picker("",selection:engine) {
            Section("Connections") { ForEach(model.settings.models.connections){Text($0.name).tag(ModelEngine.connection($0.id))};if model.appleIntelligenceAvailable{Text("Apple Intelligence").tag(ModelEngine.appleIntelligence)} }
            if allowCLI { Section("Coding CLIs"){ForEach(CLITool.allCases,id:\.self){Text("\($0.title) (\($0.rawValue))").tag(ModelEngine.cli($0))}} }
            Text("None (raw text)").tag(ModelEngine.none)
            if case .connection(let id)=engine.wrappedValue,!model.settings.models.connections.contains(where:{$0.id == id}){Text("Choose a model").tag(engine.wrappedValue)}
        }.labelsHidden()
    }
    @ViewBuilder private func thinkingOrEffort(_ use:Binding<ModelUse>)->some View {
        if case .cli(let tool)=use.wrappedValue.engine { Picker("",selection:use.effort){Text("Effort: default").tag("");ForEach(CLIArguments.efforts(for:tool),id:\.self){Text($0).tag($0)}}.labelsHidden().frame(width:130) }
        else { Picker("",selection:use.disableThinking){Text("Thinking off").tag(true);Text("Thinking on").tag(false)}.labelsHidden().frame(width:130).disabled(use.wrappedValue.engine == .none || use.wrappedValue.engine == .appleIntelligence) }
    }
    private func placeholder(_ use:ModelUse)->String {switch use.engine{case .connection(let id):model.settings.models.connections.first{$0.id==id}.map{$0.model.isEmpty ? "Connection default":"\($0.model) (connection default)"} ?? "Choose a model";case .cli:"CLI default";case .appleIntelligence,.none:"—"}}
    private func status(_ engine:ModelEngine)->ConnectionStatus? {switch engine{case .connection(let id):model.connectionStatus[id];case .cli(let tool):model.cliInfo[tool] == nil ? .failed("\(tool.rawValue) was not found on this Mac."):.reachable(models:[]);case .appleIntelligence:model.appleIntelligenceAvailable ? .reachable(models:[]):.failed("Apple Intelligence is not available on this Mac");case .none:nil}}
    private func runTest() async {
        testing=true;defer{testing=false}
        guard let cleanup=ProviderFactory.cleanupModel(model.plan(for:.dictation),keychain:model.keychain,fallbackTimeout:model.settings.models.dictationTimeoutSeconds) else {testOutput="Dictation cleanup is set to None.";return}
        let request=PromptBuilder(customRules:model.settings.styles.customRules).request(raw:Self.sample,style:.document,focus:.unknown,vocabulary:model.vocabulary,modelID:cleanup.modelID,disableThinking:cleanup.disableThinking)
        let start=Date()
        do {let output=try await cleanup.model.clean(request);let shown:String=switch OutputSanitizer.sanitize(output,raw:Self.sample){case .accepted(let text):text;case .rejected(let reason):"Rejected (\(reason.rawValue)): \(output)"};testOutput=String(format:"%@ · %.2f s",shown,Date().timeIntervalSince(start))}catch{testOutput=error.localizedDescription}
    }
}
